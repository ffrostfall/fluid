export type Error = {
	trace: string,
	message: string,
	yielded: boolean,
}

-- errors "thread is not yieldable" or "attempt to yield across metamethod/C-call boundary"
-- TODO: Luau type state issue

local function no_yield<I..., O...>(callback: (I...) -> O..., ...: I...): (thread, O...)
	local co = coroutine.create(callback)
	local output: { any } = table.pack(coroutine.resume(co, ...))
	local ok = table.remove(output, 1)

	if not ok then
		local trace = debug.traceback(co)
		error(`failed to run thread: {output[1]}\ntrace:\n{trace}`, 1)
	end

	if coroutine.status(co) ~= "dead" then
		local trace = debug.traceback(co)
		coroutine.close(co)
		error(`failed to run thread: yielded in callback\ntrace:\n{trace}`, 1)
	end

	return table.unpack(output)
end

return no_yield
