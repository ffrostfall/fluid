local graph = require("./graph")
local types = require("./types")

local refs: { [graph.Node<any>]: true? } = {}

local function root<T...>(fn: (destroy: types.Cleanup) -> T...): (types.Cleanup, T...)
	local node = graph.create_stable_node(graph.get_scope())

	-- prevent gc of root node
	refs[node] = true

	local function destroy()
		assert(refs[node], "root already destroyed")

		refs[node] = nil

		graph.destroy(node)
	end

	local results = {}

	local success, value = pcall(graph.run_as, node, function(destroy)
		results = { fn(destroy) }
		return nil
	end, destroy)

	if not success then
		destroy()
		print(tostring(value))
		-- error(tostring(value))
	end

	-- luau type issue w generic type packs
	return destroy, unpack(results) :: any
end

return root
