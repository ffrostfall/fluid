local derive = require("../reactive/derive")
local read = require("./read")
local types = require("../reactive/types")
local untrack = require("../reactive/untrack")

local function switch<T, U>(condition: () -> T)
	return function(options: { [T]: types.UsedAs<U> }): () -> U?
		return derive(function()
			local value = condition()

			return untrack(function()
				local key = options[value]
				return read(key)
			end)
		end)
	end
end

return switch
