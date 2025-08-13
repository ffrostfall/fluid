--!optimize 2
--!native
local task = task or require("@lute/task")

local tspawn = task.spawn
local cyield = coroutine.yield

local freeThread: thread? = nil

local function deletedSignalError()
	error("Cannot fire a deleted signal", 2)
end

local errorTable = {
	fire = deletedSignalError,
	connect = deletedSignalError,
	once = deletedSignalError,
	wait = deletedSignalError,
	disconnectAll = deletedSignalError,
}

local function run<T...>(func: (T...) -> (), ...: T...)
	local ref = freeThread
	freeThread = nil

	func(...)

	freeThread = ref
end

local function yieldLoop()
	while true do
		run(cyield())
	end
end

local signal = {}
signal.__index = signal
type InternalIdentity<T...> = setmetatable<{ (T...) -> () }, typeof(signal)>

--[=[
	@class signal
	
	The main class for this package. It is actually just an array with a metatable! Constructed with:
	```lua
	local signal = require(...)
	
	signal()
	```
]=]
local function constructor<T...>(): InternalIdentity<T...>
	return setmetatable({}, signal)
end

--[=[
	@method connect
	@within signal
	
	Connects a function to the signal. This will be called whenever the signal is fired.
	Connections can be "disconnected" (they won't be called when the signal is fired) by calling the function that they return.
	```lua
	local sig = signal()
	
	-- You can connect a function like this
	sig:connect(function(text)
		print(text)
	end)
	
	-- You can also directly connect the function like this.
	sig:connect(print)
	
	-- Will print twice, because two connections.
	sig:fire("Hello, world!")
	```
	
	You shouldn't connect the same function twice. This is because the function is used as a reference to disconnect when disconnecting later.
	While it *might* work for simple or specialized cases, you may find that it doesn't work as expected in some cases.
	
	Connections will be ran in order of connection.
	
	It's also worth noting that disconnecting is not an optimal operation, as it will shift the array. If you have a lot of connections to a single signal, you should avoid frequent disconnections.
	
	@param callback (T...) -> ()
	@return () -> ()
]=]
function signal.connect<T...>(self: InternalIdentity<T...>, callback: (T...) -> ())
	table.insert(self, callback)

	return function()
		local index = table.find(self, callback)

		if index then
			table.remove(self, index)
		end
	end
end

--[=[
	@method fire
	@within signal

	Firing a signal will run all connections in order, while using thread reusage.
	[You can find more on this optimization here](https://devforum.roblox.com/t/thread-reuse-how-it-works-why-it-works/1999166).
	
	You should note these things about thread reusage:
	- You cannot rely on the thread being different, or the same consistently.
	- The above means that certain "no-yield" implementations might not work correctly in connections.
	- If you have a lot of connections, you should avoid yielding in said connections. Yielding forces a new thread to be spawned, which isn't optimal, but it's still okay.
	
	@param data ...
	@return void
]=]
function signal.fire<T...>(self: InternalIdentity<T...>, ...: T...)
	for i = #(self :: any), 1, -1 do
		if not freeThread then
			freeThread = coroutine.create(yieldLoop)
			tspawn(freeThread :: thread)
		end

		-- Type states don't take into account assigning yet
		tspawn(freeThread :: thread, self[i], ...)
	end
end

--[=[
	@method once
	@within signal
	
	Connects to a signal, and disconnects after the first time it is fired.
	You can still disconnect the connection before it is fired.
	
	@param callback (T...) -> ()
	@return () -> ()
]=]
function signal.once<T...>(self: InternalIdentity<T...>, callback: (T...) -> ())
	local disconnect
	disconnect = self:connect(function(...)
		assert(disconnect ~= nil, "Luau")
		disconnect()

		callback(...)
	end)
end

--[=[
	@method wait
	@within signal
	
	Yields the current thread until the signal is fired, and returns the arguments passed.
	Will raise an error if the thread is resumed before the signal is fired.
	
	@return T...
]=]
function signal.wait<T...>(self: InternalIdentity<T...>): T...
	local running = coroutine.running()

	self:once(function(...)
		assert(
			coroutine.status(running) == "suspended",
			":wait() called, then another thread resumed the waiting thread. Please dont do that :("
		)

		tspawn(running, ...)
	end)

	return cyield()
end

--[=[
	@method disconnectAll
	@within signal
	
	Disconnects all connections to the signal. This is an efficient operation, utilizing `table.clear`.
]=]
function signal.disconnectAll<T...>(self: InternalIdentity<T...>)
	table.clear(self)
end

--[=[
	@method delete
	@within signal
	
	Disconnects all connections to the signal, and renders the signal unusable.
	While this technically isn't required or needed for memory concerns, you might want to use this when you're working with others.
	
	This will prevent and raise an error upon any attempts to use the signal, which is useful for debugging & catching leaks.
]=]
function signal.delete<T...>(self: InternalIdentity<T...>): ()
	self:disconnectAll()

	setmetatable(self, errorTable)
end

export type Identity<T...> = {
	fire: (self: Identity<T...>, T...) -> (),
	connect: (self: Identity<T...>, callback: (T...) -> ()) -> () -> (),
	once: (self: Identity<T...>, callback: (T...) -> ()) -> () -> (),
	wait: (self: Identity<T...>) -> T...,
	disconnectAll: (self: Identity<T...>) -> (),
	delete: (self: Identity<T...>) -> (),
}

return constructor :: <T...>() -> Identity<T...>
