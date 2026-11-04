---
name: gauntlet
description: Run NuVa's gauntlet loop for one platform (mac, tv, windows or site) — objective gates, then an independent judge, fixing one failure per round until everything passes or five rounds are used. Use when the user says /gauntlet, "run the gauntlet" or asks to evaluate and fix a platform end to end.
argument-hint: <mac|tv|windows|site>
---

# Gauntlet loop

Read `docs/gauntlet/README.md` first; its rules bind every round. The platform is the argument (default `mac`).

## Before round 1

- Never on `main`: if on it, create `claude/gauntlet-<platform>-<yyyymmdd>`. Work on a clean tree; if it isn't clean, stop and ask.
- Note the starting commit, so the report can list what the loop changed.

## Each round (at most 5)

1. **Gates.** `scripts/gauntlet.sh <platform>` (it takes a few minutes; give it a 10-minute timeout). If it fails, read `build/gauntlet/<platform>/summary.txt` and the failing gate's log, go to step 3 with that failure.
2. **Judge.** Only when every gate passes. Launch the `gauntlet-judge` agent with the platform name and nothing else of yours: no explanations of what you changed, so it grades the work, not the story. If the verdict is `pass`, the loop ends. Otherwise take the first blocker.
3. **Fix one thing.** The smallest change that fixes that one failure or blocker, in the style of the code around it. Then one commit, named after what it fixes, with the attribution lines. Back to step 1.

Stop early and ask the user when:
- the same failure or blocker comes back in two rounds in a row;
- the fix needs a decision that is the user's (a principle, a design call, a new string's wording beyond the obvious, anything in `docs/features.json` other than recording what exists);
- the fix would touch a rubric, `CLAUDE.md`, `docs/design-system/`, or a gate (weakening, skipping or deleting one is never a fix);
- a gate is flaky (passes and fails with no change).

## Never

- Merge, push, release or deploy. The loop ends with a branch for the user to review.
- Fix minor findings inside the loop. They go in the report; the user picks.

## Report (in the user's language)

- Rounds used and how it ended (pass, limit, or stopped and why).
- Each round: what failed, what was changed, the commit.
- The judge's last verdict, with the minor findings and "outside the rubric" notes as they came.
- What to do next: review the branch, open a PR, or a decision the user has to make.
