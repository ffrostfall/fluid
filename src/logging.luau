--!optimize 1
local colorful = require("./vendor/colorful")
local scheduler = require("./scheduler")

local dev_mode = _G.__DEV__ == true

local warn_storage: { [string]: true } = {}

local function format(text: string, is_supressed: boolean): string
	if is_supressed then
		return (string.format("[fluid][SUPRESSED]: %*", text))
	end
	return (string.format("[fluid]: %*", text))
end

local function use_traceback(text: string, is_supressed: boolean): string
	return (debug.traceback(format(text, is_supressed), 3))
end

local function warn_facade(text: string)
	if warn then
		warn(text)
		return
	end
	print(colorful.color.yellowBright(text))
end

local logging = {
	__warn_facade = warn_facade,
}

function logging.trace(text: string, traceback: boolean?)
	if traceback == nil then
		traceback = dev_mode
	end

	if dev_mode then
		print(if traceback then use_traceback(text, false) else format(text, false))
	end
end

function logging.warn(text: string, traceback: boolean?)
	if traceback == nil then
		traceback = dev_mode
	end

	logging.__warn_facade(if traceback then use_traceback(text, false) else format(text, false))
end

-- blocks warns from overlapping in most notably that happen everyframe
function logging.warn_suppressed(text: string, traceback: boolean?)
	if warn_storage[text] then
		return
	end

	warn_storage[text] = true

	if traceback == nil then
		traceback = dev_mode
	end

	logging.__warn_facade(if traceback then use_traceback(text, true) else format(text, true))

	scheduler.delay(10, function()
		warn_storage[text] = nil
	end)
end

return logging
