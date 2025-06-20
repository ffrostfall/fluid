local graph = require("./graph")
local logging = require("../logging")
local task = task or require("@lune/task")

type State = "busy" | "ok"

--[[
async nodes creates a source node for the latest valid value and for the state.
it also creates a reactive node which spawns a new thread that it runs under it's
own scope.

when created, the async node gets immediately evaluated similar to an effect.
unlike an effect though, all evaluations are deferred since we make the assumption
that async yields every single time.
]]

local function async<T>(callback: (set: (T) -> ()) -> T): (() -> T, () -> State)
	local reactive_node: graph.ReactiveNode<any>
	local value: graph.ReactiveNode<T> = graph.create_reactive_node(
		graph.assert_stable_parent(),
		function()
			graph.defer_node(reactive_node)
		end :: any,
		"async"
	)
	local state: graph.SourceNode<State> =
		graph.create_source_node("ok") :: any

	local function set(new: T)
		graph.update_source_node(value :: any, new)
	end

	local function update()
		assert(reactive_node, "reactive node does not exist")
		graph.update_source_node(state, "busy")

		-- manually set the node to be busy
		local thread = task.spawn(function()
			graph.flush_cleanups(value)
			graph.destroy_owned(value)

			value.state = coroutine.running()
			local call = graph.run_as(value, callback, set)

			if call.success then
				set(call.value)
			else
				logging.warn(`async effect error: {call.err} {call.trace}`)
			end

			graph.update_source_node(state, "ok")
			value.state = "clean"
		end)

		graph.push_cleanup(reactive_node, function()
			task.cancel(thread)
		end)
	end

	reactive_node = graph.create_reactive_node(
		graph.assert_stable_parent(),
		update :: any,
		"deferred"
	)

	graph.evaluate_node(reactive_node)

	return function()
		graph.evaluate_node(reactive_node)
		graph.push_dependency(value)
		return value.cached_value
	end, function()
		graph.evaluate_node(reactive_node)
		graph.push_dependency(state)
		return state.cached_value
	end
end

return async
