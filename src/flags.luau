local dev_mode: boolean = false

if typeof(_G.__DEV__) == "boolean" then
	dev_mode = _G.__DEV__
elseif game then
	dev_mode = (game and not game:GetService("RunService"):IsStudio()) :: boolean
end

return {
	dev_mode = dev_mode,
}
