--[[
	hook onto when fluid warns
]]
local logging = require("@src/logging")
type OnWarn = (text: string) -> ()
local on_warn_hook: OnWarn?

--

local original_function = logging.__warn_facade
function logging.__warn_facade(...)
	if on_warn_hook then
		on_warn_hook(...)
	else
		original_function(...)
	end
end

--

local function set_on_warn(hook: OnWarn?)
	on_warn_hook = hook
end

return {
	on_warn = set_on_warn,
}
