local exception = require("./exception")
local scheduler = require("../scheduler")

local function no_yield_call<U..., T...>(
	func: (T...) -> U...,
	err_handler: (unknown) -> exception.Identity,
	yield_handler: (thread) -> exception.Identity,
	...: T...
): (boolean, U...)
	local co = coroutine.create(xpcall)
	local _, ok, a, b, c, d, e = coroutine.resume(co, func, err_handler, ...)

	if coroutine.status(co) == "suspended" then
		local value = yield_handler(co)
		scheduler.cancel(co)
		return false, value :: any
	end

	return ok, a, b, c, d, e :: any
end

return no_yield_call
