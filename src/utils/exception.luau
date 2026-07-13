local logging = require("@src/logging")

export type Identity = {
	read __FLUID_ERR: {},

	text: string,
	trace: string,
	thread: thread,
}

local symbol = {}

local exception = {}

function exception.ephemeral_thread_unwrap(
	thread: thread,
	yielded: boolean
): {
	thread: thread,
	yielded: boolean,

	read __THREAD_UNWRAP: {},
	read __FLUID_ERR: {},
}
	return {
		thread = thread,
		yielded = yielded,

		__FLUID_ERR = symbol,
		__THREAD_UNWRAP = symbol,
	}
end

function exception.unwrap_ephemeral_thread_err(
	value: unknown & { thread: unknown, yielded: unknown }
): (thread, boolean)
	assert(type(value) == "table", logging.errors.fluid_assert())
	assert(type(value["thread"]) == "thread", logging.errors.fluid_assert())
	assert(type(value["yielded"]) == "boolean", logging.errors.fluid_assert())

	return value.thread, value.yielded
end

function exception.is_thread_unwrap(value): boolean
	return type(value) == "table" and value.__FLUID_ERR == symbol and value.__THREAD_UNWRAP
end

function exception.is_fluid_exception(value): boolean
	return type(value) == "table" and value.__FLUID_ERR == symbol
end

function exception.from_thread(text: string, thread: thread): Identity
	local trace = debug.traceback(thread)

	return {
		__FLUID_ERR = symbol,

		trace = trace,
		thread = thread,
		text = text,
	}
end

function exception.new(text: string, trace: string, thread: thread): Identity
	return {
		__FLUID_ERR = symbol,

		trace = trace,
		thread = thread,
		text = text,
	}
end

return exception
