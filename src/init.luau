if _G.__DEV__ == nil then
	-- thanks type state
	_G.__DEV__ = (game and not game:GetService("RunService"):IsStudio()) :: any
end

local action = require("@self/instances/action")
local async = require("@self/reactive/async")
local bind = require("@self/instances/bind")
local cleanup = require("@self/reactive/cleanup")
local create = require("@self/instances/create")
local derive = require("@self/reactive/derive")
local effect = require("@self/reactive/effect")
local for_keys = require("@self/instances/for_keys")
local for_values = require("@self/instances/for_values")
local graph = require("@self/reactive/graph")
local interval = require("@self/utils/interval")
local lerp = require("@self/anim/lerp")
local mount = require("@self/instances/mount")
local read = require("@self/utils/read")
local root = require("@self/reactive/root")
local scheduler = require("@self/scheduler")
local show = require("@self/utils/show")
local source = require("@self/reactive/source")
local spring = require("@self/anim/spring/spring_file")
local tags = require("@self/utils/tags")
local types = require("@self/reactive/types")
local untrack = require("@self/reactive/untrack")

export type UsedAs<T> = types.UsedAs<T>
export type Source<T> = types.Source<T>
export type Action = action.Identity
export type PropertiesFor<T> = create.PropertiesFor<T>

local scheduler_thread: thread? = nil

local function step(delta_time: number)
	-- This will call intervals
	scheduler.step(delta_time)

	-- Runs deferred nodes
	graph.flush_deferred_nodes()

	-- Finally, after all state is reconciled, we animate
	lerp.step(delta_time)
	spring.step(delta_time)
end

if game then
	local RunService = game:GetService("RunService")

	scheduler_thread = task.spawn(function()
		while true do
			local delta_time = RunService.PreRender:Wait()

			step(delta_time)
		end
	end)
end

local fluid = {}

fluid.create = create
fluid.mount = mount
fluid.tags = tags
fluid.bind = bind

-- actions
fluid.action = action.create
fluid.is_action = action.is_action

-- Reactive graph
fluid.cleanup = cleanup
fluid.derive = derive
fluid.effect = effect
fluid.graph = graph
fluid.root = root
fluid.source = source
fluid.untrack = untrack
fluid.interval = interval
fluid.for_keys = for_keys
fluid.async = async
fluid.for_values = for_values
fluid.read = read
fluid.show = show

-- Animation
fluid.lerp = lerp.create
fluid.spring = spring.create

-- Scheduling
fluid.provide_scheduler = function(): (delta_time: number) -> ()
	if scheduler_thread then
		task.cancel(scheduler_thread)
		scheduler_thread = nil
	end

	return step
end

fluid.__SCHEDULER_INTERFACE = scheduler

return fluid
