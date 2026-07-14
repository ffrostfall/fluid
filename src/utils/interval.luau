local exception = require("./exception")
local graph = require("../reactive/graph")
local logging = require("../logging")
local reactive_fn_calls = require("./reactive_fn_calls")
local scheduler = require("../scheduler")

local function interval_err_handler(err: unknown): exception.Identity
	if exception.is(err) then
		local new_err: exception.Identity = err :: any

		logging.warn(new_err.trace)

		return new_err
	elseif type(err) == "string" then
		local formatted_trace = debug.traceback(logging.errors.interval_user_errored(err), 3)

		logging.warn(formatted_trace)

		return exception.new({
			kind = "invoked",
			err = err,
			trace = formatted_trace,
		})
	else
		local formatted_trace = debug.traceback(logging.errors.unknown(err))

		logging.warn(formatted_trace)

		return exception.new({
			kind = "uncaught",
			err = tostring(err),
			trace = formatted_trace,
		})
	end
end

local function silent_interval_err_handler(err: unknown): exception.Identity
	if exception.is(err) then
		local new_err: exception.Identity = err :: any
		return new_err
	elseif type(err) == "string" then
		return exception.new({
			kind = "invoked",
			err = err,
			trace = debug.traceback(logging.errors.interval_user_errored(err), 3),
		})
	else
		return exception.new({
			kind = "uncaught",
			err = tostring(err),
			trace = debug.traceback(logging.errors.unknown(err)),
		})
	end
end

local function interval_yield_handler(thread: thread): exception.Identity
	local formatted_trace = debug.traceback(thread, logging.errors.interval_user_yielded(), 1)

	logging.warn(formatted_trace)

	return exception.new({
		kind = "yielded",
		trace = formatted_trace,
	})
end

local function interval<T>(func: (dt: number) -> T, hz: number?, offset: number?): () -> T
	local scope = graph.assert_stable_parent()

	local ok, res = reactive_fn_calls.no_yield_call(func, interval_err_handler, interval_yield_handler, 0)

	if not ok then
		logging.error(res.trace)
	end

	local node = graph.create_source_node(res)
	local last_eval = offset and -offset or 0
	local last_ok = true

	local function on_render(dt: number)
		if hz ~= nil then
			last_eval += dt
			if last_eval <= 1 / hz then
				return
			end
			dt = last_eval
			last_eval = 0
		end

		if not last_ok then
			local ok, res = reactive_fn_calls.no_yield_call(func, silent_interval_err_handler, function()
				return exception.new({
					kind = "yielded",
					trace = debug.traceback(logging.errors.interval_user_yielded(), 2),
				})
			end, dt)

			if ok then
				last_ok = true
				graph.update_node(node, res)
			end
			return
		end

		local ok, res = reactive_fn_calls.no_yield_call(func, interval_err_handler, interval_yield_handler, dt)

		if ok then
			graph.update_node(node, res)
		else
			last_ok = false
		end
	end

	local disconnect = scheduler.on_render(on_render)

	graph.push_cleanup(scope, disconnect)

	return function()
		graph.push_dependency(node)
		return node.cached_value
	end
end

return interval
