# Gauntlet rubric: Mac

What the judge grades after `scripts/gauntlet.sh mac` passes. Every line comes from `CLAUDE.md` or `docs/design-system/`; when they disagree, they win and this file is wrong.

Each criterion has an id. A finding names the id, its severity and its evidence (a `file:line` or a screenshot name). **blocker**: it breaks a principle or a line marked blocker here. **minor**: everything else worth fixing.

Inputs, in `build/gauntlet/mac/`: `snapshots/pt-PT/` and `snapshots/en/` (`snapshot-<view>[-<font>]-<theme or skin>.png`), `diff.patch` (the branch against `main`), `logs/`.

## Principles (always blocker)

- **P1 Folders, not metadata.** No code reads tags (`AVMetadataItem`, `commonMetadata`, ID3, Vorbis comments) to name, sort or group. Lists show folder and file names exactly as on disk. Order is `localizedStandardCompare` on the file name. The only exceptions: an audio CD's names and the artwork lookup, both as `CLAUDE.md` describes them.
- **P2 Native audio.** Playback through AVFoundation (`AVQueuePlayer`). No third-party audio code, no new dependency in `project.yml`.
- **P3 One small window.** Main window 360 to 480 wide. No new windows, sheets or navigation stacks beyond what `CLAUDE.md`'s scope lists.
- **P4 Keyboard first.** Every new action has a menu item with a shortcut; media keys and Now Playing keep working (`MPRemoteCommandCenter`, `MPNowPlayingInfoCenter`).
- **P5 Pluggable sources.** The player knows `MusicSource`, never a concrete source type.

## Design system

- **D1 Colours from tokens only.** No `Color(red:…)`, hex or `NSColor` literal in views; every colour is a token (`Assets.xcassets` or `ColorToken`). Blocker.
- **D2 One plane.** No cards, outlines around keys, rules between rows or shadows other than `shadow-display` (look at every screenshot). Blocker.
- **D3 One accent.** Amber only on the play key, the LEDs and the playing track's name. Never on a background, hover or other text.
- **D4 Keys.** Every key uses `KeyButtonStyle` with one of its three tones.
- **D5 Type.** Views use the `Font.ds…` styles, never `Typography.sans/mono` or a raw `.font(.system…)`. Numbers in the mono with tabular digits.
- **D6 Truncation.** Names truncate at the end, never the middle, and the full name is in the tooltip. No text clipped or overlapping in any screenshot, in either language (Portuguese is longer: compare `pt-PT` and `en`). Blocker.
- **D7 Skins.** Each skin only changes colours: the same view in `chumbo`, `aluminio`, `graphite-orange` and `phosphor` has the same layout and sizes.
- **D8 Contrast.** Text readable on its background in every screenshot (4.5:1 for text, 3:1 for keys and LEDs; `Tests/SkinTests.swift` checks the tokens, you check what is drawn, such as text over artwork).

## Text

- **T1 Both languages.** Every visible string in `en` screenshots is English and in `pt-PT` is European Portuguese (not Brazilian: "ecrã", "ficheiro", "pasta", never "tela", "arquivo"). No Portuguese left in English or the reverse. Blocker.
- **T2 Same meaning.** The two languages say the same thing; placeholders match (the `strings` gate checks the keys, you check the sense).

## Code

- **C1 Fits the code around it.** Names, comment density and idioms match the file. Comments in English.
- **C2 Tested.** New logic in `Sources/Player/` or `Sources/Library/` has a test in `Tests/`.
- **C3 No dead code**, debug prints or leftover TODOs in the diff.

## Done (only when the diff adds a feature)

- **F1** `docs/features.json` has the feature: `yes` on the Mac, `planned` or `n/a` with a `why` elsewhere. Blocker.
- **F2** `CHANGELOG.md` has it, and the README and site prose say it in both languages.
- **F3** `TERMS.md` is updated if the feature makes a new network call. Blocker.
