local _, _, _, FINISH = require("@vendor/testkit").test()

local reactive_graph_tests = require("@self/unit_tests/reactive_graph.spec")

local tests = {}

function tests.fuzz()
	require("@self/fuzz_tests/colors.fuzz")()
end

function tests.unit_tests()
	xpcall(reactive_graph_tests, function()
		print("tests err:")
		print(debug.traceback())
	end)

	require("@self/unit_tests/scheduler.spec")
	require("@self/unit_tests/bind.spec")
	require("@self/unit_tests/colors.spec")

	return FINISH()
end

return tests
