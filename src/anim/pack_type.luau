-- Based on https://github.com/dphfox/Fusion/blob/2790f7b6272bdf7cd0bbfee259a2f9d79ea20810/src/Animation/unpackType.luau

local oklab = require("../utils/oklab")

local function pack_type(value: unknown): (string, { number })
	local type_string = typeof(value)
	if type_string == "number" then
		value = value :: number
		return type_string, { value }
	elseif type_string == "CFrame" then
		value = value :: CFrame
		-- FUTURE: is there a better way of doing this? doing distance
		-- calculations on `angle` may be incorrect
		local axis, angle = value:ToAxisAngle()
		return type_string, { value.X, value.Y, value.Z, axis.X, axis.Y, axis.Z, angle }
	elseif type_string == "Color3" then
		value = value :: Color3
		-- oklab conversion
		local intermediate_vector = oklab.from_srgb(vector.create(value.R, value.G, value.B))

		return type_string,
			{
				intermediate_vector.x,
				intermediate_vector.y,
				intermediate_vector.z,
			}
	elseif type_string == "ColorSequenceKeypoint" then
		value = value :: ColorSequenceKeypoint

		-- oklab conversion
		local intermediate_vector =
			oklab.from_srgb(vector.create(value.Value.R, value.Value.G, value.Value.B))

		return type_string,
			{
				intermediate_vector.x,
				intermediate_vector.y,
				intermediate_vector.z,
			}
	elseif type_string == "DateTime" then
		value = value :: DateTime
		return type_string, { value.UnixTimestampMillis }
	elseif type_string == "NumberRange" then
		value = value :: NumberRange
		return type_string, { value.Min, value.Max }
	elseif type_string == "NumberSequenceKeypoint" then
		value = value :: NumberSequenceKeypoint
		return type_string, { value.Value, value.Time, value.Envelope }
	elseif type_string == "PhysicalProperties" then
		value = value :: PhysicalProperties
		return type_string,
			{
				value.Density,
				value.Friction,
				value.Elasticity,
				value.FrictionWeight,
				value.ElasticityWeight,
			}
	elseif type_string == "Ray" then
		value = value :: Ray
		return type_string,
			{
				value.Origin.X,
				value.Origin.Y,
				value.Origin.Z,
				value.Direction.X,
				value.Direction.Y,
				value.Direction.Z,
			}
	elseif type_string == "Rect" then
		value = value :: Rect
		return type_string, { value.Min.X, value.Min.Y, value.Max.X, value.Max.Y }
	elseif type_string == "Region3" then
		value = value :: Region3
		-- FUTURE: support rotated Region3s if/when they become constructable
		return type_string,
			{
				value.CFrame.X,
				value.CFrame.Y,
				value.CFrame.Z,
				value.Size.X,
				value.Size.Y,
				value.Size.Z,
			}
	elseif type_string == "Region3int16" then
		value = value :: Region3int16
		return type_string,
			{ value.Min.X, value.Min.Y, value.Min.Z, value.Max.X, value.Max.Y, value.Max.Z }
	elseif type_string == "UDim" then
		value = value :: UDim
		return type_string, { value.Scale, value.Offset }
	elseif type_string == "UDim2" then
		value = value :: UDim2
		return type_string, { value.X.Scale, value.X.Offset, value.Y.Scale, value.Y.Offset }
	elseif type_string == "Vector2" then
		value = value :: Vector2
		return type_string, { value.X, value.Y }
	elseif type_string == "Vector2int16" then
		value = value :: Vector2int16
		return type_string, { value.X, value.Y }
	elseif type_string == "Vector3" then
		value = value :: Vector3
		return type_string, { value.X, value.Y, value.Z }
	elseif type_string == "Vector3int16" then
		value = value :: Vector3int16
		return type_string, { value.X, value.Y, value.Z }
	elseif type_string == "vector" then
		value = value :: vector
		return type_string, { value.x, value.y, value.z }
	else
		return type_string, {}
	end
end

return pack_type
