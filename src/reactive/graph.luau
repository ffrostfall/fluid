local logging = require("../logging")
local result = require("../result")
local scheduler = require("../scheduler")
local types = require("./types")

local dev_mode = _G.__DEV__ == true

-- groups are an internal way of organizing nodes within developer mode to enhance
-- and add additonial debugging information for the user. nodes, should NEVER be part of multiple groups!
export type NodeGroup = {
	read name: string,

	-- nodes that are part of the group
	[number]: Node<unknown> | SourceNode<unknown>,
}

export type SourceNode<T> = {
	last_evaluation: number,
	read state: "clean",
	effect: false,

	cached_value: T,

	--- Other nodes that depend on the result of this node.
	read dependents: { ReactiveNode<T> },
}

export type StableNode<T> = {
	last_evaluation: number,
	read parent: Node<T> | false,
	read children: { Node<T> },

	--- Describes the effect to run to compute the result of this node.
	effect: false,

	read state: "clean",
	read cached_value: T,

	-- Cleanup functions run when the node dies
	read cleanups: { () -> () },
}

export type ReactiveNode<T> = {
	last_evaluation: number,
	read parent: Node<T> | false,
	read children: { Node<T> },

	--- Describes the effect to run to compute the result of this node.
	effect: types.Effect<T>,
	-- async is similar to eager, but unlike eager does not actually update the
	-- value. this is necessary to support a proper async reactive primitive
	read evaluation: "eager" | "deferred" | "lazy" | "dead" | "async",

	-- clean: the cached_value result can be used immediately
	-- dirty: you need to recompute the node
	-- thread: the node is already being recomputed - throw an error!
	-- dead: the node is dead
	state: "clean" | "dirty" | thread | "dead",

	cached_value: T,

	read cleanups: { () -> () },

	depending_on: { SourceNode<T> | ReactiveNode<T> },
	read dependents: { ReactiveNode<T> },
}

export type Node<T> = ReactiveNode<T> | StableNode<T>

local graph
local pending_eval: { ReactiveNode<unknown> } = {}
local processing_node: { [thread]: Node<unknown> } = {}
local node_groups: { [Node<unknown> | SourceNode<unknown>]: NodeGroup } = setmetatable(
	{},
	{ __mode = "k" }
)
local deferred_nodes = {}
local current_group: NodeGroup? = nil
local version = 0

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

local function new_group(name: string): NodeGroup
	if dev_mode then
		return nil :: any
	end

	return setmetatable({
		name = name,
	}, { __mode = "v" }) -- __mode doesn't collect garbage on strings
end

local function set_group(group: NodeGroup)
	if dev_mode then
		return
	end

	current_group = group
end

local function clear_group()
	if dev_mode then
		return
	end

	current_group = nil
end

local function get_group(node: Node<unknown> | SourceNode<unknown>): NodeGroup?
	return node_groups[node]
end

local function run_as_unsafe<T..., U...>(owner: Node<any>?, fn: (U...) -> T..., ...: U...): T...
	local previous_processing = get_scope()
	set_scope(owner)
	local a, b = fn(...)
	set_scope(previous_processing)
	return a, b
end

local function run_as<T, U...>(owner: Node<any>?, fn: (U...) -> T, ...: U...): result.Identity<T, unknown>
	local previous_processing = get_scope()
	set_scope(owner)
	local call = result.call(fn, ...)
	set_scope(previous_processing)
	return call
end

local deferred_thread: thread?
local function defer_node<T>(node: ReactiveNode<T>)
	if node.state == "dirty" then
		return
	end
	node.state = "dirty" :: any
	table.insert(deferred_nodes, node)

	if deferred_thread == nil then
		deferred_thread = scheduler.defer(function()
			assert(graph)

			graph.flush_deferred_nodes()
			deferred_thread = nil
		end)
	end
end

local function push_dependency<T>(node: SourceNode<T> | ReactiveNode<T>)
	local scope = get_scope()
	if not (scope and scope.effect) then
		return
	end

	assert(scope ~= node, `node tried to add itself as dependency`)

	table.insert(node.dependents, scope)
	table.insert(scope.depending_on, node)
end

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

local function destroy<T>(node: Node<T>)
	flush_cleanups(node)
	remove_dependencies(node)

	if node.parent then
		find_and_swap_pop(node.parent.children, node)

		node.parent = false :: any -- TODO: Luau type state issue
	end

	while node.children[1] do
		destroy(node.children[1])
	end
end

local function destroy_owned<T>(node: Node<T>)
	for _, node: Node<T> in node.children do
		destroy(node)
	end
	table.clear(node.children)
end

local function is_similar(a: unknown, b: unknown): boolean
	local both_are_tables = type(a) == "table"
		and type(b) == "table"
		and not table.isfrozen(a :: any)
		and not table.isfrozen(b :: any)

	return if both_are_tables then false else a == b
end

local function update_node<T>(node: ReactiveNode<T>): result.Identity<T, string>
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
			update_node(dependency :: ReactiveNode<T>)
			if dependency.last_evaluation < node.last_evaluation then
				continue
			end
			should_reevaluate = true
			break
		end
		-- if the dependency is running on the same thread, we have a recursive dependency, otherwise
		-- it's fine to just recompute the value and have it invalidate later
		if dependency.state == coroutine.running() then
			return result.fail(
				`a recursive dependency has been found, which may result in an infinite loop. this should be unreachable`,
				debug.traceback(nil, 2)
			)
		end
	end

	if not should_reevaluate then
		node.state = "clean"
		return result.ok(node.cached_value)
	end

	flush_cleanups(node)
	destroy_owned(node)
	remove_dependencies(node)

	node.state = coroutine.running()
	local previous_result = node.cached_value
	local call = run_as(node, node.effect, previous_result)
	-- we mark it as clean and bump the evaluation value since we don't
	-- want to re-run the node even if it errored
	node.state = "clean"

	if call.success then
		push_dependency(node)

		if
			node.evaluation ~= "eager" and is_similar(previous_result, call.value)
			or node.evaluation == "async"
		then
			return result.ok(node.cached_value)
		end

		node.last_evaluation = bump_version()
		node.cached_value = call.value

		return result.ok(node.cached_value)
	else
		logging.warn(`effect error: {call.err}`)
		return result.fail(`effect error: {call.err}`, call.trace)
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
			update_node(dependency :: ReactiveNode<T>)
		end

		if dependency.last_evaluation > node.last_evaluation then
			return true
		end
	end

	return #node.depending_on == 0
end

local function evaluate_node<T>(node: SourceNode<T> | ReactiveNode<T>): result.Identity<T, string>
	if node.effect == false or node.state == "clean" then
		push_dependency(node :: SourceNode<T> | ReactiveNode<T>)

		return result.ok(node.cached_value)
	elseif coroutine.running() == node.state then
		return result.fail(
			`this creates a recursive dependency, which can result in creating a infinite loop.`,
			debug.traceback(nil, 2)
		)
	elseif type(node.state) == "thread" then
		--todo: should this be allowed?
		return result.ok(node.cached_value)
	elseif node.state == "dead" then
		return result.ok(node.cached_value)
	elseif is_dirty(node :: ReactiveNode<T>) then
		return update_node(node :: ReactiveNode<T>)
	else
		node.state = "clean" :: any
		return result.ok(node.cached_value)
	end
end

local function invalidate_loop<T>(node: SourceNode<T> | ReactiveNode<T>)
	if node.state == "dirty" then
		return
	end

	for _, value in node.dependents do
		invalidate_loop(value)
		if value.evaluation == "eager" or value.evaluation == "async" then
			value.state = "dirty"
			table.insert(pending_eval, value)
		elseif value.evaluation == "deferred" then
			defer_node(value)
		elseif value.evaluation == "lazy" then
			value.state = "dirty"
		end
	end
end

local function invalidate<T>(node: ReactiveNode<T> | SourceNode<T>)
	invalidate_loop(node)

	for _, node in pending_eval do
		for _, dependent in node.depending_on do
			run_as_unsafe(nil, evaluate_node, dependent)
		end

		run_as_unsafe(nil, evaluate_node, node)
	end
	table.clear(pending_eval)
end

graph = {
	-- re-exports of local utilities
	get_scope = get_scope,
	set_scope = set_scope,

	flush_cleanups = flush_cleanups,
	destroy_owned = destroy_owned,

	defer_node = defer_node,

	invalidate = invalidate,
	destroy = destroy,
	run_as_unsafe = run_as_unsafe,
	push_dependency = push_dependency,
	evaluate_node = evaluate_node,
	run_as = run_as,

	new_group = new_group,
	set_group = set_group,
	clear_group = clear_group,
	get_group = get_group,
}

function graph.flush_deferred_nodes()
	for _, node in deferred_nodes do
		local result = evaluate_node(node)

		if result.success == false then
			warn(`deferred node error: {result}`)
		end
	end

	table.clear(deferred_nodes)
end

function graph.create_reactive_node<T>(
	parent: StableNode<T> | false,
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

		children = {} :: { Node<T> },
		cleanups = {},
	}

	if current_group then
		table.insert(current_group, node)
		node_groups[node] = current_group
	end

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

	if current_group then
		table.insert(current_group, node)
		node_groups[node] = current_group
	end

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

	if current_group then
		table.insert(current_group, node)
		node_groups[node] = current_group
	end

	return node
end

function graph.update_source_node<T>(node: SourceNode<T>, value: T)
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

return graph
