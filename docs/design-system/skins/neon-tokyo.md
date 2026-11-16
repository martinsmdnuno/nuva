# Skin: Neon Tokyo

A sign on a wet street at night: electric blue and sodium orange on a navy-black chassis, with Share Tech, the digital readout, as its type. A strong glow that holds steadier than Rave's: it shines with the music without trembling. Same layout, keys, sizes and rules as Rams. Colours in `tokens.json` (`neon-tokyo`), temperament in its `glow`; code in `Sources/DesignSystem/Skin.swift` and `android/…/ui/Theme.kt`. In Portuguese the skin keeps its name, **Neon Tokyo**.

- **Always dark**, whatever the system appearance. No light variant.
- **Default font set:** Share Tech + Share Tech Mono.
- **One accent, three roles:** `key-play`, `led` and `signal` are sodium orange #FF8A1F.
- Blue keys on a blue chassis need the mode keys lighter than usual (#4A66B0) to keep 3:1.

## Temperament

Bass 40/400 ms, middle 60/500 ms, treble 50/450 ms. Idle 20%. Breath 55%. Speed 1.3×. Lights: electric blue #2D6BFF (bass), sodium orange #FF8A1F (middle), sky blue #5FD4FF (treble).

On the Mac the temperament sets how the cover's field breathes on the Display face; on Android TV it also moves the three lights and, without a cover, colours the skin's own glow. Windows has it planned.

## Tokens

| Token | Neon Tokyo | Contrast |
|---|---|---|
| surface-0 | #0A0F1E | — |
| surface-1 | #17213D | 1.2:1 on surface-0 |
| surface-2 | #203677 | — |
| display | #04060D | — |
| display-ink | #E6F0FF | 17.6:1 on display |
| display-muted | #9AB0DA | 9.3:1 on display |
| display-track | #18223D | — |
| display-edge | #020308 | — |
| ink | #E6F0FF | 16.6:1 on surface-0, 9.8:1 on surface-2 |
| ink-muted | #9EAFD2 | 8.7:1 on surface-0, 5.1:1 on surface-2 |
| line | #1E2946 | — |
| key-face | #C2CDE6 | 12.0:1 on surface-0 |
| key-mode | #4A66B0 | 3.5:1 on surface-0 |
| key-play | #FF8A1F | 8.1:1 on surface-0, 4.8:1 on surface-2 |
| key-ink | #0A0F1E | 12.0:1 on key-face, 8.1:1 on key-play |
| key-mode-ink | #FFFFFF | 5.5:1 on key-mode |
| key-play-pressed | #D9751A | — |
| key-face-pressed | #A5AEC4 | — |
| key-mode-pressed | #3F5796 | — |
| track | #2A3658 | — |
| fill | #C2CDE6 | 7.5:1 on track |
| led | #FF8A1F | — |
| led-off | #1E2946 | — |
| signal | #FF8A1F | — |
| danger | #FF6F8A | 7.2:1 on surface-0, 7.6:1 on display |
| focus | #5FD4FF | 11.2:1 on surface-0 |

## Left out

- **Kanji or Katakana signage:** text is the app's own, in Portuguese and English.

## Checks

`Tests/SkinTests.swift` and `android/…/GlowMotionTest.kt` hold Neon Tokyo to the same rules as every skin: 4.5:1 text, 3:1 keys, LEDs and focus, distinct layers, a full palette, the accent only in its three roles, and a whole temperament.
