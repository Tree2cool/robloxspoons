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
- **Highest total points wins.** Points are earned, not deducted.
- **Spoons per round = N − 2**, where N is the round's player count.
  - 10 players → 1 hider, 9 seekers, 8 spoons → exactly one seeker finds nothing.
  - 3 players → 1 hider, 2 seekers, 1 spoon.
- **Mid-round joiners** play as seekers only. They never take a hider turn, and they
  do not add a round to the match. They will finish with fewer points than the
  starting roster by design.
- **Round end:** the top 3 players get a ~10-second podium moment displaying their
  equipped cosmetics.

### Round Flow

**1. Hide phase**

- One hider is alone in the map and places all `N − 2` spoons.
- **Free placement with validity rails** — the hider may place anywhere, but the game
  rejects spots that are not reachable or not visible from a standable position. No
  unfindable spoons.
- Hider can **end the phase early** once all spoons are placed. **Hard cap: 90
  seconds.**
- If the cap expires with spoons unplaced, the remainder **auto-fill from a pool of at
  least 16 authored default spots per map**, chosen at random.
- Meanwhile all seekers wait in a **closed-off waiting room with a parkour course**, so
  the hide phase is not dead time.

**2. Card phase**

- Seekers sit in a circle. Each holds **4 cards**.
- **One seat — the dealer — holds the remaining deck as their left pile.** The dealer
  is the player who found a spoon first in the previous round. Second finisher sits
  second in the order, and so on. This is the carried-over reward for finishing well:
  the dealer sees every fresh card first.
- Passing is **real-time and simultaneous** — no turns:
  1. Tap/click your **left pile** (what the upstream player passed on) → a card enters
     your hand, giving you **5 cards**, and the left pile **locks**.
  2. All 5 cards are selectable. **Tap once to select**, **tap again to send it to your
     right pile** — which is the next player's left pile.
  3. Back to 4 cards, left pile unlocks.
- **The chain wraps:** the last seat's right pile feeds back underneath the dealer's
  deck. Cards never leave play, so **the deck cannot run dry** and there is no
  deck-exhaustion edge case.
- **Jokers** are mixed into the deck as wilds, creating swings and near-misses.

**3. Hunt**

- The instant a seeker completes **four of a kind**, they leave the card table and head
  out to search. **Their 4 cards leave with them and the chain closes up** — neighbors
  link directly, so the circle shrinks seat-by-seat and stays solvable.
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
- **Hider scoring:** the hider earns based on **how long their spoons survive unfound** —
  roughly the inverse of what the seekers earn. Hiding well is the hider's way to score,
  so the hider turn is a real competitive round, not a bye.

## Monetization

All cosmetics are **equipped in the lobby**, never mid-round.

| Item | Where it shows |
|------|----------------|
| **Spoon skins** | Dual visibility — the **hider's** skin is what every hidden spoon looks like on the ground; a **seeker's** own skin takes over once they pick one up and carry it. Default is a plain white spoon. |
| **Special decks** | Set by the **dealer** (previous round's first finder), so the cards everyone plays with are the deck of whoever is performing best. |
| **Character cosmetics** | Hats, trails, emotes — visible in lobby, parkour room, hunt and podium. |
| **Hider effects** | Cosmetic flourishes on the act of placing spoons — placement animations, glint colors. Visual only. |
| **Podium cosmetics** | Poses and effects for the ~10-second top-3 podium at round end. |
| **VIP lobbies** | Access only — a separate lobby, not a gameplay advantage. |

**Hard rule: nothing purchasable may affect score, findability, or competitive
outcome.** Score multipliers and point boosts were considered and explicitly rejected —
in a points-scored game they sell leaderboard position outright. Hider effects must stay
purely visual; anything that changes how easy a spoon is to find crosses the line.

The design deliberately ties the most visible cosmetic slots to **performing well**
(dealer sets the deck, top 3 get the podium) rather than to paying, so purchases are
shown off as a reward for skill.

## Requirements

### Validated

<!-- Shipped and confirmed valuable. -->

(None yet — ship to validate)

### Active

<!-- Current scope. Building toward these. Hypotheses until shipped. -->

- [ ] Real-time simultaneous card passing: 4-card hand, draw-to-5 from locking left
      pile, tap-to-select / tap-to-pass to right pile
- [ ] Dealer seat holds the deck; seat order carried over from previous round's find
      order; chain wraps so the deck never empties
- [ ] Jokers as wilds in the deck
- [ ] Four-of-a-kind detection removes the player from the table and closes the chain
- [ ] Hider hide phase: free placement with reachability/visibility validation, early
      end, 90s cap, random auto-fill from ≥16 default spots per map
- [ ] Seeker waiting room with parkour during hide phase
- [ ] Close-range-only spoon glint and spoon pickup
- [ ] Round timer (5:00) and round-end conditions (all spoons found / timeout)
- [ ] Scoring: four-of-a-kind order bonus + find-time points; hider scored on spoon
      survival time
- [ ] Match structure: rounds = starting player count, min 3, full hider rotation
- [ ] Mid-round join as seeker-only with no added round
- [ ] Match scoreboard and winner determination (highest total)
- [ ] Top-3 podium moment (~10s) at round end showing equipped cosmetics
- [ ] Five maps: hotel (single floor), restaurant, mansion, maze with scattered decoy
      items, office
- [ ] Lobby with cosmetic equipping
- [ ] Cosmetic systems: spoon skins (ground + held), special decks, character
      cosmetics, hider effects, podium cosmetics
- [ ] Robux purchase flow and ownership persistence
- [ ] VIP lobby access
- [ ] Full PC and mobile parity for card UI, hunt controls and all menus

### Out of Scope

- **Score multipliers / point boosts for Robux** — sells leaderboard position directly
  in a points-scored game; rejected explicitly during design
- **Purchasable items affecting findability or hiding power** — same pay-to-win problem
  applied to the hunt
- **Elimination-ladder match format** — considered and rejected in favor of points
  across a fixed round count, so nobody sits out waiting
- **Turn-based card passing** — loses the frantic simultaneous feel that is the point
  of Spoons
- **Trash/discard pile at the end of the chain** — the wrapping chain removes the
  deck-exhaustion case entirely
- **Predefined-only hiding spots** — free placement with rails was chosen for
  expressiveness; the default-spot pool exists only as the 90s-cap fallback
- **Mid-round cosmetic swapping** — everything is equipped in the lobby

## Context

- **Platform:** Roblox, built in Luau. Full PC and mobile parity is a first-class
  requirement, not an afterthought — most Roblox players are on phones, but the design
  targets a good experience on both.
- **Genre anchors:** players will arrive with expectations set by Hide & Seek,
  Murder Mystery 2 and other Roblox party games, plus the physical card game Spoons.
- **The hard part is the card engine.** Real-time simultaneous passing across up to 9
  clients with a shrinking circle, authoritative hand state and anti-cheat is
  substantially harder than the map content. The five maps are more total work but far
  lower risk.
- **Starting state:** empty repository. No existing code, no Rojo project, no place
  file.
- **Design is unusually well specified for a greenfield project** — scoring formulas,
  round flow and monetization were worked out in detail before any code. Downstream
  phases should treat the numbers in this document as decided, not as suggestions.

## Constraints

- **Tech stack**: Roblox / Luau — the platform is the entire premise of the project
- **Platform parity**: PC and mobile must both be first-class — the tap-select-tap-pass
  card mechanic has to work with thumbs on a small screen *and* with a mouse
- **Monetization integrity**: no purchase may affect score, findability or competitive
  outcome — protects the game from pay-to-win and from Roblox policy risk
- **Round length**: 5:00 card/hunt phase plus ≤90s hide phase — a 10-player match is
  10 rounds, so round pacing directly determines whether a full match is sittable
- **Minimum viable lobby**: 3 players — the spoons = N−2 formula must hold at the
  bottom end, not just at 10
- **Authoritative server**: card state, four-of-a-kind detection, spoon placement
  validity and scoring must all be server-authoritative — a client-trusted card game
  is trivially exploitable

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Real-time simultaneous passing, not turn-based | The chaos *is* the game; turn-based Spoons isn't Spoons | — Pending |
| Tap-pile → 5 cards → tap-select → tap-pass interaction | Works identically with touch and mouse, satisfying full parity | — Pending |
| Chain wraps back under the dealer's deck | Cards never leave play, so deck exhaustion is designed out rather than handled | — Pending |
| Chain closes up when a player leaves for the hunt | Keeps player count and rank count aligned as the circle shrinks, so it stays solvable | — Pending |
| Dealer seat awarded by previous round's find order | Gives finishing well a concrete mechanical reward in a simultaneous game | — Pending |
| Points across rounds, not elimination | Nobody sits out waiting; supports drop-in play | — Pending |
| Rounds = starting player count | Makes the hider rotation exactly fair — everyone hides once | — Pending |
| Separate four-of-a-kind bonus and find-time points | Rewards card skill and hunt skill independently | — Pending |
| Hider scored on spoon survival time | Turns the hider turn into a real competitive round instead of a bye | — Pending |
| Free hide placement with reachability/visibility rails | Expressive hiding without unfindable spoons stalling rounds | — Pending |
| ≥16 default spots per map as 90s-cap fallback | Guarantees a complete round even if the hider stalls or disconnects | — Pending |
| Spoon skins show on ground (hider's) and in hand (seeker's) | Buyers get visibility every round, not only on their one hider turn | — Pending |
| Deck skin set by the dealer | Ties the most visible cosmetic slot to playing well, not to paying | — Pending |
| No score-affecting purchases | Avoids pay-to-win in a scored game and Roblox policy risk | — Pending |
| 5 maps in v1 | Variety is what keeps a hunt game alive past the first session | — Pending |
| Full PC/mobile parity | Splitting the Roblox audience is not worth the saved UI work | — Pending |

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
*Last updated: 2026-11-01 after initialization*
