# Changelog

## 1.12 — the artist, and names that scroll

- Mac and Windows: the display, the mini player and the ambient faces show the artist's folder beside the album's ("Fleetwood Mac · Rumours (1977)"), as the TV app does. A disc folder ("CD 2") gives way to its album. Control Center and the Windows media controls get the artist too. Still folders, never tags. A library folder such as "Music" is never taken for the artist.
- Mac and Windows: the equalizer's scale lines are drawn in the skin's line colour; in Phosphor they were blue.
- Mac: a folder name too long for the display's line now scrolls across it, back and forth with a rest at each end, instead of being cut off. The output readout ("AirPlay") always keeps its room. With Reduce Motion the name is truncated, as before, and the full path is in the tooltip.
- Mac: pressed keys and the display's edge take their shade from the skin's colours.

## 1.11 — NuVa on the TV

- **NuVa for Android TV**, a new app for an Android TV box or a TV with Android TV (Android 8.1 or later), in the same release as the Mac app: `NuVa-AndroidTV-1.11.apk`. It plays your Jellyfin server by its real folders, FLAC included (24-bit kept whole), through Android's own player and decoders, and has what the Mac has where a TV allows: the display with the spectrum, the 10-band equalizer, the queue, repeat and shuffle, the six ambient faces with OLED protection, album artwork with the cover's glow, the three skins and five font sets, Terms and Privacy and the update notice. The remote does everything: hold OK to add to the queue or to move and remove; Back asks before leaving; it reopens where you were. Install it with the Downloader app: `nuva.martinsnuno.com/tv`.
- **NuVa for Windows**, added to the 1.11 release on 3 November: `NuVa-Windows-1.11.zip`, for Windows 10 (2004) or 11. The Mac app's scope except AirPlay (the display lists the PC's output devices instead): folders, network shares, Jellyfin and audio CDs, FLAC through Windows' own decoders (Media Foundation), the equalizer and spectrum, the queue, the window sizes, all six ambient faces, artwork, skins and font sets, the system media controls and a tray mini player. Unzip and open NuVa.exe.
- From now on the Mac, Android TV and Windows apps share a version number and a release.
- Mac: Terms and Privacy cover the Android TV app.

## 1.10.1 — real needles, the cover's colours

- **Needles** move like a real VU meter: a damped spring that reaches a steady tone in 300 ms, overshoots by a hair and rests on its pin left of -20, on a scale proportional to voltage. Tapered needles cast a shadow on the dial, under glass.
- Ambient mode draws at your screen's own rate, 120 Hz on a ProMotion Mac or a 120 Hz TV, and the sound is measured 120 times a second to match.
- **Spectrum**: the bass is measured over a longer window, so the lowest bars move on their own instead of together; peak caps hold, then fall faster and faster, like a hi-fi analyser's.
- The album glow is now made from the cover itself: its colours, in their places, blurred into a soft field behind the face. Every cover glows, dark and grey ones too. On the Display face it breathes with the bass (not with Reduce Motion).
- Album covers are found for artist folders with a title, such as "Ms. Lauryn Hill".
- Three new font pairs in **View › Font**, each chosen for a skin: IBM Plex Sans + Plex Mono (Rams), DM Sans + DM Mono (Graphite Orange) and Share Tech + Share Tech Mono (Phosphor, a digital readout). Skins keep their default type.
- Graphite Green is retired; if you used it, NuVa opens in Graphite Orange. Skins are now ⌥⌘1 to ⌥⌘3. Phosphor is called Phosphor in Portuguese too.

## 1.10 — smoother meters and the album's colour

- With artwork on, ambient mode takes on the album's colour: a soft glow in the cover's main hue, behind every face. It stays dark enough for the text to read, changes gently with the album, and a cover in black and white leaves the screen as it was.
- The Spectrum and Meters faces move smoothly: the sound is measured 60 times a second however the player delivers it, the bars rise and fall instead of jumping, and the Meters' last segment lights in part.
- Needles and Valves are bright again with the Mac in light appearance. Ambient mode now always uses the skin's dark colours, so the VU lamp is lit and the amber is the bright one. The valves glow stronger, with a halo and a white-hot filament when the music is loud.
- The README shows the ambient faces and the Phosphor skin.

## 1.9 — keyboard and VoiceOver

- New shortcuts: ⇧⌘→ and ⇧⌘← jump 10 seconds forward or back, ⌥⌘↑ and ⌥⌘↓ move the selected track in the queue (also Move Up and Move Down in its menu), and ⌥⌘⌫ clears the queue (Controls › Clear Queue).
- VoiceOver reads the keys by name with their light on or off, the position bar and the equalizer bands with their values (adjustable with VoiceOver), and each list row with its state, as one item.
- The folder browser says "Loading…" while a slow folder lists and "No music in this folder" when it's empty. Its error no longer repeats "Try again".
- Text keeps its contrast: with the equalizer off only the faders fade, and in ambient mode's OLED protection only lit areas that aren't text are dimmed.
- In ambient mode, ← → show the new face's name for a moment, and the keys stay while the pointer is on them.
- The README lists every shortcut.

## 1.8 — reliability

- When a track can't be played (a damaged file, a server that's offline or whose sign-in expired), NuVa tries it once more, then moves on to the next track and says on the display which one it couldn't play. Before, the music just stopped with no explanation. "Loading…" shows while a track opens from a slow server.
- Jellyfin signs in again by itself when a stream is refused, also while playing a queue without browsing.
- Removing a source also takes its tracks out of the queue. A CD that macOS refuses to eject stays in NuVa instead of disappearing.
- A folder on a disk or NAS that wasn't connected at launch comes back when the disk is mounted, or when you open it.
- Space and ⌘ with the arrows type in the text fields of the Jellyfin and artwork sheets instead of controlling playback. Keys that can't be used yet look faded.
- In ambient mode, ⌘← ⌘→ ⌘↑ ⌘↓ and ⌘. work with the main window closed.
- Uses less energy: ambient mode no longer redraws the screen continuously, the audio output is checked every 10 s instead of every second while paused, and the equalizer and spectrum do less work on every block of sound.

## 1.7 — needles, valves and a 28-band spectrum

- Two new ambient faces after classic hi-fi: **Needles**, two backlit VU meters with needles and a peak light (amber in Rams, pale green in Phosphor), and **Valves**, two valves in their cage whose filaments glow with each channel's level.
- The **Spectrum** face now has 28 bands from 20 Hz to 20 kHz, as solid bars with a peak line over each, and the position bar below.

## 1.6 — ambient mode for OLED screens, spectrum and meters

- **OLED Protection** in ambient mode, on by default (View › Ambient Options): the picture drifts slowly across the screen, the parts that hardly change are dimmer, the clock's colon blinks, the face changes every 20 minutes, and after an hour without touching a key or the mouse only a small light is left, wandering on black. Any key or the mouse brings it back.
- Two new ambient faces that move with the music: **Spectrum** (the ten equalizer bands, full screen) and **Meters** (left and right levels). Both follow the speakers, AirPlay included. ← → to switch.

## 1.5 — Phosphor and ambient mode

- New skin: **Phosphor** (Fósforo in Portuguese), after the shareware players of the late nineties. A black display with green text (the spectrum meter too), a blue-grey chassis, silver keys and a blue selected row. View › Skin, ⌥⌘4.
- **Ambient mode** (View › Ambient, ⌘4): the whole screen becomes NuVa's display, in the current skin, to leave the music playing as part of the room. Two faces, ← → to switch: **Display** (track, folder and time, large) and **Clock**. It can open on another screen or a TV (View › Ambient Options), keeps the screen awake while music plays and dims after 10 minutes paused. Esc or ⌘4 leaves.
- The default skin is now called **Rams** (it was Nuno). Nothing else changes, and your choice is kept.

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
