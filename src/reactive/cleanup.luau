local scheduler = require("../scheduler")

-- objects are stored as is and get disconnected/cancelled/destroyed, instead of needing a
-- closure for each one
export type CleanupObject =
	{ destroy: (self: any) -> () }
	| { disconnect: (self: any) -> () }
	| { Destroy: (self: any) -> () }
	| { Disconnect: (self: any) -> () }

export type Cleanup = (() -> ()) | thread | RBXScriptConnection | Instance | CleanupObject

-- the solver can't narrow CleanupObject by which key it has, so cleanup looks for the method through this
type CleanupMethods = {
	read destroy: ((self: any) -> ())?,
	read disconnect: ((self: any) -> ())?,
	read Destroy: ((self: any) -> ())?,
	read Disconnect: ((self: any) -> ())?,
}

-- cleans up a value that was passed to fluid.cleanup, the graph calls it when the scope reruns or dies
local function cleanup(value: Cleanup)
	local kind = typeof(value)

	if kind == "function" then
		(value :: () -> ())()
	elseif kind == "RBXScriptConnection" then
		(value :: any):Disconnect()
	elseif kind == "thread" then
		scheduler.cancel(value :: thread)
	elseif kind == "Instance" then
		(value :: any):Destroy()
	else
		local object = (value :: CleanupObject) :: CleanupMethods

		if object.destroy then
			object:destroy()
		elseif object.disconnect then
			object:disconnect()
		elseif object.Destroy then
			object:Destroy()
		elseif object.Disconnect then
			object:Disconnect()
		end
	end
end

return cleanup
