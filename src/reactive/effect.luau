local graph = require("./graph")
local types = require("./types")

local function effect<T>(callback: types.Effect<T>, initial_value: T)
	local node =
		graph.create_reactive_node(graph.assert_stable_parent(), callback, "eager", initial_value)

	graph.evaluate_node(node)
end

-- cover effect(function() end) and effect(function() return 1 end, 1)
return effect :: ((fn: () -> ()) -> ()) & (<T>(fn: (T) -> T, initial_value: T) -> ())
