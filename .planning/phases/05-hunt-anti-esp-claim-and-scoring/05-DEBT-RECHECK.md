# Phase 5 — Verification Debt re-check

**Date:** 2026-11-10. **Method:** `scripts/dev/roblox-doc.sh` against `create.roblox.com`, all
pages `last_updated: 2026-11-10`. See `.planning/research/DOC-ACCESS.md` — this is the first phase
able to close rows rather than re-record them as unreachable.

`CLAUDE.md` requires each phase's research step to begin here and to record what was confirmed or
changed. Four rows name Phase 5. **Three are now settled and one changed a decision's reasoning.**

| Row | Was | Now | Effect on this phase |
|-----|-----|-----|----------------------|
| **V-18** `RespectCanCollide` | "defaults to `false`" — confidence HIGH | **BEHAVIOUR CONFIRMED, DEFAULT NOT DOCUMENTED — downgraded to UNVERIFIED** | **D-03 unchanged, reason improved.** See below |
| **V-21** `PhysicsService` collision groups | unverified, from training | **CONFIRMED** | D-10 stands, with two new constraints |
| **V-22** client-created `ProximityPrompt` | unverified; STACK had assumed a *server* prompt, which PROJECT.md forbids | **CONFIRMED USABLE, with a consequence D-05 must absorb** | D-05 stands; the claim path is now pinned |
| **V-30** `GetServerTimeNow` | unverified, from training | **CONFIRMED** | The two-clock rule stands, unchanged |

---

## V-18 — the row this phase was most exposed to

The claim about to be written into this phase's context as fact was *"`RespectCanCollide` defaults
to `false`, the opposite of Phase 3's sight model"*. **The documented behaviour is confirmed** —
when `true`, the raycast uses an intersected part's `CanCollide` in favour of its `CanQuery` when
deciding whether the part lands in the `RaycastResult`. **The default is stated nowhere on the
page**, and the constructor table lists only `instances`.

**This does not weaken D-03, it improves its justification.** The reason to set the flag explicitly
changes from *"the default is wrong"* to **"the default is undocumented, so it cannot be relied on,
and it can change under us without a deploy"**. That argument is stronger and survives a future
default change. The previously recorded HIGH confidence in "defaults to false" is **downgraded to
UNVERIFIED**: wherever it came from, it was not this page.

## V-21 — `PhysicsService`, and two constraints D-10 did not know about

Confirmed: `RegisterCollisionGroup(name)` and `CollisionGroupSetCollidable(name1, name2,
collidable)` are the API, and `GetMaxCollisionGroups()` exists. Two facts that bind D-10:

1. **Registering collision groups is limited to server-side `Script`s.** D-10 already puts the call
   at round start on the server, so it holds — but it means a client cannot undo it either, which
   is worth knowing when HUNT-06 is checked against a cheat client.
2. **The engine supports a maximum of 32 collision groups.** Not a constraint at one group, but it
   is a budget, and Phases 6 and 7 will want their own. Spend one, not one per phase.

## V-22 — the client prompt works, and the claim path is now pinned

Confirmed that `ProximityPrompt` is usable from a `LocalScript`: `PromptShown`, `PromptHidden`,
`IndicatorShown` and `IndicatorHidden` are all documented as firing **client-side for
`LocalScript`s**, with `Security: None`. So **D-05 stands** — the affordance can be created by the
owning client on its own local visual, and no server instance carrying a spoon position is needed.

**The consequence D-05 must absorb:** a prompt that exists only on the client has a `Triggered`
event that exists only on the client. The documented server pattern
(`prompt.Triggered:Connect(function(player) ... end)`) **is not available to us**, because there is
no server-side prompt to connect to.

So the claim path is: **client prompt fires -> the client sends a `Claim` INTENT through the
existing typed gateway -> the server validates position, range and plausibility and decides.** The
prompt is an affordance and never an authority, which is what D-05 already said; this pins the
mechanism and tells the planner not to go looking for a server `Triggered` that cannot exist. It
also means `Claim` is an ordinary rate-limited manifest kind like `Draw` and `Pass`, not a special
case.

## V-30 — the two-clock rule holds

Confirmed: `Workspace:GetServerTimeNow()` returns a **double Unix timestamp**, described as *"the
client's best approximation of the current time on the server"*, for synchronised experiences
regardless of timezone or local clock.

**"Best approximation" is exactly why it must not be the scoring clock.** The rule Phase 4
established stands unchanged and this phase inherits it: `os.clock()` floored to integer
deciseconds is the scoring clock; `GetServerTimeNow()` is published outward for client countdowns
only and is never fed back in. SCORE-02 scores from **server arrival time**, and an approximation
of a shared clock is not an arrival time.

## Not re-checked

**V-23** (server-known `HumanoidRootPart` position lags client-owned characters; a few studs of
slack suffices) and **V-34** (latency figures, glint and pickup radii, rate-limit numbers). Both
are *measurement* rows rather than API-semantics rows: no documentation page can settle what the
lag actually is on real connections. They belong to a playtest and to Phase 8's tuning, which is
where Open Question 10 already puts them. D-07's `walkSpeed * rtt` slack term is explicitly a
first pass and is labelled as such.
