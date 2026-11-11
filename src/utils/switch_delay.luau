local derive = require("../reactive/derive")
local graph = require("../reactive/graph")
local scheduler = require("../scheduler")
local types = require("../reactive/types")

type Condition<T> = (types.Readable<boolean>) -> (T, number?)

type SwitchGraph<Result> = {
	previous_effect: Condition<Result>?,
	scopes: { [Condition<Result>]: graph.StableNode<Result> },
	active_nodes: { [Condition<Result>]: graph.SourceNode<boolean> },
	delay_by: { [Condition<Result>]: number? },
	threads: { [Condition<Result>]: thread? },
	result_values: { [Condition<Result>]: Result },
	-- result_values as an array, rebuilt when the node updates instead of on every read
	values: { Result },
}

local LAZY = graph.evaluation.LAZY

local function destroy<Result>(p: SwitchGraph<Result>, c: Condition<Result>)
	graph.destroy(p.scopes[c])
	p.scopes[c] = nil
	p.active_nodes[c] = nil
	p.delay_by[c] = nil
	p.threads[c] = nil
	p.result_values[c] = nil
end

local function destroy_delayed<Result>(p: SwitchGraph<Result>, c: Condition<Result>, update_counter: graph.SourceNode<number>)
	destroy(p, c)
	graph.update_node(update_counter, update_counter.cached_value + 1)
end

local function switch<Key, Result>(condition: () -> Key)
	return function(options: { [Key]: (types.Readable<boolean>) -> (Result, number?) }): () -> { Result }
		local parent_node = graph.assert_stable_parent()
		-- allows us to force an update on the reactive node
		local update_counter = graph.create_source_node(0)

		-- we put this into a derive to reduce the amount of updates
		local callback = derive(function(): Condition<Result>?
			return options[condition()]
		end)

		local function switch_effect(
			p: SwitchGraph<Result>,
			previous_effect: Condition<Result>?,
			active_effect: Condition<Result>?
		)
			local scopes = p.scopes
			local active_nodes = p.active_nodes
			local result_values = p.result_values

			-- previous effect isn't the same as active effect, so destroy previous effect
			if previous_effect and not p.threads[previous_effect] and p.scopes[previous_effect] then
				local delay_by = p.delay_by[previous_effect]

				graph.update_node(p.active_nodes[previous_effect], false)

				if delay_by then
					p.threads[previous_effect] =
						scheduler.delay(delay_by, destroy_delayed, p, previous_effect, update_counter)
				else
					destroy(p, previous_effect)
				end
			end

			p.previous_effect = active_effect

			if not active_effect then
				return
			end

			-- first see if an old node was in the process of getting destroyed.
			-- if it is, save it
			local thread = p.threads[active_effect]
			if thread then
				scheduler.cancel(thread)
				p.threads[active_effect] = nil
				graph.update_node(p.active_nodes[active_effect], true)
				return
			end

			-- otherwise, create a new node
			local node = graph.create_stable_node(parent_node)
			local active = graph.create_source_node(true)

			local function read_active()
				graph.push_dependency(active)
				return active.cached_value
			end

			scopes[active_effect] = node
			active_nodes[active_effect] = active
			result_values[active_effect], p.delay_by[active_effect] =
				graph.run_as_unsafe(node, active_effect, read_active)
		end

		local function update(p: SwitchGraph<Result>)
			graph.push_dependency(update_counter)

			local previous_effect = p.previous_effect
			local active_effect = callback()

			if previous_effect ~= active_effect then
				switch_effect(p, previous_effect, active_effect)
			end

			-- result values can also change from delayed destruction, which bumps update_counter
			local values = {}
			for _, value in p.result_values do
				table.insert(values, value)
			end
			p.values = values

			return p
		end

		local reactive = graph.create_reactive_node(parent_node, update, LAZY, {
			previous_effect = nil,
			scopes = {},
			active_nodes = {},
			delay_by = {},
			threads = {},
			result_values = {},
			values = {},
		})

		return function()
			local result: SwitchGraph<Result> = graph.evaluate_node(reactive)
			-- a copy, so consumers mutating it don't mutate the actual values
			return table.clone(result.values)
		end
	end
end

return switch
