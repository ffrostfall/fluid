local graph = require("./graph")
local types = require("./types")

local evaluate_node = graph.evaluate_node
local LAZY = graph.evaluation.LAZY

local function derive<T>(source: types.Effect<T>): types.Readable<T>
	local node = graph.create_reactive_node(graph.assert_stable_parent(), source, LAZY)

	local function evaluate()
		return evaluate_node(node)
	end

	return evaluate
end

return derive
