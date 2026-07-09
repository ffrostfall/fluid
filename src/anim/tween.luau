local TweenService = game:GetService("TweenService")

local anim_types = require("./anim_types")
local graph = require("../reactive/graph")
local lerp = require("./lerp")
local read = require("../utils/read")
local types = require("../reactive/types")

type TweenState = {
	start: any,
	current: any,
	target: any,

	datatype: string,

	start_time: number,
	active_tween_info: TweenInfo,
}

local active_tweens: { [TweenState]: graph.SourceNode<anim_types.Animatable> } = {}

local function restart_tween(
	state: TweenState,
	target: any,
	output: graph.SourceNode<anim_types.Animatable>
)
	state.start = table.clone(state.current)
	state.target = target
	state.start_time = os.clock()

	active_tweens[state] = output
end

local tween = {}

local function step_tween(state: TweenState): boolean
	local info = state.active_tween_info

	local elapsed = os.clock() - state.start_time
	if elapsed < info.DelayTime then
		return false
	end

	elapsed -= info.DelayTime

	local duration = info.Time

	if duration <= 0 then
		state.current = state.target

		return true
	end

	local total_cycles = info.RepeatCount + 1
	local infinite = info.RepeatCount < 0

	local finished = false
	local alpha

	if not infinite and elapsed >= total_cycles * duration then
		finished = true
		alpha = if info.Reverses and total_cycles % 2 == 0 then 0 else 1
	else
		local cycle = math.floor(elapsed / duration)

		alpha = (elapsed % duration) / duration

		if info.Reverses and cycle % 2 == 1 then
			alpha = 1 - alpha
		end

		alpha = TweenService:GetValue(alpha, info.EasingStyle, info.EasingDirection)
	end

	state.current = lerp.functions[state.datatype](state.current, state.start, alpha)

	return finished
end

function tween.create<T>(
	input: types.UsedAs<T>,
	info: types.UsedAs<TweenInfo>?
): () -> read.CastIntoValue<T>
	local tween_info = info or TweenInfo.new(0)

	graph.set_group(graph.new_group("tween"))

	local output = graph.create_source_node(read(input))

	local call = graph.evaluate_node(output :: T)
	assert(call.success)

	local initial_tween_info = read(tween_info)

	local tween_state: TweenState = {
		start = call.value,
		current = call.value,
		target = call.value,

		datatype = typeof(call.value),

		start_time = os.clock(),
		active_tween_info = initial_tween_info,
	}

	local function on_input_update()
		local input_as_value = read(input)
		assert(
			typeof(input_as_value) == tween_state.datatype,
			"Can't switch the data types of a tween"
		)
		restart_tween(tween_state, input_as_value, output :: any)
		return nil
	end

	local function on_tween_info_update()
		local new_tween_info = read(tween_info)

		if tween_state.active_tween_info ~= new_tween_info then
			tween_state.active_tween_info = new_tween_info
			tween_state.start = table.clone(tween_state.current)
			tween_state.start_time = os.clock()
			active_tweens[tween_state] = output
		end

		return nil
	end

	local goal_node = graph.create_reactive_node(
		graph.assert_stable_parent(),
		on_input_update,
		"deferred",
		read(input)
	)

	graph.evaluate_node(goal_node)

	local tween_info_node = graph.create_reactive_node(
		graph.assert_stable_parent(),
		on_tween_info_update,
		"deferred",
		read(tween_info)
	)

	graph.evaluate_node(tween_info_node)

	graph.clear_group()

	return function()
		graph.push_dependency(output :: T)
		return output.cached_value
	end
end

function tween.step(delta_time: number)
	for tween_state, node in active_tweens do
		local finished = step_tween(tween_state)

		graph.update_source_node(node, tween_state.current)

		if finished then
			active_tweens[tween_state] = nil
		end
	end
end

return tween
