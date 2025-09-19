local switch_delay = require("./switch_delay")
local types = require("../reactive/types")

local function NONE() end

local function show<T, U>(
	condition: () -> any,
	truthy: (active: types.Readable<boolean>) -> (T, number?),
	falsy: ((active: types.Readable<boolean>) -> (U, number?))?
): () -> { T | U }
	return switch_delay(function()
		return not not condition()
	end)({
		[true] = truthy,
		[false] = falsy or NONE :: any,
	})
end

return show :: & (<T>(condition: () -> any, truthy: types.Readable<T>) -> () -> { T }) & <T, U>(
	condition: () -> any,
	truthy: types.Readable<T>,
	falsy: types.Readable<U>
) -> () -> { T | U }
