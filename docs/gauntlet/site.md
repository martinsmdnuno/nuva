# Gauntlet rubric: Site

What the judge grades after `scripts/gauntlet.sh site` passes. Every line comes from `CLAUDE.md` ("Parity and content", "Site"), `docs/design-system/`, `site/platform.js` or `TERMS.md`; when they disagree, they win and this file is wrong.

Each criterion has an id. A finding names the id, its severity and its evidence (a `file:line` or a screenshot name). **blocker**: it breaks a principle or a line marked blocker here. **minor**: everything else worth fixing.

Inputs, in `build/gauntlet/site/`:
- `snapshots/en/` and `snapshots/pt-PT/`: `home-<platform>-<size>-<theme>.png` (platform `mac`, `tv`, `windows`, opened at `/#mac`, `/#android-tv`, `/#windows`, or `/pt/…`) and `privacy-<size>-<theme>.png`; size `phone` (390 wide) or `desktop` (1440 wide); theme `light` (Aluminium) or `dark` (Lead). Each is the whole page, captured with reduced motion. The same captures cut into readable pieces two screens tall are in `tiles/` (`…-01.png`, `-02`…): look at the tiles, not the full images, to read text.
- `render.json`: what the browser measured on each capture (the platform shown, the page's width against the window's, and any text under 4.5:1).
- `diff.patch` (the branch against `main`) and `logs/` (one per gate).

The code: `site/` (pages, `style.css`, `platform.js`, `feedback.js`, `llms.txt`, `sitemap.xml`, `robots.txt`, `img/`, `fonts/`) and `deploy/site/` (`Caddyfile`, `feedback.py`, `docker-compose.yml`). The checks the gates ran are in `scripts/site-check.py`; the judge doesn't repeat them, it grades what they can't see.

## Principles (always blocker)

- **P1 The site says what NuVa is.** Folders, not metadata; native audio; one small window; keyboard first; pluggable sources. No sentence promises the opposite (reading tags to organise, a bundled codec, VLC or ffmpeg, a library rebuilt from tags).
- **P2 Never claims what the matrix doesn't have.** Every capability the site states for a platform is `yes` for that platform in `docs/features.json`. A `planned` one is said as "later"/"on its way" or not at all; an `n/a` one is never claimed (e.g. AirPlay on Windows or Android TV, local folders or CDs on Android TV). Out-of-scope items in `CLAUDE.md` (search, favourites, accounts, Plex, UPnP) are never offered. Generated `<!-- nuva:NAME -->` blocks come from the matrix; the prose around them is what you check.
- **P3 EU rules.** No cookies, no local or session storage, no analytics, no access log, nothing loaded from another host (fonts, images, scripts, styles, frames). The CSP in `deploy/site/Caddyfile` keeps `default-src 'self'` and names no other host. Plain links (`<a href>`) to GitHub and the like are fine.
- **P4 The privacy notice is true.** `/privacy/` and `/pt/privacidade/` describe what the site does (hosting, no access log, the feedback form through Gmail, no storage) and point to `TERMS.md` for the apps; nothing on the site or in `deploy/site/` does something the notice doesn't say. Any new third party or data use needs the notice updated in both languages first.

## Design system

- **D1 Same tokens as the app.** Lead (`chumbo`) in dark, Aluminium (`aluminio`) when the system is light; every colour in `site/style.css` is a value from `docs/design-system/tokens.json` for that theme (look at `:root` and the light media query). The display is always dark, in both themes. Blocker.
- **D2 Same type.** Inter for text and IBM Plex Mono for the display, numbers and code, served from `site/fonts/` as WOFF2. No other family is drawn.
- **D3 One plane.** No cards, outlines around keys or shadows other than the display's recess (`shadow-display`) and the pressed platform key. Hierarchy from key colour and space. Look at every screenshot.
- **D4 One accent.** Amber only on the play-tone key (Download, Send), the LEDs and the display's dots. Never on a background block, a heading or body text.
- **D5 Keys and LEDs as in the app.** Keys are flat (`key play`, `key mode`), each group with its LED and legend; the platform key that's on has its LED lit.
- **D6 Contrast.** Text readable on its background in every screenshot, 4.5:1 (3:1 for 24 px and up); the `layout` gate measures the CSS colours, you check what the measure can't (text over an image, a focus ring, a lit LED next to its key). Blocker.

## Layout

- **L1 No sideways scroll at 390 px.** Nothing wider than the window, nothing cut off at the right edge in the `phone` screenshots (code blocks scroll inside themselves). Blocker.
- **L2 Nothing overlaps or is clipped** in any screenshot, in either language (Portuguese is longer: compare `pt-PT` and `en`). Blocker.
- **L3 Images keep their shape.** Every `<img>` has `width` and `height` (the `html` gate checks); in the screenshots no image is stretched or squashed, and the screenshots shown are NuVa's own (`docs/screenshots` as WebP).
- **L4 The header** stays one line at 390 px and shows the brand, the language switch and the anchors that fit.

## Platforms (the switcher)

- **S1 One key per released platform.** The switcher has a key for each platform that is `released` and `public` in `docs/features.json`, in its order; the address is `#mac`, `#android-tv` (`#tv` also works) or `#windows`, nothing is stored, and without JavaScript the page shows the Mac and hides the switcher. Blocker.
- **S2 Every platform has its own text and pictures.** Each `home-<platform>` screenshot shows that platform's lede, download key, version line, features, ambient, design and contribute text; no section is empty or shows another platform's download for it. Where a platform has no screenshot of its own (Windows), the picture shown is the drawn display or a picture that is true for it (the skins and ambient faces it shares with the Mac), never one that shows something it doesn't do (AirPlay on Windows). Blocker.
- **S3 The download is right.** Each platform's download key links that platform's asset at `releases/latest/download/` (from the matrix), and the install hint (Gatekeeper on the Mac, Downloader on the TV, "Run anyway" on Windows) is the one for that platform.

## Text

- **T1 Both languages.** `/` and `/privacy/` are English; `/pt/` and `/pt/privacidade/` are European Portuguese (not Brazilian: "ecrã", "ficheiro", "descarregar", "tu" forms; never "tela", "arquivo", "baixar", "você"). No Portuguese left on an English page or the reverse (the language links, in their own language and with `lang`, are the exception). Blocker.
- **T2 Same meaning.** EN and PT say the same thing, section by section, in the same order, with the same platform variants and images (the `parity` gate checks the structure; you check the sense). The FAQ answers match their JSON-LD (the `seo` gate checks).
- **T3 Plain and true.** Short sentences, no marketing superlatives, no claim that can't be checked in the app (formats, requirements, versions as the matrix and `project.yml` say).

## SEO and GEO

- **G1** Each page: one `<h1>`, a title up to 65 characters and a meta description of 70–160 that say what the page is, in its language; `hreflang` pairs and canonical right; `sitemap.xml`, `robots.txt` and `llms.txt` in step (the gates check). You check that the title and description are worth reading.
- **G2** JSON-LD `SoftwareApplication` and `FAQPage` agree with the page and with each other across languages; `llms.txt` describes every released platform.

## Done (only when the diff changes what the site says)

- **F1** A new claim is in `docs/features.json` first, and in both languages. Blocker.
- **F2** A visible change that is news for users has a `Site:` line in `CHANGELOG.md`.
- **F3** Images in `site/img/` are WebP copies of `docs/screenshots` (`cwebp -q 82`); every file in `site/` is used.
