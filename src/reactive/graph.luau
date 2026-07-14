local exception = require("../utils/exception")
local logging = require("../logging")
local reactive_fn_calls = require("../utils/reactive_fn_calls")
local scheduler = require("../scheduler")
local types = require("./types")

local dev_mode = true
local deferred_thread: thread? = nil
local pending_eval: { ReactiveNode<unknown> } = {}
local processing_node: { [thread]: Node<unknown> } = {}
local deferred_nodes: { Node<unknown> } = {}
local version = 0

export type SourceNode<T> = {
	last_evaluation: number,
	state: "clean",
	effect: false,

	cached_value: T,

	--- Other nodes that depend on the result of this node.
	dependents: { ReactiveNode<T> },
}

export type StableNode<T> = {
	last_evaluation: number,
	parent: Node<T> | false,
	children: { Node<T> },

	--- Describes the effect to run to compute the result of this node.
	effect: false,

	state: "clean",
	cached_value: T,

	-- Cleanup functions run when the node dies
	cleanups: { () -> () },
}

export type ReactiveNode<T> = {
	last_evaluation: number,
	parent: Node<T> | false,
	children: { Node<T> },

	--- Describes the effect to run to compute the result of this node.
	effect: types.Effect<T> | false,
	-- async is similar to eager, but unlike eager does not actually update the
	-- value. this is necessary to support a proper async reactive primitive
	evaluation: "eager" | "deferred" | "lazy" | "dead" | "async",

	-- clean: the cached_value result can be used immediately
	-- dirty: you need to recompute the node
	-- thread: the node is already being recomputed - throw an error!
	-- dead: the node is dead
	state: "clean" | "dirty" | thread | "dead",

	cached_value: T,

	cleanups: { () -> () },

	depending_on: { SourceNode<T> | ReactiveNode<T> },
	dependents: { ReactiveNode<T> },
}

export type Node<T> = ReactiveNode<T> | StableNode<T>

local function find_and_swap_pop<T>(t: { T }, v: T)
	local i = table.find(t, v) :: number
	local n = #t
	t[i] = t[n]
	t[n] = nil
end

local function flush_cleanups<T>(node: Node<T>)
	for _, fn in node.cleanups do
		fn()
	end

	table.clear(node.cleanups)
end

local function remove_dependencies<T>(node: Node<T>)
	if not node.effect then
		return
	end

	for idx, dependency in node.depending_on do
		find_and_swap_pop(dependency.dependents, node)
	end
	table.clear(node.depending_on)
end

local function bump_version()
	version += 1
	return version
end

local function get_scope()
	return processing_node[coroutine.running()]
end

local function set_scope(node: Node<any>?)
	processing_node[coroutine.running()] = node
end

local function run_as_unsafe<T..., U...>(node: Node<any>?, fn: (U...) -> T..., ...: U...): T...
	local previous_processing = get_scope()
	set_scope(node)

	local a, b = fn(...)

	set_scope(previous_processing)
	return a, b
end

local function is_similar(a: unknown, b: unknown): boolean
	local both_are_tables = type(a) == "table"
		and type(b) == "table"
		and not table.isfrozen(a)
		and not table.isfrozen(b)

	return if both_are_tables then false else a == b
end

local function push_dependency_to_active_scope<T>(node: SourceNode<T> | ReactiveNode<T>)
	local scope = get_scope()
	if not (scope and scope.effect) then
		return
	end

	assert(scope ~= node, `node tried to add itself as dependency`)

	table.insert(node.dependents, scope)
	table.insert(scope.depending_on, node)
end

local function node_destroy<T>(node: Node<T>)
	flush_cleanups(node)
	remove_dependencies(node)

	if node.parent then
		find_and_swap_pop(node.parent.children, node)

		node.parent = false
	end

	while node.children[1] do
		node_destroy(node.children[1])
	end
	table.clear(node.children)
end

local function node_destroy_owned<T>(node: Node<T>)
	while node.children[1] do
		node_destroy(node.children[1])
	end
	table.clear(node.children)
end

local function effect_yield(thread: thread)
	return exception.new({
		kind = "yielded",
		trace = debug.traceback(thread, logging.errors.graph_effect_yielded()),
	})
end

local function effect_err(err: unknown): exception.Identity
	if exception.is(err) then
		local new_err: exception.Identity = err :: any
		return new_err
	elseif type(err) == "string" then
		return exception.new({
			kind = "invoked",
			trace = debug.traceback(logging.errors.graph_effect_errored(tostring(err))),
			err = err,
		})
	else
		return exception.new({
			kind = "uncaught",
			trace = debug.traceback(logging.errors.unknown(tostring(err))),
			err = tostring(err),
		})
	end
end

local graph = {}

local function graph_run_as<T..., U...>(node: Node<any>?, fn: (U...) -> T..., ...: U...): (boolean, T...)
	local previous_processing = get_scope()
	set_scope(node)

	local is_async_node = (node and node.effect and node.evaluation == "async")

	local yielding_errors = dev_mode and not is_async_node

	local ok, a, b
	if yielding_errors then
		-- ok, call = reactive_fn_calls.call(fn, effect_err, ...)
		ok, a, b = reactive_fn_calls.no_yield_call(run_as_unsafe, effect_err, effect_yield, node, fn, ...)
	else
		ok, a, b = xpcall(fn, effect_err, ...)
	end

	set_scope(previous_processing)

	return ok, a, b
end

local function graph_defer_node<T>(node: ReactiveNode<T>)
	if node.state == "dirty" then
		return
	end
	node.state = "dirty"
	table.insert(deferred_nodes, node)

	if deferred_thread == nil then
		deferred_thread = scheduler.defer(function()
			assert(graph)

			graph.flush_deferred_nodes()
			deferred_thread = nil
		end)
	end
end

local function graph_update_node<T>(node: ReactiveNode<T>): T
	local should_reevaluate = #node.depending_on == 0
	for _, dependency in node.depending_on do
		-- a dependency was evaluated after this dependency was invalidated
		if dependency.last_evaluation > node.last_evaluation then
			should_reevaluate = true
			break
		elseif dependency.state == "clean" then
			continue
		end
		-- the dependency is dirty, so we have to reevaluate that dependency
		if dependency.state == "dirty" then
			graph_update_node(dependency)
			if dependency.last_evaluation < node.last_evaluation then
				continue
			end
			should_reevaluate = true
			break
		end
		-- if the dependency is running on the same thread, we have a recursive dependency, otherwise
		-- it's fine to just recompute the value and have it invalidate later
		if dependency.state == coroutine.running() then
			error(
				`a recursive dependency has been found, which may result in an infinite loop. this should be unreachable`
			)
		end
	end

	if not should_reevaluate then
		node.state = "clean"
		return node.cached_value
	end

	flush_cleanups(node)
	node_destroy_owned(node)
	remove_dependencies(node)

	node.state = coroutine.running()
	local previous_result = node.cached_value
	local success, res = graph_run_as(node, node.effect, previous_result)
	-- we mark it as clean and bump the evaluation value since we don't
	-- want to re-run the node even if it errored
	node.state = "clean"

	if success then
		push_dependency_to_active_scope(node)

		if node.evaluation ~= "eager" and is_similar(previous_result, res) or node.evaluation == "async" then
			return node.cached_value
		end

		node.last_evaluation = bump_version()
		node.cached_value = res

		return node.cached_value
	else
		logging.warn(res.trace)
		error(res)
	end
end

local function is_dirty<T>(node: ReactiveNode<T>)
	if node.state == "clean" then
		return false
	end

	for _, dependency in node.depending_on do
		-- if a dependent was evaluated after this node was evaluated, it's dirty
		if dependency.effect and dependency.state == "dirty" then
			-- make sure the dependency isn't dirty
			graph_update_node(dependency :: ReactiveNode<T>)
		end

		if dependency.last_evaluation > node.last_evaluation then
			return true
		end
	end

	return #node.depending_on == 0
end

local function graph_evaluate_node<T>(node: SourceNode<T> | ReactiveNode<T>): T
	if node.effect == false or node.state == "clean" then
		push_dependency_to_active_scope(node)

		return node.cached_value
	elseif coroutine.running() == node.state then
		error(exception.new({
			kind = "fluid",
			trace = debug.traceback(logging.errors.graph_recursive_dependency_coeqnost()),
		}))
	elseif type(node.state) == "thread" then
		--todo: should this be allowed?
		return node.cached_value
	elseif node.state == "dead" then
		return node.cached_value
	elseif is_dirty(node) then
		return graph_update_node(node)
	else
		node.state = "clean"
		return node.cached_value
	end
end

local function graph_invalidate_loop<T>(node: SourceNode<T> | ReactiveNode<T>)
	if node.state == "dirty" then
		return
	end

	for _, value in node.dependents do
		graph_invalidate_loop(value)
		if value.evaluation == "eager" or value.evaluation == "async" then
			value.state = "dirty"
			table.insert(pending_eval, value)
		elseif value.evaluation == "deferred" then
			graph_defer_node(value)
		elseif value.evaluation == "lazy" then
			value.state = "dirty"
		end
	end
end

local function invalidate<T>(node: ReactiveNode<T> | SourceNode<T>)
	graph_invalidate_loop(node)

	for _, node in pending_eval do
		for _, dependent in node.depending_on do
			run_as_unsafe(nil, graph_evaluate_node, dependent)
		end

		graph_run_as(nil, graph_evaluate_node, node)
	end
	table.clear(pending_eval)
end

function graph.flush_deferred_nodes()
	for _, node in deferred_nodes do
		graph_evaluate_node(node)
	end

	table.clear(deferred_nodes)
end

function graph.create_reactive_node<T>(
	parent: Node<T> | false,
	effect: types.Effect<T> | false,
	evaluation: "eager" | "deferred" | "lazy" | "async",
	cached_value: T
): ReactiveNode<T>
	local node: ReactiveNode<T> = {
		parent = parent,
		last_evaluation = bump_version(),

		effect = effect,
		evaluation = evaluation,
		state = "dirty",
		cached_value = cached_value,
		depending_on = {},
		dependents = {},

		children = {},
		cleanups = {},
	}

	if parent then
		table.insert(parent.children, node)
	end

	if evaluation == "deferred" then
		table.insert(deferred_nodes, node)
	end

	return node
end

function graph.create_stable_node<T>(parent: Node<T> | false)
	local node: StableNode<T> = {
		parent = parent,

		effect = false,
		state = "clean",
		last_evaluation = bump_version(),

		cached_value = nil,

		children = {},
		cleanups = {},
	}

	if parent then
		table.insert(parent.children, node)
	end

	return node
end

function graph.create_source_node<T>(value: T): SourceNode<T>
	local node: SourceNode<T> = {
		last_evaluation = bump_version(),
		effect = false,
		cached_value = value,
		state = "clean",
		dependents = {},
	}

	return node
end

function graph.update_node<T>(node: ReactiveNode<T> | SourceNode<T>, value: T)
	if is_similar(node.cached_value, value) then
		return
	end
	node.last_evaluation = bump_version()
	node.cached_value = value
	invalidate(node)
end

function graph.push_cleanup<T>(scope: Node<T>, cleanup: () -> ())
	table.insert(scope.cleanups, cleanup)
end

function graph.assert_scope<T>(): ReactiveNode<T> | StableNode<T>
	return assert(get_scope(), "reactive scope error thing, TODO error message")
end

function graph.assert_stable_parent<T>(): StableNode<T>
	local scope = get_scope()

	if not scope then
		error(`cannot call {debug.info(2, "n")} without a parent scope`, 2)
	elseif scope.effect ~= false then
		error(
			`cannot call {debug.info(2, "n")} while the parent scope is reactive - this might be a component. consider using untrack() while creating the components.`,
			2
		)
	end

	return scope :: StableNode<T>
end

graph.get_scope = get_scope
graph.set_scope = set_scope
graph.flush_cleanups = flush_cleanups
graph.destroy_owned = node_destroy_owned
graph.defer_node = graph_defer_node
graph.invalidate = invalidate
graph.destroy = node_destroy
graph.run_as_unsafe = run_as_unsafe
graph.push_dependency = push_dependency_to_active_scope
graph.evaluate_node = graph_evaluate_node
graph.run_as = graph_run_as

return graph
