# Plan: ambient mode

Status: phase 1 done (Display and Clock faces). Phases 2 and 3 not started.

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

## Phase 2: Meters

Two LED ladders (L, R) with a dB scale and a peak mark in `led`. Peak and RMS per channel computed in the equalizer's `MTAudioProcessingTap`, published at 30 Hz, drawn with `TimelineView` + `Canvas`.

Check first:
- **AirPlay latency.** With the WiiM, AirPlay 2 buffers about 2 s, so levels from the tap would run ahead of the sound. Delay them by the route's output latency if AVFoundation reports it reliably; otherwise label the meters "at the source" on AirPlay.
- The tap has to run on every item, even with the equalizer off (bypass).

## Phase 3: Spectrum

28 log bands from a 1024-point vDSP FFT in the same tap, with peak caps in `led`. One colour by rule; a green-yellow-red option could exist for Phosphor only.
