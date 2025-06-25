local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local fluid = require(ReplicatedStorage.fluid)
local create = fluid.create
local indexes = fluid.indexes
local mount = fluid.mount
local source = fluid.source

local parent_screen = create("ScreenGui")({
	Name = "ParentScreen",
	ResetOnSpawn = false,
	Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
})

local list = {
	"1",
	"2",
	"3",
	"4",
}

local list_source = source(list)

local function some_component(_, k)
	return create("Frame")({
		Name = k,
	})
end

mount(function()
	return create("Frame")({
		Size = UDim2.fromScale(1, 1),

		create("Frame")({
			indexes(list_source, some_component, 10),
		}),
	})
end, parent_screen)

table.remove(list, 4)
list_source(list)
