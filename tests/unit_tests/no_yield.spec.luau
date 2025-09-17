local TEST, CASE, CHECK = require("@vendor/testkit").test()
local no_yield = require("@src/utils/no_yield")
local task = require("@lune/task")

local function yielding_function(): unknown
	return coroutine.yield()
end

local function yielding_2_function(): unknown
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
			local ok, traceback = xpcall(
				no_yield.check,
				debug.traceback :: (string) -> (),
				function()
					yielding_function()
					pass = true
				end
			)

			CHECK(
				ok == false
					and pass == false
					and string.find(traceback :: string, "yielding_function")
			)
		end
	end

	do
		CASE("ok if it's not yielding")
		local r = no_yield.check(expensive_task)

		CHECK(r == 600)
	end

	do
		CASE("paramater check")
		local input_list = { 1, "hi", "fluid", "`", nil, "e" }
		local return_list = { "7643", nil, 60000, nil, "cat", "fluid" }

		local got_return = table.pack(no_yield.check(function(...)
			local got_input = table.pack(...)
			for key, value in input_list do
				CHECK(got_input[key] == value)
			end

			return table.unpack(return_list)
		end, table.unpack(input_list)))

		for key, value in return_list do
			CHECK(got_return[key] == value)
		end
	end

	do
		CASE("no_yield error handler")

		for _, yieldable in { yielding_function, yielding_2_function } do
			local ok, traceback = xpcall(no_yield.check, no_yield.error_handler, function()
				yieldable()
			end)

			CHECK(
				ok == false
					and string.find(traceback.message, "attempted to yield in a callback")
			)
		end
	end
end)

return nil
