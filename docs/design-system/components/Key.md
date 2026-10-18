# Key

A flat key with an icon, for every playback and output action (previous, play/pause, next, repeat, shuffle, AirPlay, equalizer). Reference: the keys of the Braun ET66 calculator and the TG 60 tape recorder.

## Tones and widths
All at height `key` (36px) with corners `radius-sm`. No outline, no lip.
- **Play/pause:** `key-play`, icon in `key-ink`, width `key-w-lg` (56px). One per window.
- **Transport** (previous, next): `key-face`, icon in `key-ink`, width `key-w-md` (40px).
- **Mode and output** (repeat, shuffle, AirPlay, equalizer, folders): `key-mode`, icon in `key-mode-ink`, width `key-w-sm` (32px).

## States
- Pressed: the face darkens 15% while the mouse is down.
- On: a 4px LED above the key, `led` on, `led-off` off. Keys with state (repeat, shuffle, equalizer, folders) always show the LED. The others leave the space empty so the faces line up.
- Keyboard focus: 2px ring in `focus`, 4px away.
- Never disabled: with an empty queue, play opens the folder browser.

## Groups
Three groups with space between them and a `legend` underneath: **playback** · **mode** · **output**. Fixed order inside each. There is no Stop key (pause is enough; ⌘. stays in the menu). Folders open with the folders key in the queue header (see PlayerWindow.md), ⌘B or the View menu.

## Rules
- Icon 16px (play 18px, mode and output 14px), regular weight.
- Every key has a tooltip with its name and shortcut ("Next ⌘→").
- The caller provides the icon (SF Symbol), the tone and the action. One `ButtonStyle`.
