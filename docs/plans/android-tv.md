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
- **Keys**: mode | previous, play/pause, next | ambient, settings. One mode key moves through normal, shuffle, repeat all and repeat one, its name under it (the Mac keeps shuffle and repeat apart). Same three tones as `KeyButtonStyle`; focus is the `focus` ring.
- **Queue and folders**: two tabs at the top of the right column, each with its LED; OK on one shows it, and Back from a list goes to them.
- **Display**: format (FLAC 24/96 when known), title, folder, elapsed time in IBM Plex Mono Light, the position bar.
- **Position and quality**: the position bar takes the focus; OK holds it, ← → move 10 s a press (faster held), the track goes there when the key is let go, OK keeps it and Back goes back. In ambient, ↓ holds it. Every face has the bar. The quality badge ("FLAC 905 kbps | 16-bit/44.1 kHz", compact on the player's display) takes the bitrate from the file's size over its length (Jellyfin's `MediaSources`), as the Mac and Windows do.
- **Ambient**: the Display face full screen, entered with a key or after a minute without input while playing; any key leaves. OLED protection: a slow wander and the 55% rule for static parts. The other faces (Spectrum, Meters, Needles, Valves) need the audio's levels; they come in a later version with Media3's audio processor.
- **Playback**: gapless through Media3's playlist, keeps playing with the screen off or in another app, Now Playing on the TV's media controls.

- **Artwork**: the image file in the album's folder on the server first (`cover`, `folder`, `front`, `album`, `capa` · jpg/jpeg/png, as on the Mac; only an image whose file Jellyfin reports in that folder, never one from the tags or downloaded by Jellyfin), then MusicBrainz + Cover Art Archive by the folder names. Settings shows where the playing album's cover came from; each album's steps go to the log (`NuVa.Artwork`); a lookup that couldn't reach the server or the internet is tried again a minute later. On every ambient face, with the glow of its colours behind; without a cover, a glow in the skin's own light. The glow breathes with the bass and drifts slowly, playing or paused.

Later: the equalizer and the meters (a Media3 `AudioProcessor` measuring after the filters), Google Cast to a WiiM, more sources.

## Parity with the Mac (0.2)

- **Sound**: a tap in front of the audio output (`TapSink`) runs the 10-band equalizer (same bands, range and presets, biquads in double precision with pre-gain) and measures the 10 bands, the 28 fine bands and L/R RMS and peak 120 times a second, with two FFT sizes for the bass (`SpectrumAnalyzer`, a port of `Spectrum.swift`). Measurements carry the output clock's time, read from the audio sink's own position, so the meters show what is heard. It sits in front of the sink rather than as a Media3 audio processor because those are skipped for 24-bit sources played in float. With the equalizer off and no meter on screen, blocks pass untouched.
- **Display**: format, artist and album from the folders ("Fleetwood Mac · Rumours (1977)"), the EQ readout that opens the equalizer, the 10-band LED meter, the cover when artwork is on. Long names slide (on the display always, in lists with focus).
- **Equalizer**: ← → bands, ↑ ↓ half a decibel, eight presets, on/off with its LED.
- **Ambient**: all six faces (Display, Clock, Spectrum, Meters, Needles with `VUNeedle`, Valves), ← → faces, OK play/pause, ↑ ↓ or Back leave; OLED protection (wander, 55% static parts, blinking colon, a new face every 20 minutes, rest after an hour), dim, dimming after 10 minutes paused, the cover's glow (breathing with the bass on the Display face).
- **Artwork**: online from the folder names only (`AlbumGuess`, MusicBrainz + Cover Art Archive, confident matches, misses remembered 14 days), in the app's own files; also in Now Playing.
- **Skins and fonts**: Rams (Lead), Graphite Orange, Phosphor; the five font sets (SF becomes Roboto).
- **Queue**: hold OK on a folder or track to add it; hold OK on a queue row to move it, remove it or clear the queue. Repeat (all, one) and shuffle.
- **Settings** (the Mac's View menu): skin, font, artwork, spectrum, ambient face, OLED, dim, ambient after a minute idle, check for updates (GitHub, a notice only), Terms and Privacy (TERMS.md, bundled), sign out.
- **Leaving**: Back closes what's open, goes up a folder, then asks before leaving; the music keeps playing. Reopening brings back the last queue, paused where it was, and the last folder.
- Not on the TV: local folders, CDs, AirPlay out, the menu bar and window modes, the volume knob (the TV's volume is the remote's).

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
- Releases: from 1.11 the Android TV app shares the Mac's version number (`MARKETING_VERSION` in `project.yml`; versionCode 1.11 → 11100) and its GitHub release. `scripts/make-apk.sh` builds the release APK (R8-minified) signed with the release key, which stays on the author's Mac (`~/.android/nuva-release.jks`, password in the Keychain, a backup kept apart), never in the repository. A build signed with another key (the debug builds before 1.11) has to be uninstalled once before the signed one installs.
- On the box: the Downloader app, `nuva.martinsnuno.com/tv` (a redirect to `releases/latest/download/NuVa-AndroidTV.apk`).

## Google Play (later)

- A Play developer account (one-time fee, identity check). A new personal account has to run a closed test with at least 12 testers for 14 days before it can publish.
- An Android App Bundle (`bundleRelease`) with the target SDK Google requires that year, the TV banner, screenshots at 1920×1080, the privacy policy URL, the Data safety form and the content rating.
- Play App Signing can take this same release key ("use an existing key"), so the GitHub APK and the Play version stay interchangeable.
- Google reviews TV apps separately (D-pad everywhere, no touch, a Leanback launcher entry), and needs a way in: a demo Jellyfin server and account for the reviewers.
- Apps on Play may only update through Play, so a Play build drops the GitHub update notice.
