local derive = require("../reactive/derive")
local read = require("./read")
local types = require("../reactive/types")
local untrack = require("../reactive/untrack")

local function switch<T, U>(condition: () -> T)
	return function(options: { [T]: types.UsedAs<U> }): () -> read.CastIntoValue<U>?
		return derive(function(): read.CastIntoValue<U>
			local value = condition()

			return untrack(function()
				local key = options[value]
				return read(key) :: read.CastIntoValue<U>
			end)
		end)
	end
end

return switch
