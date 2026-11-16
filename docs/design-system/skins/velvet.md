# Skin: Velvet

For listening late: night blue, warm amber and lilac, with IBM Plex Sans. The calmest glow: it takes about a second to rise and nearly three to fall, so it follows the shape of the music, not its beat, like a fire in the room. Same layout, keys, sizes and rules as Rams. Colours in `tokens.json` (`velvet`), temperament in its `glow`; code in `Sources/DesignSystem/Skin.swift` and `android/…/ui/Theme.kt`. In Portuguese the skin is called **Velvet**.

- **Always dark**, whatever the system appearance. No light variant.
- **Default font set:** IBM Plex Sans + Plex Mono.
- **One accent, three roles:** `key-play`, `led` and `signal` are warm amber #E6A65A.
- The dimmest display text of the new skins (#A9A3C6), so its glow is also the softest.

## Temperament

Bass 0.9/2.6 s, middle 1.0/3.0 s, treble 1.1/2.8 s. Idle 40%. Breath 80%: the field barely dims. Speed 0.35×. Lights: amber #E6A65A (bass), lilac #8A6FD1 (middle), deep blue #3C4FA8 (treble).

On the Mac the temperament sets how the cover's field breathes on the Display face; on Android TV it also moves the three lights and, without a cover, colours the skin's own glow. Windows has it planned.

## Tokens

| Token | Velvet | Contrast |
|---|---|---|
| surface-0 | #0F1124 | — |
| surface-1 | #23274B | 1.3:1 on surface-0 |
| surface-2 | #302D60 | — |
| display | #070816 | — |
| display-ink | #ECE6F5 | 16.3:1 on display |
| display-muted | #A9A3C6 | 8.3:1 on display |
| display-track | #1C1F3A | — |
| display-edge | #03030A | — |
| ink | #ECE6F5 | 15.3:1 on surface-0, 10.3:1 on surface-2 |
| ink-muted | #ABA5C6 | 7.9:1 on surface-0, 5.3:1 on surface-2 |
| line | #23264A | — |
| key-face | #CFC8DE | 11.5:1 on surface-0 |
| key-mode | #6862A2 | 3.4:1 on surface-0 |
| key-play | #E6A65A | 8.9:1 on surface-0, 6.0:1 on surface-2 |
| key-ink | #0F1124 | 11.5:1 on key-face, 8.9:1 on key-play |
| key-mode-ink | #FFFFFF | 5.4:1 on key-mode |
| key-play-pressed | #C48D4C | — |
| key-face-pressed | #B0AABD | — |
| key-mode-pressed | #58538A | — |
| track | #2E3156 | — |
| fill | #CFC8DE | 7.7:1 on track |
| led | #E6A65A | — |
| led-off | #23264A | — |
| signal | #E6A65A | — |
| danger | #FF7A85 | 7.4:1 on surface-0, 7.9:1 on display |
| focus | #9FB8FF | 9.6:1 on surface-0 |

## Left out

- Nothing yet.

## Checks

`Tests/SkinTests.swift` and `android/…/GlowMotionTest.kt` hold Velvet to the same rules as every skin: 4.5:1 text, 3:1 keys, LEDs and focus, distinct layers, a full palette, the accent only in its three roles, and a whole temperament.
