local action = require("./action")
local graph = require("../reactive/graph")

local function changed(property: string, fn: (any) -> ())
	return action.create(function(instance: Instance)
		fn((instance :: any)[property])

		local con = instance:GetPropertyChangedSignal(property):Connect(function()
			fn((instance :: any)[property])
		end)

		graph.push_cleanup(graph.assert_scope(), function()
			con:Disconnect()
		end)
	end)
end

return changed
