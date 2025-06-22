local TEST, CASE, CHECK = require("@vendor/testkit").test()
local fluid = require("@src/")
local graph = require("../../src/reactive/graph")
local task = require("@lune/task")

local WEAK_TABLE = { __mode = "kv" }

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

--[=[
	Run garbage collection. We need to do garbage collection tests with this because we're still using Luau GC
	
	Fusion does scopes to avoid using Luau GC because it's easy for memory leaks to happen.
	But that's horrific for DX
]=]
local function run_garbage_collection(n: number?)
	for i = 1, n or 3 do
		(collectgarbage :: any)("collect")
	end
end

--[=[
	Creates a weak table necessary for garbage collection
]=]
local function weak<T>(t: T & {}): T
	setmetatable(t :: {}, { __mode = "kv" })
	return t
end

TEST("root", function()
	local count = 0

	do
		CASE("cleanup functions execute on source deletion")

		fluid.root(function(destroy)
			fluid.cleanup(function()
				count += 1
			end)

			destroy()
		end)

		CHECK(count == 1)
	end
end)

TEST(
	"source",
	wrap_root(function()
		do
			CASE("create source")
			local src = fluid.source(1)
			CHECK(src() == 1)
		end

		do
			CASE("set and get source value")
			local src = fluid.source(1)
			src(2)
			CHECK(src() == 2)
		end

		do
			CASE("does not update if same value")
			local src = fluid.source(1)

			local count = 0
			fluid.effect(function()
				src()
				count += 1
			end)

			CHECK(count == 1)
			src(1)
			CHECK(count == 1)
			src(2)
			CHECK(count == 2)
		end

		do
			CASE("does update if same value is mutable table")
			local src = fluid.source({})

			local count = 0
			fluid.effect(function()
				src()
				count += 1
			end)

			CHECK(count == 1)
			src(src())
			CHECK(count == 2)
		end

		do
			CASE("does not update if same value is frozen table")
			local a = table.freeze({})
			local b = table.freeze({})

			local src = fluid.source(a)

			local count = 0
			fluid.effect(function()
				src()
				count += 1
			end)

			CHECK(count == 1)
			src(a)
			CHECK(count == 1)
			src(b)
			CHECK(count == 2)
			src(b)
			CHECK(count == 2)
		end
	end)
)

TEST(
	"derive",
	wrap_root(function()
		do
			CASE("derive new value on source change")
			local a = fluid.source(1)
			local b = fluid.source(2)

			local c = fluid.derive(function()
				return tostring(a() + b())
			end)

			CHECK(c() == "3")
			a(2)
			CHECK(c() == "4")
		end

		do
			CASE("derive wrapped source")
			local a = fluid.source(1)

			local b = function()
				return tostring(a())
			end

			local c = fluid.derive(function()
				return tonumber(b())
			end)

			CHECK(c() == 1)
			a(2)
			CHECK(c() == 2)
		end

		do
			CASE("does not update if same value")
			local num = fluid.source(0)

			local is_even = fluid.derive(function()
				return bit32.band(num(), 0b01) == 0
			end)

			local count = 0

			fluid.effect(function()
				is_even()
				count += 1
			end)

			num(1) -- odd
			CHECK(count == 2)
			num(2) -- even
			CHECK(count == 3)
			num(4) -- even
			CHECK(count == 3)
			num(5) -- odd
			CHECK(count == 4)
		end

		do
			CASE("conditional derive")
			local a = fluid.source(false)
			local b = fluid.source(false)

			local c = fluid.derive(function()
				return if a() then "a" elseif b() then "b" else "never"
			end)

			local count = 0

			fluid.effect(function()
				c()
				count += 1
			end)

			b(true)
			CHECK(c() == "b")
			CHECK(count == 2)
			a(true)
			CHECK(c() == "a")
			CHECK(count == 3)
			b(false)
			CHECK(count == 3)
			b(true)
			CHECK(count == 3)
			a(false)
			CHECK(c() == "b")
			CHECK(count == 4)
		end

		do
			CASE("owner not disconnected")
			local count = 0
			local a = fluid.source(0)
			local _b

			local destroy = fluid.root(function()
				_b = fluid.derive(function()
					fluid.cleanup(function()
						count += 1
					end)

					return a()
				end)
				_b()
			end)

			CHECK(count == 0)
			a(1) -- b clears parents (should not clear owner)
			local _ = (_b :: any)()
			CHECK(count == 1)
			destroy()
			CHECK(count == 2)
		end

		do
			CASE("behavior of effect within an effect")
			local num = fluid.source(1)

			local ran = table.create(100, 0)
			local cleaned = table.create(100, 0)

			local destroy = fluid.root(function()
				local owner = fluid.derive(function()
					local i = num()

					return fluid.untrack(function()
						return fluid.derive(function()
							ran[i] += 1

							fluid.cleanup(function()
								cleaned[i] += 1
							end)

							return i
						end)
					end)
				end)

				local child1 = owner()
				owner()()
				num(2)
				owner()()
				CHECK(cleaned[1] == 1)
				local child2 = owner()

				CHECK(child1() == 1)
				CHECK(child2() == 2)
			end)

			destroy()

			CHECK(ran[1] == 1)
			CHECK(ran[2] == 1)
			CHECK(cleaned[1] == 1)
			CHECK(cleaned[2] == 1)
		end

		do
			CASE("garbage collection")
			-- check that `b` does not allow gc of `a`
			local a = fluid.source(1)

			local _b = fluid.derive(function()
				return a()
			end)

			_b = nil

			local wref = setmetatable({ a }, WEAK_TABLE)

			run_garbage_collection()
			CHECK(wref[1])
		end
	end)
)

TEST(
	"effect",
	wrap_root(function()
		do
			CASE("rerun on source change")
			local a = fluid.source(1)
			local b = fluid.source(1)

			local count = 0
			fluid.effect(function()
				a()
				b()
				count += 1
			end)

			CHECK(count == 1)
			a(2)
			CHECK(count == 2)
			b(2)
			CHECK(count == 3)
		end

		do
			CASE("rerun on derived source change")
			local num = fluid.source(0)

			local text = fluid.derive(function()
				return tostring(num())
			end)

			local count = 0
			fluid.effect(function()
				text()
				count += 1
			end)

			num(1)

			CHECK(count == 2)
		end

		do
			CASE("cache")
			local num = fluid.source(0)

			local count: number

			fluid.effect(function(x: number)
				num()
				count = x + 1
				return x + 1
			end, 0)

			num(1)

			CHECK(count == 2)
		end
	end)
)

TEST(
	"async",
	wrap_root(function()
		do
			CASE("rerun on source change")
			local a = fluid.source(1)
			local b = fluid.source(1)

			local count = 0
			local value = fluid.async(function()
				a()
				b()
				count += 1
				return count
			end)

			value()
			CHECK(count == 1)
			a(2)
			value()
			CHECK(count == 2)
			b(2)
			value()
			CHECK(count == 3)
		end

		do
			CASE("rerun on derived source change")
			local num = fluid.source(0)

			local text = fluid.derive(function()
				return tostring(num())
			end)

			local count = 0
			local value = fluid.async(function()
				text()
				count += 1
				return count
			end)

			num(1)
			value()
			num(2)
			value()
			CHECK(count == 3)
		end

		do
			CASE("state should show actual state")

			local thread
			local _, state = fluid.async(function()
				thread = coroutine.running()
				coroutine.yield()
				return 0
			end)

			CHECK(state() == "busy")
			coroutine.resume(thread :: any)
			CHECK(state() == "ok")
		end

		do
			CASE("run cleanups if thread is invalidated while yielding")
			local num = fluid.source(0)

			local did_run = false

			local value = fluid.async(function()
				num()

				fluid.cleanup(function()
					did_run = true
				end)

				coroutine.yield()
				return 0
			end)

			value()
			CHECK(did_run == false)
			num(1)
			CHECK(did_run == true)
		end

		do
			CASE("dependencies only update if value is updated")
			local count = 0
			local thread = coroutine.running()

			local value = fluid.async(function(set)
				thread = coroutine.running()
				set(0)
				coroutine.yield()

				set(1)
				set(2)
				return 3
			end)

			fluid.effect(function()
				value()
				count += 1
			end)

			coroutine.resume(thread)
			CHECK(count == 4)
		end

		do
			CASE("yield bug #1")
			local text = fluid.source("h")

			local value = fluid.async(function(set)
				task.wait(0.1)

				return #text()
			end)

			local size_value = 0
			fluid.effect(function()
				size_value = value()
			end)

			text("hi")
			task.wait(0.3)
			CHECK(size_value == 2)
			text("what")
			task.wait(0.3)
			CHECK(size_value == 4)
		end
	end)
)

TEST(
	"indexes",
	wrap_root(function()
		local create = fluid.create
		local source = fluid.source
		local effect = fluid.effect
		local indexes = fluid.indexes
		local cleanup = fluid.cleanup

		do
			CASE("use source")
			local input = source({ 1, 2, 3 })

			local output = indexes(input, function(v, k)
				return tostring(v())
			end)

			CHECK("" .. input()[1] == output()[1])
			CHECK("" .. input()[2] == output()[2])
			CHECK("" .. input()[3] == output()[3])
		end

		do
			CASE("cache result")
			local input = source({ 1, 2, 3 })

			local count = table.create(3, 0)
			local output
			local _ = fluid.root(function()
				output = indexes(input, function(v, i)
					count[i] += 1
					return v
				end)
			end)

			input({ 1, 2, 4 })

			CHECK(output()[1]() == 1)
			CHECK(output()[2]() == 2)
			CHECK(output()[3]() == 4)

			CHECK(count[1] == 1)
			CHECK(count[2] == 1)
			CHECK(count[3] == 1)
		end

		do
			CASE("removal reflected")
			local input = source({ 1, 2, 3 })

			local destroyed = false

			local output = indexes(input, function(v, i)
				local s = source()

				effect(function()
					s(tostring(v()))
				end)

				cleanup(function()
					destroyed = true
				end)

				return s
			end)

			output()

			input({ 1, 2 })

			local t = output()

			CHECK(t[1]() == "1")
			CHECK(t[2]() == "2")
			CHECK(t[3] == nil)
			CHECK(destroyed == true)
		end

		do
			CASE("garbage collection")
			do -- check that `output` does not allow gc of `input`
				local input = source({})

				local _derived = indexes(input, function(v, i)
					return v
				end)

				local wref = weak({ input })

				input = NIL

				run_garbage_collection()
				CHECK(wref[1])
			end

			do -- check that `input` allows gc of `output`
				local input = source({})

				local output = indexes(input, function(v, i)
					return v, i
				end)

				local wref = weak({ output })

				output = NIL

				run_garbage_collection()
				CHECK(not wref[1])
			end
		end

		do
			CASE("cleanup")
			local input = source({ 1, 2, 3 })

			local count = table.create(3, 0)

			local output = indexes(input, function(v, i)
				cleanup(function()
					count[i] += 1
				end)

				return {}
			end)

			output()

			CHECK(count[1] == 0)
			CHECK(count[2] == 0)
			CHECK(count[3] == 0)
		end

		do
			CASE("reactive stack resets after error")
			local scope = graph.get_scope()

			local input = source({ 1 })

			local ok = pcall(function()
				indexes(input, function()
					error("")
					return NIL
				end)()
			end)

			CHECK(not ok)
			CHECK(scope == graph.get_scope())
		end

		-- practical example based on the graph - recursive update test
		do
			CASE("recursive update")
			local items = source({ 1 })

			local updated = table.create(100, 0)

			effect(indexes(items, function(item)
				effect(function()
					item()
					updated[1] += 1
				end)

				effect(function()
					item()
					updated[2] += 1
				end)

				return {}
			end))

			effect(function()
				items()
				updated[3] += 1
			end)

			effect(function()
				items()
				updated[4] += 1
			end)

			items({ 2 })

			CHECK(updated[1] == 2)
			CHECK(updated[2] == 2)
			CHECK(updated[3] == 2)
			CHECK(updated[4] == 2)
		end
	end)
)

return nil
