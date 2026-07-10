local graph = require("./graph")
local types = require("./types")

local function derive<T>(source: types.Effect<T>): types.Readable<T>
	local node = graph.create_reactive_node(graph.assert_stable_parent(), source, "lazy")

	local function evaluate()
		local result = graph.evaluate_node(node)

		return if result.success then result.value else error(result, 0)
	end

	return evaluate
end

return derive
