# Gauntlet rubric: Android TV

What the judge grades after `scripts/gauntlet.sh tv` passes. Every line comes from `CLAUDE.md`, `android/CLAUDE.md` or `docs/design-system/`; when they disagree, they win and this file is wrong.

Each criterion has an id. A finding names the id, its severity and its evidence (a `file:line` or a screenshot name). **blocker**: it breaks a principle or a line marked blocker here. **minor**: everything else worth fixing.

## Inputs

In `build/gauntlet/tv/`: `diff.patch` (the branch against `main`), `logs/` (build, lint report, the stand-in's requests) and `snapshots/pt-PT/` and `snapshots/en/`, 1920×1080 captures of the debug build on the `nuva_tv` emulator (960×540 dp), driven with the remote's keys against `scripts/gauntlet/jellyfin-standin.py` (a made-up library; its tracks are tones, 3:00 each). Each folder has the same files:

- `tv-sign-in.png` (first run), `tv-folders.png` (the library's top), `tv-folders-long.png` and `tv-folders-long-inside.png` (a folder name longer than the list, with the focus on it and then inside it), `tv-folders-album.png` (an album's tracks, the first with the focus).
- `tv-player.png` (the queue, the second track playing), `tv-scrub.png` (the position bar held with OK, 20 s on: the elapsed time lit, the bar thicker; the quality badge right of the time), `tv-ambient-scrub.png` (↓ on the Display face holds the bar, 20 s on, the keys' hint below), `tv-equalizer.png` (Rock chosen), `tv-equalizer-bands.png` (a fader held with OK, its LED lit, and raised), `tv-equalizer-back.png` (OK lets go of the fader, ↑ reaches the presets), `tv-queue-actions.png` (OK held on a queue row), `tv-mode.png` (the mode key pressed twice: repeat all, named under it), `tv-settings.png`, `tv-exit.png` (Back on the main screen).
- `tv-ambient-display.png`, `-clock`, `-spectrum`, `-meters`, `-needles`, `-valves`: the six faces.
- `tv-player-graphite-orange.png`, `tv-folders-graphite-orange.png`, `tv-player-phosphor.png`, `tv-folders-phosphor.png`: the other skins (the unsuffixed views are Rams).

Look at every one of them in both languages. The code is in `android/app/src/main/java/pt/nunomartins/nuva/` (`ui/` for the screens), the text in `android/app/src/main/res/values/strings.xml` (English) and `values-pt/strings.xml` (Portuguese), the tests in `android/app/src/test/`.

## Principles (always blocker)

- **P1 Folders, not metadata.** Jellyfin is browsed by each item's `Path`, never by its `Name`, artists, albums, genres or other tags (no `/Artists`, `/MusicAlbums`, `AlbumArtist`, `IncludeItemTypes=MusicAlbum` or ID3/Vorbis reading). Lists show folder and file names exactly as on the server's disk (a track without its extension), folders first, in natural order (`NaturalOrder`: "2" before "10", case and accents ignored). The display's line is the artist's and album's folders (`Entry.folderLine`). The only exception is the artwork lookup by folder names, as `CLAUDE.md` describes it.
- **P2 Native audio.** Playback through Media3's ExoPlayer with Android's own decoders. No extension decoders (`media3-decoder-*`, ffmpeg, VLC) and no other audio library in `android/app/build.gradle.kts`. The stream is the original file: `/Audio/{id}/stream.<ext>?static=true`, never a transcoding URL.
- **P3 One screen.** Display and keys on the left, the folders or the queue on the right; everything else is an overlay over it (`Overlay` in `AppModel.kt`) or ambient mode. No new screen, navigation stack or `Activity`.
- **P4 Remote first.** Every action is reachable with the D-pad and OK alone, from where the focus starts, and every screen can be left with Back. A control that keeps ↑ ↓ or ← → for itself (a fader, a text field) still lets the focus reach every other control on that screen. Play/pause, next and previous work from the remote's media keys, also with another app in front (`PlaybackService`, a `MediaSessionService`). In the screenshots: the focused control always shows the focus ring or the focused row's `surface-2`, and exactly one thing has it on screens that take the focus (ambient takes none).
- **P5 Pluggable sources.** The player (`player/`) knows entries and URLs, never `JellyfinSource`.

## Remote

- **R1 Back.** Back closes the overlay that is open (and ambient mode), then goes up a folder, then asks before leaving the app (`tv-exit.png`); leaving keeps the music playing. Blocker if Back ever does nothing or leaves the app without asking from the main screen.
- **R2 Focus lands.** Opening an overlay puts the focus inside it, on its first row or key (the equalizer: its first preset; the arrows move between the on/off key, the presets and the faders, and only a fader held with OK keeps ↑ ↓ for itself, `tv-equalizer-back.png`); closing it puts the focus back on the main screen; after a folder opens or closes, the focus is on a row of the list (the folder just left, going up); playing a folder puts it on the play key (`tv-player.png`).
- **R3 Holding OK** is the "more" gesture (add to the queue, the queue row's actions), and each list says so in its legend.

## Design system

- **D1 Colours from tokens only.** Every colour on screen is a token read through `Tokens` (`ui/Theme.kt`), whose values come from `Palettes.kt`, which `scripts/tokens.swift` writes from `docs/design-system/tokens.json` (never edited by hand: its first line says so). No `Color(0x…)`, `Color(r, g, b)`, `Color.Black`, `Color.White`, `Color.Gray` or any other named colour in `ui/` outside `Palettes.kt`, with or without `.copy(alpha = …)`: a shade, a scrim or a highlight gets its own token or is a token with an alpha. A token with `.copy(alpha = …)` is a token and passes. `Color.Transparent` passes (it is no colour), and so does the path fill in `Icons.kt`, a mask that the key's tint replaces. Computing a colour from a token (darkening it, mixing two) doesn't pass where a token exists for it: a pressed key is `key-play-pressed`, `key-face-pressed` or `key-mode-pressed`. Ambient's two exceptions, as `docs/design-system/README.md` lists them (the Needles' lamp and the Valves' glow as radial gradients, and the artwork glow), pass when they are built from tokens. Blocker.
- **D2 One plane.** No cards, outlines around keys, rules between rows or shadows. Overlays (equalizer, settings, queue actions, leaving) are `surface-1` panels over the chassis darkened behind them; that is the popover, not a card. The focus ring is the only outline. Blocker.
- **D3 One accent.** The accent (`key-play`, `led`, `signal`) only on the play/pause key, the LEDs and the playing track's name. Never on a background, another key's face or other text. Text keys (Play Folder, Sign In, Stay, Leave, the equalizer's on/off and presets) are `key-mode` (`docs/design-system/README.md`, Keys).
- **D4 Keys.** Every key is `Key` (`ui/Components.kt`) with one of the three tones (`Tone.Play`, `Tone.Transport`, `Tone.Mode`); keys with state (the mode key, lit in any mode but normal, with the mode's name as its legend; the equalizer's on/off and its presets, the active one lit) have their LED, on or off; state is never shown by a different face.
- **D5 Type.** Text is drawn with `Text`, `ScrollingText` or `BasicText` in a `Type` style (`ui/Theme.kt`, the Mac's styles at twice their size, in the current font set). `.copy(color = …)` is fine; `.copy(fontSize = …)` only takes another `Type` style's size as it is. No `TextStyle(`, `FontFamily` or literal `sp` outside `Theme.kt`, except in `AmbientScreen.kt`, whose sizes come from the screen's width (the `ambient-*` styles). Numbers (time, durations, the equalizer's dB) in the mono.
- **D6 Truncation and fit.** Nothing clipped, overlapping or cut by the screen's edge in any screenshot, in either language (Portuguese is longer: compare `pt-PT` and `en` of the same view). Text that doesn't fit ends at its end, never the middle. A name longer than its place slides (`ScrollingText`): on the display always, in a list while its row has the focus; in a screenshot it may show anywhere in its slide, or cut at its end, and that passes. Any other clipped text (a key's label cut short, a title cut by a panel) is a blocker.
- **D7 Skins.** A skin changes colours and its default font set only: `tv-player.png`, `tv-player-graphite-orange.png` and `tv-player-phosphor.png` (and the three `tv-folders*`) have the same controls in the same places and sizes. Graphite Orange's font set (Roboto, as SF on the Mac) sets lines a few dp shorter, as `docs/design-system/README.md` says of SF; that passes.
- **D8 Contrast.** Text readable on its background in every screenshot (4.5:1 for text, 3:1 for keys, LEDs and the focus ring), in every skin.
- **D9 Ten feet.** Sizes for a screen across the room: the Mac's at twice their points, in dp, on the 960×540 dp canvas (`android/CLAUDE.md`). No text smaller than `Type.legend` and `Type.hint` (15 sp), the smallest styles.

## Text

- **T1 Both languages.** Every visible string in `en` screenshots is English and in `pt-PT` is European Portuguese (not Brazilian: "ecrã", "ficheiro", "utilizador", "palavra-passe", never "tela", "arquivo", "usuário", "senha"). No Portuguese left in English or the reverse. Names that aren't translated (NuVa, Jellyfin, the skins', fonts' and presets' own names, "Loudness", "Rock") pass. Blocker.
- **T2 In the resources.** Every string a user sees is in `res/values/strings.xml` and `res/values-pt/strings.xml` (the `strings` gate checks the keys, you check there's no user-visible literal in Kotlin other than names and numbers), with the same meaning and placeholders in both. Chassis legends in lowercase.

## Code

- **C1 Fits the code around it.** Names, comment density and idioms match the file. Comments in English.
- **C2 Tested.** New logic in `library/`, `audio/`, `artwork/` or `player/` has a unit test in `android/app/src/test/`; a port of the Mac's shared logic (EQ, spectrum, artwork rules, Jellyfin parsing) has the matching test.
- **C3 No dead code**, debug logs (`Log.d`, `println`) or leftover TODOs in the diff.
- **C4 No new dependency** in `android/app/build.gradle.kts` beyond AndroidX, Media3 and Kotlin's own libraries.

## Done (only when the diff adds or changes a feature)

- **F1** `docs/features.json`'s `tv` value matches what the app does: `yes` only when it works on the TV, `planned` when it doesn't yet, `n/a` with a `why` for the TV. Blocker.
- **F2** `CHANGELOG.md` has it, in a line that starts with "Android TV:".
- **F3** `TERMS.md` is updated if the change makes a new network call. Blocker.
