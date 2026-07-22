local C1 = 1.70158
local C2 = C1 * 1.525
local C3 = C1 + 1
local C4 = (2 * math.pi) / 3
local C5 = (2 * math.pi) / 4.5

local N1 = 7.5625
local D1 = 2.75

local function linear(t: number): number
	return t
end

local function sine_in(t: number): number
	return 1 - math.cos((t * math.pi) / 2)
end

local function sine_out(t: number): number
	return math.sin((t * math.pi) / 2)
end

local function sine_in_out(t: number): number
	return -(math.cos(math.pi * t) - 1) / 2
end

local function quad_in(t: number): number
	return t * t
end

local function quad_out(t: number): number
	return 1 - (1 - t) ^ 2
end

local function quad_in_out(t: number): number
	return (t < 0.5) and 2 * t * t or 1 - (-2 * t + 2) ^ 2 / 2
end

local function cubic_in(t: number): number
	return t ^ 3
end

local function cubic_out(t: number): number
	return 1 - (1 - t) ^ 3
end

local function cubic_in_out(t: number): number
	return (t < 0.5) and 4 * t ^ 3 or 1 - (-2 * t + 2) ^ 3 / 2
end

local function quart_in(t: number): number
	return t ^ 4
end

local function quart_out(t: number): number
	return 1 - (1 - t) ^ 4
end

local function quart_in_out(t: number): number
	return (t < 0.5) and 8 * t ^ 4 or 1 - (-2 * t + 2) ^ 4 / 2
end

local function quint_in(t: number): number
	return t ^ 5
end

local function quint_out(t: number): number
	return 1 - (1 - t) ^ 5
end

local function quint_in_out(t: number): number
	return (t < 0.5) and 16 * t ^ 5 or 1 - (-2 * t + 2) ^ 5 / 2
end

local function expo_in(t: number): number
	return (t == 0) and 0 or 2 ^ (10 * t - 10)
end

local function expo_out(t: number): number
	return (t == 1) and 1 or 1 - 2 ^ (-10 * t)
end

local function expo_in_out(t: number): number
	return (t == 0 or t == 1) and t
		or (t < 0.5) and 2 ^ (20 * t - 10) / 2
		or (2 - 2 ^ (-20 * t + 10)) / 2
end

local function circ_in(t: number): number
	return 1 - math.sqrt(1 - t ^ 2)
end

local function circ_out(t: number): number
	return math.sqrt(1 - (t - 1) ^ 2)
end

local function circ_in_out(t: number): number
	return (t < 0.5) and (1 - math.sqrt(1 - (2 * t) ^ 2)) / 2
		or (math.sqrt(1 - (-2 * t + 2) ^ 2) + 1) / 2
end

local function back_in(t: number): number
	return C3 * t ^ 3 - C1 * t * t
end

local function back_out(t: number): number
	return 1 + C3 * (t - 1) ^ 3 + C1 * (t - 1) ^ 2
end

local function back_in_out(t: number): number
	return (t < 0.5) and ((2 * t) ^ 2 * ((C2 + 1) * 2 * t - C2)) / 2
		or ((2 * t - 2) ^ 2 * ((C2 + 1) * (t * 2 - 2) + C2) + 2) / 2
end

local function elastic_in(t: number): number
	return (t == 0 or t == 1) and t or -2 ^ (10 * t - 10) * math.sin((t * 10 - 10.75) * C4)
end

local function elastic_out(t: number): number
	return (t == 0 or t == 1) and t or 2 ^ (-10 * t) * math.sin((t * 10 - 0.75) * C4) + 1
end

local function elastic_in_out(t: number): number
	return (t == 0 or t == 1) and t
		or (t < 0.5) and -(2 ^ (20 * t - 10) * math.sin((20 * t - 11.125) * C5)) / 2
		or (2 ^ (-20 * t + 10) * math.sin((20 * t - 11.125) * C5)) / 2 + 1
end

local function bounce_out(t: number): number
	if t < 1 / D1 then
		return N1 * t * t
	elseif t < 2 / D1 then
		t -= (1.5 / D1)
		return N1 * t * t + 0.75
	elseif t < 2.5 / D1 then
		t -= (2.25 / D1)
		return N1 * t * t + 0.9375
	else
		t -= (2.625 / D1)
		return N1 * t * t + 0.984375
	end
end

local function bounce_in(t: number): number
	return 1 - bounce_out(1 - t)
end

local function bounce_in_out(t: number): number
	return (t < 0.5) and (1 - bounce_out(1 - 2 * t)) / 2 or (1 + bounce_out(2 * t - 1)) / 2
end

local easings: { [Enum.EasingStyle]: { [Enum.EasingDirection]: (t: number) -> number } } = {
	[Enum.EasingStyle.Linear] = {
		[Enum.EasingDirection.In] = linear,
		[Enum.EasingDirection.Out] = linear,
		[Enum.EasingDirection.InOut] = linear,
	},
	[Enum.EasingStyle.Sine] = {
		[Enum.EasingDirection.In] = sine_in,
		[Enum.EasingDirection.Out] = sine_out,
		[Enum.EasingDirection.InOut] = sine_in_out,
	},
	[Enum.EasingStyle.Quad] = {
		[Enum.EasingDirection.In] = quad_in,
		[Enum.EasingDirection.Out] = quad_out,
		[Enum.EasingDirection.InOut] = quad_in_out,
	},
	[Enum.EasingStyle.Cubic] = {
		[Enum.EasingDirection.In] = cubic_in,
		[Enum.EasingDirection.Out] = cubic_out,
		[Enum.EasingDirection.InOut] = cubic_in_out,
	},
	[Enum.EasingStyle.Quart] = {
		[Enum.EasingDirection.In] = quart_in,
		[Enum.EasingDirection.Out] = quart_out,
		[Enum.EasingDirection.InOut] = quart_in_out,
	},
	[Enum.EasingStyle.Quint] = {
		[Enum.EasingDirection.In] = quint_in,
		[Enum.EasingDirection.Out] = quint_out,
		[Enum.EasingDirection.InOut] = quint_in_out,
	},
	[Enum.EasingStyle.Circular] = {
		[Enum.EasingDirection.In] = circ_in,
		[Enum.EasingDirection.Out] = circ_out,
		[Enum.EasingDirection.InOut] = circ_in_out,
	},
	[Enum.EasingStyle.Exponential] = {
		[Enum.EasingDirection.In] = expo_in,
		[Enum.EasingDirection.Out] = expo_out,
		[Enum.EasingDirection.InOut] = expo_in_out,
	},
	[Enum.EasingStyle.Back] = {
		[Enum.EasingDirection.In] = back_in,
		[Enum.EasingDirection.Out] = back_out,
		[Enum.EasingDirection.InOut] = back_in_out,
	},
	[Enum.EasingStyle.Bounce] = {
		[Enum.EasingDirection.In] = bounce_in,
		[Enum.EasingDirection.Out] = bounce_out,
		[Enum.EasingDirection.InOut] = bounce_in_out,
	},
	[Enum.EasingStyle.Elastic] = {
		[Enum.EasingDirection.In] = elastic_in,
		[Enum.EasingDirection.Out] = elastic_out,
		[Enum.EasingDirection.InOut] = elastic_in_out,
	},
}

return easings
