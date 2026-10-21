# Plan: audio CDs

Status: in progress.
Input: the user has a CD drive connected to the Mac and wants NuVa to play a CD when one is inserted.

## How macOS shows an audio CD

An audio CD mounts as a volume (`cddafs` file system) in `/Volumes/<name>`: one `N Audio Track.aiff` file per track (AVFoundation plays them like any AIFF) and a hidden `.TOC.plist` with the disc's table of contents. The volume name is "Audio CD" unless the disc has CD-Text.

## Decisions

1. **The CD is a source.** `DiscSource` (kind `.cd`) is a `MusicSource` like the others; the player doesn't know the music comes from a disc. It appears in the source list while the disc is in the drive and is never saved.
2. **Names from MusicBrainz, by disc.** A CD has no folder or file names to respect, so this is the second agreed exception to "no online lookups": NuVa computes the MusicBrainz disc ID from `.TOC.plist` and asks MusicBrainz for the release (artist, album, track titles), with the TOC as a fuzzy fallback. The answer is cached in Application Support by disc ID. No answer (offline, unknown disc): "Audio CD" and "1 Audio Track"…
3. **One folder per disc.** The source root holds a single folder named "Artist – Album" (or the volume name) with the tracks inside, so the display, `AlbumGuess` and the artwork key work as for a folder.
4. **Artwork** from the Cover Art Archive by release, only with Show Artwork on.
5. **Inserting a disc plays it.** The queue is replaced by the CD and playback starts, like a CD player. Also at launch, when macOS opened NuVa because a disc was inserted.
6. **Eject.** A key next to the CD in the source list and View/Controls ▸ Eject CD (⌘E). Ejecting, or the disc going away, removes its tracks from the queue.
7. **Opening NuVa when a CD goes in** is a macOS setting the user chooses: System Settings ▸ CDs & DVDs ▸ When you insert a music CD ▸ Open other application ▸ NuVa. NuVa never changes it.

## Sandbox

Reading `/Volumes` needs the read-only temporary exception `com.apple.security.temporary-exception.files.absolute-path.read-only` for `/Volumes/`. NuVa only lists volumes whose file system is `cddafs`.

## Steps (one commit each, `xcodebuild` after each)

1. `DiscSource`, `DiscWatcher` (mount/unmount notifications + scan at launch), entitlement, autoplay.
2. Disc ID from the TOC, MusicBrainz lookup and cache, names and artwork.
3. Eject key and ⌘E, strings (PT + EN), `TERMS.md`, README and `CLAUDE.md`.
4. Tests (disc ID, names), check with a real disc.
