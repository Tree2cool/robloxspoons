--!strict
-- The one type vocabulary for the card engine. Every other engine module imports these names, so no
-- module invents a second card, seat or event shape. Types plus seven constants; no behaviour.
--
-- 1. PURE ZONE. No Roblox API, no clock, no yields (CLAUDE.md rules 2, 5 and 6). `check-guards` R3
--    forbids the standard-Luau constructs that could suspend a mutation or read a wall clock here,
--    and `selene.pure.toml` plus `luau-lsp --platform standard` forbid Roblox values and types. Any
--    time value the engine sees is a parameter, in integer deciseconds.
-- 2. CARD IDS ARE DECK POSITIONS. `State.rankOf` IS the shuffled deck permutation, so the
--    id -> rank mapping is re-randomised every round and a leaked card id carries no rank
--    information (CLAUDE.md rule 3, research Pitfall 6). Never allocate ids in deck-build order.
-- 3. MAX_JOKERS = 2 IS LOAD-BEARING, not decorative. Research 3.3 proves that at `j <= 2` a
--    five-card hand can satisfy at most one rank, so completion needs no tiebreak and the
--    all-joker set is unreachable. A pool that wants `j >= 3` reopens both of those proofs.
-- 4. `seatCount` IS SEATED SEEKERS = (players in round) - 1. The hider does not play cards
--    (02-CONTEXT.md amendment A3), so `ranks = seatCount + k`.
-- 5. THERE IS NO `locked` FLAG ON A SEAT, and there must never be one. "The pile locks at 5" is
--    exactly the rule *draw only when #hand == HAND_SIZE*. A boolean would be a second source of
--    truth that can disagree with the hand it describes.
-- 6. `valve` IS TRAJECTORY BOOKKEEPING, not part of the table. `Invariants.hash` must not hash it
--    and `Invariants.check` must not inspect it. Hashing it would make every state unique, the
--    valve could never fire, and amendment A7's mechanism would be silently vacuous.
export type CardId = number
export type Rank = number -- 1..config.ranks for naturals; JOKER_RANK (0) for a joker
export type SeatId = number
export type PlayerId = number
export type JokerMode = "Wild" | "Blocker"
export type RemoveCause = "Completed" | "Disconnected" | "Benched"

export type EngineConfig = {
	ranks: number,
	jokers: number,
	jokerMode: JokerMode,
	-- The anti-livelock valve (02-CONTEXT.md amendment A7), implemented in plan 02-13 and wired by
	-- plan 02-07. A VALUE, never a module constant, for the same reason `jokerMode` is one: the
	-- sweep must run both positions in one process, and the valve's own mutation proof is a run
	-- with it off. The shipped configuration sets it true and plan 02-11 asserts that.
	antiLivelockValve: boolean,
}

-- The valve's whole state. Carried on State so a round is reproducible from its seed alone.
-- NOT hashed by Invariants.hash and NOT inspected by Invariants.check: it is bookkeeping about the
-- trajectory, not part of the table. If it were hashed, no state could ever repeat and the valve
-- could never fire.
export type ValveState = {
	rng: any, -- an Rng, derived in Engine.newRound so valve draws never perturb the deal
	actionsSinceProgress: number, -- reset by a completion or a removal
	armed: boolean, -- true once actionsSinceProgress passes VALVE_ARM_ACTIONS_PER_SEAT * liveCount
	seen: { [string]: true }, -- hashes observed since the last completion, removal or firing
	seenCount: number,
	firings: number, -- the first-class metric: a pool whose valve fires often is a bad pool
	seenResets: number, -- times VALVE_SEEN_CAP forced a restart of the window
	-- Exactly one valve entry point is called per SUCCESSFUL apply and none on a rejection, so plan
	-- 02-08's fuzz suite asserts observations == acceptedActions. Without it the valve could be
	-- skipped inside a conditional and read green, which is the defect class Phase 1 found twice.
	observations: number,
}

export type Seat = {
	id: SeatId,
	playerId: PlayerId,
	live: boolean,
	hand: { CardId },
	inbox: { CardId }, -- FIFO: index 1 is the front (next draw), #inbox is the tail
	next: SeatId,
	prev: SeatId,
}

export type Counters = {
	rankInPlay: { number }, -- rankInPlay[r] = copies of natural rank r in hands+inboxes
	jokersInPlay: number,
	cnt: { number }, -- cnt[a + 1] = how many natural ranks have exactly a copies in play, a in 0..4
	completions: number,
	churnRemovals: number, -- removals with cause ~= "Completed"; each adds 4 to circulation
}

export type State = {
	config: EngineConfig,
	seatCount: number, -- m0: seats dealt at round start = (players in round) - 1
	totalCards: number, -- T = 4 * ranks + jokers
	rankOf: { Rank }, -- rankOf[cardId]; the shuffled deck permutation, re-randomised per round
	seats: { Seat },
	liveCount: number,
	head: SeatId, -- any live seat, used as the ring entry point; 0 when the ring is empty
	retired: { CardId }, -- cards retired by completions
	terminal: { CardId }, -- cards held when the ring emptied (research 7.3); never destroyed
	counters: Counters,
	valve: ValveState,
}

export type Intent =
	{ kind: "Draw", seat: SeatId }
	| { kind: "Pass", seat: SeatId, cardId: CardId }
	| { kind: "Remove", seat: SeatId, cause: RemoveCause }

export type Reject =
	"UnknownSeat"
	| "SeatNotLive"
	| "UnknownCard"
	| "NotYourCard"
	| "HandNotFour"
	| "HandNotFive"
	| "InboxEmpty"

-- The locked violation vocabulary of `Invariants.check`, in the LOCKED ORDER it reports them.
-- Declared here, in the type system, so the names cannot drift and a mistyped violation is a build
-- error rather than a test that silently stops matching. `circulation` precedes `unsatisfiable`
-- deliberately: a card that vanished is a conservation bug and must be reported as one, not as a
-- stall statistic. Never reorder this to make an assertion pass.
export type Violation =
	"hand-size"
	| "ring-links"
	| "liveness"
	| "circulation"
	| "partition-count"
	| "partition-identity"
	| "counters-rankInPlay"
	| "counters-histogram"
	| "unsatisfiable"

export type Event =
	{ kind: "Drew", seat: SeatId, cardId: CardId }
	| { kind: "Passed", seat: SeatId, to: SeatId, cardId: CardId }
	| { kind: "Completed", seat: SeatId, rank: Rank, retired: { CardId }, fifth: CardId }
	| { kind: "SeatRemoved", seat: SeatId, cause: RemoveCause, routedTo: SeatId?, cards: number }
	-- The valve fired: the engine forced this seat to pass this card. `lap` is
	-- `actionsSinceProgress` at the firing, so the metric is in the event stream and not only in a
	-- counter. It carries NO hash: the hash encodes every hand, and an event may cross the network
	-- boundary in Phase 4 (CLAUDE.md rule 3).
	| { kind: "ValveForcedPass", seat: SeatId, cardId: CardId, to: SeatId, lap: number }

export type ApplyResult = { ok: boolean, events: { Event }, reject: Reject? }

return {
	JOKER_RANK = 0,
	HAND_SIZE = 4, -- a resting hand; the pile "locks at 5" is just: draw only when #hand == HAND_SIZE
	MAX_HAND = 5,
	MAX_JOKERS = 2, -- research 3.3: at j <= 2 the all-joker set is unreachable and the completing rank is unique
	MAX_DEAL_ATTEMPTS = 64, -- research 10: ~50 standard deviations above the measured max of 4
	-- The valve starts hashing only after a table has gone this many actions per live seat with no
	-- completion and no removal (48 * liveCount = 432 actions at 9 seats, roughly 22s of play).
	-- It is a COST gate and nothing else: hashing every draw costs ~2us per action, which is fine
	-- for a sweep but would blow the CI subset's wall-time budget (plan 02-09 derives it from
	-- measured throughput; do not quote a number here), while a healthy 9-seat round is
	-- ~250 actions and so never arms. The only behavioural effect is that a cycle is detected at
	-- most one lap later than it could have been, because a cycle repeats forever until broken.
	VALVE_ARM_ACTIONS_PER_SEAT = 48,
	-- Bound on the valve's seen-set so a pathological round cannot grow memory without limit.
	-- A cycle shorter than this is still caught; passing it clears the window and counts a reset.
	VALVE_SEEN_CAP = 4096,
}
