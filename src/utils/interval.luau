local exception = require("./exception")
local graph = require("../reactive/graph")
local logging = require("@src/logging")
local no_yield = require("./no_yield")
local safe_call = require("./safe_call")
local scheduler = require("../scheduler")

local dev_mode = true

local function interval<T>(func: (dt: number) -> T, hz: number?, offset: number?): () -> T
	local scope = graph.assert_stable_parent()

	local success, res_value = safe_call(dev_mode, func, 0)

	if not success then
		if exception.is_thread_unwrap(res_value) then
			local thread, yielded = exception.unwrap_ephemeral_thread_err(res_value)

			if yielded then
				logging.warn_traceback(logging.errors.interval_user_yielded(), thread)
			else
				logging.warn_traceback(logging.errors.interval_user_errored(), thread)
			end
		end
	end

	local node = graph.create_source_node(res_value)
	local last_eval = offset and -offset or 0

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
			new_value = no_yield(func, dt)
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
