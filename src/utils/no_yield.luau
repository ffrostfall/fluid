local exception = require("./exception")
-- errors "thread is not yieldable" or "attempt to yield across metamethod/C-call boundary"
local task = task or require("@lute/task")

local symbol = {}

local function no_yield<I..., O...>(callback: (I...) -> O..., ...: I...): O...
	local a, b = symbol, nil
	local thread = task.spawn(function(...)
		a, b = callback(...)
	end, ...)

	if coroutine.status(thread) == "suspended" then -- yielded case
		error(exception.ephemeral_thread_unwrap(thread, true))
	elseif a == symbol then -- error case
		error(exception.ephemeral_thread_unwrap(thread, false))
	end

	return a, b
end

return no_yield
