local graph = require("../reactive/graph")
local oklab = require("../utils/oklab")
local read = require("../utils/read")
local types = require("../reactive/types")

local active_animations = {}

local lerp_functions: { [string]: (any, any, number) -> any } = {
	number = math.lerp,
	vector = vector.lerp,
	Vector2 = vector.lerp,
	Vector3 = vector.lerp,
	UDim2 = UDim2.new().Lerp,
}

function lerp_functions.CFrame(initial: CFrame, goal: CFrame, ratio: number)
	return initial:Lerp(goal, ratio)
end

function lerp_functions.Color3(initial: Color3, goal: Color3, ratio: number)
	local initial_vector = oklab.from_srgb(vector.create(initial.R, initial.G, initial.B))
	local goal_vector = oklab.from_srgb(vector.create(goal.R, goal.G, goal.B))
	local interpolated_vector = vector.lerp(initial_vector, goal_vector, ratio)
	local result_vector = vector.clamp(oklab.to_srgb(interpolated_vector), vector.zero, vector.one)
	return Color3.new(result_vector.x, result_vector.y, result_vector.z)
end

function lerp_functions.ColorSequenceKeypoint(
	initial: ColorSequenceKeypoint,
	goal: ColorSequenceKeypoint,
	ratio: number
)
	return ColorSequenceKeypoint.new(
		math.lerp(initial.Time, goal.Time, ratio),
		lerp_functions.Color3(initial.Value, goal.Value, ratio)
	)
end

function lerp_functions.NumberRange(initial: NumberRange, goal: NumberRange, ratio: number)
	return NumberRange.new(
		math.lerp(initial.Min, goal.Min, ratio),
		math.lerp(initial.Max, goal.Max, ratio)
	)
end

function lerp_functions.NumberSequenceKeypoint(
	initial: NumberSequenceKeypoint,
	goal: NumberSequenceKeypoint,
	ratio: number
)
	return NumberSequenceKeypoint.new(
		math.lerp(initial.Time, goal.Time, ratio),
		math.lerp(initial.Value, goal.Value, ratio)
	)
end

function lerp_functions.PhysicalProperties(
	initial: PhysicalProperties,
	goal: PhysicalProperties,
	ratio: number
)
	return PhysicalProperties.new(
		math.lerp(initial.Density, goal.Density, ratio),
		math.lerp(initial.Friction, goal.Friction, ratio),
		math.lerp(initial.Elasticity, goal.Elasticity, ratio),
		math.lerp(initial.FrictionWeight, goal.FrictionWeight, ratio),
		math.lerp(initial.ElasticityWeight, goal.ElasticityWeight, ratio),
		math.lerp(initial.AcousticAbsorption, goal.AcousticAbsorption, ratio)
	)
end

function lerp_functions.Ray(initial: Ray, goal: Ray, ratio: number)
	return Ray.new(
		vector.lerp(initial.Origin :: any, goal.Origin :: any, ratio) :: any,
		vector.lerp(initial.Direction :: any, goal.Direction :: any, ratio) :: any
	)
end

function lerp_functions.Rect(initial: Rect, goal: Rect, ratio: number)
	return Rect.new(
		vector.lerp(initial.Min :: any, goal.Min :: any, ratio) :: any,
		vector.lerp(initial.Max :: any, goal.Max :: any, ratio) :: any
	)
end

function lerp_functions.Region3(initial: Region3, goal: Region3, ratio: number)
	-- FUTURE: support rotated Region3s if/when they become constructable
	local position = initial.CFrame.Position:Lerp(goal.CFrame.Position, ratio)
	local halfSize = initial.Size:Lerp(goal.Size, ratio) / 2
	return Region3.new(position - halfSize, position + halfSize)
end

function lerp_functions.UDim(initial: UDim, goal: UDim, ratio: number)
	return UDim.new(
		math.lerp(initial.Scale, goal.Scale, ratio),
		math.lerp(initial.Offset, goal.Offset, ratio)
	)
end

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
		graph.push_dependency(output :: T)
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
		graph.update_source_node(output :: any, interpolated)
	end
end

return lerp
