local graph = require("../reactive/graph")
local logging = require("../logging")
local no_yield = require("./no_yield")
local scheduler = require("../scheduler")

local dev_mode = _G.__DEV__

local function interval<T>(func: (dt: number) -> T, hz: number?)
	local scope = graph.assert_stable_parent()

	graph.set_group(graph.new_group("interval"))

	local creation_trace = debug.traceback(nil, 2)

	local inital_value
	if not dev_mode then
		inital_value = func(0)
	else
		local result = no_yield(func, 0)
		if not result.success then
			error(`interval error: {result.err} trace: {creation_trace}`)
		end
		inital_value = result.value
	end

	local node = graph.create_source_node(inital_value)
	local last_eval = 0
	graph.clear_group()

	local function on_render(dt: number)
		if hz ~= nil then
			last_eval += dt
			if last_eval <= 1 / hz then
				return
			end
			dt = last_eval
			last_eval = 0
		end

		local new_value
		if not dev_mode then
			new_value = func(dt)
		else
			local result = no_yield(func, dt)

			if not result.success then
				return logging.warn_suppressed(
					`interval error: {result.err} trace: {creation_trace}`
				)
			end

			new_value = result.value
		end

		graph.update_source_node(node, new_value)
	end

	local disconnect = scheduler.on_render(on_render)

	graph.push_cleanup(scope, disconnect)

	return function()
		graph.push_dependency(node)
		return node.cached_value
	end
end

return interval
