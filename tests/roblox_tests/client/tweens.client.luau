local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local fluid = require(ReplicatedStorage.fluid)
local create = fluid.create
local mount = fluid.mount

local parent_screen = create("ScreenGui")({
	Name = "ParentScreen",
	ResetOnSpawn = false,
	Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
})

mount(function()
	return create("Frame")({
		Size = UDim2.fromOffset(128, 128),
		AnchorPoint = Vector2.new(0.5, 0.5),

		Position = fluid.tween(
			fluid.interval(function()
				return UDim2.fromScale(math.random(), math.random())
			end, 1),
			TweenInfo.new(1, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out)
		),

		BackgroundColor3 = fluid.tween(
			fluid.interval(function()
				return Color3.fromHSV(math.random(), math.random(), 1)
			end, 1.6),
			TweenInfo.new(1, Enum.EasingStyle.Back)
		),
	})
end, parent_screen)
