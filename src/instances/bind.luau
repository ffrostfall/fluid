local graph = require("../reactive/graph")
local types = require("../reactive/types")

local function set_property(inst: Instance, prop_name: string, value: any)
	(inst :: any)[prop_name] = value
end

local function bind_property<T>(
	inst: Instance,
	property: string,
	value: types.Readable<T>
)
	local first_value = value()

	local property_node = graph.create_reactive_node(
		graph.assert_stable_parent(),
		function()
			set_property(inst, property, value())
			return nil
		end,
		"deferred",
		first_value
	)

	set_property(inst, property, first_value)

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

local function bind(props, inst: Instance)
	-- handle property sets
	for property: number | string, value in props do
		-- we use mixed tables
		if type(property) == "number" then
			continue
		end

		if type(value) == "function" then
			if
				typeof((inst :: any)[property] :: unknown)
				== "RBXScriptSignal"
			then
				bind_event(inst, property, value)
				continue
			end

			bind_property(inst, property, value)
			continue
		else
			set_property(inst, property, value)
		end
	end

	-- handle children
	for key, value in ipairs(props) do
		if typeof(value) ~= "Instance" then
			continue
		end

		value.Parent = inst
	end

	return inst
end

return bind
