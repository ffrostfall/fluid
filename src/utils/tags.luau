local CollectionService = game:GetService("CollectionService")

local action = require("../instances/action")
local cleanup = require("../reactive/cleanup")
local graph = require("../reactive/graph")

local function bind_tag(instance: Instance, tag: string)
	CollectionService:AddTag(instance, tag)

	cleanup(function()
		CollectionService:RemoveTag(instance, tag)
	end)
end

local function tags<T...>(tags: { string | () -> string | nil })
	return action.create(function(instance)
		for _, tag in tags do
			if typeof(tag) == "string" then
				bind_tag(instance, tag)
				continue
			end

			graph.create_reactive_node(
				graph.assert_stable_parent(),
				function(): nil
					local current = tag()
					return if current
						then bind_tag(instance, current)
						else nil
				end,
				"deferred",
				nil
			)
		end
	end)
end

return tags
