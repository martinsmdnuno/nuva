# Skin: Phosphor

After the classic shareware MP3 players of the late nineties: a black screen with phosphor-green text, a blue-grey chassis, silver keys and a blue selected row. Only colours change: same layout, keys, sizes and rules as Rams. Values in `tokens.json` (`phosphor`); code in `Sources/DesignSystem/Skin.swift`. In Portuguese the skin is called **Fósforo**.

- **Always dark**, whatever the system appearance. No light variant.
- **Default font set:** Inter + IBM Plex Mono. Plex Mono Light on the green display already reads like an LCD.
- **One accent, three roles:** `key-play`, `led` and `signal` are #00D02A, like the little green lights on the old players' toggle keys.
- **Display tint:** the display's ink is a brighter green (#00E838), not the accent. This is the "display tint" rule in the design system README: the display may have its own ink colour, like an amplifier's VFD, as long as it isn't the accent's value.

## From the reference to the tokens

| Token | Phosphor | Comes from | Contrast |
|---|---|---|---|
| surface-0 | #1C1C2B | the blue-grey chassis | — |
| surface-1 | #2C2C44 | popovers (equalizer) | 1.24:1 on surface-0 |
| surface-2 | #1B2A8F | the blue selected row of the playlist | 1.42:1 on surface-0 |
| display | #000000 | the black screen | — |
| display-ink | #00E838 | the green time and title | 12.6:1 |
| display-muted | #1FA83C | dimmer green: format, rate, folder | 6.7:1 |
| display-track | #0E3A18 | the position bar's track | — |
| ink | #D8DCE6 | list text, light and cool | 12.2:1, 8.6:1 on the selection |
| ink-muted | #A4A8BE | durations and legends | 7.1:1, 5.0:1 on the selection |
| key-face, fill | #B6BACB | the silver transport keys | 8.7:1 on surface-0 |
| key-mode | #66668E | the blue-grey mode keys | 3.1:1 on surface-0 |
| key-mode-ink | #F6F7FB | icons on mode keys | 5.1:1 |
| key-ink | #10101C | icons on the silver keys and on play | 9.8:1, 9.0:1 |
| key-play, led, signal | #00D02A | the green toggle lights | 8.0:1, 5.7:1 on the selection |
| track | #3E3E58 | the volume bar's track | fill 5.3:1 on it |
| line, led-off | #34344C | decorative only | — |
| danger | #FF6B6B | source errors | 6.1:1 |
| focus | #F2C744 | yellow, apart from the green and the blue | 10.4:1 |

## Left out

- **A pixel font** (VT323, Silkscreen): one weight, incomplete Latin Extended. Breaks the rules for font sets.
- **Bevels and raised keys:** layout, not colour, and against "no outlines around keys".
- **Green list with the current track in white**, as on the originals: the accent would have to be white, and so would the LEDs and the play key.
- **A green-yellow-red spectrum:** three colours outside the accent's roles.

## Checks

`Tests/SkinTests.swift` holds Phosphor to the same rules as every skin: 4.5:1 text, 3:1 keys, LEDs and focus, distinct layers, a full palette, and the accent only in its three roles. Snapshots: `NuVa --snapshot` writes `snapshot-<view>-phosphor.png`.
