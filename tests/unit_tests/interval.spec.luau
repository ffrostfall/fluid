local TEST, CASE, CHECK = require("@vendor/testkit").test()
local fluid = require("@src/")
local logging = require("@src/logging")
local result = require("@src/result")
local task = require("@lune/task")

local scheduler = fluid.__SCHEDULER_INTERFACE
local provided_scheduler = fluid.provide_scheduler()

local function step_scheduler(n: number?)
	task.spawn(provided_scheduler, n or 1 / 60)
end

--[=[
	Sandboxes the reactive graph root so we don't need to worry about side effects with implicit dependencies
]=]
local function wrap_root(fn: () -> ())
	return function()
		local destroy = fluid.root(function()
			fn()
		end)
		destroy()
	end
end

local function use_log_mode(fn: () -> ())
	fn()
	logging.on_warn(nil)
end

--

TEST("interval", function()
	do
		CASE("go active")

		local interval_run_time = 0
		local destroy = fluid.root(function()
			fluid.interval(function(dt)
				CHECK(dt == 0)
				interval_run_time += 1
				return 1
			end)
		end)

		CHECK(interval_run_time == 1)
		step_scheduler(0)
		CHECK(interval_run_time == 2)

		CASE("cleanup")

		destroy()

		step_scheduler(0)

		CHECK(interval_run_time == 2)
	end

	do
		CASE("interval with 'hz' specified")
		table.clear(scheduler.connections)

		local dt = 0
		local destroy = fluid.root(function()
			fluid.interval(function(a)
				dt = a
				return 0
			end, 100)
		end)

		CHECK(dt == 0)

		CASE("other with 'hz' specified runs")

		for i = 1, 4 do
			step_scheduler(i)
			CHECK(dt == i)
		end

		destroy()
	end

	do
		CASE("interval with no 'hz' specified")
		table.clear(scheduler.connections)

		local dt = 0
		local destroy = fluid.root(function()
			fluid.interval(function(a)
				dt = a
				return 0
			end)
		end)

		CHECK(dt == 0)

		CASE("other no 'hz' specified runs")

		for i = 1, 4 do
			step_scheduler(i)
			CHECK(dt == i)
		end

		destroy()
	end

	do
		CASE("should be blocked if last evaluation to hz is small")
		local evaulation_times = 0

		local destroy = fluid.root(function()
			fluid.interval(function(a)
				evaulation_times += 1
				return 0
			end, 1)
		end)

		CHECK(evaulation_times == 1)

		step_scheduler()

		CHECK(evaulation_times == 1)

		step_scheduler(0.5)
		CHECK(evaulation_times == 1)

		CASE("should pass if last evaulation is big enough")

		step_scheduler(0.5 + 0.001)
		CHECK(evaulation_times == 2)

		CASE("micro last evaulations")

		step_scheduler(0.999)
		CHECK(evaulation_times == 2)
		step_scheduler(0.001)
		CHECK(evaulation_times == 2)
		step_scheduler(0.001)
		CHECK(evaulation_times == 3)

		destroy()
	end

	do
		CASE("should return the time since last evaulation")

		local dt = -1
		local destroy = fluid.root(function()
			fluid.interval(function(a)
				dt = a
				return 0
			end, 1)
		end)

		CHECK(dt == 0)
		step_scheduler(0.6)
		CHECK(dt == 0)
		step_scheduler(0.6)

		CHECK(dt == (0.6 * 2)) -- should be 1.2

		CASE("should reset the evaluation time even though we have passed the interval rate")

		step_scheduler(1.1)
		CHECK(dt == 1.1)

		destroy()
	end
end)

TEST(
	"interval devmode mode",
	wrap_root(function()
		do
			CASE("error if callback yields with coroutine.yield()")

			local interval_result = result.call(fluid.interval, function(dt)
				return coroutine.yield()
			end)

			CHECK(interval_result.success == false)
			if not interval_result.success then
				CHECK(string.find(interval_result.err :: string, "thread yielded") ~= nil)
			end
		end

		do
			CASE("error if callback yields with task.wait()")

			local interval_result = result.call(fluid.interval, function(dt)
				return task.wait()
			end)

			CHECK(interval_result.success == false)
			if not interval_result.success then
				CHECK(string.find(interval_result.err :: string, "thread yielded") ~= nil)
			end
		end

		do
			CASE("log warn when fluid.interval suddenly yields and does not spam output")

			local did_yield_count = 0
			use_log_mode(function()
				logging.on_warn(function(text)
					if string.find(text, "thread yielded") ~= nil then
						did_yield_count += 1
					end
				end)

				fluid.interval(function(dt)
					if dt == 0 then
						return 0
					end
					return coroutine.yield()
				end)

				CHECK(did_yield_count == 0)
				step_scheduler(1)
				CHECK(did_yield_count == 1)

				for i = 1, 5 do
					step_scheduler(i / 60)
				end

				CHECK(did_yield_count == 1)
			end)
		end
	end)
)

return nil
