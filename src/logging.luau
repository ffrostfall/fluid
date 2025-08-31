--!optimize 1
local colorful = require("./vendor/colorful")
local flags = require("./flags")
local scheduler = require("./scheduler")

type OnWarn = (text: string) -> ()

local on_warn: OnWarn? = nil
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
	if on_warn then
		return on_warn(text)
	end

	if warn then
		warn(text)
		return
	end

	print(colorful.color.yellowBright(text))
end

local logging = {}

function logging.trace(text: string, traceback: boolean?)
	if traceback == nil then
		traceback = flags.dev_mode
	end

	if flags.dev_mode then
		print(if traceback then use_traceback(text, false) else format(text, false))
	end
end

function logging.warn(text: string, traceback: boolean?)
	if traceback == nil then
		traceback = flags.dev_mode
	end

	warn_facade(if traceback then use_traceback(text, false) else format(text, false))
end

-- blocks warns from overlapping in most notably that happen everyframe
function logging.warn_suppressed(text: string, traceback: boolean?)
	if warn_storage[text] then
		return
	end

	warn_storage[text] = true

	if traceback == nil then
		traceback = flags.dev_mode
	end

	warn_facade(if traceback then use_traceback(text, true) else format(text, true))

	scheduler.delay(10, function()
		warn_storage[text] = nil
	end)
end

-- for tests
function logging.on_warn(new_callback: OnWarn?)
	on_warn = new_callback
end

return logging
