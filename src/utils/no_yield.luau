local result = require("../result")

local function no_yield<O, I...>(callback: (I...) -> O, ...): result.Identity<O, unknown>
	local co = coroutine.create(callback)
	local ok, output = coroutine.resume(co, ...)

	if not ok then
		return result.fail(
				"failed to resume a thread",
				debug.traceback(nil, 2)
			) :: result.Identity<O, unknown>
	end

	if coroutine.status(co) ~= "dead" then
		return result.fail(
				"thread yielded",
				debug.traceback(nil, 2)
			) :: result.Identity<O, unknown>
	end

	return result.ok(output)
end

return no_yield
