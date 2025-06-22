local graph = require("../reactive/graph")
local types = require("../reactive/types")
local result = require("../result")
local read = require("../utils/read")

type IndexesGraph<K, VI, VO> = {
	transform: (() -> VI, K) -> VO,
	parent: graph.StableNode<any>,
	input: types.UsedAs<{ [K]: VI }>,
	inputs: { [K]: graph.SourceNode<VI> },
	outputs: { [K]: VO },
	scopes: { [K]: graph.StableNode<K> },
	output_node: graph.SourceNode<VO>,
}

local function indexes<K, VI, VO>(input: types.UsedAs<{ [K]: VI }>, transform: (value: () -> VI, key: K) -> ()): () -> { [K]: VO }
	local parent = graph.assert_stable_parent()
	local child_parent = graph.create_stable_node(parent)

	local input_nodes: { [K]: graph.SourceNode<VI> } = {}
	local scopes: { [K]: graph.StableNode<any> } = {}

	local function update(out: { [K]: VO }): { [K]: VO }
		local input: { [K]: VI } = read(input)

		-- remove unused values
		for key in input_nodes do
			if input[key] then
				continue
			end
			graph.destroy(scopes[key])
			input_nodes[key] = nil
			scopes[key] = nil
			out[key] = nil
		end

		-- process new / changed values
		for key, value in input do
			local source_node: graph.SourceNode<VI> = input_nodes[key]
			if source_node then -- changed
				graph.update_source_node(source_node, value)
			else -- new
				local value_node = graph.create_source_node(value)
				local output_node = graph.create_stable_node(child_parent)

				local result: result.Identity<VO> = graph.run_as(output_node, transform, function(): VI
					graph.push_dependency(value_node)
					return value_node.cached_value
				end, key)

				if not result.success then
					error(tostring(result))
				end

				input_nodes[key] = value_node
				scopes[key] = output_node
				out[key] = result.value
			end
		end

		return out
	end

	local reactive_node = graph.create_reactive_node(child_parent, update, "lazy", {})

	return function()
		local r = graph.evaluate_node(reactive_node)
		if not r.success then
			error(r)
		end

		graph.push_dependency(reactive_node)
		return reactive_node.cached_value
	end
end

return indexes
