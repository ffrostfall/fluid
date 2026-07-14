export type YieldException = {
	kind: "yielded",

	trace: string,
}

export type FluidException = {
	kind: "fluid",

	trace: string,
}

export type InvokedException = {
	kind: "invoked",

	err: string,
	trace: string,
}

export type UncaughtException = {
	kind: "uncaught",

	err: string,
	trace: string,
}

export type Identity = FluidException | YieldException | InvokedException | UncaughtException

local symbol = {}

local exception = {}

function exception.new(info: Identity): Identity
	setmetatable(info, symbol)
	return info
end

function exception.is(value)
	return type(value) == "table" and getmetatable(value) == symbol
end

return exception
