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

function scheduler.delay<T...>(n: number, fn: (T...) -> (), ...: T...)
	return task.delay(n, fn, ...)
end

function scheduler.on_render(fn: RenderCallback)
	table.insert(connections, fn)
end

return scheduler
