# Display

The device's screen: what's playing and where it's going. Always dark (`display`) in both themes, recessed into the chassis.

## Content, top to bottom
1. LED (6px, `led`) while playing, `led-off` when paused · format and rate in `display-meta` (`FLAC 24/96`) · source name on the right.
2. Track title in `title`, `display-ink`: the file name without extension or leading number.
3. Folder name in `caption`, `display-muted` · audio output in `display-meta` on the right.
4. Elapsed time in `display-time`.
5. Spectrum meter (see Spectrum.md), full width, when View ▸ Show Spectrum is on.
6. Position row: elapsed time in `display-meta` on the left, the position bar (see PositionBar.md) in between, the duration in `display-meta` on the right.

## Rules
- Padding `space-3`, corners `radius-sm`, shadow `shadow-display`. No outline.
- Clicking the duration at the end of the position row switches it to the time left ("-03:10") and back. The large time is always the elapsed time.
- No cover art.
- With no sources: "No music · Add a folder or a Jellyfin server". With sources and nothing playing: "No track · Choose a folder to play".
