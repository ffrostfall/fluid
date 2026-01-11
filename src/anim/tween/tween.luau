local easings = require("./easings")
local graph = require("../../reactive/graph")
local oklab = require("../../utils/oklab")
local read = require("../../utils/read")
local types = require("../../reactive/types")

type AnimatableDataTypeEnum = "color" | "vector" | "udim" | "udim2" | "number"
type AnimatableDataType = Color3 | vector | UDim | UDim2 | number

type TweenValue = { number }

type TweenState = {
	position: TweenValue,
	target: TweenValue,
	start: TweenValue,
	elapsed: number,

	tween_time: number,
	tween_style: Enum.EasingStyle,
	tween_direction: Enum.EasingDirection,

	datatype: AnimatableDataTypeEnum,
	elements: number,

	unpacked_value: AnimatableDataType,
}

type TweenControls<T> = {
	position: T?,
	target: T?,
	tween_info: TweenInfo?,
}

local active_tweens: { [TweenState]: graph.SourceNode<AnimatableDataType> } = {}

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

local function step_tween(state: TweenState, delta_time: number)
	state.elapsed = math.min(state.elapsed + delta_time, state.tween_time)

	local easing_function = easings[state.tween_style][state.tween_direction]
	local alpha = state.tween_time == 0 and 1 or easing_function(state.elapsed / state.tween_time)

	for i = 1, state.elements do
		state.position[i] = state.start[i] + (state.target[i] - state.start[i]) * alpha
	end

	if state.elapsed >= state.tween_time then
		active_tweens[state] = nil
	end

	state.unpacked_value = unpack_type(state.datatype, state.position)
end

local tween_file = {}

function tween_file.create<T>(
	input: types.UsedAs<T>,
	tween_info: TweenInfo
): (() -> read.CastIntoValue<T>, (TweenControls<T>) -> ())
	graph.set_group(graph.new_group("tween"))

	local output = graph.create_source_node(read(input))

	local call = graph.evaluate_node(output)
	assert(call.success)

	local starting_value_string, starting_value = pack_type(call.value :: any)

	local tween_state: TweenState = {
		position = starting_value,
		target = starting_value,
		start = starting_value,
		elapsed = 0,

		tween_time = tween_info.Time,
		tween_style = tween_info.EasingStyle,
		tween_direction = tween_info.EasingDirection,

		elements = #starting_value,
		datatype = starting_value_string,

		unpacked_value = call.value :: any,
	}

	local function on_update()
		local input_as_value = read(input)
		local datatype, array = pack_type(input_as_value)
		assert(datatype == tween_state.datatype, "Can't switch the data types of a tween")

		tween_state.target = array
		tween_state.start = table.clone(tween_state.position)
		tween_state.elapsed = 0

		active_tweens[tween_state] = output :: any

		return nil
	end

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
		return output.cached_value :: any
	end, function(controls: TweenControls<T>)
		on_update()

		local reset = false

		if controls.position then
			local datatype, array = pack_type(controls.position)
			assert(datatype == tween_state.datatype, "Can't switch the data types of a tween")
			tween_state.position = array
			tween_state.start = array
			reset = true
		end

		if controls.target then
			local datatype, array = pack_type(controls.target)
			assert(datatype == tween_state.datatype, "Can't switch the data types of a tween")
			tween_state.target = array
			tween_state.start = table.clone(tween_state.position)
			reset = true
		end

		if controls.tween_info then
			tween_state.tween_time = controls.tween_info.Time
			tween_state.tween_style = controls.tween_info.EasingStyle
			tween_state.tween_direction = controls.tween_info.EasingDirection
			reset = true
		end

		if reset then
			tween_state.elapsed = 0
			active_tweens[tween_state] = output :: any
		end
	end
end

function tween_file.step(delta_time: number)
	for tween_state, node in active_tweens do
		step_tween(tween_state, delta_time)
		graph.update_source_node(node, tween_state.unpacked_value)
	end
end

return tween_file
