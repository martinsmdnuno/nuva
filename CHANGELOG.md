# Changelog

## 1.2 — audio CDs

- Plays audio CDs. Put a disc in the drive and NuVa plays it from the first track, like a CD player, whether NuVa is already open or opens with the disc in. The CD shows up as a source while it's in the drive.
- A CD carries no names, so NuVa looks up the disc on MusicBrainz by its table of contents and names the album and the tracks. Known discs are remembered and work offline. If the disc isn't found, it stays "Audio CD" and "1 Audio Track".
- With artwork on, the album cover comes from the Cover Art Archive.
- Eject with File › Eject CD (⌘E), the eject key in the browser or the source's menu.
- To open NuVa whenever a CD goes in: System Settings › CDs & DVDs › When you insert a music CD › Open other application › NuVa.

## 1.1.1

- Fixes a crash when an album cover was found (it was handed to Control Center on the wrong thread). This is also why artwork didn't appear in 1.1.

## 1.1 — skins, fonts and album artwork

- Skins: **Nuno** (the 1.0 look, light or dark with the system), **Graphite Orange** and **Graphite Green** (always dark). View › Skin, ⌥⌘1–3, or the new key in the mini player.
- Font sets: Inter + IBM Plex Mono or SF Pro + SF Mono (View › Font).
- Album artwork, off by default (View › Show Artwork, ⌥⌘A): the image in the folder, or found on MusicBrainz and the Cover Art Archive from the folder names. Never from tags. Shown small on the display, in the mini player and in Control Center. *Wrong or Missing Artwork…* fixes a cover or picks an image.
- Tells you when a new version is out (checks GitHub once a day, never downloads anything). NuVa › Check for Updates….
- Terms and privacy inside the app (NuVa › Terms and Privacy).
- Better contrast in both Nuno themes; the Aluminium amber is a little darker.
- The mini player is as wide as the main window (360 pt).

## 1.0 — first public release

- Plays folders as they are: a folder is an album, names stay untouched.
- Sources: a folder on the Mac or a network drive, and Jellyfin servers.
- Native audio engine (AVFoundation), FLAC included, AirPlay 2 output.
- Queue, repeat, shuffle, 10-band equalizer with presets.
- Media keys, Now Playing, menu bar mini player when the window is closed.
- Dieter Rams–style interface in two themes (Lead and Aluminium), three window sizes, vertical resize.
- English and Portuguese, following the system language.
