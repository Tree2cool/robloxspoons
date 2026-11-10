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
