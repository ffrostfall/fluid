-- errors "thread is not yieldable" or "attempt to yield across metamethod/C-call boundary"
local task = task or require("@lute/task")

local function no_yield<I..., O...>(callback: (I...) -> O..., ...: I...): O...
	local a, b
	local thread = task.spawn(function(...)
		a, b = callback(...)
	end, ...)

	if coroutine.status(thread) == "suspended" then
		error(thread)
	end

	return a, b
end

return no_yield
