# NuVa for Android TV

A NuVa for an Android TV box, to play the author's FLAC library from Jellyfin on the TV in the living room, and to be the room's hi-fi display. It lives in `android/`, next to the Mac app, and shares its principles and design system, not its code.

## Why Android first

- No paid certificate: an APK installs on any Android TV box and keeps working (an Apple TV build from a free account expires every 7 days).
- The APK can sit in the GitHub releases next to the DMG.
- The author's box is an Android box; the Apple TV version waits (see `apple-tv.md` when it exists).

## Principles, as they apply here

1. **Folders, not metadata.** Jellyfin is browsed by each item's `Path`, exactly as `JellyfinSource.swift` does on the Mac: the server's real folders, with folder and file names as they are, natural sort. Never Jellyfin's artists or albums.
2. **Native audio.** On Android "native" means the platform's own engine: AndroidX Media3 (ExoPlayer, Google's player for Android) with the system's decoders. FLAC is decoded by Android's own FLAC decoder (Android 8.1, API 27, and later), so `minSdk` is 27. No VLC, no ffmpeg, no extension decoders. The stream is the original file (`/Audio/{id}/stream.flac?static=true`): a FLAC stays a FLAC.
3. **One small screen.** The TV shows one device: the display on top, the keys, and below them the folders or the queue. No deep navigation.
4. **Remote first.** D-pad and OK for everything; the remote's play/pause, next and previous keys always work, also from other apps, through a `MediaSessionService`.
5. **Pluggable sources.** Version 0.1 has Jellyfin only (a TV box has no folders worth browsing). The player knows only entries and URLs, as on the Mac.

## First version (0.1)

- **Sign in** to a Jellyfin server: address, user, password, typed with the TV keyboard. The app keeps the server, the user and the access token (Jellyfin tokens don't expire), never the password. A 401 sends you back to sign in.
- **Folders**: the music library's folders by `Path` (more than one music library shows the libraries first). OK on a folder opens it; "Play Folder" plays it from the top; OK on a track plays the folder from that track.
- **Queue**: the folder that is playing, with the playing track in `signal` and its LED.
- **Keys**: shuffle, repeat | previous, play/pause, next. Same three tones as `KeyButtonStyle`; focus is the `focus` ring.
- **Display**: format (FLAC 24/96 when known), title, folder, elapsed time in IBM Plex Mono Light, the position bar.
- **Ambient**: the Display face full screen, entered with a key or after a minute without input while playing; any key leaves. OLED protection: a slow wander and the 55% rule for static parts. The other faces (Spectrum, Meters, Needles, Valves) need the audio's levels; they come in a later version with Media3's audio processor.
- **Playback**: gapless through Media3's playlist, keeps playing with the screen off or in another app, Now Playing on the TV's media controls.

Later: the equalizer and the meters (a Media3 `AudioProcessor` measuring after the filters), artwork from folder images, Google Cast to a WiiM, more sources.

## Design

- Lead only: a TV is a dark room, and the display is always dark anyway. Tokens from `docs/design-system/tokens.json`, as Compose colours.
- Inter and IBM Plex Mono, bundled (OFL).
- Sizes for 10-foot viewing: everything at twice the Mac's points, in dp, on a 960×540 dp canvas.
- Text in English and European Portuguese, following the system language.

## Build and install

- Kotlin, Jetpack Compose for TV (`androidx.tv:tv-material`), Media3. Gradle wrapper in `android/`.
- Needs JDK 17 and the Android SDK (`brew install openjdk@17 android-commandlinetools`, then `sdkmanager "platforms;android-35" "build-tools;35.0.0" platform-tools`). `cd android && JAVA_HOME=/opt/homebrew/opt/openjdk@17 ./gradlew assembleDebug testDebugUnitTest` writes `app/build/outputs/apk/debug/app-debug.apk`.
- Playback keeps 24-bit files whole: ExoPlayer asks the system's FLAC decoder for float PCM (`setEnableAudioFloatOutput`), which it otherwise cuts to 16 bits.
- Tested on the Android TV emulator (API 33) against a stand-in Jellyfin with a 24/96 and a 16/44.1 FLAC: sign-in, folders by Path, remote focus, gapless playback through `c2.android.flac.decoder`, the remote's play/pause, ambient in and out.
- Install on the box over the network: on the box, Settings › Device Preferences › About › Build (press OK seven times), then Developer options › Network debugging; then `adb connect <box IP>:5555` and `adb install -r app-debug.apk`.
- Or copy the APK to the box with a USB stick or the Downloader app.
- Releases: a signed APK attached to the GitHub release. The signing key stays on the author's Mac, never in the repository.
