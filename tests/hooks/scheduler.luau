--[[
	hooks wait/delay in fluid
	this allows you to timeskip forward in tests
]]
local fluid = require("@src")
local logging = require("@src/logging")
local task = require("@lune/task")

local scheduler_interface = fluid.__SCHEDULER_INTERFACE
local step_fluid = fluid.provide_scheduler()

local step_tick = 0

local waiting_threads: { [thread]: WaitingThread } = {}
type WaitingThread =
	({ resume: number, start: number } | { resume: number })
	& { [any]: any }
	& { any }

-- scheduler.wait and scheduler.delay is overwritten to allow timeskip
function scheduler_interface.wait(time: number?): number
	waiting_threads[coroutine.running()] =
		{ resume = step_tick + (time or 0), start = step_tick } :: WaitingThread
	return coroutine.yield()
end

function scheduler_interface.delay<T...>(n: number, fn: (T...) -> (), ...: T...): thread
	local thread = coroutine.create(fn)
	local data: { [any]: any } = table.pack(...)
	data.resume = step_tick + n
	data.trace = debug.traceback(nil, 2)

	waiting_threads[thread] = data :: WaitingThread

	return thread
end

local function step_threads(delta_time: number)
	step_tick += delta_time

	local processing = waiting_threads
	waiting_threads = {}

	for thread, data in processing do
		if step_tick >= data.resume and coroutine.status(thread) == "suspended" then
			local ok, err
			if data.start then
				ok, err = coroutine.resume(thread, step_tick - data.start)
			else
				ok, err = coroutine.resume(thread, table.unpack(data, 1, data.n))
			end

			if not ok then
				logging.warn(`[fluid]: {err} origin: {data.trace}`)
			end
		else
			waiting_threads[thread] = data
		end
	end
end

--[[
	@example
	```lua
	local async = fluid.async(function(set)
		scheduler.wait(1)
		return "HTTP/2"
	end)

	hooks.scheduler.step(1) -- immediately fast forward by 1 second
	CHECK(async() == "HTTP/2")
	```
]]
local function step(delta_time: number?)
	local dt = delta_time or 1 / 60
	task.spawn(step_threads, dt)
	task.spawn(step_fluid, dt)
end

return {
	step = step,
}
