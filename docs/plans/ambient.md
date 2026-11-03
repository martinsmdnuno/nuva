# Plan: ambient mode

Status: done in 1.5 (phase 1), 1.6 (OLED protection, phases 2 and 3) and 1.7 (Needles and Valves).

A full-screen view to leave the music playing with the Mac as part of the room. The whole screen becomes the device's display: the `display` background and the display's tokens, so every skin gets its own ambient look with no extra work.

## Principles

- **One small window** still holds: ambient is not navigation or a second interface. Nothing to operate, no lists; the 360 pt window is where everything is done.
- **No decorative animation:** Display and Clock only move with time. Meters and Spectrum (later) show the real signal level, like an amplifier's needles.
- **No giant cover art:** no "Cover" face. With artwork on, the Display face shows a small tile beside the title, and every face sits on a glow in the cover's main hue (darkened so `display-muted` keeps 4.5:1; none for a cover in greys).
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

## Phase 3: Spectrum (1.6, redone in 1.7)

1.6 showed the window's 10 equalizer bands as segments. 1.7 follows the study's mockup: 28 bands, evenly spaced in log frequency from 20 Hz to 20 kHz, as solid bars in `display-ink` with the held peak as a thin cap in `led`, and the position bar below. The tap measures the 28 bands in the same FFT as the 10 (`SpectrumShared.fineLevels(at:)`); at 48 kHz a bin is 23 Hz wide, so the lowest bands share bins. Range -62 to -12 dBFS, lower than the 10-band meter's, since narrower bands carry less energy.

## Needles and Valves (1.7)

After a hi-fi amplifier's front (NAD C3030 and C3050) and a valve phono stage (Pro-Ject Tube Box S2), drawn flat in the skin's tokens.

- **Needles:** two backlit VU meters. The arc runs from -20 to +3 VU with a heavier band over 0 to +3; positions follow voltage, as on a real meter, so 0 VU sits at about 70%. 0 VU is -14 dBFS RMS. The needle has VU-like ballistics (`SlowMeter`, about 300 ms), and a peak light comes on within 1 dB of full scale. The lamp is `ink` warmed by `led` (amber in Rams, pale green in Phosphor), brighter in the middle, and dimmer with OLED protection.
- **Valves:** two valves in their cage (three rings, two posts). The glow, in `led`, lights the inside of the glass around the filament and follows each channel's level slowly, like a heater; it stays faintly on while paused with a track loaded.
- Both read the tap's left and right levels (`SpectrumShared.stereo(at:)`), in step with the speakers.
- OLED: the VU lamps are the largest lit areas in ambient mode. They drift and dim like the rest, and the face changes every 20 minutes, but on an OLED TV the Needles face is the one to leave on least.
