local graph = require("./graph")
local types = require("./types")

local function deferred<T>(callback: types.Effect<T>, initial_value: T)
	local node = graph.create_reactive_node(
		graph.assert_stable_parent(),
		callback,
		"deferred",
		initial_value
	)

	graph.evaluate_node(node)
end

-- cover effect(function() end) and effect(function() return 1 end, 1)
return deferred :: ((fn: () -> ()) -> ()) & (<T>(fn: (T) -> T, initial_value: T) -> ())
