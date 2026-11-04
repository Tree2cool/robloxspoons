# Spoons

> Working title. Repo is `robloxspoons`; final experience name is not yet locked.

## What This Is

A Roblox multiplayer party game that splits the classic card game Spoons into two
halves: a real-time card scramble and a hide-and-seek hunt across a map. One player
per round hides the spoons somewhere in the level; everyone else races to collect
four of a kind at the card table, and the moment you do, you leave the table and run
out to find one of the hidden spoons. There are always two fewer spoons than players,
so somebody comes home empty-handed.

It is for Roblox players who know party games like Spoons, Hide & Seek and Murder
Mystery — built for PC and mobile at full parity.

## Core Value

The two-stage race has to feel great: the frantic card scramble must flow into the
spoon hunt so that getting four of a kind feels like a starting gun, not a menu
transition.

## Game Design

### Match Structure

- **Rounds per match = player count at match start** (minimum 3 players, so minimum
  3 rounds). This means every player on the starting roster hides exactly once.
- **Highest total points wins.**  Points are earned, not deducted.
- **Spoons per round = N − 2**, where N is the round's player count.
  - 10 players → 1 hider, 9 seekers, 8 spoons → exactly one seeker finds nothing.
  - 3 players → 1 hider, 2 seekers, 1 spoon.
- **Mid-round joiners wait in the parkour room until the next round starts**, then
  play fully. They still join mid-match, still earn fewer points than the starting
  roster, and still add no round. Joining mid-round outright was rejected: spoons are
  counted out as `N − 2` for the roster at round start, so a late arrival would make
  two players finish empty-handed and silently change the stakes of a round already
  underway.
- **Joiners never take a hider turn** — the starting roster keeps the rotation.
- **Round end fires the instant the final spoon is claimed.** The 5:00 clock is a cap,
  not a duration. This matters: it is the difference between a typical ~20-30 minute
  match and the ~67 minute pathological worst case.
- **Round-end podium:** the top 3 **by that round's score** get a ~10-second podium
  moment displaying their equipped cosmetics. Round score rather than match total, so
  the podium stays live even in a match that is already decided.

### Round Flow

**1. Hide phase**

- One hider is alone in the map and places all `N − 2` spoons.
- **Free placement with validity rails** — the hider may place anywhere, but the game
  rejects spots that are not reachable or not visible from a standable position. No
  unfindable spoons. Rejections must be instant and show a reason.
- Hider can **end the phase early** once all spoons are placed. **Hard cap: 90
  seconds.**
- If the cap expires with spoons unplaced, the remainder **auto-fill from a pool of at
  least 16 authored default spots per map**, chosen at random.
- **If the scheduled hider has left**, the round runs on auto-fill and no hider points
  are awarded. The round is not skipped and nobody hides twice — this preserves
  `rounds = starting player count`.
- Meanwhile all seekers wait in a **closed-off waiting room with a parkour course**, so
  the hide phase is not dead time. Mid-round joiners wait here too.

**2. Card phase**

- Seekers sit in a circle. Each holds **4 cards**.
- **One seat — the dealer — holds the remaining deck as their left pile.** The dealer
  is the player who found a spoon first in the previous round.
- **Seat order each round:** finishers in the order they found spoons (1st, 2nd, 3rd…),
  then the empty-handed seeker, then everyone else (previous hider, returning joiners).
  Finishing well buys table position as well as the deck.
- **Dealer collision rule:** if the previous round's first finder is this round's hider,
  the deck passes to the **highest-placed finisher who is actually seated**. Round 1 has
  no prior order, so the dealer is random.
- Passing is **real-time and simultaneous** — no turns:
  1. Tap/click your **left pile** (what the upstream player passed on) → a card enters
     your hand, giving you **5 cards**, and the left pile **locks**.
  2. All 5 cards are selectable. **Tap once to select**, **tap again to send it to your
     right pile** — which is the next player's left pile.
  3. Back to 4 cards, left pile unlocks.
- "The pile locks at 5" is simply the rule **draw only when hand size is 4**.
- **The chain wraps:** the last seat's right pile feeds back underneath the dealer's
  deck. Cards never leave play, so **the deck cannot run dry** and there is no
  deck-exhaustion edge case.
- **Four of a kind is checked only on draw** — passing can only leave a subset of a
  hand that already had none.
- **Jokers are wilds — DECIDED, Gate G1 PASSED in Phase 2.** A joker counts as any rank.
  Completing a set with a joker strands the real fourth card of that rank and removes a
  wild from circulation, which can deadlock a shrinking circle, so this was gated on a
  headless bot simulator rather than assumed. **The gate passed**, selecting one joker
  (`j = 1`) in Wild mode over a pool of `ranks = seatCount + 3` (`k = 3` extra ranks, four
  cards per rank, `seatCount` = seated seekers = players − 1, so circulation = 13), with
  the engine's anti-livelock valve enabled. Measured across 320,000 gated rounds at
  10,000 rounds per (N, pool config) for every N from 3 to 10, in both joker modes and
  both churn variants: **37 stalled rounds — 0.012% aggregate, 0.070% in the worst cell —
  against the 0.500% residual ceiling**, with median time to first completion 16.2s
  against a 45s bar and p95 23.7s against 120s. That is a measured property of the
  *selected* configuration, not an unconditional property of the engine, and the residual
  is recorded rather than rounded to zero. Evidence: `02-G1-REPORT.md` in
  `.planning/phases/02-card-engine-and-pacing-simulator/`; the shipped values live in
  `src/shared/Config/CardPool.luau`.
  **The blocker variant (CARD-12) ships alongside it behind the `JOKER_MODE` flag** — it
  is a live flag rather than a dead fallback, because Blocker clears every bar at every
  player count on the same evidence. This is also why `k >= 1` is mandatory: at `k = 0` a
  Blocker joker can complete nothing, so the flag would be a cliff and not a flag.

**3. Hunt**

- The instant a seeker completes **four of a kind**, they leave the card table and head
  out to search. **The chain closes up** — neighbors link directly, so the circle shrinks
  seat-by-seat and stays solvable.
- **A removed seat's cards go to the successor's inbox, never deleted.** The completed
  four leave play; the fifth card and the seat's left pile pass on. Destroying them can
  make the remaining ranks unsolvable and deadlock the round.
- Hidden spoons **glint only at close range / in line of sight**. Finding one takes
  actually sweeping a space, not spotting a glow from across the map.
- Round ends when **all spoons are found** or the **5:00 round timer** expires.

### Scoring

Two independent components per round, summed:

| Component | Formula | Max |
|-----------|---------|-----|
| **Four-of-a-kind bonus** | 1000 for 1st to get four of a kind, −100 per place after (900, 800, 700…) | 1000 |
| **Find points** | seconds remaining on the 5:00 timer × 10 (i.e. 1 point per 100ms) | 3000 |

- Never finding a spoon → **0 find points** (the four-of-a-kind bonus is still kept).
- Worked example 1: the 8th spoon in a 10-player lobby is found with 2:40 left →
  160s × 10 = **1600 find points**. The last seeker finds nothing → **0**.
- Worked example 2: the player who was 3rd to four-of-a-kind finds a spoon with 1:00
  left → 800 bonus + 600 find = **1400 total**.
- **Seeker ceiling: 4000** (1000 bonus + 3000 find).
- **Timing is measured from server arrival time only**, in integer deciseconds. Client
  timestamps are never trusted — the scoring granularity is 100ms, so a trusted client
  clock would be a direct scoring exploit.

**Hider scoring:**

- **Hider earns `4000 × (average fraction of the round that their spoons survived)`.**
  All 8 spoons found instantly → near 0. None found → 4000.
- Scaled to the seeker ceiling of 4000 deliberately, so the hider turn is **neutral in
  expectation**. Everyone hides exactly once per match, so a hider turn that scored
  systematically worse would be a guaranteed penalty round for every player.
- A flat per-unfound-spoon bonus was rejected: it pays most for spots nobody can find,
  doubling down on the hider's existing perverse incentive.
- The **placement rails are the only counterweight** to the hider wanting unreachable
  spots. Avatar scale must be normalized during placement validation, because body
  scale changes reach and camera height.

## Monetization

All cosmetics are **equipped in the lobby**, never mid-round.

| Item | Where it shows |
|------|----------------|
| **Spoon skins** | Dual visibility — the **hider's** skin is what every hidden spoon looks like on the ground; a **seeker's** own skin takes over once they pick one up and carry it. Default is a plain white spoon. |
| **Deck skins** | Set by the **dealer**, so the cards everyone plays with belong to whoever is performing best. |
| **Deal animations** | Purchasable shuffle-and-deal flourishes that play to the whole table at card-phase start. High visibility by construction. |
| **Character cosmetics** | Hats, trails, emotes — visible in lobby, parkour room, hunt and podium. |
| **Hider effects** | Cosmetic flourishes on placing spoons — placement animations, effect styling. Visual only. |
| **Podium cosmetics** | Poses and effects for the ~10-second top-3 podium at round end. |
| **VIP lobbies** | Access only — a separate lobby, not a gameplay advantage. |

### Cosmetic visibility

Two slots had almost no audience as originally specced — hider effects are seen only by
the hider (who is alone on the map) and deck skins only by players still seated. All
three fixes are in scope:

- **Podium spoon reveal** — at round end, any unfound spoons are revealed with the
  hider's placement effect during the podium window. Shows the purchase to the whole
  server and doubles as satisfying information about where spoons were.
- **Dealer reveal flourish** — the card phase opens with a shuffle-and-deal animation
  showing the dealer's deck skin to every seeker before passing unlocks. The animation
  variants are themselves a purchasable line.
- **Lobby showcase** — the lobby displays each player's full equipped loadout on a
  plinth, so purchases are visible between rounds and while waiting for the 3-player
  minimum.

### Monetization integrity

**Hard rule: nothing purchasable may affect score, findability, or competitive
outcome.** Score multipliers and point boosts were considered and explicitly rejected —
in a points-scored game they sell leaderboard position outright.

Research surfaced that this rule can be broken **without any score multiplier**, so
these are binding constraints, not guidelines:

- **Spoon skins need an enforced template**: fixed bounding box, fixed scale, fixed
  pickup hitbox, and a luminance/contrast floor. Otherwise a dark or dull skin is
  literally purchasable camouflage — and the hider is scored on spoon survival time.
- **The glint is a fixed, non-purchasable world effect.** Glint colour and range are
  the findability mechanism and can never be a cosmetic.
- **Deck skins must not harm legibility** — an ornate deck disadvantages everyone
  except the dealer, who already knows it.
- **Character cosmetics must not change collision or occlusion** — no oversized or
  collidable accessories that alter what players can see or reach.
- **Structural enforcement:** the `Scoring`, `CardTable` and `SpoonPlacement` modules
  must have **no import path to the cosmetics or shop modules**. This makes
  no-pay-to-win a property of the dependency graph rather than a promise someone has
  to remember. A lint rule should enforce it.
- The cosmetic catalog schema contains **only visual fields**.
- **No soft currency, no random/loot crates.** Direct-purchase cosmetics only.

The design deliberately ties the most visible cosmetic slots to **performing well**
(dealer sets the deck and triggers the deal animation, top 3 get the podium) rather
than to paying, so purchases are shown off as a reward for skill.

## Requirements

### Validated

<!-- Shipped and confirmed valuable. -->

(None yet — ship to validate)

### Active

<!-- Current scope. Building toward these. Hypotheses until shipped. -->

- [ ] Pure, headless, synchronous card-ring engine with property/fuzz tests
- [ ] Headless bot pacing simulator; gates the joker-as-wild decision at N=3→10
- [ ] Real-time simultaneous passing: 4-card hand, draw-to-5, tap-select / tap-pass
- [ ] Dealer seat, seat order from previous round's find order, dealer collision rule
- [ ] Wrapping chain so the deck never empties
- [ ] Four-of-a-kind detection on draw; seat removal with cards to successor's inbox
- [ ] Validated remote gateway: server-resolved targets, stable card IDs, rate limiting
- [ ] Hider free placement with reachability + line-of-sight validation and instant
      rejection feedback
- [ ] 90s hide cap with random auto-fill from ≥16 validated default spots per map
- [ ] Departed-hider handling (auto-fill, no hider points, round still runs)
- [ ] Seeker parkour waiting room
- [ ] Server-authoritative spoon visibility — positions never replicated as Instances;
      per-client reveal on range + line of sight (anti-ESP)
- [ ] Spoon claiming without double-claim races
- [ ] Round timer with absolute deadlines, round-ID tokens and idempotent round end
- [ ] Scoring: four-of-a-kind bonus + find points from server arrival time
- [ ] Hider scoring at 4000 × average spoon survival fraction
- [ ] Match structure: rounds = starting player count, min 3, full hider rotation
- [ ] Joiners queue to next round start; no added round; no hider turn
- [ ] AFK auto-pass at the card table (an idle player stalls the whole circle)
- [ ] Leaver handling and match abort below 3 players
- [ ] Spectator mode
- [ ] Match scoreboard showing bonus and find components separately
- [ ] Top-3-by-round-score podium with unfound-spoon reveal
- [ ] Map contract + automated validator that runs every default spot through the real
      placement rules
- [ ] Five maps: hotel (single floor), restaurant, mansion, maze with scattered decoy
      items, office
- [ ] Lobby with 3-player gate, intermission, loadout showcase plinths
- [ ] Cosmetic systems: spoon skins (templated), deck skins, deal animations, character
      cosmetics, hider effects, podium cosmetics
- [ ] Shop with preview-before-buy behind an Owns/Prompt interface
- [ ] Purchase + ownership persistence (Game Pass preferred over Developer Product)
- [ ] VIP lobby access
- [ ] Full PC and mobile parity for card UI, hunt controls and all menus
- [ ] Lint rule enforcing no gameplay→cosmetics dependency

### Out of Scope

- **Score multipliers / point boosts for Robux** — sells leaderboard position directly
  in a points-scored game; rejected explicitly during design
- **Purchasable items affecting findability or hiding power** — same pay-to-win problem
  applied to the hunt; includes purchasable glint colour and untemplated spoon skins
- **Soft currency / spendable in-game coins** — the game has no waits to sell skips for,
  so a currency layer adds economy surface with nothing to spend it on
- **Random/loot crates** — Roblox's Paid Random Items policy requires odds disclosure,
  and the catalog is small enough that direct purchase is better anyway
- **Trading** — large exploit and scam surface for a cosmetics-only catalog
- **Elimination-ladder match format** — rejected in favor of points across a fixed round
  count, so nobody sits out waiting
- **Turn-based card passing** — loses the frantic simultaneous feel that is the point
- **Trash/discard pile at the end of the chain** — the wrapping chain removes the
  deck-exhaustion case entirely
- **Predefined-only hiding spots** — free placement with rails was chosen; the
  default-spot pool exists only as the 90s-cap fallback
- **Mid-round cosmetic swapping** — everything is equipped in the lobby
- **Joining mid-round into an active hunt** — breaks the `N − 2` spoon math
- **Per-round map or hider votes** — inflates round length in an already-long match
- **Player-initiated skip / vote-kick** — griefing surface
- **Custom chat** — use Roblox's native `TextChatService`
- **Hider chat to active seekers during a round** — collusion
- **Custom party queue** — use Roblox's native friend-join
- **Mandatory long tutorial** — party games are learned by playing

## Context

- **Platform:** Roblox, built in Luau. Full PC and mobile parity is a first-class
  requirement, not an afterthought — most Roblox players are on phones, but the design
  targets a good experience on both.
- **Genre anchors:** players will arrive with expectations set by Hide & Seek,
  Murder Mystery 2 and other Roblox party games, plus the physical card game Spoons.
- **The hard part is the card engine.** Research converged unanimously: build it as a
  pure, headless, synchronous module with fuzz tests and a bot pacing simulator
  *before* any UI or networking. It is simultaneously the highest-risk and most
  testable component.
- **The card ring has a clean data structure.** Seats are a circular doubly-linked
  list; each seat has a `hand` and an `inbox` (its left pile, a FIFO deque). Passing
  appends to `seat.next.inbox`; drawing pops your own inbox front. The wrap needs no
  special case because the dealer's inbox *is* the deck. Races are safe by
  construction: every command touches exactly one hand and one inbox, the engine is
  pure and synchronous, and non-yielding Luau handlers are atomic.
- **Card-engine risk is correctness, not load.** Nine clients at human tap speed
  produce only tens of remotes per second — far under Roblox's limits. The real dangers
  are stale hand indices, yields inside state mutations, and client-resolved pass
  targets.
- **Starting state:** empty repository. No existing code, no Rojo project, no place
  file.
- **Cold start is an existential risk.** A new game with a 3-player minimum will often
  sit in empty servers. The parkour room doubles as the lobby activity. Bot fill is a
  deferred high-cost decision.
- **Verification debt from research:** the container's network policy blocked
  `create.roblox.com`, `devforum.roblox.com`, `robloxapi.github.io`,
  `madstudioroblox.github.io` and `jsdotlua.github.io`. API-shape details for
  ProfileStore, `ProcessReceipt`, DataStore limits and remote-ordering guarantees are
  training-knowledge-only and flagged for re-verification. These hosts should be added
  to the environment's allowed domains.
- **Design is unusually well specified for a greenfield project** — scoring formulas,
  round flow and monetization were worked out in detail, and the post-research gaps
  were closed before any code. Downstream phases should treat the numbers in this
  document as decided, not as suggestions.

## Constraints

- **Tech stack**: Roblox / Luau — the platform is the entire premise of the project
- **Platform parity**: PC and mobile must both be first-class — the tap-select-tap-pass
  card mechanic has to work with thumbs on a small screen *and* with a mouse. Mobile
  layout is genuinely tight: five cards plus two piles must share limited landscape
  space with the default movement controls, so movement controls are disabled during
  the card phase, touch targets are ≥48px, and `ScreenInsets` is set explicitly
- **Monetization integrity**: no purchase may affect score, findability or competitive
  outcome — enforced structurally via the dependency graph, not by convention
- **Server authority**: card state, four-of-a-kind detection, spoon placement validity,
  spoon visibility and scoring are all server-authoritative. Hidden spoon positions
  never exist as replicated Instances
- **Round length**: 5:00 cap on the card/hunt phase plus ≤90s hide phase, with round
  end firing immediately on the last claim. A 10-player match is 10 rounds, so round
  pacing determines whether a full match is sittable
- **Minimum viable lobby**: 3 players — the `spoons = N − 2` formula must hold at the
  bottom end, not just at 10
- **No soft currency**: cosmetics and access only, direct purchase

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Real-time simultaneous passing, not turn-based | The chaos *is* the game; turn-based Spoons isn't Spoons | — Pending |
| Tap-pile → 5 cards → tap-select → tap-pass interaction | Works identically with touch and mouse, satisfying full parity | — Pending |
| Chain wraps back under the dealer's deck | Cards never leave play, so deck exhaustion is designed out rather than handled | — Pending |
| Chain closes up when a player leaves for the hunt | Keeps player count and rank count aligned as the circle shrinks | — Pending |
| Removed seat's cards go to the successor, never deleted | Deleting them can make remaining ranks unsolvable and deadlock the round | — Pending |
| Four-of-a-kind checked only on draw | Passing can only leave a subset of a hand that already had none | — Pending |
| Dealer seat awarded by previous round's find order | Gives finishing well a concrete mechanical reward in a simultaneous game | — Pending |
| Dealer falls to next seated finisher when first finder is hider | Keeps the reward with whoever earned it most among players present | — Pending |
| Seat order: finishers, then non-finder, then the rest | Finishing well buys table position too; consistent and easy to explain | — Pending |
| Points across rounds, not elimination | Nobody sits out waiting; supports drop-in play | — Pending |
| Rounds = starting player count | Makes the hider rotation exactly fair — everyone hides once | — Pending |
| Separate four-of-a-kind bonus and find-time points | Rewards card skill and hunt skill independently | — Pending |
| Hider scores 4000 × average spoon survival fraction | Matches the seeker ceiling so the hider turn is neutral in expectation | — Pending |
| Jokers as wilds, gated on a solvability simulator | Keeps the swings he wanted, with a pre-agreed blocker fallback if unsafe | **Wilds — Gate G1 PASSED** (Phase 2, 2026-11-04): `k = 3` extra ranks, `j = 1` joker, `JOKER_MODE = "Wild"` by default with Blocker live behind the flag. 37 stalled rounds in 320,000 gated — 0.012% aggregate, 0.070% worst cell — against a 0.500% ceiling. Evidence: `.planning/phases/02-card-engine-and-pacing-simulator/02-G1-REPORT.md` |
| Keep the 5:00 cap; end the round on the last claim | 5:00 is a cap, not a duration; avoids redesigning scoring around a rare tail | — Pending |
| Joiners queue to the next round | Preserves the `N − 2` spoon math exactly instead of changing a round mid-flight | — Pending |
| Departed hider → auto-fill, no hider points, round runs | Preserves rounds = starting count; nobody hides twice | — Pending |
| Free hide placement with reachability/visibility rails | Expressive hiding without unfindable spoons stalling rounds | — Pending |
| ≥16 validated default spots per map as 90s-cap fallback | Guarantees a complete round even if the hider stalls or disconnects | — Pending |
| Podium ranks by round score, not match total | Keeps the podium live even in a match that's already decided | — Pending |
| Spoon skins show on ground (hider's) and in hand (seeker's) | Buyers get visibility every round, not only on their one hider turn | — Pending |
| Deck skin set by the dealer | Ties the most visible cosmetic slot to playing well, not to paying | — Pending |
| Purchasable deal animations revealed at card-phase start | High-visibility by construction, unlike the two slots it replaces | — Pending |
| Podium spoon reveal carries the hider's effect | Gives an otherwise invisible purchase a server-wide audience | — Pending |
| Enforced spoon-skin template + fixed non-purchasable glint | Without it, a dull skin is purchasable camouflage in a scored game | — Pending |
| Gameplay modules cannot import cosmetics/shop modules | Makes no-pay-to-win a dependency-graph property, not a convention | — Pending |
| Spoons are server-side data, never replicated Instances | A cheat client can read any Instance position; anti-ESP is load-bearing | — Pending |
| Game Passes preferred over Developer Products | Roblox holds ownership, removing receipt idempotency and persistence risk | — Pending |
| Pure RemoteEvents behind one typed `Net` module | 10 players at tap speed is far under remote limits; codegen libs add risk | — Pending |
| No soft currency, no loot crates | Nothing to spend currency on; crates trigger odds-disclosure policy | — Pending |
| 5 maps in v1 | Variety is what keeps a hunt game alive past the first session | — Pending |
| Full PC/mobile parity | Splitting the Roblox audience is not worth the saved UI work | — Pending |
| The engine carries an anti-livelock safety valve, enabled in the shipped game | A purely greedy table livelocks at a non-zero rate at every pool; the engine detects a repeated whole-table state with no completion since the previous repeat and forces one uniformly random pass, so zero stalls is a measured property of the engine plus the selected pool rather than an assumption about how people play. **The honest limit, in the same row:** it is demonstrated for the selected pool at the confirmed round count, never universally — the valve-on residual is 0.070% in the worst cell, and k=2,j=2 carries a residual too | `ANTI_LIVELOCK_VALVE = true` in `src/shared/Config/CardPool.luau` (02-CONTEXT amendments A7, A7-CORRECTION, A8). At the selected pool the valve-DISABLED twin cells stall at 3.58–8.31% while the valve fires at the matching rate, so every firing is a real rescue. It fires in roughly 8% of rounds at a full roster: `ValveForcedPass` is an ordinary visible event for Phase 4, not an edge case. Evidence: `.planning/phases/02-card-engine-and-pacing-simulator/02-G1-REPORT.md` sections 4 and 4b |
| AFK auto-pass deadline ceiling (CARD-16, built in Phase 4) | A product value now that the valve carries the zero-stall job rather than a tuned one; CARD-16 benches a player after repeated strikes, so a short deadline would be striking ordinary players several times a round. The deadline's firing curve is in the report | `AUTO_PASS_MAX_SECONDS = 8.0` — Phase 4's deadline must not exceed it. Evidence: `.planning/phases/02-card-engine-and-pacing-simulator/02-G1-REPORT.md` section 5 (0 auto-passes at 8.0s, 2 at 5.0s, 58 at 3.0s, 38,516 at 1.5s) |
| AFK auto-pass SELECTION rule is uniform-random-from-hand | Deviation comes from the auto-pass choosing a card the player would NOT have chosen. 'Auto-pass your worst card' is the player's own greedy choice: deviation would be exactly zero and the simulator's result would transfer nothing to the shipped game. This row exists because the rule is easy to 'improve' in Phase 4 without anyone noticing it invalidates G1 | `AUTO_PASS_SELECTION = "uniform-random-from-hand"` — a **constraint on Phase 4**, not a tuning knob. The rule modelled throughout the sweep is `Bots.randomPass`, a card drawn uniformly at random from the hand. Evidence: `.planning/phases/02-card-engine-and-pacing-simulator/02-G1-REPORT.md` |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-11-04 — Phase 2 complete; Gate G1 decided and recorded (plan 02-12)*
