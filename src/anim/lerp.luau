local graph = require("../reactive/graph")
local oklab = require("../utils/oklab")
local read = require("../utils/read")
local types = require("../reactive/types")

local active_animations = {}

local function vector_lerp(a: vector, b: vector, t: number): vector
	return a + (b - a) * t
end

local function general_lerp(a: any, b: any, t: number): any
	return a + (b - a) * t
end

local lerp_functions: { [string]: (a: any, b: any, t: number) -> any } = {
	number = math.lerp,
	Vector3 = vector_lerp,
	Vector2 = general_lerp,
	Color3 = Color3.new(0, 0, 0).Lerp,
	CFrame = function(a: Color3, b: Color3, t)
		local initial_vector = oklab.from_srgb(vector.create(a.R, a.G, a.B))
		local goal_vector = oklab.from_srgb(vector.create(b.R, b.G, b.B))
		local interpolated_vector = vector_lerp(initial_vector, goal_vector, t)
		local result_vector = oklab.to_srgb(interpolated_vector)
		return Color3.new(result_vector.x, result_vector.y, result_vector.z)
	end,
	Rect = function(a: Rect, b: Rect, t: number)
		return Rect.new(
			general_lerp(a.Min, b.Min, t) :: Vector2,
			general_lerp(a.Max, b.Max, t) :: Vector2
		)
	end,
	UDim = function(a: UDim, b: UDim, t: number)
		return UDim.new(math.lerp(a.Scale, b.Scale, t), math.lerp(a.Offset, b.Offset, t))
	end,
	UDim2 = UDim2.new().Lerp,
}

local lerp = {}

function lerp.create<T>(goal: types.UsedAs<T>, takes: types.UsedAs<number>)
	graph.set_group(graph.new_group("lerp"))
	local output = graph.create_source_node(read(goal))

	local function effect()
		active_animations[output] = {
			start = output.cached_value,
			goal = read(goal),

			takes = takes,
			time_passed = 0,
		}

		return nil
	end

	graph.create_reactive_node(graph.assert_stable_parent(), effect, "deferred")
	graph.clear_group()

	return function()
		graph.push_dependency(output)
		return output.cached_value
	end
end

function lerp.step(delta_time: number)
	for output, data in active_animations do
		data.time_passed += delta_time
		local kind = typeof(output.cached_value)
		local fn = lerp_functions[kind]
		local t = math.clamp(data.time_passed / read(data.takes), 0, 1)

		if t == 1 then
			active_animations[output] = nil
		end

		local interpolated = fn(data.start, data.goal, t)
		graph.update_source_node(output, interpolated)
	end
end

return lerp
