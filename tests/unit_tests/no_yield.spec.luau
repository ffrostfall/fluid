local TEST, CASE, CHECK = require("@vendor/testkit").test()
local no_yield = require("@src/utils/no_yield")
local task = require("@lute/task")

local function yielding_function(...): unknown
	return coroutine.yield()
end

local function yielding_2_function(...): unknown
	return task.wait() :: unknown
end

local function expensive_task()
	local i = 0
	for _ = 1, 600 do
		i += 1
	end
	return i
end

TEST("no_yield", function()
	do
		CASE("fail if it's yielding")

		for _, yieldable in { yielding_function, yielding_2_function } do
			local pass = false
			local ok, traceback = xpcall(no_yield, debug.traceback :: (string) -> (), function()
				yielding_function()
				pass = true
			end)

			print("!!", traceback)
			CHECK(ok == false and pass == false and string.find(traceback :: string, "yielding_function"))
		end
	end

	do
		CASE("ok if it's not yielding")
		local r = no_yield(expensive_task)

		CHECK(r == 600)
	end

	do
		CASE("parameter check")
		local input_list = { 1, "hi", "fluid", "`", nil, "e", false, 5, coroutine.running(), function() end }

		for i = 1, #input_list do
			CHECK(no_yield(function(...)
				return ...
			end, input_list[i]) == input_list[i])
		end
	end

	do
		CASE("parameter count check")

		CHECK(select("#", no_yield(function() end)) == 2)
	end
end)

return nil
