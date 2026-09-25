local bind = require("./bind")
local root = require("../reactive/root")

-- todo(luau): inexact table (https://github.com/luau-lang/rfcs/pull/11)
local function mount(fn: () -> {}, inst: Instance): () -> ()
	return root(function()
		bind(inst, {
			fn(),
		})
	end)
end

return mount
