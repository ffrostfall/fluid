local function under_dampened(
	t: number,
	speed: number,
	damping: number
): (number, number, number, number)
	local alpha = speed * math.sqrt(1 - damping ^ 2)
	local over_alpha = 1 / alpha
	local exp = math.exp(-1 * t * speed * damping)
	local exp_sin = exp * math.sin(alpha * t)
	local exp_cos = exp * math.cos(alpha * t)
	local exp_sin_speed_damping_over_alpha = exp_sin * speed * damping * over_alpha

	return exp_sin_speed_damping_over_alpha + exp_cos,
		exp_sin * over_alpha,
		(exp_sin * alpha + speed * damping * exp_sin_speed_damping_over_alpha) * -1,
		exp_cos - exp_sin_speed_damping_over_alpha
end

local function critically_dampened(t: number, speed: number): (number, number, number, number)
	local time_speed = t * speed
	local time_speed_neg1 = time_speed * -1
	local exp = math.exp(time_speed_neg1)

	return exp * (time_speed + 1),
		exp * t,
		exp * (time_speed_neg1 * speed),
		exp * (time_speed_neg1 + 1)
end

local function over_dampened(
	t: number,
	damping: number,
	speed: number
): (number, number, number, number)
	local alpha = math.sqrt(damping ^ 2 - 1)
	local neg_half_over_alpha_speed = -0.5 / (alpha * speed)
	local z1 = speed * (alpha + damping) * -1
	local z2 = speed * (alpha - damping)
	local exp1 = math.exp(t * z1)
	local exp2 = math.exp(t * z2)

	return (exp2 * z1 - exp1 * z2) * neg_half_over_alpha_speed,
		(exp1 - exp2) * neg_half_over_alpha_speed / speed,
		(exp2 - exp1) * neg_half_over_alpha_speed * speed,
		(exp1 * z1 - exp2 * z2) * neg_half_over_alpha_speed
end

local function coefficients(
	t: number,
	damping: number,
	speed: number
): (number, number, number, number)
	if t == 0 or speed == 0 then
		return 1, 0, 0, 1
	end

	if damping > 1 then
		return over_dampened(t, speed, damping)
	elseif damping == 1 then
		return critically_dampened(t, speed)
	else
		return under_dampened(t, speed, damping)
	end
end

return coefficients
