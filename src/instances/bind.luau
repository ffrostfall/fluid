local action = require("./action")
local graph = require("../reactive/graph")
local types = require("../reactive/types")

type Result = Instance | { Result } | () -> Result

type ReactiveChild = {
	children: { [Instance]: number }, -- [child]: update said child was last in the result of
	callback: () -> Result,
	instance: Instance,
	update_id: number,
}

local DEFERRED = graph.evaluation.DEFERRED
local EAGER = graph.evaluation.EAGER
local EVENTS = table.create<<RBXScriptSignal | () -> ()>>(20)
local TOTAL_EVENTS = 0

local function set_property(inst: Instance, property: string, value: any)
	(inst :: any)[property] = value
end

local function get_property(inst: Instance, property: string): any
	return (inst :: any)[property]
end

local function bind_property<T>(inst: Instance, property: string, value: types.Readable<T>)
	local property_node = graph.create_effect_node(graph.assert_stable_parent(), function()
		set_property(inst, property, value())
		return nil
	end, EAGER, nil)

	graph.refresh_node(property_node)
end

local reactive_child_effect: (reactive_child: ReactiveChild) -> ReactiveChild

local function process_child(instance: Instance, children: { [Instance]: number }, update_id: number, child: Result)
	if typeof(child) == "Instance" then
		local seen = children[child]
		-- already parented if it's in the result more than once
		if seen == update_id then
			return
		end

		children[child] = update_id

		if not seen then
			child.Parent = instance
		end
		return
	end

	if typeof(child) == "function" then
		local scope = graph.assert_scope()
		local reactive_child: ReactiveChild = { instance = instance, callback = child, children = {}, update_id = 0 }

		graph.create_effect_node(scope :: any, reactive_child_effect, DEFERRED, reactive_child)
		graph.push_cleanup(scope, function()
			for child in reactive_child.children do
				child.Parent = nil
			end
		end)
		return
	end

	for _, nested_child in child do
		process_child(instance, children, update_id, nested_child)
	end
end

function reactive_child_effect(reactive_child: ReactiveChild): ReactiveChild
	local children = reactive_child.children
	local update_id = reactive_child.update_id + 1
	reactive_child.update_id = update_id

	local result = reactive_child.callback()
	if result then
		process_child(reactive_child.instance, children, update_id, result)
	end

	-- removes the children that weren't in this result
	for child, seen in children do
		if seen ~= update_id then
			children[child] = nil
			child.Parent = nil
		end
	end

	return reactive_child
end

local function bind_reactive_child(instance: Instance, func: () -> Result)
	local reactive_child: ReactiveChild = { instance = instance, callback = func, children = {}, update_id = 0 }
	local property_node =
		graph.create_effect_node(graph.get_scope() :: any, reactive_child_effect, DEFERRED, reactive_child)

	graph.refresh_node(property_node)
end

local function bind(instance: Instance, props: { [unknown & number]: unknown })
	local parent: (Instance | () -> Instance)?
	-- starting index for the event connections being attached to this instance in the EVENTS array
	local events_start = TOTAL_EVENTS

	for key: any, value: any in props do
		local value_type = typeof(value)
		local key_type = type(key)

		if key_type == "string" then
			if key == "Parent" then
				parent = value
			-- only functions can be event handlers, so other values skip reading the property
			elseif value_type ~= "function" then
				set_property(instance, key, value)
			else
				local property_value = get_property(instance, key)

				if typeof(property_value) ~= "RBXScriptSignal" then
					bind_property(instance, key, value)
				else
					TOTAL_EVENTS += 1
					EVENTS[TOTAL_EVENTS] = property_value
					TOTAL_EVENTS += 1
					EVENTS[TOTAL_EVENTS] = value
				end
			end
		else
			if value_type == "Instance" then
				value.Parent = instance
			elseif value_type == "table" then
				if value.__ACTION_SYMBOL == action.symbol then
					value.callback(instance)
				else
					bind(instance, value)
				end
			elseif value_type == "function" then
				bind_reactive_child(instance, value)
			end
		end
	end

	-- connecting events last so that property setting during construction can't trigger events before the instance is parented
	if TOTAL_EVENTS ~= events_start then
		local scope = graph.assert_scope()

		-- iterating backwards so each pair can be cleared right after it's connected
		-- without luau converting the EVENTS array into a hash
		for index = TOTAL_EVENTS, events_start + 2, -2 do
			local event_index = index - 1
			graph.push_cleanup(scope, (EVENTS[event_index] :: RBXScriptSignal):Connect(EVENTS[index] :: () -> ()))
			EVENTS[index] = nil
			EVENTS[event_index] = nil
		end

		TOTAL_EVENTS = events_start
	end

	-- setting parent last to avoid datamodel change tracking whilst the instance is being constructed
	if parent then
		if type(parent) == "function" then
			bind_property(instance, "Parent", parent)
		else
			instance.Parent = parent
		end
	end

	return instance
end

return bind
