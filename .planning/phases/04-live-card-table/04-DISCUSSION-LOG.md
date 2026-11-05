# Phase 4: Live Card Table - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in `04-CONTEXT.md` — this log preserves the alternatives considered.

**Date:** 2026-11-05
**Phase:** 4 — Live Card Table
**Areas discussed:** Tap-select/pass guard, Prediction & correction, AFK deadline & bench,
Forced pass & stall cues, Card face design, Other seats & piles, Mobile landscape layout,
Starting-gun moment (all eight offered areas selected)

**Mode:** interactive `discuss` (no `--auto`, `--all`, `--batch` or `--analyze`). Advisor mode
off — no `USER-PROFILE.md` present. No SPEC.md, no prior CONTEXT.md, no checkpoint, no plans,
no matched todos, no spikes or sketches, no codebase maps.

---

## Area selection

| Option | Description | Selected |
|--------|-------------|----------|
| Tap-select/pass guard | What makes one accidental tap safe (CARD-02 + CARD-15) | ✓ |
| Prediction & correction | Optimistic apply and what a disagreement looks like (CARD-14) | ✓ |
| AFK deadline & bench | Deadline inside the 8.0s ceiling, warning, strikes (CARD-16) | ✓ |
| Forced pass & stall cues | Valve affordance, start-up ramp, stuck-round cue | ✓ |
| Card face design | 5–12 suitless ranks + joker; colour-blind safety (CARD-19) | ✓ |
| Other seats & piles | Pile depth representation (CARD-13) | ✓ |
| Mobile landscape layout | Hand + two piles + table on a phone (UX-01, UX-03) | ✓ |
| Starting-gun moment | Finisher vs table experience; Phase 7 seam (CARD-17) | ✓ |

---

## Tap-select / tap-pass guard

### Where does the committing second tap land?

| Option | Description | Selected |
|--------|-------------|----------|
| On the right pile | Two separate targets make CARD-15 structural; costs a 48px pile target | |
| On the same card again | Fewest targets, easiest for thumbs; double-tap accident must be bought back | ✓ |
| Either target works | Most forgiving to learn; inherits the double-tap accident anyway | |

**Notes:** Recommendation was "on the right pile". The owner chose the same card, which made the
guard question below necessary.

### While a card is selected, what happens when the player taps a different card?

| Option | Description | Selected |
|--------|-------------|----------|
| Selection follows the tap | Selection moves; tapping the selected card or the table clears it | ✓ |
| Must deselect first | Stricter but reads as the UI ignoring you | |
| Selection times out | Protects a fumbled phone; a timeout racing a frantic player cancels intent | |

**Notes:** The selected option's own description said tapping the selected card would clear the
selection — which contradicts the second-tap-commits choice above. Resolved as D-04: the send
wins, so cancelling is "tap another card" or "tap off the hand". Flagged to the owner in the
following turn and not contradicted.

### Is there a second way to pass, beyond tap-select-then-commit?

| Option | Description | Selected |
|--------|-------------|----------|
| No — one mechanic only | One accident surface, one thing to teach, parity by construction | ✓ |
| Add drag-to-pile | Feels good, but a short drag is a new ambiguous outcome | |
| Drag on mobile only | Breaks identical-on-both-inputs deliberately; hints diverge | |

### What does the mouse-and-keyboard player get (UX-04)?

| Option | Description | Selected |
|--------|-------------|----------|
| Click, plus optional keys | Pointer is the guaranteed path; keyboard is an accelerator | ✓ |
| Mouse only | Literally identical behaviour; feels slow to keyboard-first players | |
| Full keyboard parity | Best for fast PC play; a third input surface to keep accident-safe | |

### Follow-up: since both taps land on the same card, what stops a stutter-tap?

| Option | Description | Selected |
|--------|-------------|----------|
| Animation-gated | The guard is visible — the card is not armed while still moving | (first answer) |
| Fixed debounce window | Simple and tunable, but invisible: a fast deliberate tap silently does nothing | |
| No guard at all | Max speed; CARD-15 rests on "one tap never sends" | ✓ (final) |

**User's choice:** first *"Animation-gated but the animation should be half a second, allowing for
relatively quick double taps"*, then, when the tension was pointed out — a 0.5s gate blocks quick
double taps rather than allowing them — *"Honestly remove the 0.5s, make it instant."*

**Notes:** The intermediate clarifier offered buffered-and-cancellable (second tap accepted during
the lift, firing at its end, cancellable within the window — at the cost of ~0.5s added to every
pass, which the G1 sweep did not model), armed-early-with-a-0.5s-settle, and a hard gate. The
owner rejected all three in favour of instant. Recorded in CONTEXT.md with the residual stated:
a fumbled fast double-tap will send a card.

### Does the left-pile draw get a guard too?

| Option | Description | Selected |
|--------|-------------|----------|
| No guard — draw is instant | An accidental draw costs nothing; CARD-15 names passing | ✓ |
| Same guard as the card | One rule for every tap, at the cost of frames before the four-of-a-kind check | |

### Is the right pile a touch target, or only a destination?

| Option | Description | Selected |
|--------|-------------|----------|
| Destination only, inert | Frees landscape space; no 48px obligation | ✓ |
| Also commits a selection | Forgiving to a player who aims at the pile; a second path | |
| Tapping it clears selection | Gives cancelling a home, but inverts intuition | |

---

## Prediction & correction

### Does your own card move before the server has confirmed it?

| Option | Description | Selected |
|--------|-------------|----------|
| Yes — move immediately | Required by CARD-14 at 150–300ms | ✓ |
| No — wait for the ack | Nothing can ever be wrong on screen; every pass feels laggy | |
| Predict the pass, not the draw | Avoids showing a set that is then taken away; two feels for adjacent actions | |

### When the server disagrees, what does the player see?

| Option | Description | Selected |
|--------|-------------|----------|
| Card returns visibly | A deliberate motion satisfies "no visible glitch"; a teleport does not | ✓ |
| Silent snap to truth | Simplest; at 300ms reads as a bug | |
| Ghost until confirmed | Honest, but makes every normal pass look uncertain | |

### What about a hard rejection — rate-limited, or refused outright?

| Option | Description | Selected |
|--------|-------------|----------|
| Same return, no message | A legitimate player never sees one; a message is noise or a hint to a prober | ✓ |
| Return plus a brief cue | Clearer when it happens; risks teaching fear of a mechanic | |
| Return plus a reason | Great in development; ships internal vocabulary | |

---

## AFK deadline & bench

### What auto-pass deadline, inside the locked 8.0s ceiling?

| Option | Description | Selected |
|--------|-------------|----------|
| 8.0s — the ceiling | 0 auto-passes in the sweep's 8.0s cells; V-35 unverified, so conservative | ✓ |
| 5.0s | Only 2 auto-passes across the 5.0s cells; better circle flow | |
| 6.0s | No measurement of its own — between two cells the sweep ran | |

### When does the idle clock actually run for a seat?

| Option | Description | Selected |
|--------|-------------|----------|
| Only when a legal action exists | Stops the 8.3s start-up ramp striking far seats | ✓ |
| From the seat's last action | Simpler, but punishes players for the table's state | |
| Only while owing a pass | Narrowest reading; a player who never draws is never struck | |

### What warning before it fires?

| Option | Description | Selected |
|--------|-------------|----------|
| Late visible countdown | Engaged players never see it; struck players were warned | ✓ |
| No warning at all | Uncluttered; nothing explains the first strike | |
| Countdown for the whole window | Max fairness; turns the scramble into a timed test | |

### How many strikes, and do they reset?

| Option | Description | Selected |
|--------|-------------|----------|
| 3 strikes, reset on action | Forgiving to one interruption; absent player gone in ~30s | ✓ |
| 2 strikes, reset on action | Faster removal; only ~16s of grace at an 8s deadline | |
| 3 strikes, never reset | Catches the drifter; removes someone who was genuinely playing | |

---

## Forced pass & stall cues

### A card left a hand the player did not choose. What is seen?

| Option | Description | Selected |
|--------|-------------|----------|
| Named table-wide event | At ~1 round in 12, an unexplained loss reads as a bug or a cheat | |
| Private cue to that player | Clean table; the receiving player has no idea it was forced | ✓ |
| No explanation | Zero work; the path the Phase 2 record explicitly warns against | |

**Notes:** Recommendation was the table-wide event. Consequence of the choice recorded in
CONTEXT.md D-18: the downstream player gets no explanation, and the table sees an ordinary pass.

### A far seat waits ~8 seconds for its first card. What fills the gap?

| Option | Description | Selected |
|--------|-------------|----------|
| Cards visibly travelling | Diegetic, needs no text, teaches the chain | ✓ |
| Explicit wait state | Unambiguous, but a label where the mechanic could have been shown | |
| Nothing — empty pile is enough | 8.3s is long enough to look broken | |

### If a round goes nowhere and the valve is NOT firing?

| Option | Description | Selected |
|--------|-------------|----------|
| Own no-progress detector | Required: 3 of 15 replayed stalls were armed with zero firings | ✓ |
| Nothing in Phase 4 | Honest about rarity; a player spends 5 minutes unaware | |
| End the round early | Kindest, but round-end belongs to Phases 5 and 6 | |

---

## Card face design

### What is a rank, visually?

| Option | Description | Selected |
|--------|-------------|----------|
| Real playing-card ranks | Players arrive knowing "four of a kind"; suits identify the four copies | ✓ |
| Bespoke symbol per rank | Full control of distinguishability; discards card-game literacy | |
| Plain numerals | Most legible at phone size; reads as a maths exercise | |

### How does the joker read on the face?

| Option | Description | Selected |
|--------|-------------|----------|
| Unmistakable, states its rule | `JOKER_MODE` is a live flag; the face must be able to say which | ✓ |
| Classic joker face | Recognisable, but identical in wild and blocker mode | |
| Shows what it's acting as | Helpful, but bakes in a wild-mode assumption | |

### How is colour-blind safety guaranteed rather than asserted?

| Option | Description | Selected |
|--------|-------------|----------|
| Greyscale must survive | Makes CARD-19 a falsifiable test; also covers achromatopsia | ✓ |
| Colour-blind-safe palette | Vivid table; needs per-deficiency checks and per-skin rechecks | |
| Player-toggleable mode | Tuned for affected players; makes the accessible path opt-in | |

### Five cards sharing a landscape phone width

| Option | Description | Selected |
|--------|-------------|----------|
| Overlapping fan | Mirrors a held hand; compact; the lift is the selection affordance | ✓ |
| Evenly spaced, no overlap | Every card equally readable, but each ends up small | |
| Corner index only | Most space-efficient; abstracts the hand and undercuts Phase 7 skins | |

---

## Other seats & piles

### Where do other seats' pile depths live?

| Option | Description | Selected |
|--------|-------------|----------|
| 3D stacks at the table | Zero screen cost; makes the table the thing you look at | ✓ |
| Screen-space seat ring | Identical on every device; duplicates the table and eats width | |
| Both | Most informative; two representations of one truth | |

### How precisely is depth shown?

| Option | Description | Selected |
|--------|-------------|----------|
| Exact on yours, height elsewhere | Sharp where it is actionable, uncluttered where it is not | ✓ |
| Stack height everywhere | Fully diegetic; "3 deep or 5 deep" is the judgement that matters | |
| Exact counts everywhere | Max clarity; nine numbers competing with the cards | |

### Does the table need a dealer marker?

| Option | Description | Selected |
|--------|-------------|----------|
| No marker — the deck says it | The dealer's pile IS the deck, so the role is true by geometry | ✓ |
| Explicit dealer marker | Unambiguous; a second source of truth to keep in sync | |
| Only during the deal | Reinforces the role when exercised; suits the Phase 7 flourish | |

---

## Mobile landscape layout

### Where do your own two piles sit?

| Option | Description | Selected |
|--------|-------------|----------|
| Bottom corners, flanking | Where thumbs rest; preserves left=upstream, right=downstream | ✓ |
| Vertical screen edges | Large targets, max separation; mid-edge is a reach, eats width | |
| Tap the real 3D stacks | Most diegetic; 48px floor becomes a per-map verification | |

### How do the 3D table and the hand overlay share the screen?

| Option | Description | Selected |
|--------|-------------|----------|
| Table framed above the hand | Keeps the table a place; you can watch stacks, travel and departures | ✓ |
| Hand overlays the table | More table on screen; occludes unpredictably on a phone | |
| Table as backdrop | Most legible hand; turns the card phase back into a menu | |

### A player holding the phone in portrait

| Option | Description | Selected |
|--------|-------------|----------|
| Lock to landscape | UX-01 only promised landscape; portrait genuinely does not fit | ✓ |
| Support portrait too | Captures one-handed habits; a whole second layout to test | |
| Rotate prompt only | Cheapest; lets a player sit at an unplayable table | |

**Notes:** The lock is a Creator Dashboard place setting, so it becomes a human gate —
recorded in CONTEXT.md D-28 for `MANUAL-CHECKS.md` and `NEEDS_HUMAN.md`.

### How does a hint know whether to say "tap" or "click"?

| Option | Description | Selected |
|--------|-------------|----------|
| Last input used wins | Handles touchscreen laptops, paired mice, mid-round controllers | ✓ |
| Fixed at join | Stable and trivial to test; wrong for any multi-input device | |
| Show both forms | Always accurate; longest text in the tightest phase | |

---

## Starting-gun moment

### What does the finisher experience?

| Option | Description | Selected |
|--------|-------------|----------|
| Control returns instantly | Find order drives score, so a held finisher loses points | ✓ |
| Short celebratory beat | Reads most clearly as a reward; costs race time | |
| Nothing for the finisher | Zero cost; wastes the best moment on the player who earned it | |

### What does the rest of the table see?

| Option | Description | Selected |
|--------|-------------|----------|
| Diegetic plus a callout | Information is already public; "someone is out there" is the pressure | ✓ |
| Purely diegetic | Trusts the scene; a head-down phone player misses it | |
| Callout with standings | Max drama; placement belongs to Phases 5 and 6 | |

### How much is built now versus Phase 7?

| Option | Description | Selected |
|--------|-------------|----------|
| Fixed-duration seam now | Makes the equal-duration rule enforceable instead of a retrofit | ✓ |
| Build plain, refactor later | Less speculative structure; unequal durations are pay-to-win | |
| Stub only | All presentation in one place; Gate G3's slice has no starting gun | |

### Is there audio in Phase 4?

| Option | Description | Selected |
|--------|-------------|----------|
| Completion sting plus your own cards | A silent starting gun is not a starting gun | ✓ |
| Visual only for now | Avoids early asset work; G3 judged on half the moment | |
| Full audio pass | Richest table; mixing nine passers is its own problem | |

---

## Wrap-up

| Option | Description | Selected |
|--------|-------------|----------|
| I'm ready for context | Write CONTEXT.md; carry D-22 and rate limits as planner decisions | ✓ |
| Discuss D-22 and rate limits | Decide gateway check order and Draw/Pass limits explicitly | |
| Explore more gray areas | Identify and discuss further decisions | |

## Claude's Discretion

Carried as planner-level rather than owner-level, with both options recorded in CONTEXT.md:

- **D-22 of `01-CONTEXT.md`** — the gateway's phase-gate-before-token-bucket order, explicitly
  flagged for revisit in "Phase 4 or Phase 8".
- **Rate limits for the new `Draw` / `Pass` intents** — the current default (burst 4 / refill 4
  per second) was set before any card traffic existed; V-34 marks the numbers LOW confidence.
- Intent payload shapes and schemas, state-publication shape, the no-progress detector's
  threshold, the countdown's visual form, the rank-to-glyph mapping, card art, the fan geometry,
  the D-32 fixed duration, and where AFK strike bookkeeping lives.

## Decisions derived rather than asked

Both were forced by combinations of answers and are recorded in CONTEXT.md:

- **D-04** — cancelling is "tap another card" or "tap off the hand", because a second tap on the
  selected card now sends it.
- **D-29** — movement controls hide per player while seated, not for the whole `Round` phase,
  because a finisher stands up and runs mid-round (Phase 1 D-15).

## Deferred Ideas

Table-wide valve event; drag-to-pile; portrait support; ending a stalled round early; standings
in the starting-gun callout; tightening the auto-pass deadline below 8.0s; widening the fuzz
suite's `k` grid to the shipped `k = 3`; extending the CI regression subset past N = 3/6/10.
Full detail in `04-CONTEXT.md` `<deferred>`.
