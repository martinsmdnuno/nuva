# Skin: Graphite (Orange, Green)

From `NuVa_Design_Spec_v1` (a third-party concept), applied under NuVa's principles. Only colours change: same layout, keys, sizes and rules as Nuno. Values in `tokens.json` (`graphite-orange`, `graphite-green`); code in `Sources/DesignSystem/Skin.swift`.

- **Always dark**, whatever the system appearance (the spec asks for it). No light variant.
- **Default font set:** SF Pro + SF Mono (the spec's first choice). Inter + IBM Plex Mono stays selectable in View ▸ Font.
- **One accent, three roles:** `key-play`, `led` and `signal` are the accent (#FF6A00 or #20D66B). Nothing else is.
- The two variants differ only in the accent and in the tint of the selected row (`surface-2`).

## From the spec to the tokens

| Token | Graphite | Spec value | Why it changed |
|---|---|---|---|
| surface-0 | #0B0F10 | Background #0B0F10 | — |
| surface-1 | #1C2427 | Surface #111618 | 1.06:1 against the background: hover and popovers were invisible. Now 1.22:1. |
| surface-2 | #382E22 / #1D3628 | Raised #24201B / #15251C | ~1.1:1 against surface-1: the selected row couldn't be seen. Now ≥ 1.45:1 on the background. |
| ink | #F2F4F5 | #FFFFFF | Pure white on near black glares in long lists. Still 17.5:1. |
| ink-muted | #9AA3A7 | #D8DCDE | The spec's secondary text was 1.38:1 from primary: no hierarchy. Still ≥ 5:1 on every surface. |
| line, led-off | #2A3032 | Subtle border #2A3032 | — (decorative only) |
| track | #363E41 | — | Bar tracks need to read as a control. |
| key-play, led, signal | accent | Accent | — |
| key-ink | #0B0F10 | — | White on the accent fails (2.87:1 orange, 1.93:1 green); dark passes (6.7:1, 10:1). |
| key-face, fill | #C9CED0 | — | Neutral, as in Nuno: transport keys and the volume fill are not accent. |
| key-mode | #5B656C | — | 3.2:1 against the chassis, so the key face reads as a key with no outline. |
| key-mode-ink | #F2F4F5 | — | 5.4:1 on key-mode. |
| display (+ ink, muted, track) | #050708, #F2F4F5, #9AA3A7, #252C2F | — | The display stays darker than the chassis, as in every skin. |
| danger | #FF6F8A | — | A pink-red that can't be mistaken for the orange accent. |
| focus | #8FB4E3 | — | Blue, distinct from both accents. 9:1. |

Not used from the spec: *Accent hover* (NuVa shows state with LEDs, not hover), the accent on progress and volume, the accent rail on folders, and the whole layout (three panes, search header, 36–42 pt rows, queue drawer).

## Checks

`Tests/SkinTests.swift` checks every text pair at 4.5:1 and icons, LEDs and focus at 3:1, that the layers are distinct, that the palette covers every token, and that the accent stays in its three roles. Snapshots: `NuVa --snapshot` writes `snapshot-<view>-graphite-orange.png` and `-graphite-green.png`.
