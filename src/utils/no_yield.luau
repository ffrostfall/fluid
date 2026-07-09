export type Error = {
	trace: string,
	message: string,
	yielded: boolean,
}

-- errors "thread is not yieldable" or "attempt to yield across metamethod/C-call boundary"
-- TODO: Luau type state issue

local function no_yield<I..., O...>(callback: (I...) -> O..., ...: I...): (boolean, O...)
	local co = coroutine.create(callback)
	local output: { any } = { coroutine.resume(co, ...) }
	local ok = table.remove(output, 1)

	if not ok then
		error(`failed to run thread: {output[1]}\ntrace: {debug.traceback(co)}`, 2)
	end

	if coroutine.status(co) ~= "dead" then
		coroutine.close(co)
		error(`thread yielded at {debug.traceback(co)}`, 2)
	end

	return unpack(output)
end

return no_yield
