local task = (task or require("@lune/task")) :: typeof(task)

type RenderCallback = (delta_time: number) -> ()

local connections: { RenderCallback } = {}
local scheduler_thread: thread? = nil

local scheduler = {
	connections = connections,
}

function scheduler.provide(fn: (call_render: RenderCallback) -> never)
	if scheduler_thread then
		task.cancel(scheduler_thread)
		scheduler_thread = nil
	end

	scheduler_thread = task.spawn(fn, function(delta_time)
		for _, callback in connections do
			task.spawn(callback, delta_time)
		end
	end)
end

function scheduler.on_render(fn: RenderCallback)
	table.insert(connections, fn)
end

return scheduler
