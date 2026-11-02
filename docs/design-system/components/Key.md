# Key

A flat key with an icon, for every playback and mode action (shuffle, repeat, previous, play/pause, next, folders). Reference: the keys of the Braun ET66 calculator and the TG 60 tape recorder.

## Tones and widths
All at height `key` (36px) with corners `radius-sm`. No outline, no lip.
- **Play/pause:** `key-play`, icon in `key-ink`, width `key-w-lg` (56px). One per window.
- **Transport** (previous, next): `key-face`, icon in `key-ink`, width `key-w-md` (40px).
- **Mode** (shuffle, repeat, folders): `key-mode`, icon in `key-mode-ink`, width `key-w-sm` (32px).

## States
- Pressed: the face darkens 15% and goes down 1px while the mouse is down (60ms), and springs back on release. The LED and legend stay put.
- A key whose icon changes with state (play/pause, repeat/repeat one) swaps the symbol in place.
- On: a 4px LED above the key, `led` on, `led-off` off. Keys with state (shuffle, repeat, folders) always show the LED. The others leave the space empty so the faces line up.
- Keyboard focus: 2px ring in `focus`, 4px away.
- Never disabled: with an empty queue, play opens the folder browser.

## Groups
Three groups with a `legend` underneath: **mode** (shuffle, repeat) on the left · **playback** in the middle, with play on the window's centre line · **volume** (the knob, Volume.md) on the right. The side groups take equal flexible widths, so play stays centred at any width. Fixed order inside each. There is no Stop key (pause is enough; ⌘. stays in the menu). Output and equalizer are not keys: they are readouts on the display that open their controls (Display.md). Folders open with the folders key in the queue header (see PlayerWindow.md), ⌘B or the View menu.

## Rules
- Icon 16px (play 18px, mode 14px), regular weight.
- Every key has a tooltip with its name and shortcut ("Next ⌘→").
- The caller provides the icon (SF Symbol), the tone and the action. One `ButtonStyle`.
