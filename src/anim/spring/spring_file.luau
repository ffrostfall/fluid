--[[
	Temporarily named this until luau language server fixes issue
]]
local coefficients = require("./coefficients")
local graph = require("../../reactive/graph")
local oklab = require("../../utils/oklab")
local read = require("../../utils/read")
local types = require("../../reactive/types")

local SLEEP_VELOCITY = 1e-3
local SLEEP_DISTANCE = 1e-5

type AnimatableDataTypeEnum = "color" | "vector" | "udim" | "udim2" | "number"
type AnimatableDataType = Color3 | vector | UDim | UDim2 | number

-- In order to support springing multiple data types, we need to abstract values into an array.
-- It sucks, but it is necessary to support things like UDim2 and Color3.
type SpringValue = { number }

type SpringState = {
	position: SpringValue,
	velocity: SpringValue,
	target: SpringValue,

	datatype: AnimatableDataTypeEnum,
	elements: number, -- 1-6

	damping: number,
	speed: number,

	unpacked_value: AnimatableDataType,
}

type SpringControls<T> = {
	position: T?,
	impulse: T?,
	velocity: T?,
}

local active_springs: { [SpringState]: graph.SourceNode<AnimatableDataType> } = {}

local function pack_type(value: AnimatableDataType): (AnimatableDataTypeEnum, { number })
	if typeof(value) == "Color3" then
		-- oklab conversion
		local intermediate_vector = oklab.from_srgb(vector.create(value.R, value.G, value.B))

		return "color",
			{
				intermediate_vector.x,
				intermediate_vector.y,
				intermediate_vector.z,
			}
	elseif typeof(value) == "UDim2" then
		return "udim2", { value.X.Scale, value.X.Offset, value.Y.Scale, value.Y.Offset }
	elseif typeof(value) == "UDim" then
		return "udim", { value.Scale, value.Offset }
	elseif type(value) == "vector" then
		return "vector", { value.x, value.y, value.z }
	elseif type(value) == "number" then
		return "number", { value }
	end

	error(`tried tweening {typeof(value)}`)
end

local function unpack_type(
	type_string: AnimatableDataTypeEnum,
	array: { number }
): AnimatableDataType
	if type_string == "color" then
		-- oklab conversion
		local intermediate_vector = vector.clamp(
			oklab.to_srgb(vector.create(array[1], array[2], array[3])),
			vector.zero,
			vector.one
		)

		return Color3.new(intermediate_vector.x, intermediate_vector.y, intermediate_vector.z)
	elseif type_string == "vector" then
		return vector.create(array[1], array[2], array[3])
	elseif type_string == "udim" then
		return UDim.new(array[1], array[2])
	elseif type_string == "udim2" then
		return UDim2.new(array[1], array[2], array[3], array[4])
	elseif type_string == "number" then
		return array[1]
	end

	return error("unreachable")
end

local function subtract(a: { number }, b: { number })
	local c = table.clone(a)
	for idx, value in c do
		c[idx] = value - b[idx]
	end
	return c
end

local function magnitude(a: { number })
	local d = 0
	for idx, value in a do
		d += value ^ 2
	end
	return d
end

local function step_spring<T>(state: SpringState, delta_time: number)
	local pos_pos, pos_vel, vel_pos, vel_vel = coefficients(delta_time, state.damping, state.speed)
	local low_velocity = true

	-- iterate and solve the spring for each value in our SpringValue
	for i = 1, state.elements do
		local start_pos = state.position[i]
		local target_pos = state.target[i]
		local start_vel = state.velocity[i]
		local start_delta = start_pos - target_pos

		-- todo: vectorize?
		local next_delta = (start_delta * pos_pos) + (start_vel * pos_vel)
		local next_velocity = (start_delta * vel_pos) + (start_vel * vel_vel)

		if next_delta ~= next_delta or next_velocity ~= next_velocity then
			warn("nan")
			next_delta, next_velocity = 0, 0
		end

		local next_position = next_delta + target_pos

		state.position[i] = next_position
		state.velocity[i] = next_velocity

		if next_velocity > SLEEP_VELOCITY then
			low_velocity = false
		end
	end

	if low_velocity and magnitude(subtract(state.position, state.target)) < SLEEP_DISTANCE then
		for i = 1, state.elements do
			state.position[i] = state.target[i]
			state.velocity[i] = 0
		end
		active_springs[state] = nil
	end

	state.unpacked_value = unpack_type(state.datatype, state.position)
end

local spring_file = {}

function spring_file.create<T>(
	input: types.UsedAs<T>,
	speed: number,
	damping: number
): (() -> read.CastIntoValue<T>, (SpringControls<T>) -> ())
	-- initialize spring state early so we can reference it in the effect for the output node
	graph.set_group(graph.new_group("spring"))

	local output = graph.create_source_node(read(input))

	local call = graph.evaluate_node(output)
	assert(call.success)

	local starting_value_string, starting_value = pack_type(call.value :: any)

	local spring_state: SpringState = {
		position = starting_value,
		velocity = table.create(#starting_value, 0),
		target = starting_value,

		elements = #starting_value,
		datatype = starting_value_string,

		speed = speed,
		damping = damping,

		unpacked_value = call.value :: any,
	}

	local function on_update()
		local input_as_value = read(input)

		local datatype, array = pack_type(input_as_value)
		assert(datatype == spring_state.datatype, "Can't switch the data types of a spring")

		spring_state.target = array

		-- need luau feature: bounded generics
		active_springs[spring_state] = output :: any

		return nil
	end

	-- set up the dependency
	local input_node = graph.create_reactive_node(
		graph.assert_stable_parent(),
		on_update,
		"deferred",
		read(input)
	)

	graph.evaluate_node(input_node)
	graph.clear_group()

	return function()
		graph.push_dependency(output)
		return output.cached_value
	end, function(controls: SpringControls<T>)
		on_update()

		if controls.position then
			local datatype, array = pack_type(controls.position)
			assert(datatype == spring_state.datatype, "Can't switch the data types of a spring")
			spring_state.position = array
		end

		if controls.velocity then
			local datatype, array = pack_type(controls.velocity)
			assert(datatype == spring_state.datatype, "Can't switch the data types of a spring")
			spring_state.velocity = array
		end

		if controls.impulse then
			local datatype, array = pack_type(controls.impulse)
			assert(datatype == spring_state.datatype, "Can't switch the data types of a spring")
			for i = 1, #array do
				spring_state.velocity[i] += array[i]
			end
		end
	end
end

function spring_file.step(delta_time: number)
	for spring_state, node in active_springs do
		step_spring(spring_state, delta_time)
		graph.update_source_node(node, spring_state.unpacked_value)
	end
end

return spring_file
