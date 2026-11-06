local graph = require("./graph")
local types = require("./types")

local push_dependency = graph.push_dependency
local update_node = graph.update_node

local function source<T>(initial_value: T): types.Source<T>
	local node = graph.create_source_node(initial_value)

	-- This uses varargs so we can tell the difference between f(), f(nil), and f(value)
	return function(...: T): T
		if select("#", ...) == 0 then
			-- dependency, returning the value
			push_dependency(node)
			return node.cached_value
		end

		local value = ...
		update_node(node, value)
		return value
	end
end

return source :: (<T>(value: T) -> types.Source<T>) & (<T>() -> types.Source<T>)
