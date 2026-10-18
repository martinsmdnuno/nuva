# Plan: skins, fonts and artwork

Status: proposal, nothing built yet.
Inputs: the user's request, `NuVa_Design_Spec_v1.pdf` ("Graphite" skin, Orange and Green), and the current design system (`docs/design-system/`).

## Guardrail: NuVa's principles always win

Every skin, font set and option in this plan keeps NuVa's original principles. When a spec, a mockup or a skin asks for something that breaks them, the principle wins and the spec is adapted, never the other way round. No principle is reworded to make room for a feature.

From `CLAUDE.md`:

1. **Folders, not metadata.** Folder and file names verbatim; never read tags to organise or to show.
2. **Native audio.** AVFoundation only. Skins and artwork don't touch the audio path.
3. **One small window.** 360 / 720 pt wide, Compact mode; no deep navigation.
4. **Keyboard first.** Every new option has a menu item and, where it makes sense, a shortcut.
5. **Pluggable sources.** The player doesn't know where music comes from; artwork goes through `MusicSource` too.

From `docs/design-system/README.md`:

- **Function first**, no decorative elements, no giant cover art.
- **Less, but better:** one plane, no cards, no outlines around keys, no rules between rows.
- **The device, not the app:** the display is always dark.
- **One accent in three linked roles:** play key (`key-play`), LEDs (`led`), playing track (`signal`). Never on backgrounds, hovers or other text. State is shown by LEDs.
- **Every text pair passes 4.5:1.**

What this rules out from the Graphite spec: its layout (1050 × 650, three panes, search header, queue in a drawer, 36–42 pt rows), the accent on hover and progress, outlined keys, and any artist/album text.

## Goals

1. **Skins.** The 1.0 look becomes the default skin, named **Nuno** (Lead and Aluminium, following the system). Skins are switched from the menu and the choice persists.
2. **Second skin as a test.** **Graphite Orange** and **Graphite Green**, built from the spec's colours and adapted to the principles above.
3. **Font choice.** An alternative font set, chosen independently of the skin.
4. **Artwork on/off.** Show or hide a small album image taken only from an image file in the folder.

## Core decision: a skin is tokens, not layout

- **A skin = colours + appearance policy** (follows system, or always dark). Same views, same layout, same sizes, same rules for where each token may be used.
- **Fonts are a separate setting.** Each skin names a default font set; the user can override it. Sizes, weights and line heights stay the design system's in every set.
- The Graphite layout is not built, now or later as part of this work: it breaks "one small window".

## Phases (one commit per step, `xcodebuild` after each)

### Phase 1. Skin infrastructure, zero visual change

- `Sources/DesignSystem/Skin.swift`: `struct Skin { id, name, appearance: .followsSystem | .alwaysDark, colors: [Token: (light, dark)] }`, with the 22 existing tokens as the semantic vocabulary. A skin can change a token's value, never add a role or move the accent elsewhere.
- `SkinStore` (`@Observable`, persisted in `UserDefaults` key `skin`, default `nuno`).
- `Color.ink`, `Color.surface0`… keep their names (no call-site churn), but resolve through `NSColor(name:dynamicProvider:)`, which reads the current skin and the appearance. Nuno reads the existing colour sets in `Assets.xcassets`, which stay the source of truth for that skin.
- Appearance: `.alwaysDark` sets `NSApp.appearance = .darkAqua`; `.followsSystem` sets `nil`.
- Repaint on change: `.id(...)` on the root of the window and the menu bar player.
- Fix the places that read colours by name outside `Color`: `ControlBar` (AirPlay picker ink), `KeyPreview`, `MenuBarPlayer`.
- **Check:** `--snapshot` before and after must be pixel-identical.

### Phase 2. Switching skins

- Menu **View ▸ Skin ▸ Nuno / Graphite Orange / Graphite Green**, with shortcuts (keyboard first, no pixels on the chassis).
- Same submenu in the menu bar mini player, behind a mode key (`circle.lefthalf.filled`); the mini player grows from 320 to 360 pt, the main window's width, so the key fits next to "Open NuVa" and "Quit".
- No key or picker in the main window or title bar: a control used once a month would take permanent space on a 360 pt chassis, against "function first".

### Phase 3. Font sets

- `Sources/DesignSystem/FontSet.swift`: `struct FontSet { id, name, sans, mono per weight }`, persisted in `UserDefaults` key `fontSet`, default `skin` (use the skin's default).
- Sets:
  - **Inter + IBM Plex Mono** (1.0, embedded, Nuno's default).
  - **SF Pro + SF Mono** (system, nothing to embed; Graphite's default, as the spec suggests).
- Only families that have the 300/400/500 weights, tabular digits in the mono (the display time can't change width every second) and full Latin Extended (ã, õ, ç).
- `Font.dsTitle`, `Font.dsBody`… are `static let` today (fixed at launch); they become computed and read the current set. The root `.id(...)` combines skin and font set.
- The three direct `Typography.mono(...)` calls (`BarSlider` scale, `QueueList` shortcut and detail) get named styles in `tokens.json` so they follow the set. SF Symbols stay as they are.
- Menu **View ▸ Font ▸ Skin default / Inter + Plex Mono / SF Pro + SF Mono**.
- **Check:** `--snapshot` with each set in all three window modes: truncated names, display time width, Compact height.

Done. In the snapshots SF Mono makes the display about 4 pt shorter (and Compact with it); names didn't truncate in the samples.

Risks: SF Pro is wider than Inter, so verbatim names truncate sooner in the fixed 360 / 720 pt widths; different ascenders change how 13 px text sits in a 28 pt row and the Compact height.

### Phase 4. Graphite skins (the test)

The spec's colours, applied under NuVa's rules. Contrast fixes are not optional: "every text pair passes 4.5:1" is a principle.

| NuVa token | Graphite Orange | Graphite Green | From the spec |
|---|---|---|---|
| surface-0 | #0B0F10 | #0B0F10 | Background |
| surface-1 | lighter than #111618, ≥ ~1.2:1 on surface-0 | same | Surface |
| surface-2 | lighter than #24201B, ≥ ~1.3:1 on surface-1 | lighter than #15251C | Raised / selected |
| ink | #F2F4F5 (not pure white) | same | Primary text |
| ink-muted | ~#9AA3A7 | same | Secondary text |
| line, track | #2A3032 (decorative only) | same | Subtle border |
| key-play, led, signal | #FF6A00 | #20D66B | Accent, in its three roles only |
| key-ink | #0B0F10 (dark icon on the accent key) | same | not in the spec |
| fill, key-face, key-mode, key-mode-ink | neutral greys, to define | same | not in the spec |
| display, display-ink, display-muted, display-track | always dark, to define | same | not in the spec |
| led-off, danger, focus | to define | same | not in the spec |

- Not used: "Accent hover" (NuVa shows state with LEDs, not hover), accent on progress or volume (stays neutral `fill`), the "accent rail" on folders (selection stays `surface-2`).
- Always dark, doesn't follow the system.
- Add the skins to `tokens.json` (`themes`: `nuno-lead`, `nuno-aluminium`, `graphite-orange`, `graphite-green`) and `docs/design-system/skins/graphite.md`.
- **Check:** contrast script over every text and key pair (4.5:1 text, 3:1 icons and focus).

### Phase 5. Artwork, folder-based, small and optional

- `MusicSource` gains `func artwork(for folder: Entry) async throws -> URL?`, default `nil`.
- `LocalSource` only: looks in the folder for `cover`, `folder`, `front`, `album` with `.jpg/.jpeg/.png` (case-insensitive). Never reads embedded tags.
- `JellyfinSource` returns `nil` for now: Jellyfin's `Primary` image may have been extracted from tags, and we can't tell, so it would break "folders, not metadata".
- Downsampled in-memory cache (`CGImageSourceCreateThumbnailAtIndex`).
- **View ▸ Show artwork**, `@AppStorage("showsArtwork")`, **off by default**.
- Where: a small square inside the display, at the left, the height of the time and title block (~56 pt), aspect-fit, never cropped or tinted. It sits on the device's screen, keeps one plane and isn't "giant cover art"; the window size doesn't change. Not shown in Compact. No artwork: nothing, the display looks as in 1.0.
- When on, Now Playing uses the folder image instead of the NuVa icon.
- `CLAUDE.md`: "cover art" moves from *Out* to *In* as "folder artwork (local, optional)". The design system principles stay as they are.

### Phase 6. Docs, snapshots, release

- Strings in `Localizable.xcstrings` (pt key + en).
- `--snapshot` per skin and font set; README with a Graphite image.
- `CHANGELOG.md`, version 1.1.

## Risks in the Graphite spec

Contrast numbers are WCAG ratios computed from the spec's hex values.

1. **Layers are invisible.** Background vs Surface is **1.06:1**; Raised/selected vs Surface is **1.13:1** (Orange) and **1.14:1** (Green). The selected row and the popovers would hardly be seen.
2. **Borders below 3:1.** Subtle border on Background is **1.44:1**. Fine for decorative lines only.
3. **No text hierarchy.** Secondary #D8DCDE vs primary #FFFFFF is **1.38:1**. Pure #FFFFFF on #0B0F10 (**19.3:1**) causes glare in long lists.
4. **Light icon on the accent fails.** White on #FF6A00 is **2.87:1**, on #20D66B **1.93:1**. The icon on the play key has to be dark (6.7:1 and 10:1). The mockup's outlined ring isn't allowed (no outlines on keys).
5. **Hover indistinguishable.** Accent hover vs accent is **1.18:1**; and hover isn't how NuVa shows state.
6. **Tokens missing.** 8 tokens against NuVa's 22: no focus, error, disabled, LED off, display or key faces. Those are our decisions, so the test only partly tests the spec.
7. **Accent overuse.** Active states, progress, play, playing row and hover, against NuVa's one accent in three roles.
8. **The mockup breaks its own rules.** Artist/album text in folder-only mode, hardcoded "24-bit / 96 kHz", and two progress bars.
9. **Different product.** 1050 × 650, search, queue only as a drawer, 36–42 pt rows: breaks "one small window", Compact mode and the queue.
10. **Dark only.** Graphite won't have a light variant until someone designs one under the same rules.

## Decisions settled by the principles

- Skin = colours only; the Graphite layout is not built.
- Switching from the menu only.
- Graphite with the contrast fixes from the start.
- Artwork from local folders only, small, inside the display.
- Font sets: only Inter + IBM Plex Mono and SF Pro + SF Mono; nothing new embedded.
