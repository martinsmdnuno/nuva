# Gauntlet

A loop that runs one platform through a fixed series of gates, fixes what fails and starts again, until every gate passes or the round limit is reached. Then a person decides.

```
objective gates → judge → green?  ─ yes → report
      ▲                    │
      └──── fix one ◄──── no (max 5 rounds, then stop and ask)
```

## Two halves

1. **Objective gates**: `scripts/gauntlet.sh <platform>`, the platform's gates in `scripts/gauntlet/<platform>.sh`. Build, warnings, tests, strings, content, screenshots in both languages, cheapest first, stopping at the first that fails. Logs, screenshots and the diff against `main` go to `build/gauntlet/<platform>/`.
2. **The judge**: a separate agent (`.claude/agents/gauntlet-judge.md`) that never wrote the code. It reads that folder and grades it against the platform's rubric in this directory. It reports, never edits.

Only `blocker` findings from the judge send the loop round again; `minor` ones go to the report.

## Rules

- The rubric is the contract. The judge grades against it and nothing else; it never adds criteria. The principles in `CLAUDE.md` win over any rubric line. A loop never edits a rubric, `CLAUDE.md` or `docs/design-system/` to pass.
- One fix per round, one commit per fix, on a branch, never on `main`.
- A gate is never weakened, skipped or deleted to pass. If a gate itself is wrong, the loop stops and asks.
- Five rounds at most. The same failure twice in a row also stops it.

## Platforms

| Platform | Gates | Rubric |
|---|---|---|
| Mac | `scripts/gauntlet.sh mac` | `mac.md` |
| Android TV | planned | planned |
| Windows | `scripts/gauntlet.sh windows` (builds and tests on the Mac; no screenshots, the app needs Windows) | `windows.md` |
| Site | `scripts/gauntlet.sh site` | `site.md` |

Run it in Claude Code with `/gauntlet <platform>`.
