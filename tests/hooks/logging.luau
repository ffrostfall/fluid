--[[
	hook onto when fluid warns
	used if you wanna catch a logging.warn/logging.warn_supressed this will allow you to hook onto that
]]
local logging = require("@src/logging")

type OnWarn = (text: string) -> ()

-- user callback for when fluid warns to the stdio
-- if nothing is specified, fluid will output to the stdio
local on_warn_hook: OnWarn?

-- overwrite to accommodate the user specified hook
local original_function = logging.__warn_facade
function logging.__warn_facade(...)
	if on_warn_hook then
		on_warn_hook(...)
	else
		original_function(...)
	end
end

--[[
 	user callback for when fluid warns to the stdio
 	prevents stdio from even being written

	@example
	```lua
	local did_output_something = false

	hooks.logging.on_warn(function(err)
		did_output_something = string.find(err, "did_output_something") ~= nil
	end)

	require("@src/logging").warn("did_output_something")

	CHECK(did_output_something)

	hooks.logging.on_warn(nil) -- good practice to remove on_warn
	```
]]
local function set_on_warn(hook: OnWarn?)
	on_warn_hook = hook
end

return {
	on_warn = set_on_warn,
}
