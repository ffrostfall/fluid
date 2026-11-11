local graph = require("./graph")
local types = require("./types")

local EAGER = graph.evaluation.EAGER

local function effect<T>(callback: types.Effect<T>, initial_value: T)
	local node = graph.create_effect_node(graph.assert_stable_parent(), callback, EAGER, initial_value)

	graph.refresh_node(node)
end

-- cover effect(function() end) and effect(function() return 1 end, 1)
return effect :: ((fn: () -> ()) -> ()) & (<T>(fn: (T) -> T, initial_value: T) -> ())
