# Windows gates for scripts/gauntlet.sh (sourced; `gate`, `$out` and `diff_for_judge` come from there).
# Everything runs on the Mac (EnableWindowsTargeting); the app itself needs Windows, so there are no
# screenshots (WPF can't render here) and the judge reads the code instead.

export DOTNET_ROOT=${DOTNET_ROOT:-/opt/homebrew/opt/dotnet/libexec}
export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1

# From clean, in Release as scripts/make-windows-zip.sh publishes it: the app (and with it the Core)
# and the tests' runner.
dotnet_build() {
  dotnet build windows/NuVa/NuVa.csproj -c Release --no-incremental -nologo &&
    dotnet build windows/NuVa.Core.Tests -c Release --no-incremental -nologo
}

# Any compiler or analyzer warning in our own projects fails (MSBuild prints each twice; sort -u).
no_warnings() {
  local warnings
  warnings=$(grep -E '/windows/.*: warning [A-Z]+[0-9]+' $out/logs/build.log | sed -E 's/ \[[^]]*\]$//' | sort -u)
  if [[ -n $warnings ]]; then echo $warnings; return 1; fi
  echo "no warnings in windows/"
}

core_tests() {
  dotnet run --project windows/NuVa.Core.Tests -c Release --no-build
}

# Every string in both languages, and the same Portuguese translated as the Mac translates it:
# strings.swift only warns ("! …") when Windows' English differs from the Mac's; here that fails.
strings_agree() {
  local log
  log=$(swift scripts/strings.swift) || { echo $log; return 1; }
  echo $log
  ! print -r -- $log | grep -q '^! '
}

# What windows/CLAUDE.md asks that no compiler sees. Each rule prints its matches; any match fails.
static_rules() {
  local failed=0 hits
  rule() {  # rule <description> <matches…>
    local what=$1; shift
    hits=$(printf "%s\n" "$@" | sed -E "/^[[:space:]]*$/d")
    if [[ -n $hits ]]; then echo "✗ $what"; print -r -- $hits | sed 's/^/    /'; failed=1
    else echo "ok  $what"; fi
  }
  local cs=(${(f)"$(git ls-files 'windows/*.cs')"})
  local ui=(${(f)"$(git ls-files 'windows/NuVa/UI/*.cs' | grep -v '/Theme\.cs$')"})

  rule "no NuGet packages (PackageReference, PackageVersion, packages.config)" \
    "$(git ls-files 'windows/*' | xargs grep -nE '<(PackageReference|PackageVersion|GlobalPackageReference)\b' 2>/dev/null)" \
    "$(git ls-files 'windows/*packages.config')"

  rule "no native library but Windows' own (DllImport/LibraryImport, bundled .dll)" \
    "$(grep -nE '(DllImport|LibraryImport)\(' $cs | grep -viE '"(kernel32|user32|gdi32|dwmapi|advapi32|shell32|ole32|oleaut32|uxtheme|mf|mfplat|mfreadwrite)(\.dll)?"')" \
    "$(git ls-files 'windows/*.dll' 'windows/*.so' 'windows/*.dylib')" \
    "$(grep -niE '\b(NAudio|LibVLC|libvlc|ffmpeg|FFmpeg|Un4seen|ManagedBass|CSCore|TagLib)\b' $cs)"

  # Theme.cs is the one place a token becomes a WPF colour; Brushes.Transparent is no colour (it only
  # makes an area take the mouse). A black or white with an alpha counts as a literal.
  rule "no colour literals in windows/NuVa/UI (every colour through Theme and a Token)" \
    "$(grep -nE 'Color\.From(Rgb|Argb|ScRgb|ScRgba|Values)\b|\bColors\.|\bSystemColors\.|new Color *[({]|"#[0-9A-Fa-f]{3,8}"|Theme\.Hex\(0x' $ui)" \
    "$(grep -nE '\bBrushes\.' $ui | sed -E 's/Brushes\.Transparent([^A-Za-z]|$)/(transparent)\1/g' | grep -E '\bBrushes\.')"

  # Ctrl+Alt is AltGr on Portuguese keyboards (windows/CLAUDE.md): ⌥⌘ is Ctrl+Shift.
  rule "no Ctrl+Alt shortcuts" \
    "$(grep -nE 'ModifierKeys\.(Control|Alt) *\| *ModifierKeys\.(Alt|Control)|Ctrl\+Alt|Alt\+Ctrl' $cs | grep -E 'Control *\| *ModifierKeys\.Alt|Alt *\| *ModifierKeys\.Control|Ctrl\+Alt|Alt\+Ctrl')"

  # Folders, not metadata: nothing reads a file's tags or embedded pictures. Writing the system media
  # controls' MusicProperties (what Windows shows on the lock screen) is not reading.
  rule "no tag reading (MusicProperties read, SystemProperties.Music, TagLib, IMFMetadata, PKEY_, shell thumbnails)" \
    "$(grep -nE 'GetMusicPropertiesAsync|SystemProperties\.Music|IMFMetadata|MF_METADATA|PKEY_|RetrievePropertiesAsync|GetThumbnailAsync|GetScaledImageAsThumbnailAsync|IShellItemImageFactory|ShellFile\b' $cs)" \
    "$(grep -nE 'MusicProperties' $cs | grep -vE 'MusicProperties\.[A-Za-z]+ = ')"

  return $failed
}

gate static    static_rules
gate build     dotnet_build
gate warnings  no_warnings
gate test      core_tests
gate strings   strings_agree
gate tokens    swift scripts/tokens.swift --check
gate content   scripts/check-content.sh
