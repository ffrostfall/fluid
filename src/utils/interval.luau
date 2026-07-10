local graph = require("../reactive/graph")
local no_yield = require("./no_yield")
local scheduler = require("../scheduler")

local dev_mode = _G.__DEV__ == true

local function interval<T>(func: (dt: number) -> T, hz: number?, offset: number?): () -> T
	local scope = graph.assert_stable_parent()

	local initial_value
	if dev_mode then
		initial_value = no_yield(func, 0)
	else
		initial_value = func(0)
	end
	local node = graph.create_source_node(initial_value)
	local last_eval = offset and -offset or 0

	local function on_render(dt: number)
		if hz ~= nil then
			last_eval += dt
			if last_eval <= 1 / hz then
				return
			end
			dt = last_eval
			last_eval = 0
		end

		local new_value
		if not dev_mode then
			new_value = func(dt)
		else
			new_value = no_yield(func, dt)
		end

		graph.update_source_node(node, new_value)
	end

	local disconnect = scheduler.on_render(on_render)

	graph.push_cleanup(scope, disconnect)

	return function()
		graph.push_dependency(node)
		return node.cached_value
	end
end

return interval
