local TEST, CASE, CHECK = require("@vendor/testkit").test()
local fluid = require("@src/")
local graph = require("../../src/reactive/graph")
local hooks = require("@tests/hooks")

local WEAK_TABLE = { __mode = "kv" }

local scheduler = fluid.__SCHEDULER_INTERFACE
local step_scheduler = hooks.scheduler.step

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
-- local function run_garbage_collection(n: number?)
-- for i = 1, n or 3 do
-- (collectgarbage :: any)("collect")
-- end
-- end

-- local function weak<T>(t: T & {}): T
-- 	setmetatable(t :: {}, { __mode = "kv" })
-- 	return t
-- end

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

		-- do
		-- 	CASE("garbage collection")
		-- 	-- check that `b` does not allow gc of `a`
		-- 	local a = fluid.source(1)

		-- 	local _b = fluid.derive(function()
		-- 		return a()
		-- 	end)

		-- 	_b = nil

		-- 	local wref = setmetatable({ a }, WEAK_TABLE)

		-- 	run_garbage_collection()
		-- 	CHECK(wref[1])
		-- end
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
				scheduler.wait(1)

				return #text()
			end)

			local size_value: number? = 0
			fluid.effect(function()
				size_value = value()
			end)

			text("hi")
			step_scheduler(0.5)
			CHECK(size_value == nil)
			step_scheduler(0.5)
			CHECK(size_value == 2)
			text("what")

			step_scheduler(0.5)
			CHECK(size_value == 2)
			step_scheduler(0.5)
			CHECK(size_value == 4)
		end
	end)
)

TEST(
	"for_keys()",
	wrap_root(function()
		local create = fluid.create
		local source = fluid.source
		local effect = fluid.effect
		local for_keys = fluid.for_keys
		local cleanup = fluid.cleanup
		local root = fluid.root

		do
			CASE("use source")
			local input = source({ 1, 2, 3 })

			local output = for_keys(input, function(v, k)
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
				output = for_keys(input, function(v, i)
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

			local output = for_keys(input, function(v, i)
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

		-- do
		-- 	CASE("garbage collection")
		-- 	do -- check that `output` does not allow gc of `input`
		-- 		local input = source({})

		-- 		local _derived = for_keys(input, function(v, i)
		-- 			return v
		-- 		end)

		-- 		local wref = weak({ input })

		-- 		input = NIL

		-- 		run_garbage_collection()
		-- 		CHECK(wref[1])
		-- 	end

		-- 	do -- check that `input` allows gc of `output`
		-- 		local input = source({})

		-- 		local output = for_keys(input, function(v, i)
		-- 			return v, i
		-- 		end)

		-- 		local wref = weak({ output })

		-- 		output = NIL

		-- 		run_garbage_collection()
		-- 		CHECK(not wref[1])
		-- 	end
		-- end

		do
			CASE("cleanup")
			local input = source({ 1, 2, 3 })

			local count = table.create(3, 0)

			local output = for_keys(input, function(v, i)
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
			local did_output_catch_me = false

			hooks.logging.on_warn(function(err)
				if string.find(err, "catch me") then
					did_output_catch_me = true
				end
			end)

			local ok = pcall(function()
				return for_keys(input, function()
					error("catch me")
					return nil
				end)()
			end)

			hooks.logging.on_warn(nil)

			CHECK(did_output_catch_me)
			CHECK(not ok)
			CHECK(scope == graph.get_scope())
		end

		-- practical example based on the graph - recursive update test
		do
			CASE("recursive update")
			local items = source({ 1 })

			local updated = table.create(100, 0)

			effect(for_keys(items, function(item)
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

		do
			CASE("remove after delay")
			local items = source({ 1 })

			local data = for_keys(items, function(value)
				return value, 0
			end)

			CHECK(#data() == 1)
			items({})
			CHECK(#data() == 1)
			step_scheduler()
			CHECK(#data() == 0)
		end

		do
			CASE("re-activate inactive node")
			local items = source({ 1 })
			local updates = 0

			local data = for_keys(items, function(value)
				updates += 1
				return value, 0
			end)

			CHECK(#data() == 1)
			items({})
			CHECK(#data() == 1)
			CHECK(updates == 1)
			step_scheduler()
			items({ 1 }) -- should cancel thread
			-- we need to evaluate for_keys again so it can cancel the thread.
			-- otherwise it'll get rid of the node anyways. this shouldn't be too problematic though.

			CHECK(updates == 1)
			CHECK(#data() == 1)
			step_scheduler()
			CHECK(#data() == 1)
			CHECK(updates == 2)
		end
	end)
)

TEST(
	"for_values()",
	wrap_root(function()
		local create = fluid.create
		local source = fluid.source
		local for_values = fluid.for_values
		local cleanup = fluid.cleanup
		local effect = fluid.effect

		do
			CASE("use source")
			local input = source({ 1, 2, 3 })

			local output = for_values(input, function(v, k)
				CHECK(typeof(v) == "number")
				CHECK(typeof(k()) == "number")

				return tostring(v)
			end)

			CHECK("" .. input()[1] == output()[1])
			CHECK("" .. input()[2] == output()[2])
			CHECK("" .. input()[3] == output()[3])
		end

		do
			CASE("cache result")
			local input = source({ 1, 2, 3 })

			local count = table.create(3, 0)

			local output = for_values(input, function(v, i)
				CHECK(typeof(v) == "number")
				CHECK(typeof(i()) == "number")
				count[v] += 1
				return i
			end)

			input({ 1, 3, 2 })

			CHECK(output()[1]() == 1)
			CHECK(output()[2]() == 3)
			CHECK(output()[3]() == 2)

			CHECK(count[1] == 1)
			CHECK(count[2] == 1)
			CHECK(count[3] == 1)
		end

		do
			CASE("removal reflected")
			local input = source({ 1, 2, 3 })

			local destroyed = false

			local output = for_values(input, function(v, i)
				CHECK(typeof(v) == "number")
				CHECK(typeof(i()) == "number")
				local s = source(tostring(i()))
				effect(function()
					s(tostring(i()))
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
			CASE("removal reflected 2")
			local input = source({ 1 })

			local output = for_values(input, function(v, i)
				return { v = v, i = i }
			end)

			input({ 2, 1 })
			input({ 1 })

			local t = output()

			CHECK(t[1].v == 1)
			CHECK(t[1].i() == 1)
			CHECK(t[2] == nil)
			CHECK(t[3] == nil)
		end

		do
			CASE("no unnecessary reavals")
			local input = source({ 1 })
			local evaluated = {}

			local output = for_values(input, function(v, i)
				CHECK(evaluated[v] == nil)
				evaluated[v] = true
				return true
			end)

			input({ 2, 1 })
			input({ 1 })

			local t = output()

			CHECK(t[2] == nil)
			CHECK(t[3] == nil)
		end

		do
			CASE("cleanup")
			local input = source({ 1, 2, 3 })

			local count = table.create(3, 0)

			local output = for_values(input, function(v, i)
				cleanup(function()
					count[i()] += 1
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
			local n0 = graph.get_scope()
			local input = source({ 1 })

			local did_output_catch_me = false

			hooks.logging.on_warn(function(err)
				if string.find(err, "catch me") then
					did_output_catch_me = true
				end
			end)

			local ok = pcall(function()
				for_values(input, function()
					error("catch me")
					return nil
				end)()
			end)

			CHECK(not ok)
			CHECK(did_output_catch_me == true)

			local n1 = graph.get_scope()

			CHECK(n0 == n1)
			hooks.logging.on_warn(nil)
		end

		do
			CASE("remove after delay")
			local items = source({ 1 })

			local data = for_values(items, function(value)
				return value, 0
			end)

			CHECK(#data() == 1)
			items({})
			CHECK(#data() == 1)
			step_scheduler()
			CHECK(#data() == 0)
		end

		do
			CASE("re-activate inactive node")
			local items = source({ 1 })
			local updates = 0

			local data = for_values(items, function(value)
				updates += 1
				return value, 0
			end)

			CHECK(#data() == 1)
			items({})
			CHECK(#data() == 1)
			CHECK(updates == 1)
			step_scheduler()
			items({ 1 }) -- should cancel thread
			-- we need to evaluate for_keys again so it can cancel the thread.
			-- otherwise it'll get rid of the node anyways. this shouldn't be too problematic though.
			CHECK(updates == 1)
			CHECK(#data() == 1)
			step_scheduler()
			CHECK(#data() == 1)
			CHECK(updates == 2)
		end
	end)
)

TEST(
	"show",
	wrap_root(function()
		CASE("works")
		do
			local condition_source = fluid.source(true)

			local node = fluid.show(function()
				return not condition_source()
			end, function()
				return "truthy condition"
			end, function()
				return "falsy condition"
			end)

			CHECK(node() == "falsy condition")

			condition_source(false)

			CHECK(node() == "truthy condition")
		end
	end)
)

TEST(
	"show delay",
	wrap_root(function()
		do
			CASE("works")
			local condition_source = fluid.source(true)

			local node = fluid.show_delay(function()
				return not condition_source()
			end, function()
				return "truthy condition"
			end, function()
				return "falsy condition"
			end)

			CHECK(node()[1] == "falsy condition")

			condition_source(false)

			CHECK(node()[1] == "truthy condition")
		end
		do
			CASE("delay")
			local condition_source = fluid.source(true)

			local node = fluid.show_delay(function()
				return not condition_source()
			end, function()
				return "truthy condition", 0
			end, function()
				return "falsy condition", 0
			end)

			CHECK(#node() == 1)
			condition_source(false)
			CHECK(#node() == 2)
			step_scheduler()
			CHECK(#node() == 1)
		end
		do
			CASE("re-activate destroyed nodes")
			local condition_source = fluid.source(true)
			local updates = 0

			local node = fluid.show_delay(function()
				return not condition_source()
			end, function()
				updates += 1
				return "truthy condition", 0
			end, function()
				return "falsy condition", 0
			end)

			CHECK(#node() == 1)
			condition_source(false)
			CHECK(#node() == 2)
			step_scheduler()
			condition_source(true)
			step_scheduler()
			CHECK(#node() == 2)
			CHECK(updates == 1)
		end
	end)
)

TEST(
	"switch",
	wrap_root(function()
		CASE("works")
		do
			local condition_source = fluid.source(1)

			local node = fluid.switch(condition_source)({
				[1] = function()
					return 1
				end,
				[2] = function()
					return 2
				end,
				[3] = function()
					return 3
				end,
			})

			CHECK(node() == 1)
			condition_source(2)
			CHECK(node() == 2)
			condition_source(3)
			CHECK(node() == 3)
			condition_source(4)
			CHECK(node() == nil)
			condition_source(1)
			CHECK(node() == 1)
		end
	end)
)

TEST(
	"switch delay",
	wrap_root(function()
		CASE("works")
		do
			local condition_source = fluid.source(1)

			local node = fluid.switch_delay(condition_source)({
				[1] = function()
					return 1, nil
				end,
				[2] = function()
					return 2, nil
				end,
				[3] = function()
					return 3, nil
				end,
			})

			CHECK(node()[1] == 1)
			condition_source(2)
			CHECK(node()[1] == 2)
			condition_source(3)
			CHECK(node()[1] == 3)
			condition_source(4)
			CHECK(node()[1] == nil)
			condition_source(1)
			CHECK(node()[1] == 1)
		end

		CASE("delay should destroy")
		do
			local condition_source = fluid.source(1)

			local node = fluid.switch_delay(condition_source)({
				[1] = function()
					return 1, 0
				end,
				[2] = function()
					return 2, 0
				end,
				[3] = function()
					return 3, 0
				end,
			})

			CHECK(node()[1] == 1)
			condition_source(2)
			CHECK(#node() == 2)
			condition_source(3)
			CHECK(#node() == 3)
			condition_source(4)
			CHECK(#node() == 3)
			step_scheduler()
			step_scheduler()
			CHECK(#node() == 0)
		end

		CASE("reactivate nodes")
		do
			local condition_source = fluid.source(1)
			local instantiations = 0

			local node = fluid.switch_delay(condition_source)({
				[1] = function()
					return 1, 0
				end,
				[2] = function()
					instantiations += 1
					return 2, 0
				end,
				[3] = function()
					return 3, 0
				end,
			})

			CHECK(node()[1] == 1)
			condition_source(2)
			CHECK(#node() == 2)
			CHECK(instantiations == 1)
			condition_source(3)
			CHECK(#node() == 3)
			condition_source(4)
			CHECK(#node() == 3)
			step_scheduler()
			condition_source(2)
			step_scheduler()
			CHECK(instantiations == 1)
			CHECK(#node() == 1)
		end
	end)
)

TEST(
	"groups",
	wrap_root(function()
		do
			CASE("groups exist")
			fluid.graph.set_group(fluid.graph.new_group("test"))

			local node = fluid.graph.create_stable_node(false)
			CHECK(fluid.graph.get_group(node) ~= nil)

			fluid.graph.clear_group()
		end
	end)
)

TEST(
	"no yield in reactive scopes",
	wrap_root(function()
		do
			CASE("works")

			local did_yield = false
			hooks.logging.on_warn(function(text)
				did_yield = string.find(text, "attempted to yield in a callback") ~= nil
			end)

			fluid.effect(function()
				coroutine.yield()
			end)

			CHECK(did_yield == true)
		end
	end)
)

return nil
