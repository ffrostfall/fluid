local bind = require("./bind")
local types = require("./types")

local function try_create_instance(class_name: string): Instance
	local success, call_result = pcall(Instance.new, class_name)
	assert(success, call_result)

	return call_result
end

--stylua: ignore
local function create<ClassName>(
	class_name: ClassName | keyof<types.Instances> | ""
): (props: types.PropertiesFor<ClassName>) -> types.GetInstance<ClassName, types.Instances>
	return function(properties)
		return bind(try_create_instance(class_name), properties) :: any
	end
end

return create
