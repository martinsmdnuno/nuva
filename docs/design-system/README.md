# NuVa design system

Folders, native sound, nothing extra. A macOS player for music in a local folder or on a server, in a small window, with the clean language of a hi-fi component (Braun under Dieter Rams, Cambridge Audio, B&O).

This document guides whoever builds the app in SwiftUI. Utility first: every rule here exists to make the app faster to use, not prettier.

## Principles

1. **Function first.** Every element performs an action or shows information. If it does neither, it goes. No decorative animation, no gradients, no giant cover art.
2. **Less, but better (Dieter Rams).** One flat plane. No cards inside cards, no outlines around keys, no rules between rows. Zones are separated by space. Hierarchy comes from the colour and width of the keys, never from more lines.
3. **Folders, not metadata.** Folder = album. We show folder and file names exactly as they are. We never reorganise by tags.
4. **One window.** Everything fits in a compact window. No pages, tabs or deep navigation.
5. **Keyboard first.** Everything you can do with the mouse has a shortcut. The Mac's media keys always work.
6. **The device, not the app.** The display is always dark, like an amplifier's. The rest of the chassis follows the theme (Lead or Aluminium).

## Music sources

The interface doesn't tell sources apart. Local folders and servers appear in the same list and behave the same. The only sign of the origin is the icon next to the source name (`internaldrive` or `server.rack` in SF Symbols) and, on error, the message in `danger`.

## Colour

Lead grey with a single accent.

- **Chassis:** `surface-0` is the window's only plane: display, keys and queue all sit on it. `surface-1` is for popovers (equalizer) and `surface-2` for the selected row.
- **Display:** `display` with `display-ink`, `display-muted` and `display-track` (the position track). The same in both themes, recessed with `shadow-display`.
- **Text:** `ink` for primary text, `ink-muted` for durations, metadata, legends and resting icons.
- **Keys:** three tones, as on a Braun calculator. `key-play` (amber) only on the play/pause key. `key-face` (light grey) on transport. `key-mode` (mid grey) on mode keys, the volume knob and text buttons.
- **Accent:** amber, only one, in three linked roles: the key that plays (`key-play`), the LEDs (`led`) and the name of the track that's playing (`signal`). Never on backgrounds, hovers or any text other than the current track.
- **LED:** a 4px dot, `led` on, `led-off` off. It shows state: playback and the equalizer on the display, shuffle/repeat/folders above their key, the playing track in the list.
- **Error:** `danger` only on text and icons, never as a background.
- **Focus:** `focus` as a 2px ring around the control with keyboard focus.

Themes: **Lead** (`chumbo`) is the main one. **Aluminium** (`aluminio`) is the light theme and follows the system appearance. Together they are the **Nuno** skin. Every text pair passes 4.5:1 in both themes, and keys, LEDs and focus 3:1 (checked in `Tests/SkinTests.swift`).

Other skins change token values only, never roles or layout: **Graphite Orange** and **Graphite Green**, always dark (`skins/graphite.md`). View ▸ Skin, ⌥⌘1, ⌥⌘2, ⌥⌘3.

## Type

Two families, embedded in the app (`Inter` and `IBM Plex Mono`, both OFL):

- **Inter** for the interface: track titles (`title`), lists (`body`), labels (`label`), notes (`caption`).
- **Legends** (`legend`, Inter 10px, lowercase, `ink-muted`): the name printed on the chassis under each group of keys (mode, playback, volume) and each zone (queue, folders), as on the Braun TG 60.
- **IBM Plex Mono** for numbers and the display: time (`display-time`), format and rate (`display-meta`), durations in lists (`duration`), the volume scale (`scale`) and hints beside labels (`hint`). Fixed-width digits so the time doesn't jump.

**Font sets** (View ▸ Font): *Inter + IBM Plex Mono* (above, the default) or *SF Pro + SF Mono* from the system. Each skin names its default set and the user can override it. Only the family changes: every style keeps its size and weight, and the mono keeps tabular digits. SF Mono's lines are slightly shorter, so the display (and Compact mode) is a few points lower.

Japanese names and other scripts fall back to the system font (Hiragino), which is fine. Never truncate with an ellipsis in the middle: truncate at the end, with the full name in the tooltip.

## Keys

Flat keys, as on a Braun calculator or tape recorder:

- No outline, no lip. The face is the edge. Corners `radius-sm`.
- Every icon key has the same height (`key`, 36px). Importance comes from colour and width: play `key-w-lg` 56px in `key-play`, transport `key-w-md` 40px in `key-face`, mode `key-w-sm` 32px in `key-mode`.
- Pressed: the face darkens 15% while the mouse is down. There is no "sunken" key for state.
- On (shuffle, repeat, folders): a 4px LED lit above the key. Keys with state always have their LED, on or off.
- Keys are grouped by function, with a legend underneath: **mode** (shuffle, repeat) · **playback** (previous, play/pause, next), with play on the window's centre line · **volume**, a knob the height of a key (`components/Volume.md`).
- Output and equalizer are not keys. They are readouts on the display that open their controls: the output name opens the AirPlay picker, "EQ · Rock" opens the equalizer (`components/Display.md`).
- Text buttons (Add Folder, Play Folder) use `key-mode` with a `label`, height `key-text` 28px.

## Motion

Movement only shows what the hardware would do. Nothing moves on its own, nothing loops, and everything snaps with Reduce Motion. Tokens in `Sources/DesignSystem/Motion.swift`:

- **Keys travel.** Pressed, the face goes down 1px and darkens in 60ms; released, a short spring brings it back. Changing icons (play/pause, repeat/repeat one) swap in place.
- **LEDs glow and fade.** On in 80ms; off in 350ms, a short afterglow like a filament.
- **Hover** backgrounds and resting colours fade in 120ms.
- **State in place** (a new track on the display, a switch thrown, rows added, removed or reordered, the browser going into a folder) cross-fades in 200ms. Choosing an equalizer preset moves the faders there in 300ms, like motorised ones; dragging stays direct. No slides between screens, no bounces on content.
- The time and the position bar never animate: they are the readout.
- The spectrum meter (`components/Spectrum.md`) moves with the music and only with it: columns jump up and fall at a steady rate, the peak holds and falls. Paused, it goes dark.

## Icons

SF Symbols, regular weight, never filled except `play.fill` and `pause.fill` inside the play key. Fixed symbols: `backward.end`, `forward.end`, `play.fill`, `pause.fill`, `repeat`, `shuffle`, `airplayaudio` (on the display, beside the output), `sidebar.left`, `folder`, `internaldrive`, `server.rack`.

## Windows

One device, always the same layout: display, keys with the volume knob, and below them the queue or the folders.

- **Player with queue** (⌘1): the queue below the keys.
- **Player with folders** (⌘2): the folder browser in the queue's place. ⌘B or the folders key swaps the two. Playing a folder or a track from it brings the queue back.
- **Compact** (⌘3): display, keys and the header. No rows; the height follows the content.

The width is free from 360 to 480: keys keep their size and the space between the groups grows, while the display, the meter and the lists stretch. With the queue or the folders the height is free too (minimum 540). The app remembers both between modes and launches. Double-clicking the title bar (zoom) stretches the window to the screen's height.

## Shortcuts

Space play/pause · ⌘→ next · ⌘← previous · ⌘↑ ⌘↓ volume · ⌥⌘E equalizer · ⌘L go to the current track · Enter play selection · ⌘Enter add to queue · ⌘B swap queue and folders · ⌘1 ⌘2 ⌘3 queue, folders, compact · ⌘O add folder · ⇧⌘O add Jellyfin.

## Interface text

The app is in European Portuguese and English and follows the system language; any other language falls back to English. Portuguese strings are the keys in `Resources/Localizable.xcstrings`.

In both languages: short sentences, verb first, no full stops on buttons, no "please", no exclamation marks. Chassis legends in lowercase ("mode", "playback", "volume", "queue", "folders"). English menus in Title Case, as on macOS. Examples: "Add Folder", "Play Folder", "Server offline. Try again" · "Adicionar pasta", "Tocar pasta", "Servidor offline. Tentar de novo".

## For implementers (SwiftUI)

- Colour tokens as `Color` in `Assets.xcassets` with light and dark variants, named like the tokens.
- Time with IBM Plex Mono Light 28 and `.monospacedDigit()`.
- Keys as a single `ButtonStyle` (`KeyButtonStyle`) with three tones.
- Audio through AVFoundation (`AVQueuePlayer`), AirPlay output through `AVRoutePickerView` over the output readout on the display.
- Media keys and Control Center through `MPRemoteCommandCenter` and `MPNowPlayingInfoCenter`.
