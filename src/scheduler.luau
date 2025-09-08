local task = (task or require("@lune/task")) :: typeof(task)

type RenderCallback = (delta_time: number) -> ()

local connections: { RenderCallback } = {}

local scheduler = {
	connections = connections,
}

function scheduler.step(delta_time: number)
	for _, callback in connections do
		task.spawn(callback, delta_time)
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
