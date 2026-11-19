# Plan: the output follows the track's sample rate

Status: written, steps 1 to 5, for 1.17. Heard once by hand (below): the sandboxed app sets the rate, a track's start is not clipped, and the device is put back on quit. Still to check before release: a USB DAC, AirPlay and Bluetooth left alone, the `96 → 48 kHz` readout on a real device, and Jellyfin tracks.
Input: the library is FLAC, much of it above 44.1 kHz. NuVa reads the output device's sample rate for the display (`CoreAudioDevice` in `Sources/Player/OutputRoute.swift`) but never sets it, so a 96 kHz file on a DAC left at 48 kHz is resampled by macOS and nothing says so. The idea comes from other Mac players that switch the DAC per track (Vespertine, Audirvana, Colibri); only the idea, no code.

## What changes for the user

1. When a track starts on a wired output, NuVa sets that device to the track's sample rate, if the device offers it.
2. The output readout on the display says what is really happening: `→ DAC · 96 kHz` when track and device agree, `→ DAC · 96 → 48 kHz` when macOS is resampling. The tooltip says it in words.

No "bit-perfect" badge. With `AVQueuePlayer`, the equalizer tap and the player's volume in the path, NuVa cannot prove the samples are untouched, so it only states what it can read back from Core Audio.

## Principles

- **Native audio** holds: `AudioObjectSetPropertyData` on `kAudioDevicePropertyNominalSampleRate`, the same call Audio MIDI Setup makes. No exclusive (hog) mode, no integer mode, no third-party code.
- **One small window** holds: no new view. One menu item and a few characters on a line the display already has.
- **Folders, not metadata** holds: the rate comes from the audio stream's format, never from tags.

## Decisions

1. **The track's rate comes from the asset**, not from the file: the audio track's format description (`AVAssetTrack.load(.formatDescriptions)` → `AudioStreamBasicDescription.mSampleRate`). It works the same for Local, Jellyfin and CD, where `AudioFormat.label(for:)` only opens `file://` URLs.
2. **Which rate.** The device's own list (`kAudioDevicePropertyAvailableNominalSampleRates`, which are ranges). The track's rate if offered; else its lowest offered whole multiple (44.1 → 88.2: as exact as a higher one, with less work); else the nearest higher rate; else the highest rate there is (a 96 kHz track on a 48 kHz device should not stay at 44.1). A pure function, `OutputRate.choose(track:available:)`, so it is tested without hardware.
3. **Which outputs.** Only a Core Audio device that is not AirPlay (`airp`) and not Bluetooth (`blue`, `blea`), and only when the app's AirPlay picker is not routing elsewhere (`routedDeviceNames()`). Over AirPlay and Bluetooth the readout stays as it is today.
4. **When.** In `PlayerController.currentItemChanged()`, and when the output device changes while a track plays. Tracks of one folder share a rate, so an album never switches mid-way; a switch happens between albums of different rates.
5. **NuVa puts the rate back.** It remembers the rate each device had before the first change and restores it on quit. It does not restore on pause, and it does not fight: if another app or the user changes the rate mid-track, NuVa shows the new truth and sets again only at the next track. On quit it restores only a device still at the rate NuVa last asked for, so a rate the user chose meanwhile stays.
6. **A switch, on by default:** Controls ▸ Match Output to Track (PT "Ajustar a saída à faixa"). Off, NuVa never writes to the device and only the readout part remains. On by default (decided 2026-11-19): it is the point of the feature, and decision 5 puts the device back.
7. **A failure is quiet but written down.** If the device refuses, playback continues resampled, the readout shows `96 → 48 kHz`, and the log gets a line with code `output-rate` (no device name, as the log's rule says).

## Not in this plan

- Bit depth of the device (`kAudioStreamPropertyPhysicalFormat`): a possible second phase, reading first, setting later.
- Exclusive mode, integer mode, DSD, a loopback test.
- Gapless across a rate change: the device reconfigures, so a short silence there is expected.

## Parity (`docs/features.json`)

New row `output-rate`: "The output device follows the track's sample rate, and the display says when the system resamples".
- `mac`: `yes`.
- `tv`: `n/a`. Android TV's mixer owns the output rate; an app cannot set it.
- `windows`: `n/a` (decided in step 4). AudioGraph plays in shared mode at the device's format, which is the user's to set in Windows' Sound settings; an app changes it only by taking the device for itself, which NuVa does not do.

## Steps (one commit each, `xcodebuild` after each)

1. **Spike, no UI.** `CoreAudioDevice`: available rates, set rate, a listener for rate changes. Confirm by hand that the sandboxed app may set the rate (no entitlement is expected to be needed, but this is unverified) and hear what `AVQueuePlayer` does when the rate changes under it. If the first notes are clipped: pause, set, wait for the listener, play.
2. **`OutputRate`** (`Sources/Player/OutputRate.swift`): `choose(track:available:)`, the per-device memory of the original rate, restore on quit. Tests in `Tests/OutputRateTests.swift`: exact match, multiples, nearest higher, nothing offered, AirPlay and Bluetooth skipped.
3. **Wire it.** Track rate from the asset in `PlayerController`; set on track change and on device change; the menu item and its remembered setting; log code `output-rate`; a fixed `Reports` event word for "rate set".
4. **Readout.** `OutputRoute` learns the track's rate and writes `96 → 48 kHz` and the tooltip; the listener from step 1 tells of a rate change at once (the poll stays: it is what catches the AirPlay picker). Strings in PT and EN. Decide the Windows row.
5. **Content.** `docs/features.json`, `swift scripts/content.swift`, README and site prose (EN + PT), `CHANGELOG.md`, `CLAUDE.md` scope, `scripts/check-content.sh`. `TERMS.md` does not change: no network call. No screenshot changes: the README's and the site's all show AirPlay, whose readout is as it was.

## Checked by hand

2026-11-19, a MacBook Neo's headphone jack with wired Sony WH-1000XM4 headphones, on a Debug build of step 5, playing seven 10-second test tracks whose rate changes at every track (44.1, 96, 48, 192, 88.2, 176.4, 44.1 kHz; each starts with four beeps at its first sample):

- The sandboxed app may set the device's rate: it changed with the tracks. No entitlement was added.
- All four beeps were heard on every track, so the simple way stays: the rate is set while the player runs, with no pause around it.
- On quit the device went back to the rate it had.

## Still to check by hand

- A USB DAC, which may answer more slowly than the Mac's own output: the DAC's display agrees with NuVa's, and the window does not stall (the request is made on the main thread).
- The readout on a device that doesn't reach the track's rate: `192 → 96 kHz`.
- AirPlay to the WiiM and Bluetooth headphones: untouched.
- Another app playing sound while NuVa switches the rate.
- Jellyfin and CD tracks get their rate too, and a change of rate between two albums that come over the network starts clean.

## Open for the author

- Restore on quit only, or also when the queue ends.
