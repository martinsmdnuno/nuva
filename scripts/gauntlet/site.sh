# Site gates for scripts/gauntlet.sh (sourced; `gate`, `$out` and `diff_for_judge` come from there).
# The checks themselves are in scripts/site-check.py (standard library only); the rubric the judge
# reads after is docs/gauntlet/site.md.

site_check() { python3 scripts/site-check.py "$@"; }

gate content   scripts/check-content.sh
gate html      site_check html
gate links     site_check links
gate privacy   site_check privacy
gate seo       site_check seo
gate parity    site_check parity
# Serves site/ on a free local port and captures it with Chrome headless: en and pt-PT, phone 390 and
# desktop 1440, light and dark, each platform and the privacy page, full height.
gate snapshots site_check snapshots $out
# What the browser measured on each capture: no sideways scroll, the platform asked for, 4.5:1 text.
gate layout    site_check layout $out
