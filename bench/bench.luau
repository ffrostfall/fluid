-- reactive graph benchmark, run with `lute run bench/bench.luau`
-- pass dev (`lute run bench/bench.luau dev`) to benchmark with dev mode enabled

local BENCH, START = require("@vendor/testkit").benchmark()
local fluid = require("@src/")
local process = require("@lute/process")

-- the first arg is the script's path
local DEV = process.args[2] == "dev"
if DEV then
	fluid.dev()
end

local step = fluid.provide_scheduler()

-- roots are destroyed after each benchmark, so teardown isn't measured
local destroy: () -> () = function() end

print(`dev = {DEV}`)

BENCH("create effect", function()
	destroy = fluid.root(function()
		local src = fluid.source(0)

		for _ = 1, START(10000) do
			fluid.effect(function()
				src()
			end)
		end
	end)
end)
destroy()

BENCH("set source with 1000 eager dependents", function()
	local src = fluid.source(0)

	destroy = fluid.root(function()
		for _ = 1, 1000 do
			fluid.effect(function()
				src()
			end)
		end
	end)

	for i = 1, START(200) do
		src(i)
	end
end)
destroy()

BENCH("set source of effect with 10 dependencies", function()
	local sources = {}
	for i = 1, 10 do
		sources[i] = fluid.source(0)
	end

	destroy = fluid.root(function()
		fluid.effect(function()
			for i = 1, 10 do
				sources[i]()
			end
		end)
	end)

	for i = 1, START(5000) do
		sources[i % 10 + 1](i)
	end
end)
destroy()

BENCH("set + flush deferred effect behind 5 derives", function()
	local src = fluid.source(0)

	destroy = fluid.root(function()
		local previous: () -> number = src
		for _ = 1, 5 do
			local read = previous
			previous = fluid.derive(function()
				return read() + 1
			end)
		end

		local last = previous
		fluid.deferred(function()
			last()
		end)
	end)

	for i = 1, START(2000) do
		src(i)
		step(1 / 60)
	end
end)
destroy()

BENCH("set + flush 50 derives that don't change", function()
	local src = fluid.source(0)
	local unrelated = fluid.source(0)

	destroy = fluid.root(function()
		local gate = fluid.derive(function()
			return unrelated() > 1e9
		end)

		local consumers = {}
		for i = 1, 50 do
			consumers[i] = fluid.derive(function()
				src()
				gate()
				return i
			end)
		end

		fluid.deferred(function()
			for i = 1, 50 do
				consumers[i]()
			end
		end)
	end)

	for i = 1, START(2000) do
		-- alternates between rerunning everything, and only rerunning the gate
		if i % 2 == 0 then
			src(i)
		else
			unrelated(i)
		end
		step(1 / 60)
	end
end)
destroy()

BENCH("step 1000 springs", function()
	local targets = {}

	destroy = fluid.root(function()
		for i = 1, 1000 do
			local target = fluid.source(0)
			targets[i] = target

			local spring = fluid.spring(target, 10, 0.5)
			fluid.effect(function()
				spring()
			end)
		end
	end)

	for i = 1, 1000 do
		targets[i](100)
	end

	for _ = 1, START(300) do
		step(1 / 60)
	end
end)
destroy()

BENCH("step 100 intervals", function()
	destroy = fluid.root(function()
		for _ = 1, 100 do
			local elapsed = 0
			local value = fluid.interval(function(dt)
				elapsed += dt
				return elapsed
			end)

			fluid.effect(function()
				value()
			end)
		end
	end)

	for _ = 1, START(600) do
		step(1 / 60)
	end
end)
destroy()
