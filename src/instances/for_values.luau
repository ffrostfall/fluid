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

local function values<V, KI, KO>(
	input: types.UsedAs<{ [KI]: V }>,
	transform: (value: V, key: () -> KI) -> KO,
	delay_destroy: number?
): () -> { KO }
	local parent = graph.assert_stable_parent()
	local child_parent = graph.create_stable_node(parent, delay_destroy)

	local input_nodes: { [V]: graph.SourceNode<KI> } = {}
	local scopes: { [V]: graph.StableNode<any> } = {}
	local output_cache: { [V]: KO } = {}

	local function update(): { KO }
		local input: { [KI]: V } = read(input)

		local reversed: { [V]: KI } = {}
		for key, value in input do
			reversed[value] = key
		end

		-- remove unused values
		for value in input_nodes do
			if reversed[value] then
				continue
			end

			graph.destroy(scopes[value])
			input_nodes[value] = nil
			scopes[value] = nil
			output_cache[value] = nil
		end

		-- process new / changed values
		for key, value in input do
			local source_node: graph.SourceNode<KI> = input_nodes[value]
			if source_node then -- changed
				graph.update_source_node(source_node, key)
			else -- new
				local key_node = graph.create_source_node(key)
				local output_node = graph.create_stable_node(child_parent)

				input_nodes[value] = key_node
				scopes[value] = output_node

				local output_value = graph.run_as(output_node, transform, value, function(): KI
					graph.push_dependency(key_node)
					return key_node.cached_value
				end)

				output_cache[value] = output_value
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

return values
