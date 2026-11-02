# Spoons

A Roblox multiplayer party game: the classic card game Spoons split into a real-time
card scramble and a hide-and-seek hunt. One player per round hides the spoons; everyone
else races to four of a kind, and completing a set is the starting gun to run out and
find one. There are always two fewer spoons than players.

## Planning Docs — read these before working

| Doc | What it holds |
|-----|---------------|
| `.planning/PROJECT.md` | **Authoritative.** Full game design, every decided rule, scoring formulas, monetization model, constraints, Key Decisions log |
| `.planning/REQUIREMENTS.md` | 102 v1 requirements with REQ-IDs, v2 backlog, out-of-scope with reasons, phase traceability |
| `.planning/ROADMAP.md` | 8 phases, success criteria, gates G1-G5, parallelization map, per-phase research flags |
| `.planning/STATE.md` | Current position, blockers, open owner decisions |
| `.planning/research/SUMMARY.md` | Reconciled research synthesis — consensus, contradictions, 18 open questions, **Verification Debt table** |
| `.planning/research/` | `STACK.md`, `FEATURES.md`, `ARCHITECTURE.md`, `PITFALLS.md` |

`PROJECT.md` wins over any research file where they disagree. Do not re-open decisions
recorded in its Key Decisions table or in `SUMMARY.md`'s "Settled by PROJECT.md" section.

## GSD Workflow

This project uses GSD. Config is `.planning/config.json` (mode: yolo, granularity:
standard, parallelization: on, research + plan_check + verifier all enabled).

```
/gsd-progress              # where things stand, routes to the next action
/gsd-discuss-phase <n>     # gather context before planning
/gsd-plan-phase <n>        # produce PLAN.md
/gsd-execute-phase <n>     # execute all plans in the phase
/gsd-verify-work           # conversational UAT
```

Do not skip from requirements straight to code. Phases are planned, then executed,
then verified. Commit atomically so artifacts survive a lost context.

## Non-Negotiable Rules

These are structural, not stylistic. Research found each one is cheap to honour now and
expensive to retrofit.

1. **Gameplay code must never import cosmetics or shop code.** `Scoring`, `CardTable`
   and `SpoonPlacement` have no import path to cosmetics/shop modules. A lint rule
   enforces it (`FOUND-05`). This is what makes "no pay-to-win" true rather than
   promised.
2. **The card engine references no Roblox API.** It lives in `server/engine/`, is pure
   and synchronous, and runs headless in CI. Lint-enforced (`FOUND-06`).
3. **Nothing hidden may be a replicated Instance.** Spoon positions, hands, piles and
   the default-spot pool are server-side data only. A client learns a spoon's position
   only when within glint range with line of sight (`HUNT-01`, `HUNT-02`). A cheat
   client can read any Instance.
4. **No purchase may affect score, findability or competitive outcome.** Spoon skins
   obey an enforced template (fixed bounding box, scale, pickup hitbox, luminance
   floor). Glint is fixed and non-purchasable. No score multipliers, no soft currency,
   no loot crates.
5. **The server is the only clock.** Scoring uses server arrival time in integer
   deciseconds. Never trust a client timestamp — scoring granularity is 100ms.
6. **No yields inside state mutations.** The engine's `apply` is synchronous; events are
   returned and published after the mutation. A yield mid-mutation lets two handlers
   interleave.
7. **The client never names a pass target or a hand index.** It sends intents with
   stable card IDs; the server resolves `next` at execution time.
8. **Seat removal is one generic operation** used for completion, disconnect and AFK.
   A removed seat's cards route to the successor and are **never destroyed** — deleting
   them can make the remaining ranks unsolvable and deadlock the round.

## Core Mechanic Reference

The card ring is a circular doubly-linked list of seats. Each seat has a `hand` and an
`inbox` (its left pile, a FIFO deque). Passing appends to `seat.next.inbox`; drawing pops
your own inbox front. **The wrap needs no special case — the dealer's inbox *is* the
deck.** "The pile locks at 5" is just the rule *draw only when hand size is 4*. Four of
a kind is checked **only on draw**, because passing can only leave a subset of a hand
that already had none.

## Verification Debt

Five Roblox documentation hosts were DNS-blocked during research
(`create.roblox.com`, `devforum.roblox.com`, `robloxapi.github.io`,
`madstudioroblox.github.io`, `jsdotlua.github.io`). **Every Roblox platform claim in the
research is unverified against primary docs.** Each phase's research step must begin by
re-checking the rows of the Verification Debt table in `.planning/research/SUMMARY.md`
that name that phase, and must record what was confirmed or changed. Do not upgrade a
claim's confidence without re-fetching the primary source.

## Platform Constraints

- Roblox / Luau, `--!strict` everywhere
- **Full PC and mobile parity** — the tap-select-tap-pass mechanic must work with thumbs
  and with a mouse. Movement controls hide during the card phase; touch targets ≥48px;
  `ScreenInsets` set explicitly
- 3-player minimum, 10-player cap
- Rounds per match = starting roster size, so every starting player hides exactly once
