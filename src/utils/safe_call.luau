local no_yield = require("./no_yield")

local function safe_call_user_fn<T..., U...>(use_no_yield: boolean, fn: (T...) -> U..., ...: T...): (boolean, U...)
	if use_no_yield then
		return pcall(no_yield, fn, ...)
	else
		return pcall(fn, ...)
	end
end

return safe_call_user_fn
