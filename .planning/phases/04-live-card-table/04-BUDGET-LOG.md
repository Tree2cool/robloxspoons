# Phase 4 — test runtime budget log

> Evidence for plan 04-20's budget decision checkpoint. **Append one row per wave.**
> Written by the orchestrator, because the measurement that matters is a *controlled* one and no
> single executor can take it: each sees only its own worktree.

## Why wall clock alone is useless here

The same unchanged tree has measured **20.15 s, 26.88 s and 31.54 s** on this container at different
times — an 11 s spread, roughly 3.7x this phase's entire +3 s allowance. An absolute ceiling read off
any one of those is noise, which is why `04-VALIDATION.md` makes the 23.5 s figure a target rather
than a tripwire and makes the per-spec allocation the gate.

**The method that does work, and the one used below:** measure the pre-wave commit and the post-wave
commit *back to back on the same machine under the same load*, and compare the **delta**. A git
worktree at the earlier commit makes this exact.

## Measurements

| Wave | Pre-wave commit | Pre (min) | Post (min) | **Delta** | Cases | Note |
|------|-----------------|-----------|------------|-----------|-------|------|
| 1 | `ae376d6` | 26.88 s (657) | 27.98 s (677) | **+1.10 s** | +20 | Measured back to back. Includes the four guard fixture roots (~0.9 s of subprocess work), which was the single largest named cost in the allocation table and is now **spent** — later waves are in-process pure specs and should be far cheaper. |

**Running total against the +3.0 s allowance: 1.10 s used, 1.90 s remaining.**

## What this means for 04-20's checkpoint

- Do **not** compare a post-phase reading against the 20.15 s baseline recorded during planning.
  That number was taken on a quiet machine and the machine is not quiet now; the pre-wave reading
  above for the very same commit was 26.88 s.
- Take the final reading the same way: `git worktree add` at the pre-phase commit, measure both,
  compare the delta.
- Three consecutive readings within ~0.3 s of each other (as wave 1's were) indicate a *stable*
  machine, not an absence of load — stability and speed are different properties.
