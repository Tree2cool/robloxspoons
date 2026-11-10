# Note: two commit messages in this phase's history are wrong

**2026-11-10. Orchestrator error, recorded rather than rewritten.**

Phase 5's plans were written by a background agent while the orchestrator was committing Phase 04.1
work in the same repository. **The orchestrator used `git add -A`**, which staged whatever the other
agent had written to disk at that moment. Two commits therefore carry Phase 5 plans under Phase 04.1
messages:

| Commit | Message says | Also contains |
|--------|--------------|---------------|
| `83517f7` | "docs(04.1): verify Roblox UI cannot shear" | `05-01-PLAN.md` .. `05-13-PLAN.md` (5,130 lines) |
| `c8973b1` | "docs(04.1): correct my overstatement" | `05-14-PLAN.md` .. `05-16-PLAN.md` (1,173 lines) |

`1e875a9` correctly carries `05-17` .. `05-19`, the traceability edits and the ROADMAP update.

**The files are intact and correct. Only the messages are misleading.** Nothing was lost, duplicated
or half-written: the suite stayed green at 874 passed / 0 failed throughout, and the Phase 5 planner
confirmed it had staged only Phase 5 paths itself.

**Why this is not being fixed by rewriting history.** The branch `claude/happy-cerf-ughp67` is
pushed and the owner has pulled it to a local clone for Studio testing. Rebasing to re-message two
commits would leave that clone diverged from the remote, discovered on waking, for a cosmetic gain.
**A misleading commit message is a smaller problem than a broken working copy**, so the error is
documented where someone tracing these plans would look, and the history is left alone.

**The process fix, applied from this point.** `git add -A` is unsafe whenever a background agent may
be writing. Stage explicit paths instead:

```sh
git add .planning/phases/04.1-first-person-cards/   # not -A
```

**The real lesson is about concurrency, not git.** Two agents writing into one repository need
disjoint paths AND disjoint staging. The disjoint-paths half was planned for and held — no file was
ever written by both. The staging half was not considered at all, and `-A` silently crosses every
boundary the path discipline was protecting.

---

## A second concurrency defect: both phases claimed the same M-numbers

**Found 2026-11-10, before Phase 5 executed.** Phase 04.1 and Phase 5 were planned in parallel by
two agents. Each read `MANUAL-CHECKS.md`, saw seventeen rows, and allocated "the next free ids"
starting at **M-18**. Neither could see the other's plans, because neither existed yet when the
other was read.

- 04.1 **wrote** M-18..M-23 into `MANUAL-CHECKS.md` when its wave 0 executed.
- Phase 5's nineteen plans **intended to write** M-18..M-24.

Six numbers collided. Had Phase 5 executed, its wave-1 plan would either have overwritten six of
04.1's rows or produced duplicate headings — and `verify.luau` parses those rows by name, so the
damage would have surfaced as a confusing parse result rather than as a conflict.

**Fixed by renumbering Phase 5 to M-24..M-30** across 18 files (the plans plus PATTERNS, RESEARCH
and VALIDATION), descending so no mapping collided mid-pass. 04.1's rows are untouched; it executed
first and owns the lower block.

**This is the same root cause as the `git add -A` incident above**, and that is the point worth
keeping. Two agents sharing a repository need disjoint *paths*, disjoint *staging*, and disjoint
**identifier allocations**. The first was planned for and held. The second was not considered. The
third was not considered either — and unlike staging, nothing in git would have caught it: both
plan sets were internally consistent, passed their own validators, and passed a plan check.

**The general rule:** when two agents allocate from a shared numbering space, the allocation must
be made by whoever can see both, or reserved in advance. "Take the next free id" is only safe when
exactly one party is taking.
