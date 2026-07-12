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
	local is_even_second = fluid.interval(function()
		return (os.clock() // 1) % 2 == 1
	end, 2)

	return create("Frame")({
		Size = UDim2.fromScale(1, 1),
		Position = fluid.spring(
			fluid.interval(function()
				return UDim2.fromScale(math.random(), math.random())
			end),
			1,
			1
		),

		fluid.show(function()
			return is_even_second()
		end, function()
			return Instance.new("Frame")
		end),

		BackgroundColor3 = fluid.spring(
			fluid.interval(function()
				return Color3.fromRGB(math.random() * 255, math.random() * 255, math.random() * 255)
			end, 2),
			1,
			1
		),
	})
end, parent_screen)
