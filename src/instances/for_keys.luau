local graph = require("../reactive/graph")
local read = require("../utils/read")
local scheduler = require("../scheduler")
local types = require("../reactive/types")

local function indexes<K, VI, VO>(
	input: types.UsedAs<{ [K]: VI }>,
	transform: (
		() -> VI,
		K,
		active: types.Readable<boolean>
	) -> (VO, number?)
): () -> { VO }
	graph.set_group(graph.new_group("for_keys"))
	local parent = graph.assert_stable_parent()
	local child_parent = graph.create_stable_node(parent)

	local input_nodes: { [K]: graph.SourceNode<VI> } = {}
	local scopes: { [K]: graph.StableNode<any> } = {}
	local output_cache: { [K]: VO } = {}
	-- given a key, maintains how long it should be delayed by (if necessary)
	-- and a list of source nodes given to these nodes for if a given node is
	-- active or not.
	local output_delays: { [K]: number? } = {}
	local output_active: { [K]: graph.SourceNode<boolean> } = {}
	local destruction_threads: { [K]: thread } = {}
	local reactive_node = graph.create_reactive_node(child_parent, false, "lazy", {})
	-- due to how the hybrid push pull graph works, we can't invalidate the reactive
	-- node. doing so will cause the graph to look at it's dependencies and
	-- make the correct assumption that the reactive node hasn't updated.
	-- by adding a useless dependency, we can force it to work.
	local useless_dependency = graph.create_source_node(0)

	local function destroy(key: K)
		graph.destroy(scopes[key])
		input_nodes[key] = nil
		scopes[key] = nil
		output_cache[key] = nil
		output_active[key] = nil
		output_delays[key] = nil
		destruction_threads[key] = nil
	end

	local function destroy_delayed(key: K)
		destroy(key)
		graph.update_source_node(useless_dependency, useless_dependency.cached_value + 1)
	end

	local function update(): { VO }
		local input: { [K]: VI } = read(input)
		graph.push_dependency(useless_dependency)

		-- remove unused values
		for key in input_nodes do
			if input[key] then
				continue
			end
			local node = output_active[key]
			local delay_by = output_delays[key]
			graph.update_source_node(node, false)

			if delay_by then
				destruction_threads[key] = scheduler.delay(delay_by, destroy_delayed, key)
			else
				destroy(key)
			end
		end

		-- process new / changed values
		for key, value in input do
			local source_node: graph.SourceNode<VI> = input_nodes[key]

			if destruction_threads[key] then
				scheduler.cancel(destruction_threads[key])
				destruction_threads[key] = nil
				graph.update_source_node(output_active[key], true)
			end

			if source_node then -- changed
				graph.update_source_node(source_node, value)
			else -- new
				local value_node = graph.create_source_node(value)
				local output_node = graph.create_stable_node(child_parent)
				local active_node = graph.create_source_node(true)

				local function read_value(): VI
					graph.push_dependency(value_node)
					return value_node.cached_value
				end

				local function read_active(): boolean
					graph.push_dependency(active_node)
					return active_node.cached_value
				end

				local result: VO, delay: number? =
					graph.run_as_unsafe(output_node, transform, read_value, key, read_active)

				if delay then
					output_delays[key] = delay
				end

				output_active[key] = active_node
				input_nodes[key] = value_node
				scopes[key] = output_node
				output_cache[key] = result
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

	reactive_node.effect = update
	graph.clear_group()

	return function()
		local result = graph.evaluate_node(reactive_node)
		return if result.success then result.value else error(result.err)
	end
end

return indexes :: (<K, VI, VO>(
	input: types.UsedAs<{ [K]: VI }>,
	transform: (() -> VI, K, active: types.Readable<boolean>) -> VO
) -> () -> { VO }) & <K, VI, VO>(
	input: types.UsedAs<{ [K]: VI }>,
	transform: (() -> VI, K, active: types.Readable<boolean>) -> (VO, number?)
) -> () -> { VO }
