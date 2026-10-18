# NuVa

Native macOS app in SwiftUI that plays music from folders. Winamp-like simplicity, clean hi-fi visual language (Braun/Dieter Rams, Cambridge Audio, B&O). Utility first, not design first.

## Why
- The Jellyfin app for Mac is weak; other apps scramble the library because of metadata (remixes, covers, mixes scattered around).
- Apple Music doesn't open FLAC; the library is FLAC.
- VLC sounds bad over Bluetooth headphones; QuickTime doesn't. Use Apple's native audio engine.
- It must be able to send the sound to a WiiM (AirPlay 2).

## Principles (non-negotiable)
1. **Folders, not metadata.** Folder = album. Show folder and file names exactly as they are. Never read tags to organise.
2. **Native audio.** AVFoundation (`AVQueuePlayer`). No VLC, no ffmpeg, no third-party audio libraries.
3. **One small window.** No deep navigation.
4. **Keyboard first.** Media keys, shortcuts, `MPRemoteCommandCenter` and `MPNowPlayingInfoCenter`.
5. **Pluggable sources.** The app plays from "sources". Each source is a folder tree: Local (a folder on the Mac, including mounted SMB shares), Jellyfin, and later a generic HTTP server. The player doesn't know where the music comes from.

## Architecture
```swift
protocol MusicSource {
    var id: UUID { get }
    var name: String { get }
    func list(_ path: String) async throws -> [Entry]   // folders and tracks
    func url(for track: Entry) async throws -> URL      // file:// or https://
}
```
- `LocalSource` returns `file://`. Keeps folder access with a security-scoped bookmark.
- `JellyfinSource` signs in with username and password (Keychain), browses by the items' `Path` (the disk folders, never Jellyfin's tags) and plays the original with `/Audio/{id}/stream.<ext>?static=true`.
- `ServerSource` (generic HTTP server) is still only the protocol and a stub.
- Playable extensions: flac, mp3, m4a, aac, alac, wav, aiff.
- Track order: natural sort by file name (`localizedStandardCompare`).

## Scope
In:
- Local sources (NSOpenPanel) and Jellyfin, remembered between launches.
- Browse folders, play a folder, queue (add, remove, reorder).
- Play/pause, previous, next, seek, volume, repeat, shuffle.
- Media keys and macOS Now Playing.
- AirPlay key (`AVRoutePickerView` wrapped in `NSViewRepresentable`).
- Windows: "Player with queue" (360 × 480 or taller), "With browser" (720 × 480 or taller) and "Compact" (display, keys and volume only; ⌘3). Height is free in the first two.
- Skins (View ▸ Skin, ⌥⌘1, ⌥⌘2…, and a key in the mini player): colours only, same layout and sizes. Default "Nuno" (the 1.0 look). Plan in `docs/plans/skins-and-artwork.md`.
- The folder drawer opens and closes with the folders key in the queue header, the key in the drawer header, or ⌘B.
- Closing the window doesn't stop the music: the app leaves the Dock and stays in the menu bar with a mini player.
- Album artwork (View ▸ Show Artwork, ⌥⌘A; off by default), never from tags. Order: an image file in the folder (`cover`, `folder`, `front`, `album`, `capa` · jpg/jpeg/png; a disc folder also looks in its album folder), then the user's choice for that folder, then online: artist and album inferred from the folder names (`AlbumGuess`), MusicBrainz + Cover Art Archive, confident matches only. The one fallback is "Wrong or Missing Artwork…" (search again with corrected names, choose an image, or no artwork). Covers live in Application Support, never in the user's folders. Small, inside the display and the mini player, not in Compact; also in Now Playing. Online lookup is the one agreed exception to "no online lookups".
- Update check: GitHub `releases/latest` at launch (at most daily) and NuVa ▸ Check for Updates…; an alert only, never downloads.
- Terms and privacy: `TERMS.md` (EN + PT), bundled and shown in NuVa ▸ Terms and Privacy. Update it whenever the app gains a network call.
- 10-band equalizer with presets, in an `MTAudioProcessingTap` on each `AVPlayerItem` (Accelerate biquads).

Out (for now): generic server source, search, favourites, accounts.

## Design system
In `docs/design-system/`. Read `README.md` and `tokens.json` before any UI work, and the component's file in `components/` before building it.
- Colours: one `Color` per token in `Assets.xcassets` (Any variant = Aluminium, Dark = Lead), named like the tokens.
- Type: Inter and IBM Plex Mono embedded in the app (OFL, Google Fonts files); falls back to SF Pro/SF Mono if missing. Font sets (View ▸ Font): Inter + Plex Mono or SF Pro + SF Mono; text styles are computed `Font.ds…` properties that read the current set, so never use `Typography.sans/mono` directly in views.
- Dieter Rams language in Lead: one plane, no cards or outlines, hierarchy from key colour, state shown by LEDs.
- Keys: a single `ButtonStyle` (`KeyButtonStyle`) with three tones: play, transport, mode.
- Interface text in European Portuguese and English, following the system language (English fallback). The Portuguese text is the key in `Resources/Localizable.xcstrings`; every new string gets its English translation there. Text that goes through `String` (ternaries, parameters, model) uses `String(localized:)`.

## Stack and conventions
- Swift 6, SwiftUI, macOS 14+. Project generated with XcodeGen (`project.yml`); don't edit the `.xcodeproj` by hand.
- No external dependencies.
- Folders: `App/`, `Sources/Player/`, `Sources/Library/`, `Sources/UI/`, `Sources/DesignSystem/`.
- Build with `xcodebuild` after each step and fix errors before moving on.
- Small commits, one per step. Code comments, docs and commit messages in English (the repository is public).

## Releases
- Bump `MARKETING_VERSION` in `project.yml`, commit "Version X", run `scripts/make-dmg.sh` (writes `dist/NuVa-X.dmg` and `dist/NuVa.dmg`).
- Tag `vX`, push, `gh release create vX dist/NuVa.dmg dist/NuVa-X.dmg`, and add the version to `CHANGELOG.md`.
- `releases/latest/download/NuVa.dmg` is the fixed download link in the README.
- README images: `NuVa --snapshot -AppleLanguages '(en)'` from a Debug build, then `swift scripts/make-readme-images.swift <snapshot folder> docs/screenshots`.
