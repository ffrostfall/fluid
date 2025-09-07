local logging = require("@src/logging")

local function no_yield<I..., O...>(callback: (I...) -> O..., ...: I...): (boolean, O...)
	local co = coroutine.create(callback)
	local output: { any } = { coroutine.resume(co, ...) }
	local ok = table.remove(output, 1)

	if not ok then
		logging.warn(output[1])
		error(`failed to run thread`, 2)
	end

	if coroutine.status(co) ~= "dead" then
		error("thread yielded", 2)
	end

	return unpack(output)
end

return no_yield
