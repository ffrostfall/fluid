local TEST, CASE, CHECK = require("@vendor/testkit").test()
local fluid = require("@src/")
local hooks = require("@tests/hooks")
local task = require("@lune/task")

local scheduler = fluid.__SCHEDULER_INTERFACE
local step_scheduler = hooks.scheduler.step

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

TEST("scheduler stepping", function()
	do
		CASE("1 second delta time")
		table.clear(scheduler.connections)
		local counted_seconds = 0

		local function on_render_callback(delta_time: number)
			counted_seconds += delta_time
		end
		local disconnect = scheduler.on_render(on_render_callback)

		CHECK(scheduler.connections[1] == on_render_callback)
		CHECK(counted_seconds == 0)
		step_scheduler(1)

		CHECK(counted_seconds == 1)

		CASE("check disconnected")

		disconnect()
		CHECK(scheduler.connections[1] == nil)
		step_scheduler(1)
		CHECK(counted_seconds == 1)
	end
end)

TEST(
	"bind_frame",
	wrap_root(function()
		CASE("polls each render")
		do
			table.clear(scheduler.connections)
			local counted_seconds = 0

			scheduler.on_render(function(delta_time)
				counted_seconds += delta_time
			end)

			local value = fluid.interval(function(dt)
				CHECK(dt == 1 or dt == 0)
				return counted_seconds
			end)

			step_scheduler(1)
			CHECK(value() == 1)
		end
	end)
)

TEST("schedular.delay()", function()
	do
		CASE("works")

		local triggered = false
		scheduler.delay(1, function()
			triggered = true
		end)

		CHECK(triggered == false)
		step_scheduler(0.995)
		CHECK(triggered == false)
		step_scheduler(0.005)

		CHECK(triggered == true)
	end

	do
		CASE("schedular.delay() is always resumped next step")

		local triggered = false
		scheduler.delay(0, function()
			triggered = true
		end)

		CHECK(triggered == false)
		step_scheduler()
		CHECK(triggered == true)
	end

	do
		CASE("schedular.delay() is cancelable")

		local triggered = false
		local thread = scheduler.delay(0, function()
			triggered = true
		end)

		CHECK(triggered == false)

		scheduler.cancel(thread)

		step_scheduler(1)
		step_scheduler(2)
		step_scheduler(3)

		CHECK(triggered == false)
	end
end)

TEST("schedular.wait()", function()
	do
		CASE("works")

		for _, wait_time in { 0, 0.05, 0.5, 1, 2 } do
			local ran = false
			task.spawn(function()
				scheduler.wait(wait_time)
				ran = true
			end)

			CHECK(ran == false)

			if wait_time <= 0 then
				step_scheduler()
			else
				step_scheduler()
				CHECK(ran == false)
				step_scheduler(wait_time)
			end

			CHECK(ran == true)
		end
	end

	do
		CASE("schedular.wait() is cancelable")

		local triggered = false
		local thread = task.spawn(function()
			scheduler.wait()
			triggered = true
		end)

		CHECK(triggered == false)

		scheduler.cancel(thread)

		step_scheduler(1)
		step_scheduler(2)
		step_scheduler(3)

		CHECK(triggered == false)
	end
end)

return nil
