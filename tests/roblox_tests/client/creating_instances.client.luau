local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local fluid = require(ReplicatedStorage.fluid)

local random_words = fluid.source({ "hi", "bye", "meow", "mrrp" })

local function label()
	return fluid.create("TextLabel")({
		Text = "haii!",
	})
end

local function iso_date()
	local text = fluid.interval(function()
		return string.rep("W", math.random(1, 20))
	end)

	local elements = fluid.interval(function()
		local array = {}

		for i = 1, math.random(1, 5) do
			table.insert(array, label())
		end

		return array
	end, 2)

	return fluid.create("ScreenGui")({
		Name = "iso",

		fluid.tags({ "hi" }),

		fluid.create("TextButton")({
			Text = text,

			Activated = function()
				print("button pressed!")
			end,

			Size = fluid.async(function(set)
				local text_value = text()

				local params = Instance.new("GetTextBoundsParams")
				params.Text = text_value

				local bounds = TextService:GetTextBoundsAsync(params)

				return UDim2.fromOffset(bounds.X, bounds.Y)
			end),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
		}),

		fluid.create("UIListLayout")({}),

		fluid.for_values(random_words, function(key, value)
			return fluid.create("TextLabel")({
				Name = key,
				Text = value,
			})
		end),

		fluid.create("Frame")({
			Size = UDim2.fromScale(0.2, 0.4),

			elements,
		}),
	})
end

local function list()
	local items = fluid.source({})

	local input = fluid.create("TextBox")({
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.25, 0.1),

		fluid.changed("Text", print),
	}) :: TextBox

	return fluid.create("ScreenGui")({
		input,

		fluid.create("TextButton")({
			Text = "enter",

			Size = UDim2.fromScale(0.25, 0.1),
			Position = UDim2.fromScale(0.5, 0.7),

			Activated = function()
				local existing_items = items()
				table.insert(existing_items, input.Text)
				items(existing_items)

				input.Text = ""
			end,

			fluid.tags({ "tag1", "tag2" }),
			fluid.tags({
				function()
					return items()[#items()]
				end,
			}),
		}),

		fluid.create("TextButton")({
			Text = "remove",

			Size = UDim2.fromScale(0.25, 0.1),
			Position = UDim2.fromScale(0.5, 0.85),

			Activated = function()
				local existing_items = items()
				table.remove(existing_items)
				items(existing_items)
			end,
		}),

		fluid.create("Frame")({
			Position = UDim2.fromScale(0.25, 0.5),
			Size = UDim2.fromOffset(125, 500),

			fluid.create("UIListLayout")({}),

			fluid.for_values(items, function(key, value)
				local color = fluid.source(Color3.new())
				local lerped = fluid.lerp(color, 0.1)
				color(Color3.new(1, 0, 0))

				return fluid.show(function()
					return true
				end, function()
					return fluid.create("TextLabel")({
						Size = UDim2.fromOffset(125, 50),
						BackgroundColor3 = lerped,

						Name = key,
						Text = value,
					})
				end)
			end),
		}),
	})
end

fluid.mount(function()
	return { list() }
end, Players.LocalPlayer.PlayerGui)
