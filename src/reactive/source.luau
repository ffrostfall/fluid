local graph = require("./graph")
local types = require("./types")

local function get_argument_from<T>(...: T): (boolean, T)
	if select("#", ...) == 0 then
		return false, nil :: any
	end

	local first_value = ...
	return true, first_value
end

local function source<T>(initial_value: T): types.Source<T>
	graph.set_group(graph.new_group("source"))
	local node = graph.create_source_node(initial_value)
	graph.clear_group()

	-- This uses varargs so we can tell the difference between f(), f(nil), and f(value)
	return function(...: T): T
		local has_value, value = get_argument_from(...)

		if has_value then
			-- setting the source node
			graph.update_source_node(node, value)
			return value
		else
			-- dependency, returning the value
			graph.push_dependency(node)
			return node.cached_value
		end
	end :: types.Source<T>
end

return source :: (<T>(value: T) -> types.Source<T>) & (<T>() -> types.Source<T>)
