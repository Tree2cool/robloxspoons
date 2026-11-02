# Feature Research

**Domain:** Roblox round-based multiplayer party game (real-time Spoons card scramble + hide-and-seek spoon hunt), PC + mobile parity
**Researched:** 2026-11-02
**Confidence:** MEDIUM overall. HIGH on the project-specific interaction analysis (derived directly from PROJECT.md). MEDIUM-LOW on comparable-game feature inventories (see Research Limits).

## Research Limits (read first)

- `create.roblox.com` was **not reachable** from the research session (DNS failure; it must be added to the session's allowed network domains to verify Roblox API and policy docs). Every Roblox API or policy claim below that is not backed by a search-result excerpt is training-data knowledge and is tagged accordingly.
- Web search returned mostly SEO spam for the comparable games (MM2, Flee the Facility, Hide and Seek Extreme, NDS). **Comparable-game feature lists are therefore training-knowledge (MEDIUM/LOW)**, not verified feature-by-feature. The conventions they establish (in-server lobby plus intermission, rarity-tiered cosmetic shops, codes, trading in MM2) are stable and widely corroborated, but specifics such as exact gifting or daily-reward mechanics were NOT verified.
- Verified (MEDIUM, from Roblox newsroom and docs excerpts in search results): chat now requires an age check (global from Jan 2026); the Paid Random Items policy requires published odds and regional gating; Roblox adaptive-design guidance says to adapt prompts to the active input method and respond to user text/UI scaling settings.
- **Phase-time verification needed:** `ContextActionService` mobile button behaviour, `SocialService:PromptGameInvite`, `TextChatService` per-channel muting, `TeleportService` reserved-server reconnect, `MarketplaceService.ProcessReceipt` semantics, native Private Server (VIP server) options. Use Context7 / the Creator Hub once reachable.

## Feature Landscape

Feature IDs use the prefixes intended for requirement IDs: **LOB** (lobby/matchmaking), **LIFE** (match and round lifecycle), **CARD** (card engine UX), **HIDE** (hider phase), **HUNT** (hunt and spectating), **SCORE** (scoring, results, podium), **INTEG** (server authority, anti-exploit, anti-grief), **UX** (parity, accessibility, onboarding), **SOC** (social and safety), **PROG** (progression and retention), **SHOP** (cosmetics and monetization), **MAP** (map content and authoring).

### Table Stakes (Users Expect These)

Missing these = players leave in the first session or the game is broken.

| ID | Feature | Why Expected | Complexity | Notes |
|----|---------|--------------|------------|-------|
| LOB-01 | In-server lobby with min-player gate (3), intermission countdown, auto-start | Every Roblox round game (MM2, FTF, NDS) works this way; players expect to join a server and be playing within ~30-60s | LOW | Countdown restarts or aborts if players drop below 3. Show "waiting for N more players". |
| LOB-02 | Cosmetic equip station in lobby (preview on own avatar) | Equip is lobby-only per PROJECT.md, so the lobby must make it frictionless | MED | Depends on SHOP-inventory. |
| LOB-03 | Lobby activity while waiting (parkour or free roam) | Empty-lobby dead time is the #1 cold-start churn point for a new game | LOW-MED | The waiting-room parkour from the hide phase can double as the lobby activity (reuse content). |
| LIFE-01 | Fixed roster snapshot at match start; per-match hider queue shown to everyone | "Everyone hides once" must be visible and trustworthy, or players feel cheated by the hider turn | LOW | Show upcoming hider order on the scoreboard. |
| LIFE-02 | Mid-round join handling (seeker-only, fewer points by design) | Roblox servers accept joins at any time; unhandled joins break the N-2 spoon rule | MED | **Open design question:** can a joiner take a spoon in the round in progress? See Open Questions. |
| LIFE-03 | Leaver handling: remaining players continue, match aborts cleanly below 3 | Players on mobile disconnect constantly; below 3 the N-2 formula yields zero spoons | MED | Departed hider's turn: auto-fill from default spots, no hider score (consistent with the fallback already in PROJECT.md). Aborted matches grant no win credit. |
| LIFE-04 | AFK detection with auto-pass at the card table | Real-time chain passing: one idle or lagging player locks the downstream neighbour's left pile and **stalls the whole circle** | MED-HIGH | Per-hold timeout that auto-passes a card, then bench the player after N auto-passes. Reuse the "close the chain" code path used for four-of-a-kind exits. |
| LIFE-05 | Match-end screen: final standings, winner, auto-return to lobby with new intermission | Players expect a clear end and a next game, not a dead server | LOW | Include a "leave" and "stay for next match" affordance. |
| LIFE-06 | Round skip/timeout is server-enforced (5:00 round cap, 90s hide cap already specified) | Hard caps are what keep a 10-round match sittable | LOW | Already decided in PROJECT.md. No player-initiated skip is needed (see anti-features). |
| CARD-01 | Server-authoritative hands, piles, four-of-a-kind detection | Client-trusted card state is trivially exploitable | HIGH | Core engine risk per PROJECT.md. |
| CARD-02 | Visible neighbour labels on left and right pile (who you receive from, who you pass to) | Real-time passing is unreadable without it | LOW | Needed for any chain-based play. |
| CARD-03 | Optimistic client animation with server reconciliation | Mobile ping of 100-250ms makes tap-to-pass feel broken without prediction | HIGH | Part of the card engine; must be designed in, not retrofitted. |
| CARD-04 | Clear selection state, deselect, and accidental-pass protection | Fat-finger mis-pass is catastrophic in a race; "tap again to send" is the riskiest mobile interaction in the design | MED | Prototype on a real phone early. Ensure the second tap must hit the already-selected card. |
| CARD-05 | "Four of a kind" moment: audio/visual stinger and a feed line for others | This is the core-value "starting gun"; also lets others perceive their place in the race | MED | Core value feature, not polish. |
| HIDE-01 | Hider placement mode with live validity preview (green/red ghost), undo/relocate, spoons-remaining counter, early-end button | Free placement with rails needs instant feedback or hiders waste the 90s fighting the validator | HIGH | Reachability (Pathfinding) plus visibility (raycast). Must work with thumbs: centred reticle plus a "place" button. |
| HIDE-02 | Auto-fill from >=16 authored default spots on cap or hider disconnect | Already decided; guarantees a complete round | MED | Needs a map authoring tag convention (MAP-02). |
| HIDE-03 | Waiting-room parkour, non-punishing, with a visible hide-phase countdown | Hide phase must not be dead time; mobile parkour is frustrating if punishing | MED | No fall-kill, no stakes affecting card phase. Show "hider has Xs left". |
| HUNT-01 | Close-range/line-of-sight glint, pickup by proximity | Core mechanic | MED | Glint is a standardized world effect; see anti-features for skins. |
| HUNT-02 | Spoons-remaining HUD and "X found a spoon" feed (no location leaked) | Spoons is a pressure game; the shrinking supply is the tension | LOW | |
| HUNT-03 | Spectator mode for finished/empty-handed players, plus hider spectate | Players who are done must still be watching, not staring at a frozen screen | MED | Hider chat to active players is muted until round end (collusion prevention). |
| HUNT-04 | Player-to-player collision off during hunt (and card circle exit) | Body-blocking in maze/hotel corridors and fling exploits are classic Roblox griefing | LOW | CollisionGroups. |
| SCORE-01 | Per-match scoreboard with round-by-round breakdown (bonus + find + hider points) | Two-component scoring is only legible if players can see the components | MED | Players will otherwise not understand why they lost. |
| SCORE-02 | Round-end podium (~10s) showing equipped cosmetics | Specified in PROJECT.md; also doubles as a round-result moment | MED | Ambiguity: top 3 of the round or cumulative? See Open Questions. |
| INTEG-01 | Server-side scoring, timers, spoon placement validation | Required by PROJECT.md constraints | MED | |
| INTEG-02 | Spoon positions not replicated to clients until in range (anti-ESP) | An exploiter with ESP or noclip trivialises a hide-and-seek game; Roblox replicates Instances by default | HIGH | Server holds spoon data, spawns visual only for clients within glint range. Verify with StreamingEnabled behaviour. |
| INTEG-03 | Standard exploit hygiene: server-validated remotes, rate limits, sanity checks on movement | Table stakes for any public Roblox game | MED | |
| UX-01 | First-time tutorial: Spoons rules, card tapping, hider mode | Many Roblox players have never played Spoons; hider turn is unfamiliar | MED | Context prompts, not a mandatory blocking tutorial (round-length risk). Show on first match and first hider turn. |
| UX-02 | Mobile-first UI: safe-area-aware, large touch targets, thumbstick-friendly hunt, on-screen interact button | Most Roblox traffic is mobile; PROJECT.md requires full parity | MED-HIGH | Use ScreenInsets/safe area (documented in Roblox ScreenInsets reference, third-party mirror). 44px minimum target is a third-party guideline. |
| UX-03 | Input-method-aware prompts (tap vs click vs key) | Roblox adaptive-design guidance explicitly says to update prompts for the active input method | LOW | |
| UX-04 | Colour-blind-safe and size-legible cards (suit symbol plus colour; distinct joker) | Four-of-a-kind recognition under time pressure on a small screen | LOW-MED | Never rely on red/black alone. |
| UX-05 | Respect user text/UI scaling and low-end mobile performance | Roblox guidance recommends responding to UI scaling settings; large share of low-end devices | MED | Budget maps for low-end phones (StreamingEnabled). |
| SOC-01 | Roblox default `leaderstats` (total points / match wins) on the player list | Near-zero-cost Roblox convention that every round game has | LOW | |
| SOC-02 | Use Roblox-native chat (TextChatService) with platform filtering; game fully playable without chat | Chat requires an age check since Jan 2026, so many players have chat disabled. No gameplay-critical comms in chat | LOW | Do not build custom chat. |
| SOC-03 | Friend join and invite via Roblox native join plus invite prompt | Friends joining each other is the main growth channel for a new game | LOW | Verify `SocialService` invite prompt in docs. |
| PROG-01 | Persistent ownership, equipped loadout, and currency (DataStore, with failure handling and session locking) | Losing purchases is the fastest way to get review-bombed | MED | |
| PROG-02 | Participation reward for every player, including the empty-handed last seeker and low scorers | One player per round necessarily loses; the loop needs them to still progress | LOW | Coins/XP only; never touches score. |
| PROG-03 | Persistent stats (matches, wins, rounds hidden, best hide survival) | Cheap and feeds leaderboards, badges and profile | LOW-MED | |
| SHOP-01 | Shop UI with categories matching purchasable types (spoon, deck, character, hider effect, podium, VIP) | Conventional | MED | |
| SHOP-02 | Preview-before-buy for every cosmetic type | Roblox cosmetic shops universally preview; buying blind to a deck or podium pose feels bad | MED | Viewport preview or try-on in lobby. |
| SHOP-03 | Inventory/equip UI with one slot per cosmetic type; owned vs unowned states | Required for lobby equip | MED | |
| SHOP-04 | Idempotent purchase processing (`ProcessReceipt`), restore on rejoin | Robux handling bugs cause refunds and policy trouble | MED | Verify against docs. |
| SHOP-05 | Free/earnable path to some cosmetics | Roblox kids' audience; a pure-Robux shop converts poorly and reads as predatory | LOW | Soft currency earned from play. Decision needed (see Open Questions). |
| MAP-01 | Five maps with fair spawn/seat/waiting-room layout and per-map spoon default spots | Specified | HIGH (content volume) | Lower risk than card engine. |
| MAP-02 | Authoring tags and a validation tool for default spots, reachable/visible areas | Needed to keep 5 maps x >=16 spots correct | MED | An editor plugin or tagged-parts convention with automated checks. |
| MAP-03 | Random map selection with no immediate repeats | 10 rounds, 5 maps: repeats feel stale | LOW | |
| LOB-04 | VIP lobby access (see Differentiators for private-server framing) | Specified in monetization | MED | Host controls (start, kick, min players) are table stakes inside a VIP lobby. |

### Differentiators (Competitive Advantage)

Not required, but this is where the game competes. Keep them aligned to Core Value (the scramble flowing into the hunt).

| ID | Feature | Value Proposition | Complexity | Notes |
|----|---------|-------------------|------------|-------|
| CARD-06 | Dealer reveal moment: deck-back flourish and nameplate at card-phase start | Gives the dealer deck skin real visibility; otherwise only the previous round's best performer ever displays it | LOW-MED | Deck skin exposure is the weakest cosmetic slot; this fixes it. |
| CARD-07 | Joker "wild" callout and near-miss feedback (e.g. 3 of a kind plus joker pulse) | Reinforces the frantic feel | LOW | |
| HIDE-04 | Hider scoring HUD: live "spoons surviving" timer for the hider while spectating | Makes the hider turn feel like a competition, not a bye | LOW | Pairs with HUNT-03 hider spectate. |
| HIDE-05 | End-of-round reveal of unfound spoons with the hider's placement effect | Gives the hider-effects cosmetic an audience (otherwise placement animation is seen only by the lone hider) | MED | Fold into the podium window to avoid round inflation. Cap ~3s. |
| HUNT-05 | Proximity audio/haptic cue near a spoon (global setting, equal for all) | Helps mobile players with a small FOV; improves parity | MED | Must be identical for everyone and not purchasable. |
| HUNT-06 | Carried-spoon skin visible to others (specified) | Free exposure for seeker-side spoon skins | LOW | |
| LIFE-07 | Reconnect-into-match: restore roster slot, score and hider-turn status if the same UserId rejoins the same server | Mobile disconnects are routine; a 10-round match is long | MED-HIGH | Server-memory keyed by UserId is cheap; rejoining the same server is the hard part (friend-join or saved JobId teleport). Verify TeleportService options. |
| LOB-05 | Bot fill for card seats and default-spot hiding when lobby has <3 humans (clearly labeled, excluded from stats) | New game with no player base: empty lobbies kill retention on day one | HIGH | Card bots are tractable; hunt bots (pathfinding) are costly. Decide at lobby phase. Strongly debatable. |
| SOC-04 | Quick-chat / reaction wheel | Works for under-13 and age-check-less players; cheap social layer | LOW-MED | |
| SOC-05 | In-lobby global leaderboards (all-time wins, weekly points, fastest parkour) | Cheap social proof; standard physical boards in Roblox lobbies | MED | OrderedDataStore. Use match wins and per-round averages, not raw totals, so mid-round joiners and leavers do not skew rankings. |
| PROG-04 | Daily login reward with streak | Common retention hook in top Roblox games | LOW-MED | Reward = coins or cosmetic fragments only; never score. |
| PROG-05 | Badges (welcome, first win, hide a spoon unfound all round, 4-of-a-kind in under N seconds) | Free discovery and engagement surface on Roblox | LOW | Badge creation may carry a Robux fee after a daily free allotment; verify. |
| PROG-06 | Daily/weekly quests | Gives non-winners a reason to return | MED | |
| SHOP-06 | Themed sets (spoon + deck + podium + hider effect + character hat in one purchase) | The six cosmetic types map cleanly to one theme, and the bundle framing is natural | MED | Primary merchandising unit. |
| SHOP-07 | Limited/rotating stock | Drives return visits | MED-HIGH | Needs a content pipeline. Use sparingly; avoid countdown dark patterns aimed at kids. |
| SHOP-08 | Gifting | Strong social purchase | HIGH | Roblox has no native developer-product gifting; needs a custom flow and abuse controls. Defer. |
| SHOP-09 | Premium member perk (cosmetic only) | Roblox convention; aligns with engagement-based payouts | LOW | |
| PROG-07 | Redeemable codes | Ubiquitous in Roblox (MM2 codes pages appear in search results); marketing hook | LOW | |
| UX-06 | Gamepad navigation support | Console is a large Roblox audience | MED | Not required by PROJECT.md. Cheap if UI is built with GuiService selection from the start. |
| MAP-04 | Seasonal map skins (reskinned, not rebalanced) | Long-term freshness | MED | v2. |

### Anti-Features (Commonly Requested, Often Problematic)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Score multipliers, point boosts, "double points" passes | Highest-converting monetization in many Roblox games | Sells leaderboard position; hard rule in PROJECT.md | Cosmetics only; "Premium" perks purely visual. |
| Skins that change a spoon's silhouette, size, brightness or colour contrast, or glint colour/size | Skins and "glint colours" are sold as hider effects | **Camouflage griefing and pay-to-hide**: a dull or ground-coloured skin is harder to find; a flashy one is easier. This crosses the no-findability rule even though it looks cosmetic | Enforce a skin template: identical bounding box, scale, and luminance/contrast budget; glint is a fixed, non-cosmetic world effect. Hider-effect "glint colours" must be post-find or non-world effects. |
| Hider-only paid advantages (extra time, extra hiding zones, decoys) | Hider is the monetizable role | Pay-to-hide | Hider cosmetics only. Decoys exist only as map content (maze). |
| Random crates / mystery boxes / loot boxes | MM2-style revenue driver | Paid Random Items policy requires published odds, probability-modifier disclosure and regional gating; also the strongest regulatory and child-safety target | Direct-purchase themed sets; earnable cosmetics. |
| Player-to-player trading | MM2 has it and it creates a market | Scam surface; Paid Random Items policy ties trading eligibility to random outcomes; requires moderation | No trading in v1. Gifting later at most. |
| Per-round map vote or hider-selection vote | Feels democratic | Inflates round length on a 10-round match | Random no-repeat map; fixed rotation hider queue; optional single vote at match start only. |
| Player-initiated "skip round" or vote-kick | Fixes AFK and bad hiders | Abuse vector and delay; hard caps and auto-fill already cover it | Server AFK handling (LIFE-04), hard caps. |
| Long tutorials, forced onboarding, ad breaks between rounds | Teaches rules | Inflates round length; players quit before round 1 | Contextual prompts (UX-01). |
| Custom text chat, custom voice | Perceived control | Moderation liability; chat gated by age checks already | Roblox-native chat only. |
| Hider chat or voice to seekers during a round | Social feel | Collusion: a friend as hider tells a friend where spoons are | Mute hider (and finished players) toward active players until round end. |
| Body-blocking physics and player collisions | Realistic | Trapping in doorways, fling exploits | Collision groups off. |
| Elimination ladder or "lives" | Classic party structure | Rejected in PROJECT.md; sits players out | Points across fixed rounds. |
| Mid-match cosmetic swap | Impulse purchase | Rejected; changes deck or spoon visuals mid-round | Lobby only. |
| Real-money-purchased soft currency used for random outcomes | Common F2P loop | Falls under indirect Paid Random Items rules | If a soft currency exists, keep outcomes non-random. |
| Party/squad queue system | Seems standard | Server-per-match model means Roblox's native friend-join is the party system; custom queues need a lobby place plus teleports | Rely on native join. Revisit only if moving to a hub-and-spokes architecture. |
| Pre-scripted-only hiding spots | Easier validation | Rejected in PROJECT.md | Free placement with rails; pool as fallback only. |

## Feature Dependencies

```
LOB-01 (lobby/intermission) ──requires──> LIFE-03 (leaver handling / abort <3)
                                  └──requires──> PROG-01 (persistence, for equip and rewards)

CARD-01 (authoritative engine) ──requires──> CARD-03 (prediction/reconcile)
        └──enables──> LIFE-04 (AFK auto-pass reuses chain-close path)
        └──enables──> CARD-05 (four-of-a-kind moment) ──enables──> HUNT-01 (hunt start)

HIDE-01 (placement rails) ──requires──> MAP-02 (authoring tags + validation)
        └──requires──> INTEG-02 (spoon data hidden from clients)
HIDE-02 (auto-fill) ──requires──> MAP-02 (>=16 default spots/map)

SCORE-01 (breakdown) ──requires──> INTEG-01 (server scoring)
SCORE-02 (podium) ──requires──> SHOP-03 (equipped cosmetics) ──requires──> PROG-01 (persistence)
SHOP-02 (preview) ──requires──> SHOP-03 (inventory)
SHOP-04 (receipts) ──requires──> PROG-01
SHOP-06 (themed sets) ──requires──> SHOP-01..03 (all six cosmetic types working)
SOC-05 (global leaderboards) ──requires──> PROG-03 (stats) + LIFE-03 (partial-match rules)
LIFE-07 (reconnect) ──requires──> LIFE-01 (roster snapshot) + PROG-01
CARD-06 (dealer reveal) ──enhances──> SHOP deck skins
HIDE-05 (reveal) ──enhances──> hider effects

Skin template rule (anti-feature) ──constrains──> SHOP spoon skins + hider effects
LIFE-02 (mid-round joiner) ──conflicts──> spoon-count rule (N-2) unless joiner waits for next round
LOB-05 (bots) ──conflicts──> SOC-05 leaderboards unless bots are excluded from stats
```

### Dependency Notes

- **LIFE-04 (AFK auto-pass) depends on the card engine's chain-close path:** removing an AFK player is the same operation as a four-of-a-kind exit. Design that path once, generically.
- **HIDE-01 depends on MAP-02:** the reachability and visibility validators need per-map tagging; build the tooling before authoring all 5 maps.
- **INTEG-02 shapes the whole hunt:** if spoon models are always replicated, ESP exploits trivialise the game. Decide the replication model before building spoon pickup or glint.
- **SHOP-06 requires the full cosmetic pipeline:** do not plan bundles until single-item purchase, preview and equip work.
- **Skin template rule constrains art production:** it must be established before any spoon skin or hider effect is created.
- **LIFE-02 conflicts with N-2:** a joiner entering the hunt directly competes for spoons sized for the roster at round start.

## Interactions With This Project's Specific Design

- **Match length:** worst case a round is 90s hide + 5:00 + ~10s podium = 6:40; 10 rounds is up to about 67 minutes. Typical rounds end early (all spoons found), but sessions will still often exceed 30 minutes. Implications: drop-in/drop-out and leaver handling are table stakes, not polish; nothing may add per-round time (votes, loading screens, tutorials). Avoid a per-round map teleport with load screens; keep all five maps in one place.
- **Hider-rotation fairness vs leavers:** a departing hider-in-waiting silently shortens or voids the "everyone hides once" promise. Rule needed: skipped turn means auto-filled round, no hider points.
- **Spoon count when a seeker drops mid-round:** if a seeker leaves before finding a spoon, "exactly one empty-handed" no longer holds. Decide whether to retract a spoon.
- **Dealer in round 1:** no previous find order exists. Needs a rule (random).
- **Hider as hider-then-seeker:** where the hider sits next round must be defined.
- **Podium:** top 3 of the round versus cumulative is unspecified. A leaver in the top 3 must be handled.
- **Hider effects have no audience** under the current spec (the hider is alone). HIDE-05 or equal fixes this; otherwise this SKU will under-sell.
- **Deck skins reach only the dealer's table:** weak exposure unless CARD-06 is built.
- **Parity of the hunt:** PC players with mouse-look sweep faster than thumb-camera mobile players. Glint should be omni-directional proximity (not view-cone only) and pickup radius generous; test findability by platform.
- **Last seeker finds nothing:** this is a design-intended loss, so PROG-02 participation rewards matter for retention.
- **Cold start:** a brand new game with a 3-player minimum will frequently have empty servers; LOB-03 and LOB-05 carry real retention weight at launch.

## MVP Definition

### Launch With (v1)

- [ ] LOB-01, LOB-02, LOB-03, LOB-04 — playable loop and equip
- [ ] LIFE-01..06 — roster, joiners, leavers, AFK, match end, caps
- [ ] CARD-01..05 — authoritative engine, neighbour labels, prediction, selection safety, four-of-a-kind moment
- [ ] HIDE-01..03 — placement mode, auto-fill, parkour waiting room
- [ ] HUNT-01..04 — glint/pickup, remaining HUD, spectator, collisions off
- [ ] SCORE-01, SCORE-02 — breakdown scoreboard, podium
- [ ] INTEG-01..03 — server authority, anti-ESP, remote hygiene
- [ ] UX-01..05 — tutorial prompts, mobile layout, input prompts, accessible cards, performance
- [ ] SOC-01..03 — leaderstats, native chat, friend join
- [ ] PROG-01..03 — persistence, participation reward, stats
- [ ] SHOP-01..05 — shop, preview, inventory, receipts, earnable path
- [ ] MAP-01..03 — five maps, authoring tools, rotation

### Add After Validation (v1.x)

- [ ] CARD-06, HIDE-04, HIDE-05 — visibility boosters for deck and hider-effect SKUs (trigger: cosmetic conversion data)
- [ ] SOC-05, PROG-04, PROG-05, PROG-07 — leaderboards, daily reward, badges, codes (trigger: day-1/day-7 retention)
- [ ] SHOP-06 — themed sets (trigger: at least 3 items per type exist)
- [ ] LIFE-07 — reconnect-into-match (trigger: leaver rate above threshold)
- [ ] HUNT-05 — proximity audio/haptic (trigger: mobile vs PC find-time gap)
- [ ] LOB-05 — bot fill (trigger: median lobby wait above target)

### Future Consideration (v2+)

- [ ] SHOP-07, SHOP-08, SHOP-09 — rotating stock, gifting, Premium perk
- [ ] PROG-06, battle pass or seasons, MAP-04 — need a content pipeline
- [ ] UX-06 — gamepad (unless console demand shows up early)
- [ ] SOC-04 — quick-chat

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| CARD-01/03 authoritative engine and prediction | HIGH | HIGH | P1 |
| HIDE-01 placement mode and validators | HIGH | HIGH | P1 |
| INTEG-02 spoon replication model | HIGH | HIGH | P1 |
| LIFE-04 AFK auto-pass | HIGH | MED-HIGH | P1 |
| LIFE-02/03 joiners and leavers | HIGH | MED | P1 |
| UX-02 mobile layout | HIGH | MED-HIGH | P1 |
| SCORE-01 breakdown scoreboard | HIGH | MED | P1 |
| SHOP-01..04 shop, preview, inventory, receipts | HIGH | MED | P1 |
| CARD-05 four-of-a-kind moment | HIGH | MED | P1 |
| LOB-03 lobby activity | MED | LOW | P1 |
| HUNT-03 spectator | MED | MED | P1 |
| PROG-02 participation reward | MED | LOW | P1 |
| CARD-06 dealer reveal | MED | LOW-MED | P2 |
| HIDE-05 end-of-round reveal | MED | MED | P2 |
| SOC-05 leaderboards | MED | MED | P2 |
| PROG-04 daily reward | MED | LOW-MED | P2 |
| PROG-05 badges | MED | LOW | P2 |
| LIFE-07 reconnect | MED | MED-HIGH | P2 |
| HUNT-05 audio/haptic cue | MED | MED | P2 |
| LOB-05 bot fill | MED-HIGH (cold start) | HIGH | P2 (decision point) |
| SHOP-06 themed sets | MED | MED | P2 |
| SHOP-07 rotating stock | MED | MED-HIGH | P3 |
| SHOP-08 gifting | MED | HIGH | P3 |
| UX-06 gamepad | MED | MED | P3 |
| PROG-06 quests | MED | MED | P3 |

**Priority key:** P1 must have for launch; P2 should have, add when possible; P3 future consideration.

## Competitor Feature Analysis

Confidence: MEDIUM-LOW (training knowledge plus a few search excerpts; not verified feature by feature).

| Feature | Murder Mystery 2 | Flee the Facility | Natural Disaster Survival / Hide and Seek style games | Our Approach |
|---------|------------------|-------------------|------------------------------------------------------|--------------|
| Lobby/intermission | In-server lobby, round starts after intermission | Same | Same | Same, with min 3 and parkour waiting room |
| Role rotation | Random role each round | Beast chosen per round | Seeker chosen per round | Deterministic: every player hides once, queue visible |
| Cosmetic shop | Knives, guns, pets in rarity tiers (search excerpt, MEDIUM) | Cosmetic hammers/skins (LOW) | Gear/gamepass-based (LOW) | Six cosmetic types; themed sets; no rarity tiers or randomness |
| Randomized rewards | Mystery Boxes (search excerpt, MEDIUM) | Unverified | Unverified | **None** (policy and trust) |
| Trading | Yes (search excerpt, MEDIUM) | Unverified | No | None in v1 |
| Codes | Yes, code pages are common (search result) | Unverified | Varies | Later (P3) |
| Events/seasonal | Halloween/Christmas themed maps and skins (search excerpt, MEDIUM) | Unverified | Unverified | v2 |
| In-round currency | Coin pickups during rounds | Credits for play (LOW) | Coins by survival (LOW) | Coins from round participation and performance, cosmetics only |
| Pay-to-win | Cosmetic-forward; gameplay edge is limited | Varies | Gamepass gear can help | Hard no |
| Spectating | Dead players spectate/ghost | Eliminated spectate | Eliminated spectate | Finished and empty-handed players, plus hider |

## Open Questions for Requirements Definition

1. **Mid-round joiner mechanics:** may a joiner enter the card table or hunt mid-round, or wait for the next round start? Recommendation: spectate until next round, then play as seeker (preserves N-2 fairness). Needs owner decision.
2. **Spoon retraction on seeker departure:** retract one spoon to preserve "one empty-handed"? Affects hider scoring.
3. **Round-1 dealer and hider seating next round:** define defaults.
4. **Podium contents:** per-round top 3 or cumulative? How to treat leavers.
5. **Soft currency:** is there an earn-only coin economy? Recommended yes (SHOP-05, PROG-02).
6. **VIP lobby implementation:** Roblox native Private Server versus gamepass-gated separate lobby. Native is lower cost; verify docs.
7. **Cold-start strategy:** are bots acceptable (LOB-05), and for which roles?
8. **Equip window:** is a waiting-room equip window acceptable, or lobby-only? Recommendation: keep lobby-only per PROJECT.md but accept purchase-to-equip friction.
9. **Hider effects:** how to guarantee they stay non-findability-affecting (skin template) and who sees them (HIDE-05).

## Sources

- Roblox newsroom, age checks required to chat (Jan 2026): https://about.roblox.com/newsroom/2026/01/roblox-age-checks-required-to-chat (MEDIUM, via search result)
- Roblox Creator Hub, Paid Random Items policy: https://create.roblox.com/docs/production/monetization/paid-random-items (MEDIUM, search-result excerpt only; page fetch failed)
- Roblox Creator Hub, adaptive design: https://create.roblox.com/docs/en-us/production/publishing/adaptive-design (MEDIUM, search-result excerpt only)
- Roblox ScreenInsets enum reference (third-party mirror): https://robloxapi.github.io/ref/enum/ScreenInsets.html (LOW-MEDIUM)
- Roblox Creator Hub, Add rounds tutorial: https://create.roblox.com/docs/tutorials/curriculums/gameplay-scripting/add-rounds (title only; content not retrieved)
- MM2 overview (marketplace, rarity tiers, mystery boxes, trading): https://rowatcher.com/news/what-is-murder-mystery-2-a-guide-to-roblox-s-legendary-social-deduction-game (LOW-MEDIUM)
- Training-knowledge on MM2, Flee the Facility, Natural Disaster Survival, Hide and Seek Extreme conventions (LOW-MEDIUM)

---
*Feature research for: Roblox round-based party/hunt game (Spoons)*
*Researched: 2026-11-02*
