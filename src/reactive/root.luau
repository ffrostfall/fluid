local graph = require("./graph")
local types = require("./types")

local refs: { [graph.Node<any>]: true | nil } = {}

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

	local result = graph.run_as(node, function(destroy)
		results = { fn(destroy) }
		return nil
	end, destroy)

	if not result.success then
		destroy()
		error(`error while running root():\n\n{result}`, 0)
	end

	-- luau type issue w generic type packs
	return destroy, unpack(results) :: any
end

return root
