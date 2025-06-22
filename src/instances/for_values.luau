local graph = require("../reactive/graph")
local types = require("../reactive/types")

local function for_values<K, V>(
	source: types.Readable<{ [K]: V }>,
	iterator: (index: K, value: V) -> Instance
): () -> { Instance }
	local node = graph.create_reactive_node(
		graph.assert_stable_parent(),
		function()
			local input = source()
			local output: { Instance } = {}

			for key, value in input do
				table.insert(output, iterator(key, value) :: any)
			end

			return output
		end,
		"lazy"
	)

	return function()
		local result = graph.evaluate_node(node)
		return if result.success then result.value else error(result.err)
	end
end

return for_values
