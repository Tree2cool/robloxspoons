---
phase: 5
slug: hunt-anti-esp-claim-and-scoring
status: strategy (written before execution; no plan has run)
nyquist_compliant: true
wave_0_complete: false
created: 2026-11-10
---

# Phase 5 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Derived from `05-RESEARCH.md` § "Validation Architecture". Written **before** any plan executes,
> as Phase 4 did: a strategy authored after the results is a description, not a contract.
> **Task IDs are filled in at sign-off** from the plan summaries; the results document is
> `05-VALIDATION-RESULTS.md` (plan 05-19), and **divergence between this file and that one is a
> finding to record, not a document to rewrite.**

**Read this first:** every command assumes `export PATH="$HOME/.rokit/bin:$PATH"` — the `lune`
binary lives at `~/.rokit/bin/lune` and is **not** on `PATH`. Prefer **`--root <dir>`** over
`--filter`: Phase 4's validation contract records that `--filter` labels collide across suites
(Phase 2 deferred item D-02-09-2). Where a single spec must be targeted, the only form this phase
uses is a **path-qualified** filter (`tests/hunt/scoring`), which cannot collide.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Project harness `tests/harness/Test.luau` (`t.test/equal/deepEqual/truthy/falsy/contains/throws/fuzz`) on Lune |
| **Config file** | `tests/run.luau` — discovers `**/*.spec.luau`; exits non-zero on failing, unloadable, **empty** or filter-matching-nothing runs |
| **Scanner** | `scripts/ci/lex.luau` → `stripComments`. **This is the repo's scanner and every source gate in this phase uses it.** Phase 04.1 plans a shell-side equivalent at `scripts/dev/scan.luau`; it has **not landed** and this phase deliberately does not depend on it (see "Scanning text" below) |
| **Reusable fakes** | `tests/harness/FakeClock.luau`, `FakeScheduler.luau`, `Fuzz.luau`, `RecordingPublisher.luau`. **Wave 1 adds** `tests/harness/HuntRecording.luau` (plan 05-04) |
| **Quick run command** | `lune run tests/run.luau -- --root tests/hunt` |
| **Full suite command** | `lune run tests/run.luau` |
| **Baseline** | **874 passed, 0 failed, 0 todo** measured 2026-11-10 on an unmodified tree |

### Counts in this phase are LOWER BOUNDS, not equalities

Wave 1 is **eight plans executing against one shared working tree**. Any absolute total
("874 + 13 = 887") is unassertable: seven siblings are adding cases concurrently. Every suite
assertion in this phase is therefore `passed >= 874` and `failed == 0`.

Phase 4's validation file measured an **11-second spread on an unchanged tree** from container load
alone — roughly 3.7× that phase's whole timing allowance. The same applies here: a single reading
proves nothing, and no plan in this phase asserts a runtime.

### The wave barrier

A repo-wide command (`stylua --check src scripts tests`, `selene src scripts tests`,
`check-guards.luau`, `tests/run.luau`, `verify.luau`) reads siblings' half-written files. So:

- **Per-plan verification is scoped** to that plan's own `files_modified` (`stylua --check <files>`,
  `selene <files>`) plus `--root tests/hunt` and any specific sibling spec the plan is known to
  affect.
- **The repo-wide chain runs once per wave, after every plan in it reports done.**
- `tests/run.luau` **loads every discovered spec before applying a filter**, so a sibling's
  half-written spec fails at load regardless of scoping. A failure in a file a plan does not own is a
  sibling mid-write: record it, re-run at the barrier, and **never edit another plan's file to go
  green**.

### Scanning text — the rule, stated once for the whole phase

Three shipped files in this phase cannot be loaded by Lune (`HuntService.luau`, `HuntClient.luau`,
`SpoonView.luau`, plus `RemainingHud.luau` and `SpectateCamera.luau`), so their gates are
comment-stripped **source scans**. The rule:

1. **Every scan this phase writes strips comments** via `lex.stripComments`. Not one reads raw text.
2. **Because** the headers of those files are *required* to name the constructs they forbid —
   `HuntService` names `os.clock`, `GetServerTimeNow`, `Instance.new`, `SetAttribute`,
   `ProximityPrompt`; `HuntTable` names `task.wait`/`task.spawn`/`coroutine`; `SpectateCamera` names
   `LoadCharacterAsync` — **a raw grep for those tokens cannot be satisfied by a correct file.** No
   plan in this phase may put such a grep in its acceptance criteria. Several drafts did; all were
   removed.
3. **One existing gate is raw and is not ours.**
   `tests/card/renderer_discipline.spec.luau`'s forbidden-identifier case reads raw text *by design*
   (*"stricter than the guards, and it keeps headers honest"*) and walks every file under
   `src/client/ui`. Consequence: the hunt client files must express guard R4 **without naming**
   `OnClientEvent`, `FireServer`, `FireClient` or `FireAllClients`, even in a comment.
4. Every scan **states which text it reads**, and every slice is **two-anchor**, because the hunt's
   closures and handlers are short and adjacent.

---

## Sampling Rate

| When | What runs |
|------|-----------|
| **Per task commit** | scoped `stylua`/`selene` + `lune run tests/run.luau -- --root tests/hunt` |
| **Per plan** | the above + any sibling spec the plan edits (`tests/net/manifest`, `tests/card/netguard`, `tests/card/renderer_discipline`, `tests/card/deci_lock`) |
| **Per wave (barrier)** | `stylua --check src scripts tests && selene src scripts tests && lune run scripts/ci/check-guards.luau && lune run tests/run.luau` |
| **Phase gate** | full `lune run scripts/verify.luau` (14 steps) green, then M-18..M-24 signed by a human |

---

## Per-Requirement Test Map

| Req | Behaviour | Type | Command | Owning plan(s) |
|-----|-----------|------|---------|----------------|
| HUNT-01 | no position to a non-entitled user; adapter and client create nothing readable | unit + source scan | `--root tests/hunt` (`privacy`, `service_wiring`, `client_discipline`) | 04, 09, 12, 15, 16, 17 |
| HUNT-01 **live** | client DataModel replication audit | **manual** | **M-18** | 02 |
| HUNT-02 | 25-stud prefilter, injected LoS, hysteresis, transition-only | unit | `--root tests/hunt` (`visibility`) | 07, 09 |
| HUNT-02 **live** | validator-vs-runtime sight, teammate occlusion, raycast cost | **manual** | **M-22** (+ **M-23** eye offset) | 02 |
| HUNT-03 | `Claim` schema; prompt only in client source; server re-validates | unit + source scan | `--root tests/net`, `--root tests/hunt` | 03, 11, 12, 16 |
| HUNT-03 **live** | client-created prompt on phone and PC | **manual** | **M-19** | 02 |
| HUNT-04 | two same-instant claims, one winner; no yield in the shipped claim | unit + source scan | `--root tests/hunt` (`claim` CL-01, CL-22) | 06, 12 |
| HUNT-04 **live** | two clients, one spoon | **manual** | **M-20** | 02 |
| HUNT-05 | count on change, audience all, no position | unit | `--root tests/hunt` (`privacy`, `routing`) | 04, 09, 15 |
| HUNT-06 | collision pair set at start and restored at end; group on add/descendant/existing | source scan | `--root tests/hunt` (`service_wiring` WR-H05) | 14, 17 |
| HUNT-06 **live** | avatars pass through each other all round | **manual** | **M-21** | 02 |
| HUNT-07 | spectator set membership; bounds payload; zero reveals | unit + source scan | `--root tests/hunt` (`privacy`, `client_discipline` CD-05) | 09, 13, 15, 16 |
| HUNT-07 **live** | free camera, bounded, sees nothing | **manual** | **M-21** | 02 |
| HUNT-08 | reach threshold ±ε, rtt slack and its clamp, strikes, silence | unit | `--root tests/hunt` (`plausibility`) | 08, 12 |
| SCORE-01 | 1000 then −100 per place, from the core's OWN place counter | unit | `--root tests/hunt` (`scoring`, `hunt_table` case 1) | 05, 09, 18 |
| SCORE-02 | find points = remaining deci, arrival read once, deadline exclusive | unit | `--root tests/hunt` (`scoring`, `claim` CL-13/14) | 05, 12 |
| SCORE-03 | zero find, bonus kept | unit | `--root tests/hunt` (`scoring` case 3, `round_end` case 5) | 05, 12 |
| SCORE-04 | hider = 4000 × mean survived fraction of a fixed 300 s, integer | unit | `--root tests/hunt` (`scoring` cases 10-15) | 05, 12 |
| SCORE-05 | end on last claim or at the cap, exactly once, publish before clear | unit + source scan | `--root tests/hunt` (`round_end`) | 12, 18 |
| **Gate G3** | the full loop with 3-10 clients | **manual** | **M-24** | 02 |

**Criterion 3 is the one ROADMAP criterion a machine can close completely.** Its four worked examples
are exact integer vectors over shipped config in `tests/hunt/scoring.spec.luau`. Criteria 1 and 5
cannot be closed by any machine in this repo.

---

## Wave 0 / Wave 1 Requirements

- [ ] `tests/harness/HuntRecording.luau` (plan 05-04) — the recording publisher with a **silent**
      `leak` switch
- [ ] `tests/hunt/` directory; discovered automatically by `tests/run.luau`. **A spec that registers
      nothing FAILS**, so no placeholder files
- [ ] `MANUAL-CHECKS.md` rows **M-18..M-24 written before any hunt code** (plan 05-02), plus the
      `NEEDS_HUMAN.md` index rows including **D-17**
- [ ] `src/shared/Config/Hunt.luau` + its lock spec (plan 05-01) — every number this phase tunes
- [ ] Existing-gate edits, each **owned** by a plan and each with a mutant:
      `tests/net/manifest.spec.luau` (05-03), `tests/card/netguard.spec.luau` (05-10),
      `tests/card/renderer_discipline.spec.luau` (05-13)
- [ ] `tests/card/deci_lock.spec.luau` **re-run, never edited** — it is the no-third-clock gate
- [ ] `scripts/ci/zones.luau` **unchanged**: `src/server/core` is already a pure zone and `Scoring`
      is already a `guardedNamePrefixes` entry, so every new core file is an R2/R3 root with no
      registration. **No guard may be weakened to make room**
- [ ] `scripts/verify.luau` **gains no step**: new specs under `tests/hunt/` are discovered, new pure
      files are picked up by the zones list, new shipped files by the typecheck

---

## Existing gates that this phase turns red, and who owns each

A phase that reddens an existing gate has two honest options: edit it deliberately, or restructure so
the rule still holds. **Silently loosening it is neither.** Each row names which was chosen.

| Gate | Why it reddens | Choice | Owner |
|---|---|---|---|
| `manifest.spec` intent-set `deepEqual` (lines 113-120) | a fourth intent exists | **edit**: `{Claim, Draw, Pass, Ping}`, + a missing-Claim mutant | 05-03 |
| `manifest.spec` forbidden-key count (line 202) | 2 intents → 3 | **edit**: 14 → 36, list extended by `pos, position, x, y, z`, + mutation (e) | 05-03 |
| `manifest.spec` clean-payload count (~line 197) | `BASES` gains Claim | **edit**: 2 → 3 | 05-03 |
| `netguard` whole-file `:FireClient(` / `:FireAllClients(` (lines 249-250) | a third remote sends | **edit**: 2 → 3 and 1 → 2, counts kept exact (not `>=`), + a stray-send mutant | 05-10 |
| `netguard` publisher body slicer (`MARKERS`, first occurrence) | both publishers spell two markers identically | **restructure**: the hunt publisher is assembled **after** the card one, + an offset assertion and a swap mutant | 05-10 |
| `renderer_discipline` send-site list (line 436) | `HuntClient` is a third send site | **edit**: `{MAIN, CARD_CLIENT, HUNT_CLIENT}`, + a fourth-site mutant. The neighbouring "CardClient has exactly 1" and "Main.client sends only Ping" assertions stay byte-identical | 05-13 |
| `renderer_discipline` colour/font constructors (line 556) | a new UI file might construct one | **restructure**: hunt UI reads `CardTheme.COLOR`/`FONT` and constructs neither | 05-11, 05-13 |
| `renderer_discipline` geometry and timing literals (470, 578) | a named local might collide | **restructure**: check every named local against `Layout.DESIGN`, `Card.TWEEN`, `Card.PULSE_HZ`, `Card.AFK_WARN_SECONDS` before committing | 05-11, 05-13 |
| `renderer_discipline` forbidden identifiers, **RAW** (line 583) | a header naming `OnClientEvent` is itself a hit | **restructure**: express guard R4 without naming the APIs | 05-11, 05-13 |
| `deci_lock` clock allow-list (lines 203-233) | would redden if the hunt read a clock | **restructure**: `HuntService` imports `CardService.nowDeci`. **The list is not extended**, and 05-17 asserts it was not | 05-14, 05-17 |
| `placement/config_lock` ten-constant pin (line 38) | would redden on an 11th constant | **restructure**: `GLINT_RANGE` goes in a new `Config/Hunt.luau` | 05-01 |
| `seathold.spec` exact telemetry list (line 180) | would redden on new events in a shared path | **restructure**: hunt telemetry only in hunt files | 05-09 |

---

## Mutation Tests (mandatory per gate)

Every gate in this phase gets **all four**:

1. a **clean control** through the same helper (`t.deepEqual(problems, {}, "clean path")`);
2. a **non-vacuity count** — a body size, a node count, a call count, a `seen > 0`;
3. a **no-defect twin** — an identity edit through the same plumbing, asserted green, so no mutant
   can be red for harness reasons;
4. a **mutation** driven through the **same** checker, named `MUTATION:` at the start of the case
   name, **run by hand and observed red with its problem count recorded**.

**Two kinds of mutant, and the ledger labels which.**

- **Source-text mutants** edit the REAL shipped file in memory via `replaceOnce` (which asserts its
  needle exists, so a typo errors rather than passing vacuously) and run it through the same problems
  function. These exercise shipped code.
- **In-spec fakes** are local reimplementations that prove the *assertion can discriminate*. About
  nine of this phase's mutants are of this kind (05-06 cases 5/14, 05-07 cases 19/20, 05-08 cases
  24/25, 05-09 cases 2/21, 05-12 cases 2/20). That is the Phase 4 precedent and it is legitimate —
  **but it exercises no shipped source and the ledger must say so.** A reader who assumes otherwise
  has been misled.

**Per-needle discipline.** Every needle carries a comment of the form
`-- needle "<X>": the mutant replaces it with "<Y>", which does not contain "<X>".` Writing that
sentence forces looking at the mutant text — the step that was skipped the three times a gate in this
repo could not fire. The recorded case is
`tests/card/service_wiring.spec.luau:196-199`: `player.Character` is a **prefix** of
`player.CharacterAdded`, so the loose needle matched its own mutant.

**A mutant that produces zero problems means the needle is wrong.** Fix the needle, re-run, and
record both the wrong needle and the fix. Those records are the most valuable rows in the ledger.

**Expected counts** (authoritative table in plan 05-19; verify against the plans, not the table):
05-01 1 · 05-03 2+5 · 05-04 1+1 · 05-05 3+4 · 05-06 4+2 · 05-07 4+4 · 05-08 5+4 · 05-09 5+2 ·
05-10 12 · 05-12 16 · 05-13 1 · 05-15 5 · 05-16 16 · 05-17 **34** · 05-18 **15**.

---

## Gates that protect a rule no guard covers

| Rule | Why `check-guards` does not cover it | This phase's gate |
|---|---|---|
| **Rule 6, no yield in `HuntTable.claim`** | R3's banned constructs are `getfenv`, `setfenv`, `loadstring`, `coroutine`, `rawget(_G`, `_G[`, `os.` (`check-guards.luau:57`, `:398`). **`task.` is not on that list** | `claim.spec` **CL-22/CL-23**: a stripped, two-anchor scan of the claim body for `task.`, `:Wait(`, `pcall`, `coroutine`, `:Connect(`, `require(`, with a non-vacuity body size, two checker negative controls, and five insertion mutants |
| **`debugState` never wired in production** | no guard mentions it; it hands out raw spoon positions | `service_wiring` **WR-H09** |
| **No third clock** | R3 bans `os.` in pure zones only; services may name it | `deci_lock` re-run + `service_wiring` **WR-H03**, which also asserts the allow-list text was not extended |
| **Publisher assembled through `makePublisher`** | guard R4 only confines the send calls | `net_wiring` **NW-01** mutant (d): an inlined publisher bypasses `assertPublic` entirely |

---

## Manual-Only Verifications

| Row | Carries | Blocking | What no machine here can do |
|---|---|---|---|
| **M-18** | HUNT-01 live, criterion 1 | **yes (highest risk)** | read a live client's DataModel |
| **M-19** | HUNT-03, A5 | yes | render a prompt on a touch device |
| **M-20** | HUNT-04, HUNT-08, D-08 | yes | two real clients racing |
| **M-21** | HUNT-06, HUNT-07, A10 | yes | two avatars colliding; a spectator's view |
| **M-22** | HUNT-02, A1, A3, V-18, V-34 | yes | compare validator sight to runtime sight; MicroProfiler |
| **M-23** | HUNT-02, A2, V-19 | no | measure a real R15 root height |
| **M-24** | criterion 5, **Gate G3** | yes | the vertical slice |

**No requirement in this phase is met *only* by a human row** — every one has a machine-proved half.
But **HUNT-01's live half, HUNT-03's touch half and Gate G3 are**, so
`requirements.mark-complete` must not run for Phase 5 before M-18, M-19 and M-24 are signed.

**Files with no behavioural machine coverage at all** (source scans only; Lune cannot load them):
`src/server/services/HuntService.luau`, `src/client/ui/HuntClient.luau`,
`src/client/ui/SpoonView.luau`, `src/client/ui/RemainingHud.luau`,
`src/client/ui/SpectateCamera.luau`. This is the phase's most important disclosure.

---

## Success criteria for the validation chain itself

1. Every plan's scoped checks green; every wave barrier green; `verify.luau` 14/14 at the gate.
2. `passed >= 874`, `failed == 0`, `todo == 0` at the barrier.
3. Every gate has all four mutation elements, and **every mutant was run with its count recorded**.
4. `zones.luau`, `deci_lock.spec.luau`, `Gateway.luau` and `src/server/engine/` **unchanged** —
   asserted by `git diff --name-only` at the gate.
5. No `MANUAL-CHECKS.md` checkbox ticked by a machine; `verify.luau` lists all seven as unticked.
6. `05-VALIDATION-RESULTS.md` records every divergence from this file.

## Validation Sign-Off

_Filled in by plan 05-19. Nothing below is signed._

- [ ] Wave barriers all green
- [ ] Mutation ledger complete, with source-edit and in-spec totals reported separately
- [ ] `05-VALIDATION-RESULTS.md` written, divergences recorded
- [ ] M-18, M-19, M-20, M-21, M-22, M-24 signed by a human
