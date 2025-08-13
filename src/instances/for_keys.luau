local graph = require("../reactive/graph")
local read = require("../utils/read")
local types = require("../reactive/types")

type IndexesGraph<K, VI, VO> = {
	transform: (() -> VI, K) -> VO,
	parent: graph.StableNode<any>,
	input: types.UsedAs<{ [K]: VI }>,
	inputs: { [K]: graph.SourceNode<VI> },
	outputs: { [K]: VO },
	scopes: { [K]: graph.StableNode<K> },
	output_node: graph.SourceNode<VO>,
}

local function indexes<K, VI, VO>(
	input: types.UsedAs<{ [K]: VI }>,
	transform: (value: () -> VI, key: K) -> VO,
	delay_destroy: number?
): () -> { VO }
	local parent = graph.assert_stable_parent()
	local child_parent = graph.create_stable_node(parent, delay_destroy)

	local input_nodes: { [K]: graph.SourceNode<VI> } = {}
	local scopes: { [K]: graph.StableNode<any> } = {}
	local output_cache: { [K]: VO } = {}

	local function update(): { VO }
		local input: { [K]: VI } = read(input)

		-- remove unused values
		for key in input_nodes do
			if input[key] then
				continue
			end
			graph.destroy(scopes[key])
			input_nodes[key] = nil
			scopes[key] = nil
			output_cache[key] = nil
		end

		-- process new / changed values
		for key, value in input do
			local source_node: graph.SourceNode<VI> = input_nodes[key]
			if source_node then -- changed
				graph.update_source_node(source_node, value)
			else -- new
				local value_node = graph.create_source_node(value)
				local output_node = graph.create_stable_node(child_parent)

				input_nodes[key] = value_node
				scopes[key] = output_node

				local output_value = graph.run_as(output_node, transform, function(): VI
					graph.push_dependency(value_node)
					return value_node.cached_value
				end, key)

				output_cache[key] = output_value
			end
		end

		local output_array = {}
		local idx = 0
		for _, value in output_cache do
			output_array[idx + 1] = value
			idx += 1
		end

		return output_array
	end

	local reactive_node = graph.create_reactive_node(child_parent, update, "lazy", {})

	return function()
		return graph.evaluate_node(reactive_node) :: any
	end
end

return indexes
