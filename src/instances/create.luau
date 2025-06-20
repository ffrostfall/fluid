local bind = require("./bind")

local function try_create_inst(class_name: string): Instance
	local success, result =
		pcall(Instance.new :: (name: string) -> Instance, class_name)
	if not success then
		-- error at the location of the create call
		error(`Instance class "{class_name}" does not exist`, 3)
	end

	return result
end

local function create(
	class_name: string
): (props: { [string | number]: unknown }) -> Instance
	return function(props)
		return bind(props :: any, try_create_inst(class_name))
	end
end

return create
