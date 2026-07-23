local action = require("./action")
local graph = require("../reactive/graph")
local types = require("../reactive/types")

local function set_property(inst: Instance, property: string, value: any)
	(inst :: any)[property] = value
end

local function get_property(inst: Instance, property: string): any
	return (inst :: any)[property]
end

local function bind_property<T>(inst: Instance, property: string, value: types.Readable<T>)
	local property_node = graph.create_reactive_node(graph.assert_stable_parent(), function()
		set_property(inst, property, value())
		return nil
	end, "eager", nil)

	graph.evaluate_node(property_node)
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
			old_inst.Parent = nil
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
			local children: { new: { [Instance]: true }, current: { [Instance]: true } } = { new = {}, current = {} }

			graph.create_reactive_node(graph.get_scope(), function(value)
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
	local stable_node = graph.get_scope() :: graph.StableNode<unknown>

	local children: { new: { [Instance]: true }, current: { [Instance]: true } } = { new = {}, current = {} }

	local property_node = graph.create_reactive_node(stable_node :: any, function(value)
		return reactive_child_effect(inst, func, value)
	end, "deferred", children)

	graph.evaluate_node(property_node)
end

local function bind(inst: Instance, props: { [unknown & number]: unknown })
	for key: any, value: any in props do
		local key_type, value_type = type(key), typeof(value)

		if key_type == "string" then
			local property_value = get_property(inst, key)
			if typeof(property_value) ~= "RBXScriptSignal" then
				if value_type == "function" then
					bind_property(inst, key, value)
				else
					set_property(inst, key, value)
				end
			elseif value_type == "function" then
				local connection = property_value:Connect(value)

				graph.push_cleanup(graph.assert_scope(), function()
					connection:Disconnect()
				end)
			end
		else
			if value_type == "Instance" then
				print("THIS CODE PATH")
				value.Parent = inst
			elseif value_type == "table" then
				if value.__ACTION_SYMBOL == action.metatable then
					value.callback(inst)
				else
					bind(inst, value)
				end
			elseif value_type == "function" then
				bind_reactive_child(inst, value)
			end
		end
	end
	return inst
end

return bind
