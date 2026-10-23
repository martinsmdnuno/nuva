# Spectrum

A level meter for the equalizer's 10 bands, inside the display, between the time and the position bar. Reference: the LED level meters of a hi-fi deck. It shows what is heard: measured after the equalizer, at the moment the speakers play (also over AirPlay).

## Anatomy
- 10 columns, one per equalizer band (32 Hz to 16 kHz), 3px apart, full display width.
- 8 segments per column, 3px tall with 1px gaps (31px in all), with `space-3` above and `space-1` below.
- Lit segments in `led`, unlit in `display-track`, the peak segment in `display-ink`.

## Behaviour
- A column jumps up to the level and falls back at a steady rate (full scale in about 0.6 s), like a hardware meter.
- The peak segment holds for 0.8 s, then falls.
- Scale: -54 dBFS is an empty column, -6 dBFS a full one.
- Paused or stopped, the columns fall and the meter goes dark. It moves only with the music, so it is the one exception to "nothing moves on its own".

## Rules
- View ▸ Show Spectrum (⌥⌘V), on by default. Off, the display is as before.
- In every window size and in the mini player.
- No labels, no colours other than these three, no mirror or glow effects.
- The audio tap only measures while a meter is on screen.
