local task = (task or require("@lute/task")) :: typeof(task)

type RenderCallback = (delta_time: number) -> ()

-- giving this a type because coroutine.close has returns and task.cancel doesn't
local cancel: (thread) -> () = task.cancel or coroutine.close

local connections: { RenderCallback } = {}

local scheduler = {
	connections = connections,
}

local free_runner: thread? = nil

local function run_callback(callback: RenderCallback, delta_time: number)
	free_runner = nil
	callback(delta_time)
	free_runner = coroutine.running()
end

local function runner_loop(callback: RenderCallback, delta_time: number)
	run_callback(callback, delta_time)

	while true do
		run_callback(coroutine.yield())
	end
end

function scheduler.step(delta_time: number)
	for _, callback in connections do
		task.spawn(free_runner or coroutine.create(runner_loop), callback, delta_time)
	end
end

function scheduler.defer<T...>(fn: (T...) -> (), ...: T...)
	return task.defer(fn, ...)
end

function scheduler.delay<T...>(n: number, fn: (T...) -> (), ...: T...): thread
	return task.delay(n, fn, ...)
end

function scheduler.wait<T...>(time: number?): number
	return task.wait(time)
end

function scheduler.cancel(thread: thread)
	return cancel(thread)
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
