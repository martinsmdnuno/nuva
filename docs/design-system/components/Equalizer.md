# Equalizer

Popover of the equalizer readout on the display ("EQ · Rock", beside the time; Display.md), also opened with Controls ▸ Equalizer… (⌥⌘E). Ten bands from -12 to +12 dB, and presets.

## Anatomy
1. Header: "equalizer" in `label` · on the right, a slide switch with an LED and the word "on" or "off" (`legend`). The word describes the state, not the action.
2. Presets in a grid of 4, as lowercase text (`caption`) with an LED on the left. The active one has its LED on and text in `ink`; the others in `ink-muted`.
3. Bands: a printed scale behind them (+12, +6, 0, -6, -12, 1px rules, the zero rule in `line`), a 2px track and a 16 × 8px rectangular cap in `key-face`, like a fader.

## Rules
- Background `surface-1`, padding `space-4`, width 380px.
- Off: bands at 50% opacity.
- Double-clicking a band resets it to 0 dB.
- Preset names are stored in Portuguese (the localization key) and shown in the app's language.
