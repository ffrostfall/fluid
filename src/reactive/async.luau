local graph = require("./graph")
local logging = require("../logging")
local scheduler = require("../scheduler")
local task = task or require("@lute/task")

type State = "busy" | "ok"

--[[
async nodes creates a source node for the latest valid value and for the state.
it also creates a reactive node which runs the callback on a thread under it's
own scope.

when created, the async node gets immediately evaluated similar to an effect.
unlike an effect though, all evaluations are deferred since we make the assumption
that async yields every single time.
]]

local ASYNC = graph.evaluation.ASYNC
local free_runner: thread? = nil

local function runner_loop(run: () -> ())
	local thread = coroutine.running()

	while true do
		free_runner = nil
		run()
		free_runner = thread
		run = coroutine.yield()
	end
end

local function async<T>(callback: (set: (T) -> ()) -> T): (() -> T, () -> State)
	local reactive_node: graph.ReactiveNode<any>
	local value: graph.SourceNode<T> = graph.create_source_node(nil)
	local state: graph.SourceNode<State> = graph.create_source_node("busy") :: any
	local running: thread? = nil

	local function set(new: T)
		graph.update_node(value :: any, new)
	end

	local function run()
		running = coroutine.running()
		local ok, result = graph.run_as(reactive_node, callback, set)
		running = nil

		if ok then
			set(result)
		else
			logging.report_error((result :: any).trace)
		end

		graph.update_node(state, "ok")
	end

	local function cancel()
		local thread = running
		if thread then
			running = nil
			scheduler.cancel(thread)
		end
	end

	local function update()
		graph.update_node(state, "busy")
		graph.push_cleanup(reactive_node, cancel)
		task.spawn(free_runner or coroutine.create(runner_loop), run)
	end

	reactive_node = graph.create_reactive_node(graph.assert_stable_parent(), update :: any, ASYNC)

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
