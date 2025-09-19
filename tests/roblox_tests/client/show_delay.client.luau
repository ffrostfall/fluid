local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local fluid = require(ReplicatedStorage.fluid)

local function main()
	local active = fluid.source(false)

	return fluid.create("ScreenGui" :: "ScreenGui")({
		fluid.create("TextButton" :: "TextButton")({

			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(200, 50),
			AnchorPoint = Vector2.new(0.5, 0.5),

			Activated = function()
				active(not active())
			end,

			fluid.show_delay(active :: () -> boolean, function(active: types.Readable<boolean>)
				return fluid.create("Frame" :: "Frame")({

					Position = UDim2.fromScale(0, 1),
					Size = UDim2.fromOffset(100, 100),
				}),
					0.5 :: number?
			end) :: () -> { Instance },
		}),
	})
end

fluid.mount(function()
	return main()
end, Players.LocalPlayer.PlayerGui)
