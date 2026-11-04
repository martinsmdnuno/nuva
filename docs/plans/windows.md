# NuVa for Windows

Status: built (all steps below), not yet run on Windows. Joins the release when a tester confirms it.
Input: there is no Windows machine for development. A friend of the author installs and uses it on Windows 11 (x64), with a CD drive and access to the author's Jellyfin. So the app builds and is tested on the Mac as far as possible, and everything that only Windows can check is written to a log the friend can send back (`%LOCALAPPDATA%\NuVa\nuva.log`, and `NuVa.exe --selftest [file]`, which decodes a file (or a WAV of silence it makes), plays a second of silence through AudioGraph, lists the output devices and shows what worked).

A NuVa for Windows 10 and 11, with the Mac app's scope (`CLAUDE.md`) wherever Windows allows. It lives in `windows/`, next to the Mac app and `android/`, and shares their principles and design system, not their code. It ships in the same GitHub release as the DMG and the APK, with the same version number.

## Principles, as they apply here

1. **Folders, not metadata.** Same as the Mac: folder = album, names exactly as they are, natural sort by file name. Local folders, network shares (`\\server\share` or a mapped drive) and Jellyfin by each item's `Path`. Tags are never read to organise.
2. **Native audio.** On Windows "native" means the platform's own engine: **Media Foundation** decodes (the Source Reader, with Windows' own decoders: FLAC and ALAC from Windows 10, MP3, AAC/M4A, WAV) and **`Windows.Media.Audio.AudioGraph`** plays, on the Windows audio engine. No NAudio, VLC, ffmpeg, BASS or any other audio library. The stream is the original file (`/Audio/{id}/stream.flac?static=true`): a FLAC stays a FLAC. AIFF has no Windows decoder; it is plain PCM in chunks, so NuVa reads it itself (a small parser, no decoding).
3. **One small window.** The same device: display, keys, and below them the queue or the folders. 360 to 480 wide, the same three modes.
4. **Keyboard first.** The Mac's shortcuts with Ctrl for ⌘ (table below); media keys and the system media controls (SMTC) always work, also from the lock screen and other apps.
5. **Pluggable sources.** The player knows only entries and URLs: `LocalSource` (a path), `JellyfinSource`, `DiscSource`. `ServerSource` stays a stub.

This extends principle 2 to Windows; it doesn't change it for the Mac.

## Stack

- **C# on .NET 10 (LTS) with WPF**, target `net10.0-windows10.0.19041.0` (Windows 10 2004 and later), so the app can call WinRT (AudioGraph, SMTC, device lists) through the SDK's own projection. Everything else is in the .NET Windows Desktop runtime: no NuGet packages.
- **Two projects**: `windows/NuVa.Core` (`net10.0`, no Windows APIs: the DSP, the folder and Jellyfin model, artwork rules, skins, strings, the update check) and `windows/NuVa` (the WPF app: audio I/O, SMTC, windows). A small test runner (`windows/NuVa.Core.Tests`, a console app with its own asserts, since xUnit and MSTest are NuGet packages) runs on any OS.
- **Built on the Mac**: `brew install dotnet`, then `scripts/make-windows-zip.sh` (the Core tests, then `dotnet publish` for win-x64, self-contained, one file). WPF and the Windows SDK projection compile on macOS; only running the app needs Windows. `dotnet run --project windows/NuVa.Core.Tests` runs the DSP and library tests on the Mac.
- **Delivered as a zip**: `dist/NuVa-Windows-X.zip` (and `dist/NuVa-Windows.zip`, the fixed download name) with one self-contained `NuVa.exe` for x64 (no .NET to install, about 70 MB zipped), the licences and a read-me. Unpack anywhere and run; settings in `%APPDATA%\NuVa`, covers, CD names and the log in `%LOCALAPPDATA%\NuVa`. Unsigned, so SmartScreen asks once ("More info ▸ Run anyway"); a signing certificate costs money and can come later. ARM64 would be a separate asset (`-r win-arm64`).

Why not the others: WinUI 3 builds only on Windows and needs the Windows App SDK runtime (an extra install or a NuGet package), and NuVa draws its own look anyway. C++/Win32 with Direct2D would be smaller but is several times the code, and cross-compiling it from the Mac needs a MinGW toolchain.

## Sound

The Mac's tap sits inside AVPlayer; Windows has no supported way to put a C# filter inside `MediaPlayer` (`IBasicAudioEffect` must be a registered WinRT class, which needs C#/WinRT authoring from NuGet). So NuVa owns the pipe between the platform's decoder and the platform's output, as the Android port does with `TapSink`:

```
Media Foundation Source Reader (float PCM, per track)
  → ring buffer (decoder thread, a second ahead)
  → Equalizer (10 biquads, double precision, pre-gain) → SpectrumAnalyzer (10 + 28 bands, L/R RMS and peak)
  → AudioGraph AudioFrameInputNode (resamples to the device) → AudioDeviceOutputNode (volume as its gain)
```

- **Equalizer and meters**: a straight port of `Sources/Player/Equalizer.swift` and `Spectrum.swift` by way of `android/…/audio/Equalizer.kt` and `Spectrum.kt` (same bands, range, presets, short and long FFTs, 120 measurements a second). The FFT is a small radix-2 written in C#, as on Android. With the EQ off and no meter on screen, blocks pass untouched.
- **What is heard**: each measurement carries the track time of its block; the screen reads them at the output's clock (frames handed to the graph minus the graph's latency and what is queued), so the meters match the sound, as on the Mac and Android.
- **Gapless**: the decoder thread opens the next track before the current one ends and keeps filling the same ring buffer. A change of sample rate between tracks swaps the input node at the boundary (a few milliseconds).
- **Seek**: `SetCurrentPosition` on the reader and a flush of the ring buffer.
- **Jellyfin**: Media Foundation opens `https://` URLs itself (with range requests for seeking). If a server misbehaves, the fallback is a byte stream of NuVa's own over `HttpClient`.
- **Output**: AudioGraph follows the default device and is rebuilt when it changes or goes away (headphones unplugged).

## How each Mac feature maps

| Mac | Windows |
|---|---|
| `LocalSource`, NSOpenPanel, security-scoped bookmark | A folder picker (`OpenFolderDialog`, .NET 8+); a path is enough, no bookmark. Network shares by UNC path or mapped drive; offline shows the `danger` message, as on the Mac. |
| `JellyfinSource`, password in the Keychain | Same API calls (port of `JellyfinSource.swift`); the password in Windows Credential Manager (`CredWrite`/`CredRead`). |
| `DiscSource` (cddafs volume) | The CD drive read directly: TOC with `IOCTL_CDROM_READ_TOC_EX`, audio with `IOCTL_CDROM_RAW_READ` (16/44.1 PCM), insert and eject from `WM_DEVICECHANGE` and `IOCTL_STORAGE_EJECT_MEDIA`. Disc ID and MusicBrainz lookup as `DiscTOC`/`DiscLookup`. Opening NuVa when a CD goes in is Windows' AutoPlay setting, which NuVa never changes. Needs a drive to test. |
| AVQueuePlayer, gapless | Media Foundation + AudioGraph, above. |
| MTAudioProcessingTap EQ and spectrum | Our pipe, above. |
| `MPRemoteCommandCenter`, `MPNowPlayingInfoCenter` | System Media Transport Controls (play, pause, next, previous, seek, the title, folder and cover in the volume flyout and lock screen); media keys arrive through SMTC. Taskbar thumbnail buttons (previous, play/pause, next) as a bonus of WPF's `TaskbarItemInfo`. |
| AirPlay picker on the output readout | **No AirPlay on Windows.** The readout opens a list of the system's output devices (`DeviceInformation` with the render selector) and NuVa sends the graph there; "System default" follows Windows. A WiiM is reached by cable, Bluetooth or as a USB device, which show up in that list. |
| Menu bar (NuVa, File, View, Controls) | One menu key in the header (and right-click on the display) with the same items and groups; the shortcuts work without it. |
| Closing the window keeps playing in the menu bar | Closing keeps playing in the notification area: a tray icon (WinForms `NotifyIcon`, part of the desktop runtime) that opens the mini player above the taskbar. Quit from the tray menu or Ctrl+Q. |
| Window modes ⌘1–⌘3, widths, heights, zoom | Ctrl+1–Ctrl+3, same sizes; maximise stretches to the screen's height, as zoom does. |
| Ambient (own Space, full screen) | A borderless full-screen window on the chosen screen (Windows has no Spaces), Ctrl+4 or F11; Esc leaves. All six faces and OLED protection. The screen stays awake with `SetThreadExecutionState`. Drawn every frame from `CompositionTarget.Rendering`, which follows the screen's rate. |
| `ArtworkGlow`, `VUNeedle`, radial lamps | Ported as they are (the glow computed into a bitmap, then blurred). |
| Artwork order and rules | Same order: an image in the folder (`cover`, `folder`, `front`, `album`, `capa` · jpg/jpeg/png; a disc folder looks in its album folder too), the user's choice, then MusicBrainz + Cover Art Archive from `AlbumGuess`, confident matches only, misses remembered. "Wrong or Missing Artwork…" with the same three choices. Covers in `%LOCALAPPDATA%\NuVa\Artwork`, never in the music folders. Also in SMTC. |
| Skins and font sets | Same tokens per skin (Rams with Lead and Aluminium following Windows' light/dark app mode, Graphite Orange, Phosphor), from `tokens.json` and `Skin.swift`. Fonts embedded as on the Mac; "SF Pro + SF Mono" becomes "Segoe UI + Cascadia Mono" (the system's). |
| SF Symbols | NuVa's own vector icons, drawn to match (as `android/…/ui/Icons.kt`). |
| Update check | Same: GitHub `releases/latest` at launch (at most daily) and the menu's Check for Updates…; a notice only, never downloads. |
| Terms and Privacy | `TERMS.md` bundled and shown in its own window. |
| `Localizable.xcstrings`, system language | The same rule: the Portuguese text is the key, with its English translation, in `windows/NuVa.Core/Strings.json`; the Windows display language picks PT or EN (English fallback). |
| Reduce Motion | Windows' "Animation effects" setting (`SystemParameters.ClientAreaAnimation`). |
| `--snapshot` for README images | Not yet: README images for Windows come with the first tested build. |

## Shortcuts

⌘ becomes Ctrl. ⌥⌘ becomes **Ctrl+Shift**, never Ctrl+Alt: Ctrl+Alt is AltGr on Portuguese and other European keyboards, and would type € or @ instead.

Space play/pause · Ctrl+→ next · Ctrl+← previous · Ctrl+Shift+→ ← 10 s · Ctrl+. stop · Ctrl+↑ ↓ volume · Ctrl+Shift+E equalizer · Ctrl+L go to the current track · Enter play selection · Ctrl+Enter add to queue · Ctrl+Shift+↑ ↓ move in the queue · Ctrl+Shift+Delete clear the queue · Ctrl+B swap queue and folders · Ctrl+1 2 3 queue, folders, compact · Ctrl+4 or F11 ambient · Ctrl+O add folder · Ctrl+Shift+O add Jellyfin · Ctrl+E eject CD · Ctrl+R repeat · Ctrl+Shift+S shuffle · Ctrl+Shift+A artwork · Ctrl+Shift+V spectrum · Ctrl+Shift+1 2 3 skins · Ctrl+Q quit.

## What doesn't apply

- **AirPlay**: no native AirPlay sender on Windows; the system's output-device choice instead (above).
- **Spaces, Dock, menu bar**: replaced by a full-screen window, the taskbar and the notification area.
- **Security-scoped bookmarks and the sandbox**: a Windows desktop app reads paths directly.
- **Keychain**: Credential Manager.
- **macOS's "When you insert a music CD" setting**: Windows AutoPlay, the user's choice.
- **Signing and notarisation**: none at first (SmartScreen asks once).

## Steps (one commit each; build and run the tests after each)

1. Plan (this file).
2. Solution skeleton: `NuVa.Core`, `NuVa`, the test runner, a build script `scripts/make-windows-zip.sh`; an empty window with the tokens and fonts.
3. Core: entries, natural sort, `LocalSource`, the browser model, settings, strings (PT + EN).
4. Audio: Media Foundation reader, ring buffer, AudioGraph output; play, pause, seek, volume, gapless. A console smoke test that plays a file, for the Windows machine.
5. Player: queue (add, remove, reorder), repeat, shuffle, restore the last queue paused.
6. UI: display, keys, position bar, volume knob, queue and folders, the three window modes, shortcuts.
7. SMTC and media keys, taskbar buttons, tray icon with the mini player.
8. Equalizer and spectrum (port of the DSP, tests on the Mac), the EQ panel, the display's meter.
9. Jellyfin: sign-in, Credential Manager, browsing by `Path`, streams.
10. Output devices on the display readout.
11. Skins and font sets.
12. Artwork: folder images, the user's choice, MusicBrainz + Cover Art Archive, the fix dialog, SMTC thumbnail.
13. Ambient: the six faces, OLED protection, glow, dimming, options.
14. Audio CD.
15. Update check, Terms and Privacy, `TERMS.md` and `CLAUDE.md` ("Other platforms"), README, the zip in the release.

## As built

- **Fonts**: WPF draws only a variable font's default instance, so Inter and DM Sans ship as static Regular and Medium instances (fontTools); IBM Plex Sans keeps its variable file, since its Reserved Font Name rules out a modified copy, and draws at Regular weight on Windows.
- **Locations** are strings, not `Uri`: `Uri` turns a file named "a%20b" into "a b".
- **Streams**: if Media Foundation won't open a Jellyfin URL itself, NuVa hands it the file over HTTP range requests (`HttpByteStream`, an IStream).
- **Menus**: the Mac's menu bar is one menu, opened from Alt, F10, the title bar's icon or a right-click on the window.
- **Not yet**: the lists aren't read row by row by Narrator (keys and controls are), so `screen-reader` stays `planned`; reopening where you left off is `planned` on the Mac too.

## Testing

On the Mac: the build and the Core tests (DSP, sorting, `AlbumGuess`, Jellyfin parsing, artwork rules). On Windows, by the friend: everything that touches Windows (audio, SMTC, devices, CD, the look), with the log and `--selftest` coming back to the author. The zip is left in `windows/dist/` for the author to pass on, and later goes on the GitHub release.
