local graph = require("./graph")
local types = require("./types")

local refs: { [graph.Node<any>]: true? } = {}

-- the scope only passes 1 value through, so the results get put in a table instead of using a closure to capture them
local function call_packed(fn: (destroy: types.Cleanup) -> ...unknown, destroy: types.Cleanup)
	return { fn(destroy) }
end

local function root<T...>(fn: (destroy: types.Cleanup) -> T...): (types.Cleanup, T...)
	local node = graph.create_stable_node(graph.get_scope() or false)

	-- prevent gc of root node
	refs[node] = true

	local function destroy()
		assert(refs[node], "root already destroyed")

		refs[node] = nil

		graph.destroy(node)
	end

	local success, results = graph.run_as(node, call_packed, fn, destroy)

	if not success then
		destroy()
		error((results :: any).trace)
	end

	-- luau type issue w generic type packs
	return destroy, table.unpack(results :: any)
end

return root
