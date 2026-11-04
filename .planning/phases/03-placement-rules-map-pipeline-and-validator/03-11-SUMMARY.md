# Plan 03-11 — Owner sign-off on Gate G2 and the Studio manual checks

**Completed:** 2026-11-04
**Type:** checkpoint:human-verify (non-autonomous)
**Outcome:** **Gate G2 PASSED (owner).** Phase 3 closes; Phase 7a is unblocked.

## What the owner did

One Studio session on `build/spoons.rbxl`, covering both blocking manual checks.

| Check | Reading | Verdict |
|---|---|---|
| **M-08** | `StarterPlayer.CharacterMaxSlopeAngle = 89` vs `MAX_SLOPE_DEGREES = 30` | PASSES, 59 degrees headroom |
| **M-10** step 1 | `[Spoons] map loaded: GrayBox`, no `MapValidator` error | PASSES |
| **M-10** step 2 | `GrayBox: yes \| Geometry: yes \| Data: yes` | PASSES |
| **M-10** step 3 | `Workspace` held `Geometry` only; `Data` and `GrayBox` absent | PASSES |
| **M-10** step 4 | `CollectionService:GetTagged("SpoonDefaultSpot")` = **21** | PASSES |

`verify.luau` now reports **8 signed off, 2 unsigned**; both remaining checks are playtest-gated and
neither blocks this phase.

## Two things worth keeping

**Gate 8's structural gap is closed as far as it can be.** `MapLoader` ran the same
`MapValidator.validate` over its **own** snapshot of the live tree against the same
`Config.Placement`, so a value-level divergence between the runtime and CI snapshotters big enough
to change a verdict would have surfaced as a named issue code. It did not. CI compares key sets
only and no CI arrangement can do more — this is why M-10 was added as blocking during planning.

**The anti-ESP property was observed directly for the first time.** `Data` and `GrayBox` were both
absent from `Workspace`. M-06's own note recorded that this had never been eyeballed.
`CrateNorthEastRoom` in `Workspace.Geometry` independently confirms the session ran against the v2
map, since 03-06 added that crate for the fourth spot height.

## Deviations from the plan

1. **The plan grouped M-09 into this session; it does not belong there.** M-09's own text says
   "Blocking: no for Phase 3 — it needs a Phase 4/6 playtest", because standing avatars at the
   scale extremes requires a full roster. The orchestrator made this error in STATE.md, corrected
   it before the session, and only M-08 and M-10 were run. M-09 remains carried and unsigned.
2. **The Tag Editor route did not exist in this Studio build.** Its View menu does not list the Tag
   Editor, so the 21-spot count was taken with
   `#game:GetService("CollectionService"):GetTagged("SpoonDefaultSpot")` in the command bar, in Edit
   mode. Same measurement, fewer steps; future runs of M-10 should prefer the command bar.
3. **`ServerStorage` reads as EMPTY in the Explorer while Playing**, which looked like a failure and
   is not: it does not replicate to clients. `MapLoader.luau:91` would have thrown
   `ServerStorage.Maps does not exist` otherwise. **M-10's steps should say so**, because the next
   person to run this check will hit the same thing.

## Unrelated observation

A Studio warning, `rbxassetid://203785492 ... Asset type does not match requested type (x2)`,
appeared in Output. The id does not occur anywhere in this repository.

## Decisions taken at sign-off

- **CI suite timing ACCEPTED** as a second approved departure: 15.94 s -> ~25-26 s -> **29.9 s**
  (chain 32.6 s). Nothing was trimmed to reach it. `03-VALIDATION.md`'s latency item is ticked with
  that rationale. Phase 4 should expect to revisit it.
- **Section 5's Phase 7a authoring rules reviewed and stand.**

## Final measured state

- `tests/run.luau`: **657 passed, 0 failed, 0 todo**
- `scripts/verify.luau`: **all 14 automated steps**, exit 0
- `validate-map maps/gray-box.rbxm`: **ok (21 spots, 9 seats)**
- `MapContract.ISSUE_CODES`: **23**
