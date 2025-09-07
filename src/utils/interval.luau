local graph = require("../reactive/graph")
local logging = require("../logging")
local no_yield = require("./no_yield")
local scheduler = require("../scheduler")

local dev_mode = _G.__DEV__

local function interval<T>(func: (dt: number) -> T, hz: number?)
	local scope = graph.assert_stable_parent()

	graph.set_group(graph.new_group("interval"))

	local creation_trace = if dev_mode then debug.traceback(nil, 2) else "stack trace not defiend"
	local initial_value = if dev_mode then no_yield(func, 0) else func(0)

	local node = graph.create_source_node(initial_value)
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
			local ok, result = xpcall(no_yield, function(err)
				return logging.warn_suppressed(`interval error: {err} trace: {creation_trace}`)
			end, func, dt)

			if not ok then
				return
			end

			new_value = result
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
