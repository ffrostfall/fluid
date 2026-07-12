local oklab = require("@src/utils/oklab")

local function within(epsilon: number)
	return function(value1: vector, value2: vector): boolean
		return vector.magnitude(value1 - value2) <= epsilon
	end
end

local colors_within = within(0.01)

local function oklab_fuzz()
	for r = 1, 256 do
		for g = 1, 256 do
			for b = 1, 256 do
				local original = vector.create(r, g, b)

				assert(colors_within(oklab.to_srgb(oklab.from_srgb(original)), original), "colors not within")
			end
		end
	end
end

return oklab_fuzz
