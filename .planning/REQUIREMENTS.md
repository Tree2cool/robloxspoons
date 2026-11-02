# Requirements: Spoons

**Defined:** 2026-11-02
**Core Value:** The two-stage race has to feel great — the frantic card scramble must flow
into the spoon hunt so that getting four of a kind feels like a starting gun, not a menu
transition.

## v1 Requirements

Requirements for initial release. Each maps to exactly one roadmap phase.

### Foundations

- [ ] **FOUND-01
**: Rojo project syncs to Studio with git as source of truth, with `$ignoreUnknownInstances` on Workspace so Studio-authored maps are not deleted on sync
- [ ] **FOUND-02
**: Toolchain is pinned via Rokit (StyLua, Selene, luau-lsp) and every Luau file is `--!strict`
- [ ] **FOUND-03**: Engine tests and the fuzz suite run headless outside Studio in CI
- [ ] **FOUND-04**: Every client-to-server message passes a single typed gateway that validates arguments (including NaN) and rate-limits per player
- [ ] **FOUND-05**: The build fails if `Scoring`, `CardTable` or `SpoonPlacement` gain an import path to any cosmetics or shop module
- [ ] **FOUND-06**: The build fails if the card engine references any Roblox API
- [ ] **FOUND-07**: A Studio session cannot write to production player data
- [ ] **FOUND-08**: Server enforces a 10-player cap and a 3-player minimum to start

### Card Engine

- [ ] **CARD-01**: Player holds 4 cards and can draw from their left pile only when their hand size is exactly 4
- [ ] **CARD-02**: Player selects a card with one tap and sends it to their right pile with a second tap
- [ ] **CARD-03**: A passed card arrives in the next seat's left pile, with the server resolving which seat that is at execution time
- [ ] **CARD-04**: The last seat's passes land beneath the dealer's deck, so the deck never runs dry
- [ ] **CARD-05**: The dealer is the previous round's first finder; if that player is hiding, the deck goes to the highest-placed finisher actually seated; round 1's dealer is random
- [ ] **CARD-06**: Seat order each round is finishers in find order, then the empty-handed seeker, then everyone else
- [ ] **CARD-07**: Four of a kind is detected on draw and immediately removes that player from the table
- [ ] **CARD-08**: A removed seat's remaining cards route to the successor's left pile and are never destroyed
- [ ] **CARD-09**: No player is dealt an opening hand that is already complete or completable by a held wild
- [ ] **CARD-10**: Jokers act as wilds, and natural cards are spent before jokers when a set completes
- [ ] **CARD-11**: A headless pacing simulator proves the table stays solvable at every player count from 3 to 10, and selects the card pool and joker count
- [ ] **CARD-12**: Jokers revert to blockers that can never complete a set if the simulator cannot prove solvability
- [ ] **CARD-13**: Player can see their own hand and only the pile depths of others
- [ ] **CARD-14**: Passing feels immediate on a normal connection, with server reconciliation correcting any mismatch
- [ ] **CARD-15**: Player is protected from passing a card by accident
- [ ] **CARD-16**: An idle player is auto-passed so they cannot stall the circle, and is benched after repeated strikes
- [ ] **CARD-17**: Completing four of a kind plays a distinct moment that reads as a starting gun
- [ ] **CARD-18**: The card phase opens with a shuffle-and-deal animation showing the dealer's deck skin before passing unlocks
- [ ] **CARD-19**: Card faces are legible and colour-blind-safe

### Hide Phase

- [ ] **HIDE-01**: Hider can place all `N − 2` spoons anywhere in the map, with a live ghost preview showing whether the spot is valid
- [ ] **HIDE-02**: An invalid spot is rejected instantly with a visible reason
- [ ] **HIDE-03**: Hider can undo a placement, and can end the phase early once every spoon is placed
- [ ] **HIDE-04**: The hide phase ends automatically at 90 seconds
- [ ] **HIDE-05**: Any unplaced spoons auto-fill at random from the map's validated default spots
- [ ] **HIDE-06**: A spot is valid only when a reachable standable position exists within pickup range of it with clear line of sight
- [ ] **HIDE-07**: Placement validity is unaffected by the hider's avatar scale
- [ ] **HIDE-08**: If the scheduled hider has left, the round still runs on auto-fill and awards no hider points
- [ ] **HIDE-09**: Seekers wait in a closed-off parkour room for the duration of the hide phase
- [ ] **HIDE-10**: The hider cannot communicate with active seekers during the round

### Hunt

- [ ] **HUNT-01**: Hidden spoon positions exist only as server-side data and never as replicated instances, attributes or values
- [ ] **HUNT-02**: A seeker learns a spoon's position only while within glint range of it with clear line of sight
- [ ] **HUNT-03**: Seeker picks up a spoon through a client-side prompt that the server re-validates before granting
- [ ] **HUNT-04**: A spoon can be claimed by exactly one player, even when two claim in the same instant
- [ ] **HUNT-05**: Seekers can see how many spoons remain unfound
- [ ] **HUNT-06**: Player-to-player collisions are disabled during the hunt
- [ ] **HUNT-07**: A player who has finished their round can spectate
- [ ] **HUNT-08**: Implausible movement toward a spoon is detected and the claim rejected

### Scoring

- [ ] **SCORE-01**: The first player to four of a kind earns a 1000-point bonus, decreasing by 100 for each subsequent place
- [ ] **SCORE-02**: Finding a spoon earns 10 points per second remaining on the 5:00 cap, measured from server arrival time in integer deciseconds
- [ ] **SCORE-03**: A seeker who finds no spoon earns 0 find points but keeps their four-of-a-kind bonus
- [ ] **SCORE-04**: The hider earns 4000 × the average fraction of a fixed 300 seconds that their spoons survived, with unfound spoons counting as the full 300
- [ ] **SCORE-05**: The round ends the instant the final spoon is claimed, or at the 5:00 cap
- [ ] **SCORE-06**: Round end happens exactly once, and a scheduled callback from an earlier round can never affect a later one
- [ ] **SCORE-07**: The scoreboard shows four-of-a-kind bonus and find points as separate figures
- [ ] **SCORE-08**: The top 3 by that round's score get a ~10-second podium displaying their equipped cosmetics
- [ ] **SCORE-09**: The podium reveals any unfound spoons using the hider's placement effect
- [ ] **SCORE-10**: The match winner is the highest total, with ties broken by a deterministic rule

### Match Lifecycle

- [ ] **MATCH-01**: A match runs a number of rounds equal to the starting roster size, with a 3-player minimum
- [ ] **MATCH-02**: Every player on the starting roster hides exactly once per match
- [ ] **MATCH-03**: The lobby holds until 3 players are present, with an intermission and the parkour course available
- [ ] **MATCH-04**: Player equips cosmetics in the lobby only, never mid-round
- [ ] **MATCH-05**: The lobby displays each player's equipped loadout on a showcase plinth
- [ ] **MATCH-06**: A player who joins mid-round waits in the parkour room and enters play at the next round start
- [ ] **MATCH-07**: A joiner adds no round to the match and never takes a hider turn
- [ ] **MATCH-08**: A player who leaves and rejoins is treated as a joiner and forfeits any unplayed hider turn
- [ ] **MATCH-09**: Players can see the hider rotation order
- [ ] **MATCH-10**: If the roster drops below 3, the round in progress finishes, its points are awarded, and the match ends on current totals with no win credit
- [ ] **MATCH-11**: Each phase waits for clients to signal ready before starting, with a timeout
- [ ] **MATCH-12**: Chat is muted per phase for the hider and for players who have finished their round

### Maps

- [ ] **MAP-01**: Maps are data behind one shared contract, with no per-map code branches
- [ ] **MAP-02**: An automated validator runs every authored default spot through the real placement rules and fails the build on any that would be unfindable
- [ ] **MAP-03**: Every map provides at least 16 validated default hiding spots
- [ ] **MAP-04**: Maps are selected at random without repeating the previous map
- [ ] **MAP-05**: Hotel map (single floor) is playable end to end
- [ ] **MAP-06**: Restaurant map is playable end to end
- [ ] **MAP-07**: Mansion map is playable end to end
- [ ] **MAP-08**: Maze map with scattered decoy items is playable end to end
- [ ] **MAP-09**: Office map is playable end to end

### Shop and Cosmetics

- [ ] **SHOP-01**: Player can buy a spoon skin that appears on every spoon they hide, and on any spoon they carry
- [ ] **SHOP-02**: Every spoon skin conforms to an enforced template — fixed bounding box, scale, pickup hitbox and a luminance/contrast floor — so no skin is camouflage
- [ ] **SHOP-03**: Glint appearance and range are fixed and cannot be purchased or altered
- [ ] **SHOP-04**: Player can buy a deck skin, used by the whole table on rounds where they are dealer
- [ ] **SHOP-05**: Player can buy a deal animation, with one fixed duration enforced across every variant
- [ ] **SHOP-06**: Player can buy character cosmetics that cannot change collision or occlusion
- [ ] **SHOP-07**: Player can buy hider placement effects
- [ ] **SHOP-08**: Player can buy podium cosmetics
- [ ] **SHOP-09**: Player can buy VIP lobby access, which confers no gameplay advantage
- [ ] **SHOP-10**: Player can preview any item and see its exact price before buying
- [ ] **SHOP-11**: Player can see what they own and equip it from an inventory view
- [ ] **SHOP-12**: Purchases are granted server-side and are still owned after rejoining
- [ ] **SHOP-13**: A purchase is never granted twice and never lost
- [ ] **SHOP-14**: The default spoon and default deck are free to every player
- [ ] **SHOP-15**: A set of cosmetics is unlocked by achievement rather than purchase, so a non-paying player has something to work toward
- [ ] **SHOP-16**: Player loadout, stats and settings persist across sessions with session locking

### Parity and Accessibility

- [ ] **UX-01**: The card hand and both piles are fully playable on a phone in landscape, with touch targets of at least 48px
- [ ] **UX-02**: Movement controls are hidden during the card phase so they cannot occlude the hand
- [ ] **UX-03**: UI respects device safe areas on every supported screen
- [ ] **UX-04**: Prompts and hints match the player's current input method
- [ ] **UX-05**: First-run contextual prompts teach the loop without a mandatory tutorial
- [ ] **UX-06**: The game runs acceptably on low-end mobile hardware
- [ ] **UX-07**: Supported devices and screen orientation are set explicitly, with console and VR disabled

### Social

- [ ] **SOC-01**: Leaderstats show the player's current score
- [ ] **SOC-02**: Chat uses Roblox's native `TextChatService`
- [ ] **SOC-03**: Players can join friends through Roblox's native flow

## v2 Requirements

Deferred to future release. Tracked but not in the current roadmap.

### Cold Start

- **BOT-01**: Labelled, stats-excluded card bots fill below-minimum lobbies
- **BOT-02**: Bot fill decision is driven by lobby-wait telemetry

### Lifecycle

- **LIFE-07**: Player can reconnect into a match in progress

### Progression

- **PROG-01**: Global and seasonal leaderboards
- **PROG-02**: Roblox badges for milestones
- **PROG-03**: Quests and seasonal objectives

### Shop

- **SHOP-17**: Themed cosmetic sets
- **SHOP-18**: Rotating limited stock
- **SHOP-19**: Gifting
- **SHOP-20**: Roblox Premium perk

### Feel

- **HUNT-09**: Proximity audio and haptic cue near a spoon
- **HIDE-11**: Hider spectate HUD during the hunt
- **CARD-20**: Joker callout moment
- **MAP-10**: Seasonal map skins

### Input

- **UX-08**: Gamepad support
- **UX-09**: Quick-chat phrases

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Score multipliers / point boosts for Robux | Sells leaderboard position directly in a points-scored game |
| Purchasable glint colour or range | Glint *is* the findability mechanism — making it a cosmetic makes finding purchasable |
| Untemplated spoon skins | A dark or dull skin is purchasable camouflage, and the hider is scored on survival time |
| Soft currency / spendable coins | No waits to sell skips for; adds economy surface with nothing to spend it on |
| Random / loot crates | Triggers Roblox's Paid Random Items odds-disclosure policy; catalog is small enough for direct purchase |
| Trading | Large scam and exploit surface for a cosmetics-only catalog |
| Elimination-ladder format | Rejected for points-across-rounds so nobody sits out waiting |
| Turn-based card passing | Loses the frantic simultaneous feel that is the entire point |
| Trash pile at the end of the chain | The wrapping chain removes deck exhaustion entirely |
| Predefined-only hiding spots | Free placement with rails chosen instead; defaults exist only as the 90s fallback |
| Mid-round cosmetic swapping | Everything is equipped in the lobby |
| Joining mid-round into an active hunt | Breaks the `N − 2` spoon math and changes a round already underway |
| Per-round map or hider votes | Inflates round length in an already-long match |
| Player-initiated skip / vote-kick | Griefing surface |
| Custom chat system | Use native `TextChatService` |
| Hider chat to active seekers | Collusion |
| Custom party queue | Use Roblox's native friend-join |
| Mandatory long tutorial | Party games are learned by playing |
| Bot seekers in the hunt | Undermines hide-and-seek integrity and scoring; card-only fill is the v2 option |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| FOUND-01 | Phase 1 | Pending |
| FOUND-02 | Phase 1 | Pending |
| FOUND-03 | Phase 1 | Pending |
| FOUND-04 | Phase 1 | Pending |
| FOUND-05 | Phase 1 | Pending |
| FOUND-06 | Phase 1 | Pending |
| FOUND-07 | Phase 1 | Pending |
| FOUND-08 | Phase 1 | Pending |
| CARD-01 | Phase 2 | Pending |
| CARD-02 | Phase 4 | Pending |
| CARD-03 | Phase 2 | Pending |
| CARD-04 | Phase 2 | Pending |
| CARD-05 | Phase 2 | Pending |
| CARD-06 | Phase 2 | Pending |
| CARD-07 | Phase 2 | Pending |
| CARD-08 | Phase 2 | Pending |
| CARD-09 | Phase 2 | Pending |
| CARD-10 | Phase 2 | Pending |
| CARD-11 | Phase 2 | Pending |
| CARD-12 | Phase 2 | Pending |
| CARD-13 | Phase 4 | Pending |
| CARD-14 | Phase 4 | Pending |
| CARD-15 | Phase 4 | Pending |
| CARD-16 | Phase 4 | Pending |
| CARD-17 | Phase 4 | Pending |
| CARD-18 | Phase 7 | Pending |
| CARD-19 | Phase 4 | Pending |
| HIDE-01 | Phase 6 | Pending |
| HIDE-02 | Phase 6 | Pending |
| HIDE-03 | Phase 6 | Pending |
| HIDE-04 | Phase 6 | Pending |
| HIDE-05 | Phase 6 | Pending |
| HIDE-06 | Phase 3 | Pending |
| HIDE-07 | Phase 3 | Pending |
| HIDE-08 | Phase 6 | Pending |
| HIDE-09 | Phase 6 | Pending |
| HIDE-10 | Phase 6 | Pending |
| HUNT-01 | Phase 5 | Pending |
| HUNT-02 | Phase 5 | Pending |
| HUNT-03 | Phase 5 | Pending |
| HUNT-04 | Phase 5 | Pending |
| HUNT-05 | Phase 5 | Pending |
| HUNT-06 | Phase 5 | Pending |
| HUNT-07 | Phase 5 | Pending |
| HUNT-08 | Phase 5 | Pending |
| SCORE-01 | Phase 5 | Pending |
| SCORE-02 | Phase 5 | Pending |
| SCORE-03 | Phase 5 | Pending |
| SCORE-04 | Phase 5 | Pending |
| SCORE-05 | Phase 5 | Pending |
| SCORE-06 | Phase 1 | Pending |
| SCORE-07 | Phase 6 | Pending |
| SCORE-08 | Phase 6 | Pending |
| SCORE-09 | Phase 7 | Pending |
| SCORE-10 | Phase 6 | Pending |
| MATCH-01 | Phase 6 | Pending |
| MATCH-02 | Phase 6 | Pending |
| MATCH-03 | Phase 6 | Pending |
| MATCH-04 | Phase 7 | Pending |
| MATCH-05 | Phase 7 | Pending |
| MATCH-06 | Phase 6 | Pending |
| MATCH-07 | Phase 6 | Pending |
| MATCH-08 | Phase 6 | Pending |
| MATCH-09 | Phase 6 | Pending |
| MATCH-10 | Phase 6 | Pending |
| MATCH-11 | Phase 6 | Pending |
| MATCH-12 | Phase 6 | Pending |
| MAP-01 | Phase 1 | Pending |
| MAP-02 | Phase 3 | Pending |
| MAP-03 | Phase 3 | Pending |
| MAP-04 | Phase 6 | Pending |
| MAP-05 | Phase 7 | Pending |
| MAP-06 | Phase 7 | Pending |
| MAP-07 | Phase 7 | Pending |
| MAP-08 | Phase 7 | Pending |
| MAP-09 | Phase 7 | Pending |
| SHOP-01 | Phase 7 | Pending |
| SHOP-02 | Phase 7 | Pending |
| SHOP-03 | Phase 7 | Pending |
| SHOP-04 | Phase 7 | Pending |
| SHOP-05 | Phase 7 | Pending |
| SHOP-06 | Phase 7 | Pending |
| SHOP-07 | Phase 7 | Pending |
| SHOP-08 | Phase 7 | Pending |
| SHOP-09 | Phase 7 | Pending |
| SHOP-10 | Phase 7 | Pending |
| SHOP-11 | Phase 7 | Pending |
| SHOP-12 | Phase 7 | Pending |
| SHOP-13 | Phase 7 | Pending |
| SHOP-14 | Phase 7 | Pending |
| SHOP-15 | Phase 7 | Pending |
| SHOP-16 | Phase 7 | Pending |
| UX-01 | Phase 4 | Pending |
| UX-02 | Phase 4 | Pending |
| UX-03 | Phase 4 | Pending |
| UX-04 | Phase 4 | Pending |
| UX-05 | Phase 8 | Pending |
| UX-06 | Phase 8 | Pending |
| UX-07 | Phase 8 | Pending |
| SOC-01 | Phase 6 | Pending |
| SOC-02 | Phase 6 | Pending |
| SOC-03 | Phase 8 | Pending |

**Coverage:**
- v1 requirements: 102 total
- Mapped to phases: 102 ✓
- Unmapped: 0

---
*Requirements defined: 2026-11-02*
*Last updated: 2026-11-02 after roadmap creation (traceability mapped)*
