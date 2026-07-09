-- Based on https://github.com/dphfox/Fusion/blob/2790f7b6272bdf7cd0bbfee259a2f9d79ea20810/src/Animation/packType.luau

local anim_types = require("./anim_types")
local oklab = require("../utils/oklab")

local function unpack_type(type_string: string, numbers: { number }): anim_types.Animatable
	if type_string == "number" then
		return numbers[1]
	elseif type_string == "CFrame" then
		return CFrame.new(numbers[1], numbers[2], numbers[3])
			* CFrame.fromAxisAngle(
				Vector3.new(numbers[4], numbers[5], numbers[6]).Unit,
				numbers[7]
			)
	elseif type_string == "Color3" then
		local intermediate_srgb = oklab.to_srgb(vector.create(numbers[1], numbers[2], numbers[3]))
		return Color3.new(intermediate_srgb.x, intermediate_srgb.y, intermediate_srgb.z)
	elseif type_string == "ColorSequenceKeypoint" then
		local intermediate_srgb = oklab.to_srgb(vector.create(numbers[1], numbers[2], numbers[3]))
		return ColorSequenceKeypoint.new(
			numbers[4],
			Color3.new(intermediate_srgb.x, intermediate_srgb.y, intermediate_srgb.z)
		)
	elseif type_string == "DateTime" then
		return DateTime.fromUnixTimestampMillis(numbers[1])
	elseif type_string == "NumberRange" then
		return NumberRange.new(numbers[1], numbers[2])
	elseif type_string == "NumberSequenceKeypoint" then
		return NumberSequenceKeypoint.new(numbers[2], numbers[1], numbers[3])
	elseif type_string == "PhysicalProperties" then
		return PhysicalProperties.new(numbers[1], numbers[2], numbers[3], numbers[4], numbers[5])
	elseif type_string == "Ray" then
		return Ray.new(
			Vector3.new(numbers[1], numbers[2], numbers[3]),
			Vector3.new(numbers[4], numbers[5], numbers[6])
		)
	elseif type_string == "Rect" then
		return Rect.new(numbers[1], numbers[2], numbers[3], numbers[4])
	elseif type_string == "Region3" then
		-- FUTURE: support rotated Region3s if/when they become constructable
		local position = Vector3.new(numbers[1], numbers[2], numbers[3])
		local halfSize = Vector3.new(numbers[4] / 2, numbers[5] / 2, numbers[6] / 2)
		return Region3.new(position - halfSize, position + halfSize)
	elseif type_string == "UDim" then
		return UDim.new(numbers[1], math.round(numbers[2]))
	elseif type_string == "UDim2" then
		return UDim2.new(numbers[1], math.round(numbers[2]), numbers[3], math.round(numbers[4]))
	elseif type_string == "Vector2" then
		return Vector2.new(numbers[1], numbers[2])
	elseif type_string == "Vector3" then
		return Vector3.new(numbers[1], numbers[2], numbers[3])
	elseif type_string == "vector" then
		return vector.create(numbers[1], numbers[2], numbers[3])
	else
		return error(`unsupported type {type_string}`)
	end
end

return unpack_type
