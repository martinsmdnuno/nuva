# Volume

The app's volume, as a knob at the right end of the keys, under its own legend. Reference: the volume knob of a Cambridge Audio or B&O amplifier.

## Rules
- The knob is the height of a key (`key`, 36px): a 26px disc in `key-mode` with a 2 × 9px pointer in `key-mode-ink`.
- Printed scale around it: 11 ticks over 270°, from 7 to 5 o'clock, in `line` (0, 5 and 10 longer, in `ink-muted`).
- Below, like the other groups: the "volume" legend and the reading 0 to 10 in `hint`, right-aligned.
- No LED (the space above stays empty so it lines up with the keys).
- Drag up or down (160pt for the whole range), scroll over it, or the arrows when it has focus: 5% a step. ⌘↑ and ⌘↓ from anywhere.
- The pointer follows the value directly, never animated: it's the readout.
- Focus: 2px ring in `focus` around the disc.
- Controls the app's volume, not the system's. Over AirPlay, it controls the receiving device.
