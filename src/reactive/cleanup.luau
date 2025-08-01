local graph = require("./graph")
local get_scope = graph.get_scope
local push_cleanup = graph.push_cleanup

local function helper(obj: any)
	return if typeof(obj) == "RBXScriptConnection"
		then function()
			obj:Disconnect()
		end
		elseif type(obj) == "thread" then function()
			task.cancel(obj)
		end
		elseif typeof(obj) == "Instance" then function()
			obj:Destroy()
		end
		elseif obj.destroy then function()
			obj:destroy()
		end
		elseif obj.disconnect then function()
			obj:disconnect()
		end
		elseif obj.Destroy then function()
			obj:Destroy()
		end
		elseif obj.Disconnect then function()
			obj:Disconnect()
		end
		else error("cannot cleanup given object")
end

local function cleanup(value: unknown)
	local scope = get_scope()

	if not scope then
		error("cannot cleanup outside a stable or reactive scope")
	end
	assert(scope)

	if type(value) == "function" then
		push_cleanup(scope, value :: () -> ())
	else
		push_cleanup(scope, helper(value))
	end
end

type Destroyable = { destroy: (any) -> () } | { Destroy: (any) -> () }
type Disconnectable = { disconnect: (any) -> () } | { Disconnect: (any) -> () }

return cleanup :: ((callback: () -> ()) -> ()) & ((thread: thread) -> ()) & ((instance: Destroyable) -> ()) & ((connection: Disconnectable) -> ()) & ((instance: Instance) -> ()) & ((connection: RBXScriptConnection) -> ())
