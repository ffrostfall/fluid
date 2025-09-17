local fluid_yield_error = "attempted to yield in a callback"

export type Error = {
	trace: string,
	message: string,
	yielded: boolean,
}

-- errors "thread is not yieldable" or "attempt to yield across metamethod/C-call boundary"
-- TODO: Luau type state issue
local function no_yield<T..., R...>(callback: (T...) -> R..., ...: T...): R...
	local packed = table.pack(...)
	-- stylua: ignore
	for _ in function(): nil
		packed = table.pack(callback(table.unpack(packed, 1, packed.n)))  
		return nil 
	end do  
		break
	end

	return table.unpack(packed, 1, packed.n)
end

--[[
	formats yielded errors into "attempted to yield in a callback"
	
	@example
	```lua
	local function fn()
		coroutine.yield()
	end

	local ok, error = xpcall(no_yield.check, no_yield.error_handler, fn)

	assert(ok == false)

	print(error.message) --> "attempted to yield in a callback"
	```
]]
local function error_handler(err: string): Error
	local message = string.gsub(tostring(err), "^.+:%d+:%s*", "")
	local trace = debug.traceback(nil, 2)

	local yielded = string.match(message, "attempt to yield") ~= nil
		or string.match(message, "thread is not yieldable") ~= nil

	if yielded then
		message = fluid_yield_error
	end

	return {
		trace = trace,
		message = message,
		yielded = yielded,
	}
end

return {
	error_handler = error_handler,
	check = no_yield,
}
