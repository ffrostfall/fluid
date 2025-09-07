local graph = require("./graph")
local types = require("./types")

local function deferred<T>(callback: types.Effect<T>, initial_value: T)
	graph.set_group(graph.new_group("deferred"))
	local node = graph.create_reactive_node(
		graph.assert_stable_parent(),
		callback,
		"deferred",
		initial_value
	)

	graph.evaluate_node(node)
	graph.clear_group()
end

-- cover effect(function() end) and effect(function() return 1 end, 1)
return deferred :: ((fn: () -> ()) -> ()) & (<T>(fn: (T) -> T, initial_value: T) -> ())
