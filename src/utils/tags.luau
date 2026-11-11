local action = require("../instances/action")
local graph = require("../reactive/graph")

local DEFERRED = graph.evaluation.DEFERRED

local function bind_tag(instance: Instance, tag: string)
	instance:AddTag(tag)

	graph.push_cleanup(graph.assert_scope(), function()
		instance:RemoveTag(tag)
	end)
end

local function tags(tags: { string | () -> string? }): action.Identity
	return action.create(function(instance)
		for _, tag in tags do
			if typeof(tag) == "string" then
				bind_tag(instance, tag)
				continue
			end
			graph.create_effect_node(graph.assert_stable_parent(), function(): nil
				local current = tag()
				return if current then bind_tag(instance, current) else nil
			end, DEFERRED, nil)
		end
	end)
end

return tags
