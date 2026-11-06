# Changelog

## 1.14 — the TV, made for the TV

- Android TV: two screens. The folders take the whole screen, with a "now playing" bar at the foot; playing a folder or a track opens the player, and Back (or its ‹ key) goes back to the folders. OK on the bar opens the player again.
- Android TV: the player fills the screen. A large cover, and beside it the title (level with the cover's top), the artist and album (both slide when they're too long) and the time (level with its foot), on one left edge. Under them the position bar, and the keys: the mode and its name on the left, previous · play · next centred under the time, ambient and the menu on the right.
- Android TV: the menu key (☰) opens the queue, the equalizer and the settings. The queue opens on the playing track; holding OK on a row moves or removes it, as before.
- Android TV: updating is one step. When there's a new version, the menu shows "Update to X": the app downloads it from the GitHub release and Android asks to confirm; your settings, sign-in and queue stay. The first time, Android asks you to let NuVa install apps.
- Android TV: the glow behind the player and the ambient faces is drawn at the screen's own resolution, with no blocks or bands on a 4K TV. Three soft lights in the cover's colours move over it with the music: one with the bass, one with the middle, one with the treble, faster as the music gets louder and slowly when it's quiet. They never go brighter than the cover's own colours, so the text stays easy to read.
- Android TV: the "Show spectrum" setting is gone with the old display; the spectrum is still an ambient face.

## 1.13 — the TV, by hand

- Android TV: queue and folders are two tabs at the top of the right column, each with its light; OK on one shows it, and Back from a list goes up to them. The folders key on the left is gone.
- Android TV: one mode key moves through normal, shuffle, repeat all and repeat one, with the mode's name under it.
- Android TV: the position bar takes the focus. OK holds it, ← → move 10 seconds a press (faster when held), the track goes there when you let go; OK keeps the place, Back goes back. In ambient mode ↓ holds the bar, ↑ leaves.
- Android TV: a quality badge on the display and the ambient faces: "FLAC 905 kbps | 16-bit/44.1 kHz", the bitrate being the file's average, as on the Mac and Windows.
- Android TV: covers come first from the image file in the album's folder on your Jellyfin server (cover, folder, front, album or capa), then from MusicBrainz; an image Jellyfin took from the tags never counts. Settings shows where the playing album's cover came from, and a lookup that couldn't reach the server is tried again.
- Android TV: the cover is on every ambient face, and without one a soft glow in the skin's own light sits behind the face. The glow breathes with the bass and drifts slowly, paused too; with OLED Protection the big time is a little dimmer.
- Android TV: every ambient face has the position bar, and the top line names the source ("Server") instead of the server's address.
- Android TV: in the equalizer the arrows move between the on/off key, the presets and the bands; OK on a band holds it for ↑ ↓, OK or Back lets go.
- Android TV: names too long for a list end in an ellipsis; with the focus they slide, with a pause at the start and soft ends.
- Android TV: finer icons, one spacing throughout, and the display's lines lined up.

## 1.12.1 — the remote reaches everything, Windows in step

- Android TV: the equalizer's presets and its on/off key can be reached with the remote: the presets come first, as on the Mac, and Back on a fader goes back to them. The active preset is lit by its LED.
- Android TV: on the sign-in screen, ↑ and ↓ move between the fields and the Sign In key; a field no longer keeps the remote's focus.
- Android TV: the equalizer's on/off key shows "Desligado" whole.
- Android TV: pressed keys, the dimming behind a panel and the VU meters' glass take their shade from the skin's colours; amber is kept for the play key and the lights.
- Windows: a selected track moves in the queue with Ctrl+Shift+↑ ↓, the Mac's ⌥⌘↑ ↓ (it was Alt+↑ ↓).
- Windows: pressed keys, the display's edge, a held equalizer fader and the VU meters' glass take their shade from the skin's colours, as on the Mac.
- Site: the privacy page names the daily update check, and the Windows answer in the FAQ says what the app does today.

## 1.12 — the artist, and names that scroll

- Mac and Windows: the display, the mini player and the ambient faces show the artist's folder beside the album's ("Fleetwood Mac · Rumours (1977)"), as the TV app does. A disc folder ("CD 2") gives way to its album. Control Center and the Windows media controls get the artist too. Still folders, never tags. A library folder such as "Music" is never taken for the artist, on the TV too.
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
