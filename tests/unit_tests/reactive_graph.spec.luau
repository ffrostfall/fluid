local TEST, CASE, CHECK = require("@vendor/testkit").test()
local dev = require("@src/dev")
local fluid = require("@src/")
local graph = require("../../src/reactive/graph")
local hooks = require("@tests/hooks")

local function tests()
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

	-- slots are u16s, each one is where the edge back is in the other node's array
	local function edges_consistent(node: any): boolean
		local dependents = node.dependents
		if dependents then
			for idx, dependent in dependents do
				local slot = buffer.readu16(node.dependent_slots, idx * 2)
				if
					dependent.depending_on[slot] ~= node
					or buffer.readu16(dependent.depending_on_slots, slot * 2) ~= idx
				then
					return false
				end
			end
		end

		local depending_on = node.depending_on
		if depending_on then
			for idx, dependency in depending_on do
				local slot = buffer.readu16(node.depending_on_slots, idx * 2)
				if
					dependency.dependents[slot] ~= node
					or buffer.readu16(dependency.dependent_slots, slot * 2) ~= idx
				then
					return false
				end
			end
		end

		return true
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

		do
			CASE("cleanup accepts objects")
			local calls = {}
			local thread = coroutine.create(function()
				coroutine.yield()
			end)
			coroutine.resume(thread)

			-- methods get called with the object as self
			local function record(name: string)
				return function(_self: any)
					table.insert(calls, name)
				end
			end

			local destroy = fluid.root(function()
				fluid.cleanup({ destroy = record("destroy") })
				fluid.cleanup({ disconnect = record("disconnect") })
				fluid.cleanup({ Destroy = record("Destroy") })
				fluid.cleanup({ Disconnect = record("Disconnect") })
				-- same priority as before, destroy wins over Destroy
				fluid.cleanup({ destroy = record("priority"), Destroy = record("wrong") })
				fluid.cleanup(function()
					table.insert(calls, "function")
				end)
				fluid.cleanup(thread)
			end)

			CHECK(#calls == 0)
			destroy()
			CHECK(table.concat(calls, ",") == "destroy,disconnect,Destroy,Disconnect,priority,function")
			CHECK(coroutine.status(thread) == "dead")
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
				CASE("derive doesn't rerun if nothing changed since its last run")
				local first = fluid.source(0)
				local second = fluid.source(0)
				local gate = fluid.derive(function()
					return second() > 100
				end)

				local runs = 0
				local value = fluid.derive(function()
					first()
					gate()
					runs += 1
					return 0
				end)

				value()
				first(1) -- reruns, but returns the same value
				value()
				CHECK(runs == 2)
				second(1) -- gate reruns, but doesn't change
				value()
				CHECK(runs == 2)
			end

			do
				CASE("keeps dependency on a dirty derive that didn't change")
				local first = fluid.source(0)
				local condition = fluid.source(1)
				local text = fluid.source("a")

				local positive = fluid.derive(function()
					return condition() > 0
				end)
				local value = fluid.derive(function()
					return if positive() then text() else "none"
				end)

				local seen
				fluid.deferred(function()
					first()
					seen = value()
				end)

				CHECK(seen == "a")
				condition(2) -- positive reruns, but stays true
				first(1)
				step_scheduler()
				text("b")
				step_scheduler()
				CHECK(seen == "b")
			end

			do
				CASE("node destroyed by its owner rerunning doesn't run again")
				local src = fluid.source(0)
				local other = fluid.source(0)
				local runs = 0

				local owner: () -> number
				owner = fluid.derive(function()
					local value = src()

					-- owned by the derive, so the derive rerunning destroys it
					fluid.untrack(function()
						fluid.deferred(function()
							other()
							owner()
							runs += 1
						end)
						return nil
					end)

					return value
				end)

				owner()
				CHECK(runs == 1)

				-- it couldn't depend on owner while owner was running, so this run adds that edge
				other(1)
				step_scheduler()
				CHECK(runs == 2)

				-- updating it reruns owner first, which destroys it and creates a new one
				src(1)
				step_scheduler()
				CHECK(runs == 3)

				-- only the new one is still subscribed
				other(2)
				step_scheduler()
				CHECK(runs == 4)
			end

			do
				CASE("destroying a node with dependents keeps edges consistent")
				local scope = graph.assert_scope()
				local src = graph.create_source_node(0)
				local other = graph.create_source_node(0)

				local derived = graph.create_reactive_node(scope, function()
					graph.evaluate_node(src)
					return math.random()
				end, graph.evaluation.LAZY, nil)

				local readers: { graph.Computation<any> } = {}
				for i = 1, 5 do
					readers[i] = graph.create_effect_node(scope, function()
						-- the dead node's edge ends up in the middle of depending_on
						graph.evaluate_node(other)
						graph.evaluate_node(derived)
						graph.evaluate_node(src)
						return nil
					end, graph.evaluation.EAGER, nil)
					graph.refresh_node(readers[i])
				end

				local function all_consistent(): boolean
					local ok = edges_consistent(src) and edges_consistent(other) and edges_consistent(derived)
					for _, reader in readers do
						ok = ok and edges_consistent(reader)
					end
					return ok
				end

				CHECK(#derived.dependents == 5)
				graph.destroy(derived)
				-- the dead node keeps its dependents until they rerun
				CHECK(#derived.depending_on == 0)
				CHECK(all_consistent())

				graph.update_node(other, 1)
				CHECK(#derived.dependents == 0)
				CHECK(all_consistent())

				local still_reading = false
				for _, reader in readers do
					if table.find(reader.depending_on, derived :: any) then
						still_reading = true
					end
				end
				CHECK(not still_reading)
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

			do
				CASE("destroyed nodes don't rerun")
				local src = fluid.source(0)
				local child_runs = 0

				fluid.effect(function()
					src()

					fluid.untrack(function()
						fluid.effect(function()
							src()
							child_runs += 1
						end)
						return nil
					end)
				end)

				CHECK(child_runs == 1)
				src(1)
				CHECK(child_runs == 2)
				src(2)
				CHECK(child_runs == 3)
			end

			do
				CASE("error inside untrack doesn't kill the node")
				local src = fluid.source(0)
				local runs = 0

				hooks.logging.on_warn(function() end)
				hooks.logging.on_error(function() end)

				fluid.effect(function()
					local value = src()
					runs += 1

					fluid.untrack(function()
						if value == 1 then
							error("untracked boom")
						end
						return nil
					end)
				end)

				src(1)
				src(2)
				hooks.logging.on_warn(nil)
				hooks.logging.on_error(nil)

				CHECK(runs == 3)
			end

			do
				CASE("many effects setting sources in one invalidation don't nest")
				local src = fluid.source(0)
				local reads = 0

				for _ = 1, 300 do
					local own = fluid.source(0)

					fluid.effect(function()
						own(src())
					end)

					fluid.effect(function()
						own()
						reads += 1
					end)
				end

				reads = 0
				src(1)
				CHECK(reads == 300)
			end

			do
				CASE("erroring deferred node doesn't stop the flush")
				local src = fluid.source(0)
				local other_runs = 0
				local reported = 0

				hooks.logging.on_error(function(text)
					if string.find(text, "deferred boom") then
						reported += 1
					end
				end)

				fluid.deferred(function()
					if src() == 1 then
						error("deferred boom")
					end
				end)

				fluid.deferred(function()
					src()
					other_runs += 1
				end)

				src(1)
				local ok = pcall(fluid.provide_scheduler(), 1 / 60)
				hooks.logging.on_error(nil)

				CHECK(ok)
				CHECK(reported == 1)
				CHECK(other_runs == 2)
			end

			do
				CASE("dependencies are exactly what was read in the last run")
				local scope = graph.assert_scope()
				local a = graph.create_source_node(0)
				local b = graph.create_source_node(0)
				local c = graph.create_source_node(0)
				local trigger = graph.create_source_node(0)
				local reads: { { graph.SourceNode<number> } } = { { a, b }, { b, a }, { a }, {}, { c, a, c } }
				local runs = 0

				local node = graph.create_reactive_node(scope, function()
					runs += 1
					graph.evaluate_node(trigger)
					for _, dependency in reads[runs] do
						graph.evaluate_node(dependency)
					end
					return nil
				end, graph.evaluation.EAGER, nil)

				local function depends_on(expected: { graph.SourceNode<number> }): boolean
					local depending_on = node.depending_on
					if depending_on[1] ~= trigger or #depending_on ~= #expected + 1 then
						return false
					end

					for idx, dependency in expected do
						if depending_on[idx + 1] ~= dependency then
							return false
						end
					end

					-- and every source only has an edge back if it's still a dependency
					for _, source in { a, b, c } do
						local edges = 0
						for _, dependent in source.dependents do
							if dependent == node then
								edges += 1
							end
						end

						if edges ~= (if table.find(expected, source) then 1 else 0) then
							return false
						end
					end

					return true
				end

				graph.evaluate_node(node)
				CHECK(depends_on({ a, b }))
				graph.update_node(trigger, 1)
				CHECK(depends_on({ b, a }))
				graph.update_node(trigger, 2)
				CHECK(depends_on({ a }))
				-- b was only read in earlier runs, so it shouldn't rerun the node anymore
				graph.update_node(b, 1)
				CHECK(runs == 3)
				graph.update_node(trigger, 3)
				CHECK(depends_on({}))
				graph.update_node(trigger, 4)
				CHECK(depends_on({ c, a }))
			end

			do
				CASE("reading a dependency multiple times adds one edge")
				local scope = graph.assert_scope()
				local src = graph.create_source_node(0)
				local runs = 0

				local node = graph.create_reactive_node(scope, function()
					graph.evaluate_node(src)
					graph.evaluate_node(src)
					graph.evaluate_node(src)
					runs += 1
					return nil
				end, graph.evaluation.EAGER, nil)
				graph.evaluate_node(node)

				CHECK(#src.dependents == 1)
				CHECK(#node.depending_on == 1)

				graph.update_node(src, 1)
				CHECK(runs == 2)
				CHECK(#src.dependents == 1)
				CHECK(#node.depending_on == 1)
			end

			do
				CASE("dependency edges stay consistent")
				math.randomseed(1)
				local scope = graph.assert_scope()
				local sources: { graph.SourceNode<number> } = {}
				local nodes: { graph.ReactiveNode<any> } = {}

				for i = 1, 8 do
					sources[i] = graph.create_source_node(0)
				end

				-- lazy nodes reading random sources, then eager ones reading random sources & lazy nodes.
				-- duplicate reads are intentional, and what's read changes every run
				for i = 1, 16 do
					local is_lazy = i <= 4
					nodes[i] = graph.create_reactive_node(scope, function()
						for _ = 1, math.random(0, 6) do
							if is_lazy or math.random() < 0.6 then
								graph.evaluate_node(sources[math.random(1, 8)])
							else
								graph.evaluate_node(nodes[math.random(1, 4)])
							end
						end
						return math.random()
					end, if is_lazy then graph.evaluation.LAZY else graph.evaluation.EAGER, nil)
				end

				for i = 1, 16 do
					graph.evaluate_node(nodes[i])
				end

				for step = 1, 300 do
					graph.update_node(sources[math.random(1, 8)], math.random())

					if step == 150 then
						for i = 5, 8 do
							graph.destroy(nodes[i])
						end
					end
				end

				for _, node in sources do
					CHECK(edges_consistent(node))
				end

				for _, node in nodes do
					CHECK(edges_consistent(node))
				end

				CHECK(#nodes[5].depending_on == 0)
			end

			do
				CASE("reading more nodes than a u16 can index errors")
				local scope = graph.assert_scope()
				local sources: { graph.SourceNode<number> } = {}
				for i = 1, 65536 do
					sources[i] = graph.create_source_node(i)
				end

				local reads = 0
				local node = graph.create_reactive_node(scope, function()
					for _, source in sources do
						graph.evaluate_node(source)
						reads += 1
					end
					return nil
				end, graph.evaluation.EAGER, nil)

				local ok, err = pcall(graph.evaluate_node, node)
				CHECK(not ok)
				CHECK(string.find(tostring(err), "too_many_edges", 1, true) ~= nil)
				-- the last index a u16 can hold still works
				CHECK(reads == 65535)
				-- and hitting the limit didn't leave a half added edge behind
				local destroyed = pcall(graph.destroy, node)
				CHECK(destroyed)
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
				-- local did_output_catch_me = false

				-- hooks.logging.on_warn(function(err)
				-- 	if string.find(err, "catch me") then
				-- 		did_output_catch_me = true
				-- 	end
				-- end)

				local ok = pcall(function()
					return for_keys(input, function()
						error("catch me")
						return nil
					end)()
				end)

				hooks.logging.on_warn(nil)

				-- CHECK(did_output_catch_me)
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

			do
				CASE("keeps false values")
				local input = source({ a = false } :: { [string]: boolean })
				local creations = 0

				local output = for_keys(input, function(value)
					creations += 1
					return value()
				end)

				output()
				input({ a = false, b = true })
				output()
				CHECK(creations == 2)
			end

			do
				CASE("nil outputs are left out, false is kept")
				local input = source({ 1, 2, 3 })

				local output = for_keys(input, function(value)
					local v = value()
					return if v == 2 then nil elseif v == 3 then false else v
				end)

				local result = output()
				CHECK(#result == 2)
				CHECK(result[1] == 1)
				CHECK(result[2] == false)
			end

			do
				CASE("active is false while being removed")
				local items = source({ 1 })
				local active: () -> boolean = nil :: any

				local data = for_keys(items, function(_, _, is_active)
					active = is_active
					return 1, 0
				end)

				data()
				CHECK(active() == true)
				items({})
				data()
				CHECK(active() == false)
				items({ 1 })
				data()
				CHECK(active() == true)
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

				-- local did_output_catch_me = false

				-- hooks.logging.on_warn(function(err)
				-- 	if string.find(err, "catch me") then
				-- 		did_output_catch_me = true
				-- 	end
				-- end)

				local ok = pcall(function()
					for_values(input, function()
						error("catch me")
						return nil
					end)()
				end)

				CHECK(not ok)
				-- CHECK(did_output_catch_me == true)

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

			do
				CASE("false values")
				local items = source({ false, true })
				local created = 0

				local output = for_values(items, function(value)
					created += 1
					return value
				end)

				CHECK(#output() == 2)
				items({ true, false })
				CHECK(#output() == 2)
				CHECK(created == 2)
			end

			do
				CASE("duplicate values use the last key")
				local input = source({ "a", "a" })
				local read_key: () -> number = nil :: any

				local output = for_values(input, function(_, key)
					read_key = key
					return true
				end)

				CHECK(#output() == 1)
				CHECK(read_key() == 2)
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
		"no yield in reactive scopes",
		wrap_root(function()
			do
				CASE("works")

				local success, err: any = pcall(fluid.effect, function()
					coroutine.yield()
				end)

				CHECK(not success)
				CHECK(string.find(err, "yield") ~= nil)
			end

			do
				CASE("non-destructive erroring on yield")

				local src = fluid.source(1)
				local run_count = 0

				pcall(function()
					fluid.effect(function()
						run_count += 1
						if src() == 2 then
							coroutine.yield()
						end
					end)
				end)

				CHECK(src() == 1)

				pcall(function()
					src(2)
				end)

				CHECK(src() == 2)
				CHECK(run_count == 2)
			end

			do
				CASE("effects run on the caller's thread outside dev mode")
				local caller = coroutine.running()
				local thread

				dev.enabled = false
				fluid.effect(function()
					thread = coroutine.running()
				end)
				dev.enabled = true

				CHECK(thread == caller)
			end
		end)
	)
end

return tests
