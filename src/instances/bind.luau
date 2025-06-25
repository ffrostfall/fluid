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

local function bind_property<T>(
	inst: Instance,
	property: string,
	value: types.Readable<T>
)
	local property_node = graph.create_reactive_node(
		graph.assert_stable_parent(),
		function()
			set_property(inst, property, value())
			return nil
		end,
		"deferred",
		nil
	)

	graph.evaluate_node(property_node)
end

local function bind_event(
	inst: Instance,
	event_name: string,
	func: <T...>(T...) -> ()
)
	local event = (inst :: any)[event_name] :: RBXScriptSignal
	local connection = event:Connect(func :: any)

	graph.push_cleanup(graph.assert_scope(), function()
		connection:Disconnect()
	end)
end

local function bind_reactive_child(
	inst: Instance,
	func: () -> { Instance } | Instance
)
	local stable_node = graph.assert_stable_parent()

	-- Walk up the parent chain to find destroy delay
	local function find_delay(
		node: graph.StableNode<any> | graph.ReactiveNode<any>
	): number
		if node.delay_destroy and node.delay_destroy > 0 then
			return node.delay_destroy
		end

		local children = node.children
		if next(children) then
			for _, children_node in children do
				return find_delay(children_node)
			end
		end

		return 0
	end

	local delay_destroy: number = find_delay(stable_node)

	local property_node = graph.create_reactive_node(
		stable_node,
		function(value: { [Instance]: true })
			local source_result = func()

			if typeof(source_result) == "Instance" then
				if value[source_result] then
					return value
				end

				source_result.Parent = inst
				value[source_result] = true
				return value
			end

			for _, source_inst in source_result do
				if value[source_inst] then
					continue
				end

				value[source_inst] = true
				source_inst.Parent = inst
			end

			for old_inst in value do
				if not table.find(source_result, old_inst) then
					task.delay(delay_destroy, old_inst.Destroy, old_inst)
					value[old_inst] = nil
				end
			end

			return value
		end,
		"deferred",
		{}
	)

	graph.evaluate_node(property_node)
end

local function evaluate(
	inst: Instance,
	props: { [unknown]: unknown },
	existing_array: { Pair }?
): { Pair }
	local resulting_array: { Pair } = existing_array or {}

	for key, value in props do
		local value_is_action = action.is_action(value :: any)

		if
			type(key) == "number"
			and type(value) == "table"
			and value_is_action
		then
			table.insert(resulting_array, {
				tag = "action",
				action = value,
			})
		elseif
			type(key) == "number"
			and type(value) == "table"
			and not value_is_action
		then
			evaluate(inst, value :: any, resulting_array)
		elseif type(key) == "number" and type(value) == "function" then
			table.insert(resulting_array, {
				tag = "reactive_child",
				value = value,
			})
		elseif
			type(key) == "string"
			and typeof(get_property(inst, key)) == "RBXScriptSignal"
		then
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

local function bind(inst: Instance, props: { [unknown]: unknown })
	local pairings = evaluate(inst, props)
	local parent: (ReactivePropertyPair<Instance> | PropertyPair<Instance>)? =
		nil

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
