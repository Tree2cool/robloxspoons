--!strict
-- Injected scheduler matching the RoundLifecycle dependency contract (CLAUDE.md rule 5: the server is the
-- only clock, integer deciseconds). Time moves only through advance().
export type Scheduler = {
	nowDeci: () -> number,
	delay: (seconds: number, fn: () -> ()) -> () -> (),
}
export type FakeScheduler = Scheduler & {
	advance: (seconds: number) -> (),
	pending: () -> number,
}
export type Options = { cancelIsNoop: boolean? }

type Entry = { dueDeci: number, seq: number, fn: () -> (), cancelled: boolean }

local function new(options: Options?): FakeScheduler
	local cancelIsNoop = options ~= nil and options.cancelIsNoop == true
	local nowDeci = 0
	local nextSeq = 0
	local entries: { Entry } = {}

	local function remove(entry: Entry)
		local i = table.find(entries, entry)
		if i ~= nil then
			table.remove(entries, i)
		end
	end

	local function delay(seconds: number, fn: () -> ()): () -> ()
		nextSeq += 1
		local entry: Entry = {
			dueDeci = nowDeci + math.floor(seconds * 10),
			seq = nextSeq,
			fn = fn,
			cancelled = false,
		}
		table.insert(entries, entry)
		return function()
			if cancelIsNoop then
				-- Models a task.cancel that fails to stop the callback, so the round-ID token guard
				-- can be proven independently of the platform cancel.
				return
			end
			entry.cancelled = true
			remove(entry)
		end
	end

	-- The earliest non-cancelled entry due at or before limitDeci; ties break by registration order.
	local function nextDue(limitDeci: number): Entry?
		local best: Entry? = nil
		for _, e in entries do
			if not e.cancelled and e.dueDeci <= limitDeci then
				if best == nil or e.dueDeci < best.dueDeci or (e.dueDeci == best.dueDeci and e.seq < best.seq) then
					best = e
				end
			end
		end
		return best
	end

	local function advance(seconds: number)
		local target = nowDeci + math.floor(seconds * 10)
		while true do
			local e = nextDue(target)
			if e == nil then
				break
			end
			remove(e) -- removed before invoking, so a callback can never re-fire itself
			if e.dueDeci > nowDeci then
				nowDeci = e.dueDeci -- a callback observes the time it was due, as a real scheduler would
			end
			e.fn()
		end
		nowDeci = target
	end

	local function pending(): number
		local n = 0
		for _, e in entries do
			if not e.cancelled then
				n += 1
			end
		end
		return n
	end

	return {
		nowDeci = function()
			return nowDeci
		end,
		delay = delay,
		advance = advance,
		pending = pending,
	}
end

return { new = new }
