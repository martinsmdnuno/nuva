# Display

The device's screen: what's playing and where it's going. Always dark (`display`) in both themes, recessed into the chassis.

## Content, top to bottom
1. LED (6px, `led`) while playing, `led-off` when paused · format and rate in `display-meta` (`FLAC 24/96`) · source name on the right.
2. Track title in `title`, `display-ink`: the file name without extension or leading number.
3. Folder name in `caption`, `display-muted` · the output on the right (`airplayaudio` 9px + "AirPlay WiiM" or "Speakers · 48 kHz", `display-meta`).
4. Elapsed time in `display-time` · the equalizer on the right, on the time's baseline: LED + "EQ · Rock" ("EQ" alone when off), `display-meta`.
5. Spectrum meter (see Spectrum.md), full width, when View ▸ Show Spectrum is on.
6. Position row: elapsed time in `display-meta` on the left, the position bar (see PositionBar.md) in between, the duration in `display-meta` on the right.

## Rules
- Padding `space-3`, corners `radius-sm`, shadow `shadow-display`. No outline.
- Clicking the duration at the end of the position row switches it to the time left ("-03:10") and back. The large time is always the elapsed time.
- Two readouts are also controls, because what they show is what they change. The output opens the native AirPlay picker (an `AVRoutePickerView` stretched over the text, almost transparent). The equalizer opens its panel (Equalizer.md), as does Controls ▸ Equalizer… (⌥⌘E). On hover they go from `display-muted` to `display-ink` (120ms); no background, no underline. Nothing else on the display reacts to the mouse, except the duration and the position bar.
- Small artwork only when View ▸ Show Artwork is on (see the skins and artwork plan).
- With no sources: "No music · Add a folder or a Jellyfin server". With sources and nothing playing: "No track · Choose a folder to play".
