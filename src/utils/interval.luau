local graph = require("../reactive/graph")
local logging = require("../logging")
local no_yield = require("./no_yield")
local scheduler = require("../scheduler")

local dev_mode = _G.__DEV__ == true

local function interval<T>(func: (dt: number) -> T, hz: number?, offset: number?): () -> T
	local scope = graph.assert_stable_parent()

	graph.set_group(graph.new_group("interval"))

	local initial_value
	if dev_mode then
		-- throw immediately, lets just format the error
		local ok, r = xpcall(no_yield.check, no_yield.error_handler, func, 0)

		if not ok then
			error(`{r.message}\n{r.trace}`)
		end
	else
		initial_value = func(0)
	end
	local node = graph.create_source_node(initial_value)
	local last_eval = offset and -offset or 0

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
			local ok, err = xpcall(no_yield.check, no_yield.error_handler, func, dt)

			if not ok then
				logging.warn_suppressed(`{err.message}\n{err.trace}`)
				return
			end

			new_value = err
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
