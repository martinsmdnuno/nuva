# Gauntlet rubric: Windows

What the judge grades after `scripts/gauntlet.sh windows` passes. Every line comes from `CLAUDE.md`, `windows/CLAUDE.md` or `docs/design-system/`; when they disagree, they win and this file is wrong. The Mac is the reference: where this file says "as on the Mac", read the Mac's code (`App/`, `Sources/`) for the behaviour.

Each criterion has an id. A finding names the id, its severity and its evidence (a `file:line`). **blocker**: it breaks a principle or a line marked blocker here. **minor**: everything else worth fixing.

Inputs, in `build/gauntlet/windows/`: `diff.patch` (the branch against `main`) and `logs/` (`static.log` lists what the static rules checked). Then the code: `windows/NuVa` (the WPF app) and `windows/NuVa.Core` (the logic, with its tests in `windows/NuVa.Core.Tests`). There are **no screenshots**: the app needs Windows and WPF can't render on the Mac, so everything visual is judged from the code that draws it (`windows/NuVa/UI/`). Say so in the report when a finding can only be confirmed on Windows.

## Principles (always blocker)

- **P1 Folders, not metadata.** No code reads tags to name, sort, group or find artwork: no `MusicProperties` read, `GetMusicPropertiesAsync`, `SystemProperties.Music`, `IMFMetadata`, `PKEY_…`, shell thumbnails (`GetThumbnailAsync`), TagLib or an embedded picture. Writing `MusicProperties` on the system media controls (what Windows shows) is not reading. Lists show folder and file names exactly as on disk; order is `NaturalComparer` on the file name (the Mac's `localizedStandardCompare`). Jellyfin is browsed by each item's `Path`, never its tags. The only exceptions are the Mac's: an audio CD's names (MusicBrainz by disc ID) and the artwork lookup (artist and album from the folder names).
- **P2 Native audio.** Media Foundation's Source Reader decodes and `AudioGraph` plays; AIFF and CD audio are PCM that NuVa reads itself. No NAudio, VLC, ffmpeg, BASS, CSCore or any other audio library; no NuGet package at all (`PackageReference` in any `.csproj` or `.props`); P/Invoke only into Windows' own DLLs. Jellyfin streams the original file (`stream.<ext>?static=true`), never a transcode.
- **P3 One small window.** The main window's content is 360 to 480 wide, with the three modes (player with queue, player with folders, compact) and a minimum height of 540 in the first two. The only other windows are the ones the Mac has: the equalizer popover, Ambient (a borderless full-screen window), the mini player in the notification area, the Jellyfin sign-in, the artwork fix, Terms and Privacy, About and the update alert. Closing the main window keeps the music playing.
- **P4 Keyboard first.** Every Mac shortcut exists on Windows with Ctrl for ⌘ and Ctrl+Shift for ⌥⌘, and the same for ⇧⌘ (the Mac's shortcuts are in `App/NuVaApp.swift` and `docs/design-system/README.md`, Shortcuts). Never Ctrl+Alt (it is AltGr on Portuguese keyboards). Every action in the menu (`UI/AppMenu.cs`) shows its shortcut, and the shortcut works without the menu. Media keys and the lock screen work through the system media controls (SMTC), with the media keys handled by the window when SMTC isn't there.
- **P5 Pluggable sources.** The player (`PlayerController`, `Pipeline`) knows entries and location strings (a path, a URL, `cdda://D/3`), never `LocalSource`, `JellyfinSource` or `DiscSource`.

## Design system

- **D1 Colours from tokens only.** Every colour in `windows/NuVa/UI/` comes from a `Token` through `Theme` (`Theme.Brush`, `Theme.Color`, `Theme.Hex(Theme.Skin.Color(token, …))`, `Theme.Rgb`), whose values `scripts/tokens.swift` writes into `NuVa.Core/TokenPalettes.cs` from `docs/design-system/tokens.json`. A literal is any colour not read from a token: `Color.FromRgb/FromArgb/FromScRgb` with numbers, `Colors.…`, `SystemColors.…`, any `Brushes.…` but `Brushes.Transparent`, a `"#RRGGBB"` string or a `0xRRGGBB` passed to `Theme`. **A black or white with an alpha (`FromArgb(128, 0, 0, 0)`, `FromArgb(16, 255, 255, 255)`) is a literal**: a shade or a highlight takes its token (`display-edge`, `key-*-pressed`) or a token with an opacity, as the Mac does. `Brushes.Transparent` is not a colour (it only makes an area take the mouse). `Theme.cs` is the one place that turns a token's value into a WPF colour. The only exceptions are Ambient's, as `docs/design-system/README.md` lists them (the Needles' lamp and the Valves' glow as radial gradients, the cover's glow), and even those are made of tokens. Blocker.
- **D2 One plane.** No cards, outlines around keys, rules between rows or shadows other than `shadow-display` (the display's 1px top edge in `display-edge`). `line` only for printed scales and the edge of a borderless popup or mini player against what is behind it. Blocker.
- **D3 One accent.** `key-play`, `led` and `signal` only on the play key, the LEDs and the playing track's name. Never on a background, hover or other text.
- **D4 Keys.** Every key is a `KeyButton` (`UI/Controls.cs`) with one of its three tones (`Tone.Play`, `Tone.Transport`, `Tone.Mode`); pressed, its face turns to that tone's `key-*-pressed` token and travels 1px; text keys are 28 high in the mode tone.
- **D5 Type.** Text is set through a `TextStyle` (`UI/TextStyles.cs`: `Apply`, `Format`, `Family`, `Size`, `FontWeight`), the counterpart of the Mac's `Font.ds…`; no raw `FontSize`, `FontFamily`, `FontWeight` or `new Typeface` outside `TextStyles.cs`. Numbers in the mono with tabular digits. The font set follows `Theme.FontSet`.
- **D6 Icons.** Every icon is drawn from `UI/Icons.cs` (NuVa's own vectors after the SF Symbols the design system names), never a font glyph, emoji or image file.
- **D7 Truncation.** Names truncate at the end (`CharacterEllipsis`), never in the middle, and the full name is in the tooltip. The display's folder line truncating instead of scrolling is right on Windows (`display-names` is `planned`).
- **D8 Skins.** A skin only changes colours (and its default font set): layout and sizes don't depend on the skin. Rams follows Windows' app mode (Aluminium light, Lead dark); the other skins, and Ambient, always take the dark colours.
- **D9 Motion.** As `docs/design-system/README.md`, Motion: keys 60 ms down and a short spring back, LEDs on in 80 ms and off in 350 ms, hovers 120 ms, state cross-fades 200 ms, faders 300 ms; the time and the position bar never animate.

## Text

- **T1 Both languages.** Every visible string goes through `L.T` or `L.F` with its Portuguese as the key and its English in `NuVa.Core/Strings.json`; none is written in one language only (names that are the same in both, such as "VU", "EQ" or a skin's name, are fine). Portuguese is European ("ecrã", "ficheiro", "pasta", never "tela", "arquivo"). Blocker.
- **T2 Same meaning, same words as the Mac.** The two languages say the same thing and placeholders match. The same Portuguese key has the same English as the Mac's `Resources/Localizable.xcstrings` (the `strings` gate fails on a difference; you check the sense of new keys). Menus in English are in Title Case, legends lowercase, no full stops on buttons.

## Parity

- **M1 The matrix says what the code does.** Each feature's `windows` value in `docs/features.json` matches the code: `yes` only when Windows has it as the Mac does, `planned` when it doesn't yet, `n/a` with a `why` when a principle can't apply (AirPlay). For example: the artist's folder beside the album's on the display, the mini player and Ambient is there (1.12), but the folder line doesn't scroll, so `display-names` is `planned`. Compare each `yes` with the Mac's behaviour; a `yes` that Windows lacks, or a Windows feature the matrix doesn't record, is a blocker.
- **M2 Shared logic is ported.** A Mac change to shared logic (EQ, spectrum, meters, artwork rules, `AlbumGuess`, Jellyfin parsing, disc IDs) has its counterpart in `NuVa.Core`, in the same spirit, with its test in `NuVa.Core.Tests`.

## Code

- **C1 Fits the code around it.** Names, comment density and idioms match the file. Comments in English. No XAML; one file per area in `UI/`.
- **C2 Tested.** New logic in `NuVa.Core` has a `[Test]` in `NuVa.Core.Tests`.
- **C3 No dead code**, debug output (`Console.WriteLine`, `Debug.WriteLine`) or leftover TODOs in the diff. What only Windows can tell goes to `Log.Write` (`nuva.log`).

## Done (only when the diff adds or changes something user-visible)

- **F1** `CHANGELOG.md` has it, one line prefixed "Windows:". Blocker for a new feature.
- **F2** `docs/features.json` records it (`windows` column) and the README and site prose say it in both languages when it's a feature.
- **F3** `TERMS.md` is updated if the change makes a new network call. Blocker.
