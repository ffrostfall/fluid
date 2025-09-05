local types = require("../reactive/types")
local switch_delay = require("./switch_delay")

local function show<T, U>(
	condition: () -> any,
	truthy: (active: types.Readable<boolean>) -> (T, number?),
	falsy: ((active: types.Readable<boolean>) -> (U, number?))?
): () -> { T | U }
	return switch_delay(function()
		return not not condition()
	end) {
		[true] = truthy,
		[false] = falsy :: any
	}
end

return show ::
	& (<T>(condition: () -> any, truthy: types.Readable<T>) -> () -> { T })
	& <T, U>(condition: () -> any, truthy: types.Readable<T>, falsy: types.Readable<U>) -> () -> { T | U }
