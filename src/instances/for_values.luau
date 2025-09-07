local graph = require("../reactive/graph")
local read = require("../utils/read")
local scheduler = require("../scheduler")
local types = require("../reactive/types")

local function values<V, KI, KO>(
	input: types.UsedAs<{ [KI]: V }>,
	transform: (
		value: V,
		key: () -> KI,
		active: types.Readable<boolean>
	) -> (KO, number?)
): () -> { KO }
	graph.set_group(graph.new_group("for_values"))
	local parent = graph.assert_stable_parent()
	local child_parent = graph.create_stable_node(parent)

	local input_nodes: { [V]: graph.SourceNode<KI> } = {}
	local scopes: { [V]: graph.StableNode<any> } = {}
	local output_cache: { [V]: KO } = {}
	-- given a key, maintains how long it should be delayed by (if necessary)
	-- and a list of source nodes given to these nodes for if a given node is
	-- active or not.
	local output_delays: { [V]: number? } = {}
	local output_active: { [V]: graph.SourceNode<boolean> } = {}
	local destruction_threads: { [V]: thread } = {}
	local reactive_node = graph.create_reactive_node(child_parent, false, "lazy", {})
	-- due to how the hybrid push pull graph works, we can't invalidate the reactive
	-- node. doing so will cause the graph to look at it's dependencies and
	-- make the correct assumption that the reactive node hasn't updated.
	-- by adding a useless dependency, we can force it to work.
	local useless_dependency = graph.create_source_node(0)

	local function destroy(value: V)
		graph.destroy(scopes[value])
		input_nodes[value] = nil
		scopes[value] = nil
		output_cache[value] = nil
		output_active[value] = nil
		output_delays[value] = nil
		destruction_threads[value] = nil
		graph.invalidate(reactive_node)
	end

	local function destroy_delayed(value: V)
		destroy(value)
		graph.update_source_node(useless_dependency, useless_dependency.cached_value + 1)
	end

	local function update(): { KO }
		local input: { [KI]: V } = read(input)
		graph.push_dependency(useless_dependency)

		local reversed: { [V]: KI } = {}
		for key, value in input do
			reversed[value] = key
		end

		-- remove unused values
		for value in input_nodes do
			if reversed[value] then
				continue
			end

			local node = output_active[value]
			local delay_by = output_delays[value]
			graph.update_source_node(node, false)

			if delay_by then
				destruction_threads[value] = scheduler.delay(delay_by, destroy_delayed, value)
			else
				destroy(value)
			end
		end

		-- process new / changed values
		for key, value in input do
			local source_node: graph.SourceNode<KI> = input_nodes[value]

			if destruction_threads[value] then
				scheduler.cancel(destruction_threads[value])
				destruction_threads[value] = nil
				graph.update_source_node(output_active[value], true)
			end

			if source_node then -- changed
				graph.update_source_node(source_node, key)
			else -- new
				local key_node = graph.create_source_node(key)
				local output_node = graph.create_stable_node(child_parent)
				local active_node = graph.create_source_node(true)

				local function read_key(): KI
					graph.push_dependency(key_node)
					return key_node.cached_value
				end

				local function read_active(): KI
					graph.push_dependency(active_node)
					return active_node.cached_value
				end

				local result: KO, delay: number? =
					graph.run_as_unsafe(output_node, transform, value, read_key, read_active)

				if delay then
					output_delays[value] = delay
				end

				output_active[value] = active_node
				input_nodes[value] = key_node
				scopes[value] = output_node
				output_cache[value] = result
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

-- need to do this because nil != ()
return values :: (<V, KI, KO>(
	input: types.UsedAs<{ [KI]: V }>,
	transform: (value: V, key: () -> KI, active: types.Readable<boolean>) -> KO
) -> () -> { KO }) & <V, KI, KO>(
	input: types.UsedAs<{ [KI]: V }>,
	transform: (value: V, key: () -> KI, active: types.Readable<boolean>) -> (KO, number?)
) -> () -> { KO }
