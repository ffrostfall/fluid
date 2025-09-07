local graph = require("../reactive/graph")
local scheduler = require("../scheduler")

local function interval<T>(func: (dt: number) -> T, hz: number?)
	local scope = graph.assert_stable_parent()

	graph.set_group(graph.new_group("interval"))
	local node = graph.create_source_node(func(0))
	local last_eval = 0
	graph.clear_group()

	local function on_render(dt: number)
		if hz ~= nil then
			last_eval += dt
			if last_eval <= 1 / hz then
				return
			end
			dt = last_eval
			last_eval = 0
		end

		graph.update_source_node(node, func(dt))
	end

	local disconnect = scheduler.on_render(on_render)

	graph.push_cleanup(scope, disconnect)

	return function()
		graph.push_dependency(node)
		return node.cached_value
	end
end

return interval
