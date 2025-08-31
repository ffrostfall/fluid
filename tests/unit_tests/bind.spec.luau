local TEST, CASE, CHECK = require("@vendor/testkit").test()
local bind = require("@src/instances/bind")
local fluid = require("@src/")
local graph = require("@src/reactive/graph")
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

TEST(
	"async bindings",
	wrap_root(function()
		CASE("works")
		local text = fluid.source("hi")

		local mock_inst: { derivedvalue: number? } = {
			derivedvalue = 0,
		}

		bind(mock_inst :: any, {
			derivedvalue = fluid.async(function(set)
				scheduler.wait(1)
				return #text()
			end),
		})

		graph.flush_deferred_nodes()
		step_scheduler(0.5)
		CHECK(mock_inst.derivedvalue == nil)

		step_scheduler(0.5)
		CHECK(mock_inst.derivedvalue == 2)

		text("one")
		graph.flush_deferred_nodes()

		step_scheduler(0.5)
		CHECK(mock_inst.derivedvalue == 2)
		step_scheduler(0.5)

		CHECK(mock_inst.derivedvalue == 3)
	end)
)

return nil
