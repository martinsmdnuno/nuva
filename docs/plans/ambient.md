# Plan: ambient mode

Status: done in 1.5 (phase 1) and 1.6 (OLED protection, phases 2 and 3).

A full-screen view to leave the music playing with the Mac as part of the room. The whole screen becomes the device's display: the `display` background and the display's tokens, so every skin gets its own ambient look with no extra work.

## Principles

- **One small window** still holds: ambient is not navigation or a second interface. Nothing to operate, no lists; the 360 pt window is where everything is done.
- **No decorative animation:** Display and Clock only move with time. Meters and Spectrum (later) show the real signal level, like an amplifier's needles.
- **No giant cover art:** no "Cover" face. With artwork on, the Display face shows a small tile beside the title.
- **Folders, not metadata:** title is the file name, folder is the folder name.

## Phase 1 (done)

- `Sources/UI/Ambient.swift`: `Ambient` (face, dimming, open/close, screens, display-sleep assertion) and `AmbientWindow` (a titled, borderless-looking window that goes into native full screen in its own Space).
- `Sources/UI/AmbientView.swift`: faces **Display** and **Clock**, sized from 1% of the screen's width; the key strip that shows for 3 s when the mouse moves; a slow shift of a few points each minute against burn-in; dim at 40% (View ▸ Ambient Options ▸ Dim) or at 30% after 10 minutes paused.
- View ▸ Ambient, ⌘4 (⌃⌘F is the system's "Enter Full Screen"). View ▸ Ambient Options: face, Dim, and "Open on <screen>" with more than one screen. In the mini player, the view key (`circle.lefthalf.filled`) has Ambient above the skins: the mini player has no room for another key.
- Keys while open, in a local key monitor so they also work with the main window closed (no menu bar): Esc and ⌘4 leave, ← → change face, Space plays or pauses. Media keys work as always.
- `IOPMAssertion` PreventUserIdleDisplaySleep only while ambient is open and music plays.
- Snapshots: `snapshot-ambiente-ecra-*` and `snapshot-ambiente-relogio-*` at 1280 × 800.

## OLED protection (1.6)

1.5 only shifted the content a few points each minute and never rested while music played: hours a night on an OLED TV would wear the same pixels. View ▸ Ambient Options ▸ OLED Protection, on by default:

- The content takes 84% of the screen and wanders over the rest, 8% each way, from two sine waves per axis with periods that don't divide each other (53 and 21 minutes across, 71 and 26 down).
- Parts that hardly change (format, folder, date, position bar) at 55%.
- The clock's colon blinks each second.
- A new face every 20 minutes (`Ambient.tick`, every 30 s).
- After an hour without a key or the mouse, rest: black with only the LED wandering. The first key or mouse move wakes it (Esc and ⌘4 still leave).

## Phase 2: Meters (1.6)

Two ladders of 40 segments, L and R, -48 to 0 dBFS: RMS lit in `led`, the held peak in `display-ink`. The tap's `SpectrumAnalyzer` now also keeps each channel's sum of squares and highest sample between measurements and stores them with the bands (`SpectrumShared.stereo(at:)`), so the meters are in step with the speakers, AirPlay included, like the spectrum. Ballistics from `SpectrumMeter` (two columns, wider range).

## Phase 3: Spectrum (1.6)

The window's 10-band spectrum (1.3) at the scale of the screen, 24 segments per band, band frequencies printed below. Same measurement and ballistics. One colour by rule, as on the display.
