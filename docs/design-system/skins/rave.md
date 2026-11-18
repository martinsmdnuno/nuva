# Skin: Rave

A club at night: neon magenta, cyan and lime on a violet-black chassis, and the liveliest glow NuVa has. Every kick drum lights the screen and falls away within a fifth of a second, so the glow follows the beat instead of the loudness. Same layout, keys, sizes and rules as Rams. Colours in `tokens.json` (`rave`), temperament in its `glow`; code in `Sources/DesignSystem/Skin.swift` and `android/…/ui/Theme.kt`. In Portuguese the skin is called **Rave**.

- **Always dark**, whatever the system appearance. No light variant.
- **Default font set:** Inter + IBM Plex Mono.
- **One accent, three roles:** `key-play`, `led` and `signal` are magenta #FF4ADB (the glow's own magenta, #FF2BD6, lifted a little so the playing track reads 4.5:1 on the selected row).
- The display's muted text is a pale lilac (#C4BDE6), the lightest of any skin, so the glow has the most room above the display before the text would lose its 4.5:1.

## Temperament

Bass light: 15 ms to swell, 160 ms to settle; middle 30/250 ms; treble 20/150 ms. Idle 6% (dark between beats, so each one stands out). Breath 35%: the field swings from a third to full on every kick, which reads as a flash. Speed 2.2×. Lights: magenta #FF2BD6 (bass), cyan #00E5FF (middle), lime #B6FF3B (treble).

On the Mac the temperament sets how the field breathes on the Display face and, without a cover, its lights colour the field; on Android TV it also moves the three lights. Windows has it planned.

## Tokens

| Token | Rave | Contrast |
|---|---|---|
| surface-0 | #0E0B1A | — |
| surface-1 | #251E3E | 1.2:1 on surface-0 |
| surface-2 | #33275E | — |
| display | #050409 | — |
| display-ink | #F6F2FF | 18.5:1 on display |
| display-muted | #C4BDE6 | 11.5:1 on display |
| display-track | #251E3D | — |
| display-edge | #020104 | — |
| ink | #F4F0FF | 17.3:1 on surface-0, 11.8:1 on surface-2 |
| ink-muted | #ADA6CC | 8.4:1 on surface-0, 5.7:1 on surface-2 |
| line | #2A2440 | — |
| key-face | #C9C3E0 | 11.4:1 on surface-0 |
| key-mode | #6A5CA6 | 3.4:1 on surface-0 |
| key-play | #FF4ADB | 6.7:1 on surface-0, 4.6:1 on surface-2 |
| key-ink | #0E0B1A | 11.4:1 on key-face, 6.7:1 on key-play |
| key-mode-ink | #FFFFFF | 5.7:1 on key-mode |
| key-play-pressed | #D93FBA | — |
| key-face-pressed | #ABA6BE | — |
| key-mode-pressed | #5A4E8D | — |
| track | #352D52 | — |
| fill | #C9C3E0 | 7.5:1 on track |
| led | #FF4ADB | — |
| led-off | #2A2440 | — |
| signal | #FF4ADB | — |
| danger | #FF7A6B | 7.6:1 on surface-0, 8.0:1 on display |
| focus | #00E5FF | 12.6:1 on surface-0 |

## Left out

- **A strobe or full-screen flash.** The glow only brightens up to the contrast ceiling, and a flash faster than three times a second is a seizure risk; the fastest swing here is one per beat.
- **A two-colour spectrum** (magenta to cyan, as in the first mock-ups): the spectrum stays in `led`, the accent's role.

## Checks

`Tests/SkinTests.swift` and `android/…/GlowMotionTest.kt` hold Rave to the same rules as every skin: 4.5:1 text, 3:1 keys, LEDs and focus, distinct layers, a full palette, the accent only in its three roles, and a whole temperament.
