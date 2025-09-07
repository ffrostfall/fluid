local action = require("../instances/action")
local cleanup = require("../reactive/cleanup")
local graph = require("../reactive/graph")

local function bind_tag(instance: Instance, tag: string)
	instance:AddTag(tag)

	cleanup(function()
		instance:RemoveTag(tag)
	end)
end

local function tags(tags: { string | () -> string? }): action.Identity
	return action.create(function(instance)
		graph.set_group(graph.new_group("bind tags"))
		for _, tag in tags do
			if typeof(tag) == "string" then
				bind_tag(instance, tag)
				continue
			end
			graph.create_reactive_node(graph.assert_stable_parent(), function(): nil
				local current = tag()
				return if current then bind_tag(instance, current) else nil
			end, "deferred", nil)
		end
		graph.clear_group()
	end)
end

return tags
