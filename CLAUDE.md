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
5. **Pluggable sources.** The app plays from "sources". Each source is a folder tree: Local (a folder on the Mac, including mounted SMB shares), Jellyfin, an audio CD in the drive, and later a generic HTTP server. The player doesn't know where the music comes from.

## Other platforms
Each platform has its own `CLAUDE.md` next to its code, with how the principles apply there, its stack, build and test. It shares the principles and the design system, not the code, and extends a principle to its platform without changing it for the Mac.
- **Android TV**: `android/` (`android/CLAUDE.md`, plan in `docs/plans/android-tv.md`). Media3 with Android's system decoders.
- **Windows**: `windows/` (`windows/CLAUDE.md`, plan in `docs/plans/windows.md`). Media Foundation decodes with Windows' own decoders and AudioGraph plays. It joins the release when it is `released` in `docs/features.json`, after a tester confirms the build.

## Parity and content
- `docs/features.json` is the one list of what NuVa does on each platform: `yes`, `planned`, or `n/a` with a `why`. The Mac is the reference; a new feature lands as `yes` on the Mac and `planned` elsewhere, so a gap is always written down. An `n/a` says how a principle applies on that platform, never changes the principle.
- The README, the site and `llms.txt` carry generated blocks between `<!-- nuva:NAME -->` and `<!-- /nuva:NAME -->` (downloads, requirements, the "which app does what" table, the site's version line and JSON-LD `operatingSystem`/`softwareVersion`). Edit `docs/features.json`, then `swift scripts/content.swift`; never edit inside a block by hand. The prose around the blocks stays hand-written.
- `scripts/check-content.sh` fails on a stale block, a bad matrix entry, a changelog whose newest entry is older than the current version (or has none for it), a download link no release carries, a build script or `gh release create` line that misses an asset, or terms that don't name a released platform in both languages.
- A feature is done when: the matrix is updated, the README and site prose say it (both languages), the screenshots are regenerated, the `CHANGELOG.md` has it, and `scripts/check-content.sh` passes.

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
- `DiscSource` is an audio CD while it is in the drive (cddafs volume in `/Volumes`, never saved): one folder named "Artist – Album", tracks named from MusicBrainz by disc ID (`DiscTOC`, `DiscLookup`, cached in Application Support), else the volume's "Audio CD" / "1 Audio Track". `DiscDrive` watches mounts; inserting a disc (or launching with one in) replaces the queue and plays it. Eject CD ⌘E. Plan in `docs/plans/audio-cd.md`.
- `ServerSource` (generic HTTP server) is still only the protocol and a stub.
- Playable extensions: flac, mp3, m4a, aac, alac, wav, aiff.
- Track order: natural sort by file name (`localizedStandardCompare`).

## Scope
In:
- Local sources (NSOpenPanel) and Jellyfin, remembered between launches.
- Browse folders, play a folder, queue (add, remove, reorder).
- Play/pause, previous, next, seek, volume, repeat, shuffle.
- Media keys and macOS Now Playing.
- AirPlay from the output readout on the display (`AVRoutePickerView` wrapped in `NSViewRepresentable`, stretched over the text). Keys: mode | playback | volume knob, play on the centre line; the equalizer opens from "EQ · preset" on the display (⌥⌘E).
- One window, 360 to 480 wide (free width, remembered): "Player with queue" (⌘1), "Player with folders" (⌘2, the browser in the queue's place) and "Compact" (display and keys only; ⌘3). Height is free in the first two (minimum 540).
- Skins (View ▸ Skin, ⌥⌘1, ⌥⌘2…, and a key in the mini player): colours only, same layout and sizes. Default "Rams" (the 1.0 look, called "Nuno" up to 1.4). Plan in `docs/plans/skins-and-artwork.md`.
- ⌘B or the folders key in the header swaps queue and folders. With the folders, the header row holds the browser's keys (up, Play Folder, eject); playing from them brings the queue back.
- Ambient mode (View ▸ Ambient, ⌘4; also in the mini player's view key): a full-screen window, in its own Space, that is all display, in the current skin. Faces Display, Clock, Spectrum (28 bands, 20 Hz–20 kHz), Meters (L/R from the tap), Needles (backlit VU meters) and Valves (filaments glowing with each channel), ← →; always the skin's dark colours; with artwork on, a blurred field of the cover's own colours behind the face (`ArtworkGlow`, dark enough for 4.5:1), breathing with the bass on the Display face; meters drawn at the screen's rate (120 Hz), Needles with a real VU movement (`VUNeedle`); Esc or ⌘4 to leave; View ▸ Ambient Options for the face, dimming, OLED Protection and the screen. Keeps the display awake while playing. OLED Protection (on by default): a slow wander over 8% of the screen, static parts at 55%, a blinking colon, a new face every 20 minutes, and rest (only the LED) after an hour without a key or the mouse. Plan in `docs/plans/ambient.md`.
- Closing the window doesn't stop the music: the app leaves the Dock and stays in the menu bar with a mini player.
- Album artwork (View ▸ Show Artwork, ⌥⌘A; off by default), never from tags. Order: an image file in the folder (`cover`, `folder`, `front`, `album`, `capa` · jpg/jpeg/png; a disc folder also looks in its album folder), then the user's choice for that folder, then online: artist and album inferred from the folder names (`AlbumGuess`), MusicBrainz + Cover Art Archive, confident matches only. The one fallback is "Wrong or Missing Artwork…" (search again with corrected names, choose an image, or no artwork). Covers live in Application Support, never in the user's folders. Small, inside the display and the mini player, not in Compact; also in Now Playing. Online lookup is one of the two agreed exceptions to "no online lookups"; the other is an audio CD's names.
- Update check: GitHub `releases/latest` at launch (at most daily) and NuVa ▸ Check for Updates…; an alert only, never downloads.
- Terms and privacy: `TERMS.md` (EN + PT), bundled and shown in NuVa ▸ Terms and Privacy. Update it whenever the app gains a network call.
- 10-band equalizer with presets, in an `MTAudioProcessingTap` on each `AVPlayerItem` (Accelerate biquads).
- Spectrum meter on the display (View ▸ Show Spectrum, ⌥⌘V; on by default): the same tap measures the 10 EQ bands with an FFT after the filters, tagged with track time so it matches what is heard (also over AirPlay). LED segments in the Braun deck style. Spec in `docs/design-system/components/Spectrum.md`.

Out (for now): generic server source, search, favourites, accounts.

## Design system
In `docs/design-system/`. Read `README.md` and `tokens.json` before any UI work, and the component's file in `components/` before building it.
- Colours: one `Color` per token in `Assets.xcassets` (Any variant = Aluminium, Dark = Lead), named like the tokens.
- Type: Inter, IBM Plex (Sans, Mono), DM Sans + DM Mono and Share Tech + Share Tech Mono embedded in the app (OFL, Google Fonts files); falls back to SF Pro/SF Mono if missing. Font sets (View ▸ Font, `FontSet`): Inter + Plex Mono (default), SF Pro + SF Mono, IBM Plex Sans + Plex Mono, DM Sans + DM Mono, Share Tech + Share Tech Mono; text styles are computed `Font.ds…` properties that read the current set, so never use `Typography.sans/mono` directly in views.
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
- Write the version's entry in `CHANGELOG.md` (`## X — title`, then the changes) and commit it with the work. Then, on main, `scripts/release.sh X`; `--dry-run` first does everything up to the commit and puts the files back.
- The script checks the tree, bumps `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml` (the Android TV app takes its version from it too), runs `scripts/update-site.sh`, `swift scripts/content.swift` and `scripts/check-content.sh`, and builds every released platform in `docs/features.json` with its `buildScript`: `scripts/make-dmg.sh` (`dist/NuVa-X.dmg`, `dist/NuVa.dmg`) and `scripts/make-apk.sh` (`dist/NuVa-AndroidTV-X.apk`, `dist/NuVa-AndroidTV.apk`, signed with the release key: `~/.android/nuva-release.jks`, password in the Keychain item `nuva-android-release`, never in the repository).
- Then it commits "Version X" and asks before going public: push, tag `vX`, `gh release create vX dist/NuVa.dmg dist/NuVa-X.dmg dist/NuVa-AndroidTV.apk dist/NuVa-AndroidTV-X.apk dist/NuVa-Windows.zip dist/NuVa-Windows-X.zip` (title and notes from the `CHANGELOG.md` entry, downloads from the matrix), the site's deploy (`NUVA_DEPLOY` in the git-ignored `scripts/release.local`), and a check that the download links and the site answer with X. Every release carries every released platform; the Android app's update notice looks for `NuVa-AndroidTV-<version>.apk` in `releases/latest`, the Windows app's for `NuVa-Windows-<version>.zip`. Windows is in the line, but `release.sh` builds and uploads it only once it is `released` in the matrix.
- A new platform joins the release by becoming `released` in `docs/features.json` with its `asset` and a `buildScript` that writes `dist/<asset>` and `dist/<asset with -X>`, and by adding its files to the `gh release create vX` line above.
- `releases/latest/download/NuVa.dmg` and `releases/latest/download/NuVa-AndroidTV.apk` are the fixed download links in the README; `nuva.martinsnuno.com/tv` redirects to the APK (for the Downloader app on a TV).
- README images: `NuVa --snapshot -AppleLanguages '(en)'` from a Debug build, then `swift scripts/make-readme-images.swift <snapshot folder> docs/screenshots`.

## Site
- nuva.martinsnuno.com, static, in `site/` (English at `/`, Portuguese at `/pt/`, privacy notice at `/privacy/` and `/pt/privacidade/`).
- Hosted on the author's Hetzner server behind its edge Caddy: `deploy/site/` (a Caddy that serves `site/` from the checkout and a stdlib Python service for `/api/feedback`, which emails the form through Gmail; secrets in `deploy/site/.env` on the server only). Publishing is `git pull` in `/opt/nuva`; the server's own runbook lives outside this repository.
- Same tokens and type as the app (Lead, Aluminium when the system is light; Inter and IBM Plex Mono subset to WOFF2 and served from the site). Images are WebP copies of `docs/screenshots`.
- EU rules: no cookies, no local storage, no analytics, no access log, nothing loaded from other hosts (the CSP enforces it). Any new third party or data use needs the privacy notice updated in both languages first.
- SEO and GEO: titles and descriptions, hreflang, JSON-LD (`SoftwareApplication` and `FAQPage`, kept equal to the visible FAQ), `sitemap.xml`, `robots.txt` and `llms.txt`.
