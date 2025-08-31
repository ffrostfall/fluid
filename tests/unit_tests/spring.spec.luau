local TEST, CASE, CHECK = require("@vendor/testkit").test()
local fluid = require("@src/")
local task = require("@lune/task")

local provided_scheduler = fluid.provide_scheduler()

local function step_scheduler(n: number?)
	task.spawn(provided_scheduler, n or 1 / 60)
end

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

TEST(
	"spring",
	wrap_root(function()
		for _, test in
			{
				{ 5, 15, 5, -5, -60, 60, 20 },
				{
					vector.create(5, 10),
					vector.create(10, 5),
					vector.create(-5, -10),
					vector.create(1, 7),
					vector.create(0, 0),
					vector.create(10, 10),
				},
			}
		do
			local spring_target = fluid.source(test[1])
			local spring, controls = fluid.spring(spring_target, 10, 1)
			local data_type = type(test[1])

			local function rng_self_type()
				if data_type == "vector" then
					return vector.create(math.random(), math.random(), math.random())
				end
				return math.random() :: any
			end

			for i = 2, #test do
				local target = test[i]

				CASE(`spring [{test[i - 1]}] to [{target}]`)
				spring_target(target)
				step_scheduler(1 / 60)
				CHECK(spring() ~= target)
				step_scheduler(100)
				CHECK(spring() == target)

				CASE(`spring position`)
				controls({
					position = rng_self_type() * 10,
				})
				step_scheduler(1 / 60)
				CHECK(spring() ~= target)
				step_scheduler(3)
				CHECK(spring() == target)

				CASE(`spring velocity [self-type]`)
				controls({
					velocity = rng_self_type() * 10,
				})
				step_scheduler(1 / 60)
				CHECK(spring() ~= target)
				step_scheduler(3)
				CHECK(spring() == target)

				CASE(`spring impulse [self-type]`)
				controls({
					impulse = rng_self_type() * 10,
				})

				step_scheduler(1 / 60)
				CHECK(spring() ~= target)
				step_scheduler(3)
				CHECK(spring() == target)
			end
		end
	end)
)

return nil
