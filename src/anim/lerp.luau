local graph = require("../reactive/graph")
local read = require("../utils/read")
local scheduler = require("../scheduler")
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
	Color3 = function(a: Color3, b: Color3, t: number)
		return a:Lerp(b, t)
	end,
	CFrame = function(a: CFrame, b: CFrame, t: number)
		return a:Lerp(b, t)
	end,
	Rect = function(a: Rect, b: Rect, t: number)
		return Rect.new(
			general_lerp(a.Min, b.Min, t) :: Vector2,
			general_lerp(a.Max, b.Max, t) :: Vector2
		)
	end,
	UDim = function(a: UDim, b: UDim, t: number)
		return UDim.new(
			math.lerp(a.Scale, b.Scale, t),
			math.lerp(a.Offset, b.Offset, t)
		)
	end,
	UDim2 = function(a: UDim2, b: UDim2, t: number)
		return UDim2.new(
			math.lerp(a.X.Scale, b.X.Scale, t),
			math.lerp(a.X.Offset, b.X.Offset, t),
			math.lerp(a.Y.Scale, b.Y.Scale, t),
			math.lerp(a.Y.Offset, b.Y.Offset, t)
		)
	end,
}

local function lerp<T>(goal: types.UsedAs<T>, takes: types.UsedAs<number>)
	local output = graph.create_source_node(read(goal))

	local function effect()
		active_animations[output] = {
			start = output.cached_value,
			goal = read(goal),

			takes = takes,
			time_passed = 0,
		}
	end

	graph.create_reactive_node(
		graph.assert_stable_parent(),
		effect,
		"deferred"
	)

	return function()
		graph.push_dependency(output)
		return output.cached_value
	end
end

scheduler.on_render(function(dt)
	for output, data in active_animations do
		data.time_passed += dt
		local kind = typeof(output.cached_value)
		local fn = lerp_functions[kind]
		local t = math.clamp(data.time_passed / read(data.takes), 0, 1)

		if t == 1 then
			active_animations[output] = nil
		end

		local interpolated = fn(data.start, data.goal, t)
		graph.update_source_node(output, interpolated)
	end
end)

return lerp
