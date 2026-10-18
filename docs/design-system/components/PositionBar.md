# Position bar

Shows and controls the position in the track. Lives inside the display, under the time.

## Rules
- Track `display-track`, elapsed part `display-ink`, thickness `bar` (2px), square ends.
- No visible head at rest. On hover, a 2 × 10px vertical tick in `display-ink` and a tooltip with the time at that point.
- 16px tall hit area, taller than the bar.
- Arrow keys skip 5 seconds when it has focus.
