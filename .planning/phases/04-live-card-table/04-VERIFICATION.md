---
phase: 04-live-card-table
verified: 2026-11-07T21:00:00Z
status: human_needed
score: 1/5 criteria fully machine-closed (4); 4/5 have a device-dependent half; 11/11 requirements have a machine path, 10/11 have a correctly attributed human path (UX-04's is nominal only, see Finding A)
overrides_applied: 0
re_verification: false
gaps: []
human_verification:
  - test: "M-15 first: lock landscape in Creator Dashboard; pin Workspace.PlayerScriptsUseInputActionSystem explicitly"
    expected: "Landscape locked, IAS flag not left at Default"
    why_human: "Dashboard/Studio setting. Gates M-11 and M-12"
  - test: "M-16 (non-blocking): upload audio and suit pips, confirm a Builder Sans weight exists"
    expected: "Real assets judged in M-14/M-17, not placeholders. A missing font weight is a blocker to raise, not to substitute"
    why_human: "Asset upload"
  - test: "M-14 (desk, greyscale): all 50 faces incl. jokers, spade vs club at 16 px first"
    expected: "Every pair reliably distinguishable without colour"
    why_human: "Legibility is a judgement. Machine proves only 50 keys -> 50 distinct assets (CARD-19)"
  - test: "M-11 (highest risk): 6 cells (IAS Disabled/Enabled x PC/phone/gamepad) plus 4 separately recorded cheat-client attempts"
    expected: "Controls hide on seat and return after the flourish; seated avatar cannot walk, jump or thumbstick away; (a) TouchControlsEnabled alone is NOT sufficient to tick"
    why_human: "Needs Studio and devices (UX-02, D-29, D-30, CARD-17 hold)"
  - test: "M-12 on a notched phone in landscape, Largest text on"
    expected: ">=48 px on glass, thumb reach, nothing under notch/top bar, strip does not wrap, depth stacks of other seats render, a second client sees no hand but its own"
    why_human: "UX-01, UX-03, CARD-13 on-glass half"
  - test: "M-13 at 150-300 ms real or simulated lag, PC and phone"
    expected: "Pass card is gone within a frame; a correction does not read as a teleport; a rejection is not distinguishable from a correction; single tap never sends"
    why_human: "Feel (CARD-02, CARD-14, CARD-15)"
  - test: "M-17: finish a set with the flourish; fumbled double-tap"
    expected: "Reads as a starting gun, finisher is not running before the flourish ends; D-03 residual does nothing worse than accepted. ALSO verify behaviourally the three service-layer review fixes WR-03 (failed start is retryable), WR-04 (gateway reject returns the card), WR-05 (removed seat still gets RoundEnd/Depths/Table)"
    why_human: "CardService/Main.server cannot load in Lune; these are source-scanned only"
  - test: "UX-04 on-glass hints (NEEDS A NEW STEP WRITTEN, see Finding A): with mouse, then touch, then keyboard, then gamepad on one device, watch the strip text"
    expected: "Hint text switches to the last input actually used; no hint names a control the player is not using"
    why_human: "Device behaviour of LastInputTypeChanged (V-27). No M-row currently contains this procedure"
  - test: "V-35 / M-07 playtest of the 8.0 s AFK deadline on humans"
    expected: "Deadline neither stalls the ring nor strikes people mid-thought"
    why_human: "Open since Phase 2"
owner_questions:
  - "WR-05 / D-31: a finisher (removed seat) still receives RoundEnd, Depths and later Table batches, so still sees later 'X is out' callouts. Fixer read D-31 as covering every seat dealt in. If callouts were meant for seats still in the card phase only, it is a one-line revert. NOT decided here."
---

# Phase 4: Live Card Table Verification Report

**Phase Goal:** Seekers can play the real-time simultaneous card scramble on PC and on a phone, and it feels immediate.
**Status:** human_needed. Not `passed`, because four of five criteria are device-dependent. Not `gaps_found`, because no gap is code-fixable. The one real finding (A) is a missing procedure in MANUAL-CHECKS.md.
**Re-verification:** No.

## What I could and could not re-run
No `lune` in this container, so I did NOT re-run the suite. The 871/0/0, 14/14 verify.luau and check-guards figures are the executors' (04-REVIEW-FIX.md, d53cbb5) and are unconfirmed by me. What I did confirm from git and source: zero diff of `src/server/engine/` and of `src/server/Gateway.luau` against `ae376d6`; `requirements.mark-complete` never run (7 summaries state so explicitly, and REQUIREMENTS.md still shows all 11 `[ ]` and `Pending`); all seven M-11..M-17 boxes unticked (MANUAL-CHECKS.md lines 599, 624, 647, 669, 692, 717, 742); every artifact in the client and server tree exists and is wired (`Main.client` requires `CardClient`; `CardClient` requires Controls, Flourish, Hints, Faces, Prediction, Layout; `CardService` required from `Main.server`).

## Success criteria

| # | Criterion | Verdict | Machine-proven | Human-gated |
|---|-----------|---------|----------------|-------------|
| 1 | tap selects, 2nd tap sends, single tap never sends | half | one Pass per second tap, zero-send on single tap, first-tap-commit mutant (Prediction) | feel, fumbled double-tap (D-03 accepted residual): M-13, M-17 |
| 2 | own 5 cards, others' depths only, immediate at 150-300 ms | half | owner-only Sync, recursive leak walk, Depths counts-only (privacy.spec 285-350 asserts keys, audience, count values and last==truth; 3 Depths mutants), convergence at 150/300 ms virtual | on-glass depth rendering M-12; immediacy M-13 |
| 3 | phone landscape, 48 px, controls hidden, safe areas, input-matched hints | human only | geometry at 4 viewports + 0.85 floor, ScreenInsets=CoreUISafeInsets constant, control-seam order, hint table | M-11, M-12, M-15 (+ Finding A for hints) |
| 4 | idle auto-pass within timeout; bench via same removal path | machine-closed (subject to V-35 and the 0.1 s note below) | CardTable benches via `runApply({kind="Remove", cause="Benched"})`, the same Remove as disconnect (CardTable.luau ~L599); cardtable.spec L821 asserts one Benched removal and cards reaching the successor; 80 deci reaches IdleClock; uniform pick; D-35 | V-35/M-07 only |
| 5 | distinct starting gun; faces colour-blind legible | half | 1.5 s cap, yield cancel, input during flight, F8 scans; 50 keys -> 50 assets, no colour in a key | M-14 legibility, M-16 assets, M-17 feel |

The phase's own split in 04-VALIDATION.md and 04-20-SUMMARY.md matches mine. Criteria 1, 2, 5 half; 3 entirely human; 4 machine-closed.

## Requirements (all 11 appear in at least one plan's frontmatter; REQUIREMENTS.md agrees: all Pending, correctly)

| Req | Plans | Machine | Human path | Verdict |
|-----|-------|---------|-----------|---------|
| CARD-02 | 03,09,12,14,17,18,20 | one Pass per 2nd tap | M-13, M-17 | machine half real; human open |
| CARD-13 | 01,02,05,12,13,14,17,19,20 | owner-only Sync; leak walk; `Depths` kind exists in CardTable (publishes `toSeated("Depths")` at L317 and L450), CardRouting, Prediction, CardService, CardSeatsView, CardClient (`Depths = onDepths`, `setDepths`); privacy.spec asserts payload keys, audience, numeric counts and truth | M-12 (two clients, depth on glass) | late-added path is real and asserted. Client rendering of it is source-asserted only, not executed (CardSeatsView cannot load in Lune) |
| CARD-14 | 03,07,09,12,13,14,18,20 | convergence 150/300 ms, cumulative ack, watchdog | M-13 | machine half real |
| CARD-15 | 09,17,18,20 | zero-send single tap | M-13, M-17 | as above |
| CARD-16 | 01,06,07,11,12,14,16,18,20 | gating, 80 deci, 3 strikes, bench, uniform, D-35 | V-35/M-07 | see Finding B |
| CARD-17 | 01,02,10,11,12,15,19,20 | cap, cancel, F8 | M-16, M-17 | machine half real |
| CARD-19 | 02,04,05,12,17,19,20 | 50 keys/assets | M-14 | colour-blind half human only |
| UX-01 | 02,08,16,17,20 | 48 px arithmetic | M-12 | pure arithmetic, not glass |
| UX-02 | 02,11,15,18,20 | hide/restore order, src scan, hold core | M-11 | human is the real proof |
| UX-03 | 02,08,16,20 | inset containment, 58% region | M-12 | human is the real proof |
| UX-04 | 11,16,18,20 | input-kind map (22 names), 20 hint cells | **none written** | **Finding A** |

Correction to the brief: "UX-01..04 are claimed by NO plan" is true only in the sense of "met by no plan". All four ARE in plan frontmatter (UX-01: 02,08,16,17,20; UX-02: 02,11,15,18,20; UX-03: 02,08,16,20; UX-04: 11,16,18,20). No orphaned requirement.

## Findings

**A. UX-04 has no real human path (the only genuine hole).** 04-VALIDATION.md (L237, L380) assigns the UX-04 human half to "M-11 gamepad column, V-27". But the M-11 procedure in MANUAL-CHECKS.md is about controls hiding and the avatar hold. Nothing in M-11..M-17 (L560-760) mentions hints, mouse, keyboard or last-input switching. The MANUAL-CHECKS "Carries" table at L26-32 never lists UX-04, and its only UX-04 mention says it is "met only by these rows". The owner cannot sign a check that is not written, and `hints.spec` proves the copy table and map, not that `LastInputTypeChanged` drives the strip on a device. Fix is a documentation edit: add a UX-04 step (above) to M-11 or M-13 and add UX-04 to the table. Do before UAT.

**B. Stale record of the AFK decision.** CONTEXT D-39 (commit 9db095f, 05:12) records the owner's decision: keep 80 deci, restate CARD-16's bound as the configured value. REQUIREMENTS.md CARD-16 already carries the restated wording. But `deferred-items.md` D-04-13 ("Status: OPEN"), 04-20-SUMMARY ("checkpoint open", "2 owner decisions open"), 04-VALIDATION and STATE.md (`stopped_at`: "2 owner decisions open") were all written before it and were never updated. Net: one owner decision (AFK) is RESOLVED, not open. Arithmetic (realised window 7.9007..8.0996 s) is documented consistently. No code effect. Update the four docs; the genuinely open owner items are now WR-05/D-31 and the device matrix.

**C. Recorded weaknesses vs claims (none undermines a claim).** Checked each requirement for a known-weak gate as sole evidence. Service-layer wiring (the 5th never-written gate, including WR-03/04/05) is the sole *executed-test* gap, but it is source-scanned and explicitly routed to M-17 and flagged "requires human verification"; no requirement is marked machine-proven on it. I2/I3 and the mis-stated counts affect only the credibility of their own gates, not a requirement's only evidence (each has an independent covering spec, e.g. `round_end.spec` for RoundEnd). The stale brief figure of 858 tests in 04-20-SUMMARY vs 871 final is just the pre-review count.

**D. Nothing claimed machine-proven that is not.** I found no over-claim. The summaries repeatedly say "not claimed closed" for CARD-13, CARD-17, UX-01, UX-02, UX-03 (04-19). One nuance: UX-01's "48 px at 4 viewports" is arithmetic over `Layout`, which is correct as a floor check but not a glass measurement; the phase labels it so.

**E. Delivered but not credited.** Mild: criterion 4 is credited as "essentially" closed but is tighter than that, with executed assertions on the Benched Remove path, cards routed to the successor, and the D-35 reachable mutant. CARD-13's `Depths` path (04-19) is under-credited in 04-20-SUMMARY, which says only "depth data path exists"; it is in fact asserted four ways in privacy.spec. Also unreported benefit: server-side seat hold (04-15), which is beyond the "hide controls" ask and makes a cheating client unable to walk off (still M-11-gated).

**F. Locked decisions honoured.** Instant tap, no debounce (D-02/03), silent rejection (D-12), AFK at 80 deci (D-39), `src/client/ui` not a guarded root, and engine/Gateway zero diff were all found consistent. Nothing that looks like a defect here is one.

## Open owner questions
1. WR-05/D-31 callout audience (see frontmatter). Not decided.
2. IN-02 and IN-04 (deferred Info) need behaviour judgements.

## Gaps Summary
No code gaps. One documentation gap (A: UX-04 has no written M-row procedure) and one stale-record cleanup (B). Phase 4 closes only when a human signs M-11, M-12, M-13, M-14, M-15, M-17 (M-16 non-blocking) and Finding A is written into a row.

_Verified: 2026-11-07_
_Verifier: Claude (gsd-verifier)_
