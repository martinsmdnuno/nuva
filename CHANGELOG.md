# Changelog

## 1.4 — a deck with a volume knob

- The keys now read like a deck: shuffle and repeat on the left, play in the middle of the window, and the volume as a knob on the right. Drag it up or down, scroll over it, or use ⌘↑ ⌘↓. The volume bar is gone, so the window is a row shorter and Compact mode smaller.
- AirPlay lives where the display says the sound is going: click "AirPlay WiiM" (or your speakers' name) to choose the output.
- The equalizer shows its preset beside the time ("EQ · Rock", with a light when it's on). Click it, or press ⌥⌘E (Controls › Equalizer…), to open the bands.

## 1.3 — spectrum meter, one small window

- A spectrum meter on the display: ten columns of amber segments, one per equalizer band, that move with what you hear. Measured after the equalizer and in step with the speakers, AirPlay included. View › Show Spectrum (⌥⌘V) hides it.
- The folders now take the queue's place below the keys instead of opening a drawer on the left. ⌘B or the folders key swaps the two; playing a folder brings the queue back. ⌘1 queue, ⌘2 folders, ⌘3 compact.
- The window can be widened from 360 to 480, for long file names. Width and height are remembered.
- The position bar shows the elapsed time and the duration at its ends; click the duration to see the time left.
- Keys travel when pressed, lights fade like filaments, and the display and lists change in place. Everything snaps with Reduce Motion.
- With the window open, the menu bar shows only macOS's Now Playing item; NuVa's mini player appears there when you close the window.

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
