local exception = require("./exception")
local scheduler = require("@src/scheduler")

local reactive_fn_calls = {}

function reactive_fn_calls.no_yield_call<U, T...>(
	func: (T...) -> U,
	err_handler: (unknown) -> exception.Identity,
	yield_handler: (thread) -> exception.Identity,
	...: T...
): (boolean, U)
	local co = coroutine.create(xpcall)
	local ok, value = coroutine.resume(co, func, err_handler, ...)

	if coroutine.status(co) == "suspended" then
		value = yield_handler(co)
		scheduler.cancel(co)
		return false, value
	end

	return ok, value
end

function reactive_fn_calls.call<U, T...>(fn: (T...) -> U, err_handler: (unknown) -> exception.Identity, ...: T...): (boolean, U)
	return xpcall(fn, err_handler, ...)
end

return reactive_fn_calls
