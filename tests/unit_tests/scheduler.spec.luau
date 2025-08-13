local TEST, CASE, CHECK = require("@vendor/testkit").test()
local fluid = require("@src/")
local signal = require("@vendor/signal")
local task = require("@lute/task")

local scheduler = fluid.__SCHEDULER_INTERFACE
local render_event: signal.Identity<number> = signal()

local step_fluid = fluid.provide_scheduler()

task.spawn(function()
	while true do
		step_fluid(render_event:wait())
	end

	return error("unreachable")
end)

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
	CASE("1 second delta time")
	do
		table.clear(scheduler.connections)
		local counted_seconds = 0

		scheduler.on_render(function(delta_time)
			counted_seconds += delta_time
		end)

		CHECK(counted_seconds == 0)
		render_event:fire(1)
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

			local value = fluid.interval(function()
				return counted_seconds
			end)

			render_event:fire(1)
			CHECK(value() == 1)
		end
	end)
)

return nil
