local TEST, CASE, CHECK = require("@vendor/testkit").test()
local no_yield = require("@src/utils/no_yield")
local task = require("@lune/task")

local function yielding_function(): unknown
	return coroutine.yield()
end

local function yielding_2_function(): unknown
	return task.wait() :: unknown
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
		CASE("result.fail if it's yielding #coroutine.yield")
		local r = no_yield(yielding_function)

		CHECK(not r.success)
	end

	do
		CASE("result.fail if it's yielding #task.wait")
		local r = no_yield(yielding_2_function)

		CHECK(not r.success)
	end

	do
		CASE("result.ok if it's not yielding")
		local r = no_yield(no_yieding_function)

		CHECK(r.success)
	end
end)

return nil
