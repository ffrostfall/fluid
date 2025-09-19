local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local fluid = require(ReplicatedStorage.fluid)
local create = fluid.create
local keys = fluid.for_keys
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

local function some_component(_, k, active): (Instance, number?)
	print("CREATED?")
	return create("TextLabel")({
		Name = k,

		Size = UDim2.fromOffset(100, 100),

		Text = function()
			return `{k}`
		end,
	}),
		2
end

mount(function()
	print("RUNNING")
	return create("Frame")({
		Size = UDim2.fromScale(1, 1),

		create("UIListLayout")({}),

		keys(list_source, some_component),
	})
end, parent_screen)

table.remove(list, 4)
list_source(list)
