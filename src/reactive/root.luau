local graph = require("./graph")
local types = require("./types")

local refs: { [graph.Node<any>]: true? } = {}

local function root<T...>(fn: (destroy: types.Cleanup) -> T...): (types.Cleanup, T...)
	graph.set_group(graph.new_group("root"))
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
		error(result)
	end
	graph.clear_group()

	-- luau type issue w generic type packs
	return destroy, unpack(results) :: any
end

return root
