local _, _, _, FINISH = require("@vendor/testkit").test()

local function call_tests(fn: () -> ())
	xpcall(fn, function(err)
		print(debug.traceback(tostring(err)))
	end)
end

local tests = {}

function tests.fuzz()
	require("@self/fuzz_tests/colors.fuzz")()
end

function tests.unit_tests()
	require("@self/unit_tests/logging.spec")
	call_tests(require("@self/unit_tests/reactive_graph.spec"))
	require("@self/unit_tests/scheduler.spec")
	require("@self/unit_tests/bind.spec")
	call_tests(require("@self/unit_tests/interval.spec"))
	require("@self/unit_tests/spring.spec")
	require("@self/unit_tests/colors.spec")

	local ok = FINISH()
	if not ok then
		require("@lute/process").exit(1)
	end
end

return tests
