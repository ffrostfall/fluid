local colorful = require("./vendor/colorful")
local flags = require("./flags")
local task = (task or require("@lune/task")) :: typeof(task)

type RenderCallback = (delta_time: number) -> ()
type WaitingThread =
	({ resume: number, start: number } | { resume: number })
	& { [any]: any }
	& { any }

local connections: { RenderCallback } = {}
local waiting_threads: { [thread]: WaitingThread } = {}
local step_tick = 0

local function warn_facade(text: string)
	if warn then
		warn(text)
		return
	end
	print(colorful.color.redBright(text))
end

local scheduler = {
	connections = connections,
}

function scheduler.step(delta_time: number)
	step_tick += delta_time

	for _, callback in connections do
		task.spawn(callback, delta_time)
	end

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
				warn_facade(
					if data.trace
						then `[fluid]: {err} origin: {data.trace}`
						else `[fluid]: {err}`
				)
			end
		else
			waiting_threads[thread] = data
		end
	end
end

function scheduler.defer<T...>(fn: (T...) -> (), ...: T...)
	return task.defer(fn, ...)
end

function scheduler.delay<T...>(n: number, fn: (T...) -> (), ...: T...): thread
	local thread = coroutine.create(fn)
	local data: { [any]: any } = table.pack(...)
	data.resume = step_tick + n
	if flags.dev_mode then
		data.trace = debug.traceback(nil, 2)
	end
	waiting_threads[thread] = data :: WaitingThread

	return thread
end

function scheduler.wait<T...>(time: number?): number
	waiting_threads[coroutine.running()] =
		{ resume = step_tick + (time or 0), start = step_tick } :: WaitingThread
	return coroutine.yield()
end

function scheduler.cancel(thread: thread)
	return task.cancel(thread)
end

function scheduler.on_render(fn: RenderCallback)
	table.insert(connections, fn)
	return function()
		local index = table.find(connections, fn)
		if index then
			table.remove(connections, index)
		end
	end
end

return scheduler
