# Android TV gates for scripts/gauntlet.sh (sourced; `gate`, `$out` and `diff_for_judge` come from there).
# The snapshots run the debug build on the AVD nuva_tv (booted headless when no device is attached)
# against scripts/gauntlet/jellyfin-standin.py, driven with the remote's keys.

sdk=$HOME/Library/Android/sdk
adb=$sdk/platform-tools/adb
apk=android/app/build/outputs/apk/debug/app-debug.apk
package=pt.nunomartins.nuva

gradle() {
  (cd android && JAVA_HOME=/opt/homebrew/opt/openjdk@17 ANDROID_HOME=$sdk ./gradlew --console=plain "$@")
}

# Clean, so every file is compiled and none hides its warnings.
tv_build() { gradle clean assembleDebug }

# Kotlin warnings in our own code (not in Gradle's or the libraries'); any is a failure.
no_warnings() {
  local warnings
  warnings=$(grep -E '^w: .*/android/app/src/main/' $out/logs/build.log | sort -u)
  if [[ -n $warnings ]]; then echo $warnings; return 1; fi
  echo "no warnings in android/app/src/main"
}

tv_test() { gradle testDebugUnitTest }

# Android lint; an error fails (warnings are in the report, for the judge).
tv_lint() {
  gradle lintDebug
  local result=$?   # not `status`: zsh's read-only alias of $?
  local report=android/app/build/intermediates/lint_intermediate_text_report/debug/lintReportDebug/lint-results-debug.txt
  # Warnings first, so the errors are the log's last lines.
  grep ': Warning:' $report 2>/dev/null
  grep ': Error:' $report 2>/dev/null
  return $result
}

# MARK: Snapshots

booted=0     # 1 when this gate booted the emulator (and so shuts it down)
standin=     # the stand-in's process
port=18096   # not Jellyfin's own 8096: a real server may be running on this Mac

# Remote keys, one after another, with time for the focus and the cross-fades to settle.
press() { local key; for key in "$@"; do $adb shell input keyevent $key; sleep 0.6; done }

# The screen as it is, 1920×1080: shot <view>.
shot() {
  sleep ${2:-1}
  $adb exec-out screencap -p > $dir/tv-$1.png
  [[ -s $dir/tv-$1.png ]] || { echo "no image for $1"; return 1; }
  echo "  tv-$1.png"
}

# Wherever the focus is after an overlay closes, it ends on the leftmost key (mode):
# a row goes left to the display or the keys, the display goes down to the keys, the keys go left.
home() { press DPAD_LEFT DPAD_DOWN DPAD_LEFT DPAD_LEFT DPAD_LEFT DPAD_LEFT DPAD_LEFT DPAD_LEFT DPAD_LEFT DPAD_LEFT; }

# The keys from mode: 0 mode, 1 previous, 2 play, 3 next, 4 ambient, 5 settings.
key() { home; local i; for (( i = 0; i < $1; i++ )); do press DPAD_RIGHT; done; }

snapshot_cleanup() {
  [[ -n $standin ]] && kill $standin 2>/dev/null
  if (( booted )); then
    $adb emu kill >/dev/null 2>&1
  elif $adb get-state >/dev/null 2>&1; then
    $adb shell am force-stop $package
    $adb shell ime reset >/dev/null 2>&1   # the keyboards no_keyboard turned off
  fi
}

# A few seconds of two tones per channel, as FLAC (afconvert, macOS's own), in build/: never real music.
make_audio() {
  local audio=build/gauntlet-audio n
  mkdir -p $audio
  python3 - $audio <<'EOF'
import math, struct, sys, wave
# Two seconds that loop seamlessly (every frequency a multiple of 0.5 Hz), repeated for three minutes.
for n, (low, high) in enumerate([(110, 1760), (220, 3520), (82.5, 880)]):
    rate = 44100
    block = bytearray()
    for i in range(rate * 2):
        t = i / rate
        beat = 0.55 + 0.45 * math.sin(math.pi * t)
        left = 0.5 * math.sin(2 * math.pi * low * t) * beat + 0.2 * math.sin(2 * math.pi * high * t)
        right = 0.35 * math.sin(3 * math.pi * low * t) + 0.25 * math.sin(2 * math.pi * high * t) * (1 - beat)
        block += struct.pack("<hh", int(left * 32767), int(right * 32767))
    with wave.open(f"{sys.argv[1]}/tone-{n}.wav", "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(rate)
        w.writeframes(bytes(block) * 90)
EOF
  for n in 0 1 2; do afconvert -f flac -d flac $audio/tone-$n.wav $audio/tone-$n.flac || return 1; done
  echo $audio
}

# The device: an attached one, or the AVD booted headless.
device() {
  if ! $adb get-state >/dev/null 2>&1; then
    echo "booting nuva_tv"
    $sdk/emulator/emulator -avd nuva_tv -no-window -no-audio -no-snapshot-save -no-boot-anim > $out/logs/emulator.log 2>&1 &
    booted=1
    $adb wait-for-device
  fi
  local waited=0
  until [[ $($adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r') == 1 ]]; do
    sleep 2; (( waited += 2 ))
    (( waited > 240 )) && { echo "the emulator didn't boot"; return 1; }
  done
  $adb shell input keyevent WAKEUP
}

# No on-screen keyboard: `input text` types straight into the field. The system keeps one input method
# on, so the remote service's (no keys, a bar at the bottom while a field has the focus) is the one.
bridge=com.google.android.tv.remote.service/.ImeBridgeService
no_keyboard() {
  local ime
  $adb shell ime enable $bridge >/dev/null
  $adb shell ime set $bridge >/dev/null
  $adb shell ime list -s | tr -d '\r' | while read -r ime; do
    [[ $ime == $bridge ]] || $adb shell ime disable $ime >/dev/null
  done
}

# A fresh app in the language: no account, no options, no last session.
fresh() {
  $adb shell am force-stop $package
  $adb shell pm clear $package >/dev/null
  $adb shell cmd locale set-app-locales $package --locales $1
  no_keyboard
  $adb shell am start -W -n $package/.MainActivity >/dev/null
  sleep 3
}

# One language's views, into snapshots/<lang>/.
tour() {
  dir=$out/snapshots/$1
  mkdir -p $dir
  echo "$1:"
  fresh $1
  # With the focus on the Sign In key (↓ from each field) the input method's bar goes, and the form shows whole.
  press DPAD_DOWN DPAD_DOWN DPAD_DOWN
  shot sign-in || return 1
  press DPAD_UP DPAD_UP DPAD_UP

  # Any user and password: the stand-in accepts them. Enter moves to the next field and signs in from the last.
  $adb shell input text "http://10.0.2.2:$port"; press ENTER
  $adb shell input text gauntlet; press ENTER
  $adb shell input text standin; press ENTER
  shot folders 4 || return 1

  # A folder whose name is longer than the list (Kraftwerk's only album), and inside it.
  press DPAD_DOWN DPAD_CENTER
  shot folders-long 2
  press DPAD_CENTER
  shot folders-long-inside 2
  # Back goes up a folder, twice, to the artists; then Fleetwood Mac › Rumours (1977).
  press BACK BACK DPAD_UP DPAD_CENTER
  sleep 1; press DPAD_CENTER
  shot folders-album 2

  # The second track: the queue comes back, playing.
  press DPAD_DOWN DPAD_CENTER
  shot player 5

  # The equalizer from the display's "EQ" readout (the one control up from the keys): Rock (the
  # focus starts on the first preset), then OK on a fader to hold it and ↑ half a decibel (its LED lit);
  # OK lets go and ↑ goes back up to the presets, as everywhere else; Back closes.
  home; press DPAD_UP DPAD_CENTER
  sleep 1; press DPAD_DOWN DPAD_RIGHT DPAD_CENTER
  shot equalizer 1
  press DPAD_DOWN DPAD_CENTER DPAD_UP
  shot equalizer-bands 1
  press DPAD_CENTER DPAD_UP
  shot equalizer-back 1
  press BACK

  # Holding OK on a queue row: move, remove, clear.
  key 5; press DPAD_RIGHT
  $adb shell input keyevent --longpress DPAD_CENTER
  shot queue-actions 1.5
  press BACK

  # Ambient: every face, → from one to the next (each shows its name for a moment first).
  key 4; press DPAD_CENTER
  local face
  for face in display clock spectrum meters needles valves; do
    shot ambient-$face 4
    press DPAD_RIGHT
  done
  press DPAD_UP

  # Settings; OK on the skin moves to the next one: Graphite Orange, then Phosphor.
  # The mode key twice: shuffle, then repeat all, its name under it.
  key 0; press DPAD_CENTER DPAD_CENTER
  shot mode 1
  press DPAD_CENTER DPAD_CENTER

  key 5; press DPAD_CENTER
  shot settings 1.5
  local skin
  for skin in graphite-orange phosphor; do
    press DPAD_CENTER BACK
    shot player-$skin 1.5
    # The folders from the tabs: → into the queue, Back to its tab, → to Folders, OK. OK on the
    # album's first track plays it and brings the queue back.
    key 5; press DPAD_RIGHT BACK DPAD_RIGHT DPAD_CENTER
    shot folders-$skin 1.5
    press DPAD_CENTER
    key 5; press DPAD_CENTER
  done
  press BACK

  # Back on the main screen asks before leaving.
  press BACK
  shot exit 1.5
  press BACK
}

snapshots() {
  trap snapshot_cleanup EXIT INT TERM
  [[ -f $apk ]] || { echo "no $apk: the build gate makes it"; return 1; }
  local audio
  audio=$(make_audio | tail -n 1) || return 1
  python3 scripts/gauntlet/jellyfin-standin.py $audio $port 2> $out/logs/standin.log &
  standin=$!
  sleep 1
  kill -0 $standin 2>/dev/null || { echo "the stand-in didn't start (port $port in use?)"; cat $out/logs/standin.log; return 1; }
  device || return 1
  $adb install -r $apk >/dev/null || return 1

  local lang count
  for lang in pt-PT en; do tour $lang || return 1; done
  for lang in pt-PT en; do
    count=$(ls $out/snapshots/$lang | wc -l | tr -d ' ')
    echo "$lang: $count images"
  done
  [[ $(ls $out/snapshots/pt-PT | wc -l) == $(ls $out/snapshots/en | wc -l) ]]
}

gate build     tv_build
gate warnings  no_warnings
gate test      tv_test
gate lint      tv_lint
gate strings   swift scripts/strings.swift
gate content   scripts/check-content.sh
gate snapshots snapshots
