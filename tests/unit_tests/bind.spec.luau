local TEST, CASE, CHECK = require("@vendor/testkit").test()
local bind = require("@src/instances/bind")
local fluid = require("@src/")
local graph = require("@src/reactive/graph")
local task = require("@lute/task")

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
		local text = fluid.source("hi")

		local mock_inst = {
			derivedvalue = 0,
		}

		bind(mock_inst :: any, {
			derivedvalue = fluid.async(function(set)
				task.wait(0.02)
				return #text()
			end),
		})

		task.wait(0.05)

		graph.flush_deferred_nodes()
		CHECK(mock_inst.derivedvalue == 2)

		text("one")
		graph.flush_deferred_nodes()

		task.wait(0.05)

		graph.flush_deferred_nodes()
		CHECK(mock_inst.derivedvalue == 3)
	end)
)

return nil
