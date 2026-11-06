local graph = require("./graph")
local types = require("./types")

local DEFERRED = graph.evaluation.DEFERRED

local function deferred<T>(callback: types.Effect<T>, initial_value: T)
	local node = graph.create_effect_node(graph.assert_stable_parent(), callback, DEFERRED, initial_value)

	graph.refresh_node(node)
end

-- cover effect(function() end) and effect(function() return 1 end, 1)
return deferred :: ((fn: () -> ()) -> ()) & (<T>(fn: (T) -> T, initial_value: T) -> ())
