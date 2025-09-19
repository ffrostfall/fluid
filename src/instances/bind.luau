local action = require("./action")
local graph = require("../reactive/graph")
local types = require("../reactive/types")

type PropertyPair<T> = {
	tag: "property",
	name: string,
	value: T,
}

type ReactivePropertyPair<T> = {
	tag: "reactive_property",
	name: string,
	value: () -> T,
}

type EventPair<T...> = {
	tag: "event",
	name: string,
	event: (T...) -> (),
}

type ActionPair = {
	tag: "action",
	action: action.Identity,
}

type ChildPair = {
	tag: "child",
	value: Instance,
}

type ReactiveChildPair = {
	tag: "reactive_child",
	value: () -> Instance | { Instance },
}

type Pair =
	| ReactivePropertyPair<unknown>
	| PropertyPair<unknown>
	| EventPair<unknown>
	| ReactiveChildPair
	| ActionPair
	| ChildPair

local function set_property(inst: Instance, property: string, value: any)
	(inst :: any)[property] = value
end

local function get_property(inst: Instance, property: string): any
	return (inst :: any)[property]
end

local function bind_property<T>(inst: Instance, property: string, value: types.Readable<T>)
	graph.set_group(graph.new_group(`bind "{property}"`))
	local property_node = graph.create_reactive_node(graph.assert_stable_parent(), function()
		set_property(inst, property, value())
		return nil
	end, "deferred", nil)

	graph.evaluate_node(property_node)
	graph.clear_group()
end

local function bind_event(inst: Instance, event_name: string, func: <T...>(T...) -> ())
	local event = (inst :: any)[event_name] :: RBXScriptSignal
	local connection = event:Connect(func :: any)

	graph.push_cleanup(graph.assert_scope(), function()
		connection:Disconnect()
	end)
end

type Result = Instance | { Result } | () -> Result

local function reactive_child_effect(
	inst: Instance,
	func: () -> Result,
	sets: {
		new: { [Instance]: true },
		current: { [Instance]: true },
	}
)
	local new_child_set = sets.new
	local current_child_set = sets.current
	local source_result = func()

	if not source_result then
		for old_inst in current_child_set do
			old_inst:Destroy()
		end

		return sets
	end

	local function process_child(child: Result)
		if typeof(child) == "Instance" then
			new_child_set[child] = true

			if current_child_set[child] then
				current_child_set[child] = nil
				return
			end

			child.Parent = inst
			return
		end

		if typeof(child) == "function" then
			local children: { new: { [Instance]: true }, current: { [Instance]: true } } =
				{ new = {}, current = {} }

			graph.create_reactive_node(graph.get_scope() :: any, function(value)
				return reactive_child_effect(inst, child, value)
			end, "deferred", children)

			graph.push_cleanup(graph.get_scope(), function()
				for child in children.current do
					child.Parent = nil
				end
			end)

			return
		end

		for _, child in child do
			process_child(child)
		end

		return
	end

	process_child(source_result)

	for child in current_child_set do
		child.Parent = nil
	end

	table.clear(current_child_set)
	sets.current, sets.new = new_child_set, current_child_set

	return sets
end

local function bind_reactive_child(inst: Instance, func: () -> Result)
	graph.set_group(graph.new_group("children"))
	local stable_node = graph.get_scope() :: graph.StableNode<unknown>

	local children: { new: { [Instance]: true }, current: { [Instance]: true } } =
		{ new = {}, current = {} }

	local property_node = graph.create_reactive_node(stable_node :: any, function(value)
		return reactive_child_effect(inst, func, value)
	end, "deferred", children)

	graph.evaluate_node(property_node)
	graph.clear_group()
end

local function evaluate(
	inst: Instance,
	props: { [unknown & number]: unknown },
	existing_array: { Pair }?
): { Pair }
	local resulting_array: { Pair } = existing_array or {}

	for key, value in props do
		local value_is_action = action.is_action(value :: any)

		if type(key) == "number" and type(value) == "table" and value_is_action then
			table.insert(resulting_array, {
				tag = "action",
				action = value,
			})
		elseif type(key) == "number" and type(value) == "table" and not value_is_action then
			evaluate(inst, value :: any, resulting_array)
		elseif type(key) == "number" and type(value) == "function" then
			table.insert(resulting_array, {
				tag = "reactive_child",
				value = value,
			})
		elseif type(key) == "string" and typeof(get_property(inst, key)) == "RBXScriptSignal" then
			table.insert(resulting_array, {
				tag = "event",
				name = key,
				event = value,
			})
		elseif
			type(key) == "string"
			and typeof(get_property(inst, key)) ~= "RBXScriptSignal"
			and type(value) == "function"
		then
			table.insert(resulting_array, {
				tag = "reactive_property",
				name = key,
				value = value,
			})
		elseif
			type(key) == "string"
			and typeof(get_property(inst, key)) ~= "RBXScriptSignal"
			and type(value) ~= "function"
		then
			table.insert(resulting_array, {
				tag = "property",
				name = key,
				value = value,
			})
		elseif typeof(value) == "Instance" then
			table.insert(resulting_array, {
				tag = "child",
				value = value,
			})
		end
	end

	return resulting_array
end

local function bind(inst: Instance, props: { [unknown & number]: unknown })
	local pairings = evaluate(inst, props)
	local parent: (ReactivePropertyPair<Instance> | PropertyPair<Instance>)? = nil

	for _, pairing in pairings do
		if
			(pairing.tag == "property" or pairing.tag == "reactive_property")
			and pairing.name == "Parent"
		then
			parent = pairing :: any
			continue
		end

		if pairing.tag == "property" then
			set_property(inst, pairing.name, pairing.value)
		elseif pairing.tag == "reactive_property" then
			bind_property(inst, pairing.name, pairing.value)
		elseif pairing.tag == "event" then
			bind_event(inst, pairing.name, pairing.event)
		elseif pairing.tag == "child" then
			pairing.value.Parent = inst
		elseif pairing.tag == "reactive_child" then
			bind_reactive_child(inst, pairing.value)
		elseif pairing.tag == "action" then
			pairing.action.callback(inst)
		else
			error("unreachable")
		end
	end

	if parent and parent.tag == "reactive_property" then
		bind_property(inst, "Parent", parent.value)
	elseif parent and parent.tag == "property" then
		set_property(inst, "Parent", parent.value)
	end

	return inst
end

return bind
