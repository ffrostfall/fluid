local derive = require("../reactive/derive")
local read = require("./read")
local types = require("../reactive/types")
local untrack = require("../reactive/untrack")

local function show<T, U>(
	condition: types.UsedAs<any>,
	truthy: types.UsedAs<T>,
	falsy: types.UsedAs<U>?
): () -> T | U
	return derive(function()
		if read(condition) then
			return untrack(function()
				return read(truthy)
			end)
		elseif falsy then
			return untrack(function()
				return read(falsy)
			end)
		end

		return nil
	end)
end

return show :: & (<T>(
		condition: types.UsedAs<any>,
		truthy: types.UsedAs<T>
	) -> () -> read.CastIntoValue<T>?) & <T, U>(
		condition: types.UsedAs<any>,
		truthy: types.UsedAs<T>,
		falsy: types.UsedAs<U>
	) -> () -> T | U
