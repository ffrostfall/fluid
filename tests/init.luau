local process = require("@lune/process")
local _, _, _, FINISH = require("@vendor/testkit").test()

local tests = {}

function tests.fuzz()
	require("@self/fuzz_tests/colors.fuzz")()
end

function tests.unit_tests()
	require("@self/unit_tests/logging.spec")
	require("@self/unit_tests/no_yield.spec")
	require("@self/unit_tests/reactive_graph.spec")
	require("@self/unit_tests/scheduler.spec")
	require("@self/unit_tests/bind.spec")
	require("@self/unit_tests/interval.spec")
	require("@self/unit_tests/spring.spec")
	require("@self/unit_tests/colors.spec")

	local ok = FINISH()
	if not ok then
		process.exit(1)
	end
end

return tests
