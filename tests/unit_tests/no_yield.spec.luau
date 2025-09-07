local TEST, CASE, CHECK = require("@vendor/testkit").test()
local no_yield = require("@src/utils/no_yield")
local task = require("@lune/task")

local function yielding_function(): unknown
	return coroutine.yield()
end

local function yielding_2_function(): unknown
	return task.wait() :: unknown
end

local function error_handler()
	return "failed"
end

local function no_yieding_function()
	local i = 0
	for _ = 1, 600 do
		i += 1
	end
	return i
end

TEST("no_yield", function()
	do
		CASE("fail if it's yielding #coroutine.yield")
		local ok, result = xpcall(no_yield, error_handler, yielding_function)

		CHECK(ok == false and result == "failed")
	end

	do
		CASE("fail if it's yielding #task.wait")
		local ok, result = xpcall(no_yield, error_handler, yielding_2_function)

		CHECK(ok == false and result == "failed")
	end

	do
		CASE("ok if it's not yielding")
		local ok, result = xpcall(no_yield, error_handler, no_yieding_function)

		CHECK(ok == true and result == 600)
	end
end)

return nil
