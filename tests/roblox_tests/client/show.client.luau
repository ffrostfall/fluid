local ReplicatedStorage = game:GetService("ReplicatedStorage")

local fluid = require(ReplicatedStorage.fluid)

local mount = fluid.mount
local source = fluid.source
local show = fluid.show
local show_delay = fluid.show_delay
local create = fluid.create
local scale = UDim2.fromScale
local px = UDim2.fromOffset

mount(function()
	local active_show_delay = source(false)
	local active = source(false)

	return create("ScreenGui")({
		ResetOnSpawn = false,

		show(active, function()
			return create("Frame")({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = scale(0.5, 0.5) + px(-250, -60),
				Size = px(60, 60),
			})
		end),
		show_delay(active_show_delay, function()
			return create("Frame")({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = scale(0.5, 0.5) + px(-250, 60),
				Size = px(60, 60),
				BackgroundColor3 = function()
					return active_show_delay() and Color3.new(1, 1, 1) or Color3.new(1, 0, 0)
				end,
			}),
				0.5
		end),

		create("TextButton")({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = scale(0.5, 0.5),
			AutoButtonColor = false,

			Size = px(150, 50),

			Text = function()
				if active() then
					return "Working...."
				end
				return "Activate delay"
			end,

			MouseButton1Click = function()
				if active() then
					return
				end

				active(true)
				task.delay(0.5, active, false)
			end,
		}),
		create("TextButton")({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = scale(0.5, 0.5) + px(0, 55),
			AutoButtonColor = false,

			Size = px(150, 50),

			Text = function()
				if active_show_delay() then
					return "Working...."
				end
				return "Activate show_delay"
			end,

			MouseButton1Click = function()
				if active_show_delay() then
					return
				end

				active_show_delay(true)
				task.delay(0.5, active_show_delay, false)
			end,
		}),
	})
end, game:GetService("Players").LocalPlayer.PlayerGui)
