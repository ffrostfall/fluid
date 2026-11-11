local cleanup = require("./cleanup")
local dev = require("../dev")
local exception = require("../utils/exception")
local logging = require("../logging")
local no_yield_call = require("../utils/no_yield_call")
local scheduler = require("../scheduler")
local types = require("./types")

export type SourceNode<T> = {
	--- Version the value last changed at
	last_evaluation: number,
	--- The node's kind and state, see the flags above
	flags: number,
	effect: false,
	cached_value: T,

	--- Other nodes that depend on the result of this node.
	dependents: { Computation<T> },
	--- stores the index of this node in each dependant's depending_on array
	dependent_slots: buffer,
	--- epoch of the last run that read this node, so reading it multiple times in one run doesn't add duplicate edges
	tracked_epoch: number,
}

export type StableNode<T> = {
	last_evaluation: number,
	flags: number,
	effect: false,
	cached_value: T,

	parent: Node<T> | false,
	--- index of this node in its parent's children
	child_index: number,
	children: { Node<T> },
	cleanups: { Cleanup },
}

export type ReactiveNode<T> = {
	last_evaluation: number,
	flags: number,
	--- Describes the effect to run to compute the result of this node.
	effect: types.Effect<T> | false,
	cached_value: T,

	parent: Node<T> | false,
	child_index: number,
	children: { Node<T> },
	cleanups: { Cleanup },

	--- the version the node was last known to be up to date at, deps that changed after it make the node rerun
	verified_at: number,
	depending_on: { SourceNode<T> | ReactiveNode<T> },
	--- stores the index of this node in each dependant's dependents array
	depending_on_slots: buffer,
	--- the epoch of the last run of the node
	epoch: number,
	--- how many dependencies have been read in the current run; reads are matched against depending_on by position,
	--- so edges that are read again in the same order get kept instead of being removed and added again
	tracking_index: number,

	dependents: { Computation<T> },
	dependent_slots: buffer,
	tracked_epoch: number,
}

-- node that runs an effect but never gets read by another node (effect(), deferred(), property bindings, reactive children),
-- so it has nothing for tracking dependents to save memory
export type EffectNode<T> = {
	last_evaluation: number,
	flags: number,
	effect: types.Effect<T> | false,
	cached_value: T,

	parent: Node<T> | false,
	child_index: number,
	children: { Node<T> },
	cleanups: { Cleanup },

	verified_at: number,
	depending_on: { SourceNode<T> | ReactiveNode<T> },
	depending_on_slots: buffer,
	epoch: number,
	tracking_index: number,
}

--- Nodes that run an effect
export type Computation<T> = ReactiveNode<T> | EffectNode<T>

export type Node<T> = ReactiveNode<T> | EffectNode<T> | StableNode<T>

export type CleanupObject = cleanup.CleanupObject
export type Cleanup = cleanup.Cleanup

-- weak so threads that errored or got cancelled while they had a scope can be collected
local processing_nodes: { [thread]: Node<unknown> } = setmetatable({}, { __mode = "ks" })
local deferred_nodes: { Computation<unknown> } = {}
local pending_eval: { Computation<unknown> } = {}
local TOTAL_PENDING_EVAL = 0
local deferred_thread: thread? = nil
local version = 0
-- increments every time a node runs, so reads can tell which run they happened in
local epoch = 0

-- a node's flags hold what kind of node it is in the low bits, and the state it's in above them. the state bits
-- are ordered so most checks are comparisons: below RUNNING is clean, DIRTY and up is dirty or dead.
-- DIRTY and DEAD are never set together

-- the kind of computation a node is, set when it's created. sources and stable nodes don't have one
local EAGER = 1
local DEFERRED = 2
local LAZY = 4
local ASYNC = 8 -- async is similar to eager, but unlike eager it does not actually update the value.
local KIND = EAGER + DEFERRED + LAZY + ASYNC

local RUNNING = 16 -- running its effect right now, reading it returns cached_value
local DIRTY = 32 -- has to be recomputed before cached_value can be used
local DEAD = 64

-- most nodes never get children or cleanups, so they share this until the first one gets added
local EMPTY_TABLE = table.freeze({}) :: { any }

-- slot indexes are stored as u16s in buffers, with the first u16 indicating how many slots the current buffer can hold
local EMPTY_BUFFER = buffer.create(2)
local MAX_SLOTS = 65_535

@native
local function IS_DIRTY_AND_ALIVE<T>(flags: number): boolean
	return flags >= DIRTY and flags < DEAD
end

@native
local function grow_slots(slots: buffer): buffer
	local capacity = buffer.readu16(slots, 0)
	if capacity == MAX_SLOTS then
		logging.error(logging.errors.graph_too_many_edges(MAX_SLOTS))
	end

	local grown_capacity = if capacity == 0 then 8 else math.min(math.ceil(capacity * 1.5), MAX_SLOTS)
	local grown = buffer.create(grown_capacity * 2 + 2)
	buffer.writeu16(grown, 0, grown_capacity)
	buffer.copy(grown, 2, slots, 2)
	return grown
end

@native
local function add_child<T>(parent: Node<T>, node: Node<T>)
	local children = parent.children

	if children == EMPTY_TABLE then
		children = { node }
		parent.children = children
		node.child_index = 1
	else
		local index = #children + 1
		children[index] = node
		node.child_index = index
	end
end

-- swap pops the node out of its parent's children, pointing the child that gets moved into its place at its new index
@native
local function remove_child<T>(parent: Node<T>, node: Node<T>)
	local children = parent.children
	local index = node.child_index
	local last = #children

	if index ~= last then
		local moved = children[last]
		children[index] = moved
		moved.child_index = index
	end

	children[last] = nil
end

local function flush_cleanups<T>(node: Node<T>)
	local cleanups = node.cleanups
	if not cleanups[1] then
		return
	end

	for _, value in cleanups do
		cleanup(value)
	end
	table.clear(cleanups)
end

@native
local function unlink_dependency<T>(node: Computation<T>, index: number, dependency: SourceNode<T> | ReactiveNode<T>)
	local slot = buffer.readu16(node.depending_on_slots, index * 2)
	local dependents = dependency.dependents
	local last = #dependents

	if slot ~= last then
		local dependent_slots = dependency.dependent_slots
		local moved = dependents[last]
		local moved_slot = buffer.readu16(dependent_slots, last * 2)

		dependents[slot] = moved
		buffer.writeu16(dependent_slots, slot * 2, moved_slot)
		buffer.writeu16(moved.depending_on_slots, moved_slot * 2, slot)
	end

	dependents[last] = nil
end

@native
local function remove_dependencies_from<T>(node: Computation<T>, index: number)
	local depending_on = node.depending_on

	for i = #depending_on, index, -1 do
		unlink_dependency(node, i, depending_on[i])
		depending_on[i] = nil
	end
end

@native
local function remove_dependencies<T>(node: Node<T>)
	if node.effect then
		remove_dependencies_from(node, 1)
	end
end

@native
local function bump_version(): number
	version += 1
	return version
end

local function get_scope()
	return processing_nodes[coroutine.running()]
end

local function set_scope(node: Node<any>?)
	processing_nodes[coroutine.running()] = node
end

-- nothing run in a scope returns more than 2 values (e.g. for_keys transforms return the result and a delay),
-- so they're hardcoded instead of passing a vararg pack through
local function run_as_unsafe<A, B, U...>(node: Node<any>?, fn: (U...) -> (A, B), ...: U...): (A, B)
	local co = coroutine.running()
	local old = processing_nodes[co]
	processing_nodes[co] = node

	local a, b = fn(...)

	processing_nodes[co] = old
	return a, b
end

-- dev mode runs reactive functions on a fresh thread from no_yield_call, so there's no previous scope to restore.
local function run_on_new_thread<T, U...>(node: Node<any>?, fn: (U...) -> T, ...: U...): T
	processing_nodes[coroutine.running()] = node
	return fn(...)
end

-- mutable tables are never similar so mutating a table and setting it again pushes an update,
-- frozen tables are compared by reference. checks == first since most updates are changes
@native
local function is_similar(a: unknown, b: unknown): boolean
	return a == b and (type(a) ~= "table" or table.isfrozen(a :: {}) or table.isfrozen(b :: {}))
end

@native
local function push_dependency_to_active_scope<T>(node: SourceNode<T> | ReactiveNode<T>)
	local scope = get_scope()
	if not (scope and scope.effect) then
		return
	end

	-- already read during this run. if another node read it in between this just adds a duplicate edge, which is harmless
	local scope_epoch = scope.epoch
	if node.tracked_epoch == scope_epoch then
		return
	end
	node.tracked_epoch = scope_epoch

	if scope == node then
		error("node tried to add itself as dependency")
	end

	local depending_on = scope.depending_on
	local index = scope.tracking_index + 1
	scope.tracking_index = index

	-- nodes usually read the same dependencies in the same order every run, so the edge from the last run can be kept
	local existing = depending_on[index]
	if existing == node then
		return
	end

	local dependents = node.dependents
	local slot = #dependents + 1

	local depending_on_slots = scope.depending_on_slots

	if index > buffer.readu16(depending_on_slots, 0) then
		depending_on_slots = grow_slots(depending_on_slots)
		scope.depending_on_slots = depending_on_slots
	end

	local dependent_slots = node.dependent_slots
	if slot > buffer.readu16(dependent_slots, 0) then
		dependent_slots = grow_slots(dependent_slots)
		node.dependent_slots = dependent_slots
	end

	if existing then
		unlink_dependency(scope, index, existing)
	end

	depending_on[index] = node
	dependents[slot] = scope
	buffer.writeu16(depending_on_slots, index * 2, slot)
	buffer.writeu16(dependent_slots, slot * 2, index)
end

@native
local function node_destroy<T>(node: Node<T>)
	-- marked dead so it can't rerun if it's still queued in pending_eval / deferred_nodes
	node.flags = bit32.band(node.flags, KIND) + DEAD
	flush_cleanups(node)
	remove_dependencies(node)

	local parent = node.parent
	if parent then
		remove_child(parent, node)
		node.parent = false
	end

	-- destroying a child removes it from children, so this empties it
	local children = node.children
	while children[1] do
		node_destroy(children[1])
	end
end

@native
local function node_destroy_owned<T>(node: Node<T>)
	local children = node.children
	while children[1] do
		node_destroy(children[1])
	end
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

local function graph_run_as<T, U...>(node: Node<any>?, fn: (U...) -> T, ...: U...): (boolean, T)
	if dev.enabled and not (node and bit32.band(node.flags, ASYNC) ~= 0) then
		return no_yield_call(run_on_new_thread, effect_err, effect_yield, node, fn, ...)
	end

	local co = coroutine.running()
	local previous_processing = processing_nodes[co]
	processing_nodes[co] = node

	local ok, result = xpcall(fn, effect_err, ...)

	processing_nodes[co] = previous_processing
	return ok, result
end

@native
local function graph_defer_node<T>(node: Computation<T>)
	local flags = node.flags
	-- already queued, or dead
	if flags >= DIRTY then
		return
	end
	node.flags = flags + DIRTY
	table.insert(deferred_nodes, node)

	if not deferred_thread then
		deferred_thread = scheduler.defer(graph.flush_deferred_nodes)
	end
end

@native
local function graph_update_node<T>(node: Computation<T>)
	local depending_on = node.depending_on
	local verified_at = node.verified_at
	local should_reevaluate = #depending_on == 0

	for _, dependency in depending_on do
		-- the dependency changed since this node was last up to date
		if dependency.last_evaluation > verified_at then
			should_reevaluate = true
			break
		end

		-- the dependency is dirty, so we have to reevaluate that dependency. one that's mid evaluation
		-- (e.g. its effect set a source this node depends on) just keeps its cached value
		local dependency_flags = dependency.flags
		if dependency_flags >= DIRTY and dependency_flags < DEAD then
			graph_update_node(dependency :: ReactiveNode<T>)

			-- the dependency can own this node, rerunning it destroys this node
			if node.flags >= DEAD then
				return
			end

			if dependency.last_evaluation > verified_at then
				should_reevaluate = true
				break
			end
		end
	end

	local kind = bit32.band(node.flags, KIND)

	if not should_reevaluate then
		node.flags = kind
		node.verified_at = version
		return
	end

	-- untrack() swaps the effect out while it runs, so it has to be restored if it errored
	local effect = node.effect :: types.Effect<T>

	if node.cleanups[1] then
		flush_cleanups(node)
	end
	if node.children[1] then
		node_destroy_owned(node)
	end

	-- dependencies are kept, and matched against what gets read during this run
	epoch += 1
	node.epoch = epoch
	node.tracking_index = 0

	local evaluated_at = version
	node.flags = kind + RUNNING
	local previous_result = node.cached_value
	local success, res = graph_run_as(node, effect, previous_result)
	node.effect = effect

	local flags = node.flags
	local destroyed = flags >= DEAD
	if destroyed then
		-- destroyed by its own effect, anything it read afterwards shouldn't stay subscribed
		remove_dependencies(node)
	else
		-- anything that wasn't read this run isn't a dependency anymore
		remove_dependencies_from(node, node.tracking_index + 1)
		-- if it got invalidated while running (e.g. it set a source it depends on), changes
		-- made during the run still have to count as newer
		node.verified_at = if flags >= DIRTY then evaluated_at else version
		-- we mark it as clean and bump the evaluation value since we don't
		-- want to re-run the node even if it errored
		node.flags = kind
	end

	if not success then
		error((res :: any).trace)
	end

	if destroyed or kind == ASYNC then
		return
	elseif kind == LAZY then
		-- only lazy nodes get read by other nodes, so they're the only ones that need to track when their
		-- value changed. eager and deferred nodes just keep it as the previous value for their next run
		if is_similar(previous_result, res) then
			return
		end

		node.last_evaluation = bump_version()
	end

	node.cached_value = res
end

-- brings a node up to date without tracking it as a dependency of anything
@native
local function refresh_node<T>(node: Computation<T>): T
	if IS_DIRTY_AND_ALIVE(node.flags) then
		graph_update_node(node)
	end

	return node.cached_value
end

@native
local function graph_evaluate_node<T>(node: SourceNode<T> | ReactiveNode<T>): T
	local flags = node.flags

	-- sources are always clean
	if flags >= RUNNING then
		if IS_DIRTY_AND_ALIVE(flags) then
			graph_update_node(node :: ReactiveNode<T>)
		else
			-- dead, or mid evaluation. reading a node while it's evaluating can happen without a
			-- recursive dependency (e.g. its effect sets a source something reading it depends on)
			return node.cached_value
		end
	end

	push_dependency_to_active_scope(node)
	return node.cached_value
end

-- brings a node up to date outside of whatever's reading, reporting errors instead of unwinding the caller
local function evaluate_detached<T>(node: Computation<T>)
	local success, err = xpcall(refresh_node, effect_err, node)

	if not success then
		-- if a dependency errored, the node never got to run. it has to be marked clean
		-- since dirty nodes don't get queued again, otherwise it'd never update again
		local flags = node.flags
		if IS_DIRTY_AND_ALIVE(flags) then
			node.flags = bit32.band(flags, KIND)
		end

		logging.report_error((err :: any).trace)
	end
end

@native
local function graph_invalidate_loop<T>(node: SourceNode<T> | ReactiveNode<T>)
	for _, dependent in node.dependents do
		local flags = dependent.flags
		-- already invalidated through another path, or dead
		if flags >= DIRTY then
			continue
		end

		local kind = bit32.band(flags, KIND)
		if kind == DEFERRED then
			graph_defer_node(dependent)
		else
			dependent.flags = flags + DIRTY

			if kind ~= LAZY then
				TOTAL_PENDING_EVAL += 1
				pending_eval[TOTAL_PENDING_EVAL] = dependent
			end

			-- eager and deferred nodes are never read, so only lazy and async nodes can have dependents to invalidate
			if kind ~= EAGER then
				-- the solver can't refine through the kind local, only reactive nodes are lazy or async
				graph_invalidate_loop(dependent :: ReactiveNode<T>)
			end
		end
	end
end

@native
local function invalidate<T>(node: ReactiveNode<T> | SourceNode<T>)
	-- an invalidation that happens while evaluating (e.g. an effect setting a source) only evaluates what it
	-- queued itself, the rest is left to the outer invalidation. otherwise every nested one would evaluate
	-- the rest of the queue inside of it, which overflows the stack with enough nodes
	local start = TOTAL_PENDING_EVAL + 1
	graph_invalidate_loop(node)
	-- nested invalidations push after this and set TOTAL_PENDING_EVAL back before returning, so this stays the end
	local finish = TOTAL_PENDING_EVAL

	for idx = start, finish do
		local pending = pending_eval[idx]

		-- dependencies get evaluated first, so an erroring dependency doesn't stop the node itself from running.
		-- sources are always clean, so they're skipped by the flags check
		for _, dependency in pending.depending_on do
			if IS_DIRTY_AND_ALIVE(dependency.flags) then
				evaluate_detached(dependency :: ReactiveNode<T>)

				-- the dependency can own this node, rerunning it destroys this node
				if pending.flags >= DEAD then
					break
				end
			end
		end

		evaluate_detached(pending)
	end

	for idx = finish, start, -1 do
		pending_eval[idx] = nil
	end

	TOTAL_PENDING_EVAL = start - 1
end

function graph.flush_deferred_nodes()
	deferred_thread = nil

	for _, node in deferred_nodes do
		evaluate_detached(node)
	end

	table.clear(deferred_nodes)
end

@native
function graph.create_reactive_node<T>(
	parent: Node<T> | false,
	effect: types.Effect<T> | false,
	evaluation: number,
	cached_value: T
): ReactiveNode<T>
	local node: ReactiveNode<T> = {
		last_evaluation = bump_version(),
		flags = evaluation + DIRTY,
		effect = effect,
		cached_value = cached_value,

		parent = parent,
		child_index = 0,
		children = EMPTY_TABLE,
		cleanups = EMPTY_TABLE,

		verified_at = 0,
		depending_on = {},
		depending_on_slots = EMPTY_BUFFER,
		epoch = 0,
		tracking_index = 0,

		dependents = {},
		dependent_slots = EMPTY_BUFFER,
		tracked_epoch = 0,
	}

	if parent then
		add_child(parent, node)
	end

	if evaluation == DEFERRED then
		table.insert(deferred_nodes, node)
	end

	return node
end

@native
function graph.create_effect_node<T>(
	parent: Node<T> | false,
	effect: types.Effect<T>,
	evaluation: number, -- only EAGER or DEFERRED are allowed
	cached_value: T
): EffectNode<T>
	local node: EffectNode<T> = {
		last_evaluation = 0,
		flags = evaluation + DIRTY,
		effect = effect,
		cached_value = cached_value,

		parent = parent,
		child_index = 0,
		children = EMPTY_TABLE,
		cleanups = EMPTY_TABLE,

		verified_at = 0,
		depending_on = {},
		depending_on_slots = EMPTY_BUFFER,
		epoch = 0,
		tracking_index = 0,
	}

	if parent then
		add_child(parent, node)
	end

	if evaluation == DEFERRED then
		table.insert(deferred_nodes, node)
	end

	return node
end

@native
function graph.create_stable_node<T>(parent: Node<T> | false)
	local node: StableNode<T> = {
		last_evaluation = bump_version(),
		flags = 0,
		effect = false,
		cached_value = nil,

		parent = parent,
		child_index = 0,
		children = EMPTY_TABLE,
		cleanups = EMPTY_TABLE,
	}

	if parent then
		add_child(parent, node)
	end

	return node
end

@native
function graph.create_source_node<T>(value: T): SourceNode<T>
	local node: SourceNode<T> = {
		last_evaluation = bump_version(),
		flags = 0,
		effect = false,
		cached_value = value,

		dependents = {},
		dependent_slots = EMPTY_BUFFER,
		tracked_epoch = 0,
	}

	return node
end

@native
function graph.update_node<T>(node: ReactiveNode<T> | SourceNode<T>, value: T)
	if is_similar(node.cached_value, value) then
		return
	end
	node.last_evaluation = bump_version()
	node.cached_value = value
	invalidate(node)
end

@native
function graph.push_cleanup<T>(scope: Node<T>, value: Cleanup)
	local cleanups = scope.cleanups
	if cleanups == EMPTY_TABLE then
		scope.cleanups = { value }
	else
		table.insert(cleanups, value)
	end
end

function graph.assert_scope<T>(): Node<T>
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
graph.refresh_node = refresh_node
graph.run_as = graph_run_as
graph.evaluation = table.freeze({
	DEFERRED = DEFERRED,
	EAGER = EAGER,
	ASYNC = ASYNC,
	LAZY = LAZY,
})

return table.freeze(graph)
