local derive = require("../reactive/derive")
local graph = require("../reactive/graph")
local scheduler = require("../scheduler")
local types = require("../reactive/types")

local function show<T, U>(
	condition: () -> any,
	truthy: (active: types.Readable<boolean>) -> (T, number?),
	falsy: ((active: types.Readable<boolean>) -> (U, number?))?
): () -> { T | U }
	local returns = {}
	local parent_node = graph.assert_stable_parent()
	local result_node = graph.create_source_node(returns)

	local is_true = function()
		return not not condition()
	end

	-- we put this into a derive to reduce the amount of updates
	local callback = derive(function(): ((active: types.Readable<boolean>) -> (U, number?))?
		if is_true() then
			return truthy
		else
			return falsy
		end
	end)

	local old_active: graph.SourceNode<boolean>?
	local old_node: graph.StableNode<unknown>?
	local delay_by: number?
	local effect = function(previous: ((active: types.Readable<boolean>) -> (U, number?))?)
		local result = callback()

		if previous == result then
			return result
		end

		-- destroy old node
		if old_active then
			graph.update_source_node(old_active, false)
		end

		if old_node and delay_by then
			scheduler.delay(delay_by, graph.destroy, old_node)
			scheduler.delay(delay_by, table.remove, returns)
		elseif old_node then
			graph.destroy(old_node)
			table.remove(returns)
		end

		old_node = nil
		old_active = nil
		delay_by = nil

		if not result then
			return result
		end

		-- create a new node.
		old_active = graph.create_source_node(false)
		old_node = graph.create_stable_node(parent_node)

		local value
		local active = old_active :: graph.SourceNode<boolean>
		graph.run_as_unsafe(old_node, function()
			value, delay_by = result(function()
				graph.push_dependency(active)
				return active.cached_value
			end)

			return value
		end)
		table.insert(returns, 1, value)

		scheduler.defer(function()
			if old_active ~= active then
				return
			end
			graph.update_source_node(active, true)
		end)

		return result
	end

	graph.create_reactive_node(parent_node, effect, "lazy", nil)

	return function()
		graph.push_dependency(result_node)
		return result_node.cached_value
	end
end

return show :: (<T>(condition: () -> any, truthy: types.UsedAs<T>) -> T?) & <T, U>(
	condition: () -> any,
	truthy: types.UsedAs<T>,
	falsy: types.UsedAs<U>
) -> T | U
