if _G.__DEV__ == nil then
	-- thanks type state
	_G.__DEV__ = (game and not game:GetService("RunService"):IsStudio()) :: any
end

local action = require("@self/instances/action")
local async = require("@self/reactive/async")
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
local root = require("@self/reactive/root")
local scheduler = require("@self/scheduler")
local source = require("@self/reactive/source")
local tags = require("@self/utils/tags")
local types = require("@self/reactive/types")
local untrack = require("@self/reactive/untrack")

export type UsedAs<T> = types.UsedAs<T>
export type Source<T> = types.Source<T>

if game then
	local RunService = game:GetService("RunService")

	scheduler.provide(function(render)
		while true do
			local delta_time = RunService.PreRender:Wait()
			graph.flush_deferred_nodes()
			render(delta_time)
		end

		return error("unreachable")
	end)
end

local fluid = {}

fluid.create = create
fluid.mount = mount
fluid.tags = tags

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

fluid.lerp = lerp

fluid.__SCHEDULER_INTERFACE = scheduler

return fluid
