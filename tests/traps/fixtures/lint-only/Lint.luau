--!strict
local function unusedLocalTrap(): number
	local neverRead = 1
	return 2
end

return unusedLocalTrap
