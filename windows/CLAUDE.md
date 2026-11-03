# NuVa for Windows

The root `CLAUDE.md` holds for this app too: its principles, the parity matrix and the release. This file only adds what is different on Windows. The plan and its history are in `docs/plans/windows.md`.

## Principles, as they apply here
1. **Folders, not metadata.** Local folders, mapped drives and network shares (`\\server\share`) by path; Jellyfin by each item's `Path`, as `JellyfinSource.swift`. Names as they are, natural sort (`NaturalComparer`, the counterpart of `localizedStandardCompare`). Tags are never read.
2. **Native audio.** The platform's own engine: Media Foundation's Source Reader decodes (Windows' own FLAC, ALAC, MP3, AAC and WAV decoders) and `Windows.Media.Audio.AudioGraph` plays on the Windows audio engine. AIFF and CD audio are plain PCM that NuVa reads itself. No NAudio, VLC, ffmpeg, BASS or any other audio library. The stream is the original file (`stream.<ext>?static=true`).
3. **One small window.** The Mac's layout and sizes (360 to 480 wide, three modes). Ambient is a borderless full-screen window; closing the main window leaves NuVa in the notification area with its mini player.
4. **Keyboard first.** The Mac's shortcuts with Ctrl for ⌘ and Ctrl+Shift for ⌥⌘ (never Ctrl+Alt: it is AltGr on Portuguese keyboards). Media keys and the lock screen through the system media controls (SMTC). The menu bar's items open from Alt, F10, the title bar's icon or a right-click.
5. **Pluggable sources.** `LocalSource`, `JellyfinSource`, `DiscSource`; the player knows only entries and location strings (a path, a URL, `cdda://D/3`).

## Code
- C# on .NET 10 with WPF, target `net10.0-windows10.0.19041.0` (Windows 10 2004 and later). No NuGet packages: WinRT comes from the SDK's projection, COM is called through vtables (`Audio/MediaFoundation.cs`), Win32 through P/Invoke.
- `NuVa.Core` (`net10.0`, no Windows APIs, tested on any OS): `Audio/` (`Pipeline`: the decoder thread, gapless, the tap; `Equalizer`, `Spectrum`, `AiffDecoder`), `Player/` (`PlayerController`, meters, `VUNeedle`, `ArtworkGlow`), `Library/` (sources, `AlbumGuess`, artwork, discs), `Skin`, `Settings`, `Strings` (`L`), `Updates`.
- `NuVa` (WPF): `Audio/` (Media Foundation, `GraphOutput`, the CD drive, the HTTP byte stream), `App/` (`AppModel`, durations, artwork store, Credential Manager), `System/` (SMTC, tray), `UI/` (one file per area, every element drawn to the tokens; no XAML), and the `App.*.cs` partials per feature.
- A Mac change to shared logic (EQ, spectrum, artwork rules, Jellyfin parsing, disc IDs) is ported to `NuVa.Core` in the same spirit, with the matching test in `NuVa.Core.Tests`.

## Design
- Same design system as the Mac (`docs/design-system/`): read it before UI work. Every skin's value for every token is in `NuVa.Core/TokenPalettes.cs`, written by `scripts/tokens.swift` from `docs/design-system/tokens.json` (never by hand); `Skin.cs` reads it. Rams follows Windows' app mode (Aluminium light, Lead dark).
- Fonts embedded (OFL). WPF draws only a variable font's default instance, so Inter and DM Sans are static Regular and Medium instances made with fontTools; IBM Plex Sans keeps its variable file (its Reserved Font Name forbids a modified copy) and draws at Regular. SF Pro + SF Mono becomes Segoe UI + Cascadia Mono.
- Icons are NuVa's own vectors after the SF Symbols (`UI/Icons.cs`, as `android/…/ui/Icons.kt`).
- Text: the Portuguese is the key, its English in `NuVa.Core/Strings.json`; `StringTests` fails on a key without English.

## Build and test
- `brew install dotnet` (the .NET 10 SDK). Everything builds on the Mac (`EnableWindowsTargeting`).
- `dotnet run --project windows/NuVa.Core.Tests` and `dotnet build windows/NuVa/NuVa.csproj` after each step; fix errors before moving on.
- Running needs Windows. There is no Windows machine for development: a tester installs the zip. What only Windows can tell goes to `%LOCALAPPDATA%\NuVa\nuva.log` (the last two runs), and `NuVa.exe --selftest [file]` checks Media Foundation, the decoder, AudioGraph and the output devices and shows the result.

## Release
- The version comes from `MARKETING_VERSION` in `project.yml`; never set it here.
- `scripts/make-windows-zip.sh` runs the Core tests and writes `dist/NuVa-Windows-X.zip` and `dist/NuVa-Windows.zip`: one self-contained `NuVa.exe` for x64 (nothing to install), the licences and a read-me. Unsigned, so SmartScreen asks once ("More info ▸ Run anyway").
- The update notice looks for `NuVa-Windows-<version>.zip` in `releases/latest`.
- Windows joins the release when its `status` in `docs/features.json` is `released` (and `public`), after the tester confirms the build; then run `swift scripts/content.swift`.
- When a feature lands or changes here, set its `windows` status in `docs/features.json` and run `swift scripts/content.swift`.
