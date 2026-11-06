# NuVa for Android TV

The root `CLAUDE.md` holds for this app too: its principles, the parity matrix and the release. This file only adds what is different on Android. The plan and its history are in `docs/plans/android-tv.md`.

## Principles, as they apply here
1. **Folders, not metadata.** Jellyfin is browsed by each item's `Path`, as `JellyfinSource.swift` does on the Mac: the server's real folders, names as they are, natural sort. Never Jellyfin's artists or albums.
2. **Native audio.** The platform's own engine: AndroidX Media3 (ExoPlayer) with Android's system decoders (FLAC from API 27, so `minSdk` 27). No VLC, no ffmpeg, no extension decoders. The stream is the original file (`/Audio/{id}/stream.<ext>?static=true`); 24-bit stays whole (`setEnableAudioFloatOutput`).
3. **Two screens, no deep navigation.** The folders, the whole screen, with a "now playing" bar at the foot; playing opens the player (cover, title, time, keys, the glow behind), and Back goes back to the folders. The queue, the equalizer and the settings open from the menu key (☰) as panels.
4. **Remote first.** D-pad and OK for everything; play/pause, next and previous always work, also from other apps, through `PlaybackService` (a `MediaSessionService`).
5. **Pluggable sources.** Jellyfin only (a TV box keeps no music). The player knows only entries and URLs.

## Code
- Kotlin, Jetpack Compose for TV (`androidx.tv:tv-material`), Media3; package `pt.nunomartins.nuva`.
- `audio/`: `TapSink` sits in front of the audio output and runs `Equalizer` and `Spectrum` (ports of the Mac's `Equalizer.swift` and `Spectrum.swift`: same bands, presets and FFTs). Media3 audio processors are skipped for 24-bit float sources, which is why the tap is in the sink.
- `library/`: `JellyfinSource`, `Entry`, `Account`. `artwork/`: `AlbumGuess` rules as on the Mac, folder names only. `player/`: `PlayerModel`, `PlaybackService`. `ui/`: one file per area. `Palettes.kt` (every theme's value for every token) is written by `scripts/tokens.swift` from `docs/design-system/tokens.json`; `Theme.kt` picks a palette per skin.
- A Mac change to shared logic (EQ, spectrum, artwork rules, Jellyfin parsing) is ported here in the same spirit, with the matching unit test.

## Design
- Same design system as the Mac (`docs/design-system/`): read it before UI work. Lead only; the skins change colours only.
- Sizes for 10-foot viewing: twice the Mac's points, in dp, on a 960×540 dp canvas. Focus is the `focus` ring.
- Fonts bundled (OFL); SF becomes Roboto in the font sets.
- Text in English (`res/values/strings.xml`, the default) and European Portuguese (`res/values-pt/strings.xml`). Every new string goes in both (`scripts/strings.swift` checks it); text that isn't translated, like the app's name, is `translatable="false"`.

## Build and test
- JDK 17 (`/opt/homebrew/opt/openjdk@17`) and the Android SDK (`~/Library/Android/sdk`).
- `cd android && JAVA_HOME=/opt/homebrew/opt/openjdk@17 ./gradlew assembleDebug testDebugUnitTest` after each step; fix errors before moving on.
- The emulator is the AVD `nuva_tv` (Android TV, API 33), against a stand-in Jellyfin. The author's box can't do ADB: on the box, install with the Downloader app from `nuva.martinsnuno.com/tv`.
- Never type the author's real Jellyfin password; ask them to sign in.

## Release
- The version comes from `MARKETING_VERSION` in `project.yml` (1.11 → versionCode 11100); never set it here.
- `scripts/make-apk.sh` builds the signed release APK; `scripts/release.sh` runs it with the Mac's build, in the same GitHub release. The release key stays on the author's Mac (`~/.android/nuva-release.jks`, password in `~/.android/nuva-release.password`, both backed up outside the repository), never in the repository. The key was replaced in 1.14 (the old one's password was lost), so a 1.13 install must be removed once before 1.14 goes on.
- When a feature lands or changes here, set its `tv` status in `docs/features.json` and run `swift scripts/content.swift`.
