# Skin: Tropicália

After the Brazilian movement's record sleeves: coral, hot pink and mango on deep burgundy, with DM Sans. Warm and bright, with a glow that moves the way Rams's does. Same layout, keys, sizes and rules as Rams. Colours in `tokens.json` (`tropicalia`), temperament in its `glow`; code in `Sources/DesignSystem/Skin.swift` and `android/…/ui/Theme.kt`. In Portuguese the skin is called **Tropicália**.

- **Always dark**, whatever the system appearance. No light variant.
- **Default font set:** DM Sans + DM Mono.
- **One accent, three roles:** `key-play`, `led` and `signal` are coral #FF6B4A.
- The error colour is a pink-red (#FF86B0) so it isn't mistaken for the coral accent.

## Temperament

Bass 60/550 ms, middle 80/700 ms, treble 60/600 ms. Idle 30%. Breath 65%. Speed 1×. Lights: coral #FF6B4A (bass), hot pink #FF3D8B (middle), mango #FFC93C (treble).

On the Mac the temperament sets how the cover's field breathes on the Display face; on Android TV it also moves the three lights and, without a cover, colours the skin's own glow. Windows has it planned.

## Tokens

| Token | Tropicália | Contrast |
|---|---|---|
| surface-0 | #1E0D14 | — |
| surface-1 | #3A1F2B | 1.3:1 on surface-0 |
| surface-2 | #4E2337 | — |
| display | #12060B | — |
| display-ink | #FFF1E6 | 18.0:1 on display |
| display-muted | #DDAEA0 | 10.1:1 on display |
| display-track | #34171F | — |
| display-edge | #080204 | — |
| ink | #FFF1E6 | 16.9:1 on surface-0, 11.7:1 on surface-2 |
| ink-muted | #D6ACA1 | 9.2:1 on surface-0, 6.3:1 on surface-2 |
| line | #3A1E27 | — |
| key-face | #EAD3C6 | 13.0:1 on surface-0 |
| key-mode | #9A5169 | 3.3:1 on surface-0 |
| key-play | #FF6B4A | 6.6:1 on surface-0, 4.6:1 on surface-2 |
| key-ink | #1E0D14 | 13.0:1 on key-face, 6.6:1 on key-play |
| key-mode-ink | #FFFFFF | 5.6:1 on key-mode |
| key-play-pressed | #D95B3F | — |
| key-face-pressed | #C7B3A8 | — |
| key-mode-pressed | #834559 | — |
| track | #4A2A34 | — |
| fill | #EAD3C6 | 8.8:1 on track |
| led | #FF6B4A | — |
| led-off | #3A1E27 | — |
| signal | #FF6B4A | — |
| danger | #FF86B0 | 8.3:1 on surface-0, 8.8:1 on display |
| focus | #FFC93C | 12.2:1 on surface-0 |

## Left out

- **A light, sunlit variant:** the skin is always dark, like the others after Rams.

## Checks

`Tests/SkinTests.swift` and `android/…/GlowMotionTest.kt` hold Tropicália to the same rules as every skin: 4.5:1 text, 3:1 keys, LEDs and focus, distinct layers, a full palette, the accent only in its three roles, and a whole temperament.
