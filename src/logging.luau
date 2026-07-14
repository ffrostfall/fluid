--!optimize 1
local dev_mode = true

local function format(text: string): string
	return (string.format("[fluid]: %*", text))
end

local function warn_facade(text: string)
	(warn or print)(text)
end

local logging = {
	__warn_facade = warn_facade,

	errors = {},
}

function logging.fmt(text: string): string
	return format(text)
end

function logging.warn(text: string)
	logging.__warn_facade(format(text))
end

function logging.error(text: string)
	error(format(text))
end

function logging.warn_traceback(text: string, thread: thread)
	logging.__warn_facade(debug.traceback(thread, format(text), 2))
end

function logging.errors.inst_prop_nonexistent(inst_class: string, inst_property: string)
	return `Property {inst_property} does not exist on instance {inst_class} [inst_prop_nonexistent]`
end

function logging.errors.inst_class_nonexistent(inst_class: string)
	return `Instance class {inst_class} does not exist [inst_class_nonexistent]`
end

function logging.errors.changed_user_fn_errored()
	return ""
end

function logging.errors.cleanup_invalid_scope()
	return "Cannot use cleanup outside of a reactive/stable scope [cleanup_invalid_scope]"
end

function logging.errors.cleanup_unknown_destructor(value_type: string)
	return `Cannot cleanup the given object {value_type} [cleanup_unknown_destructor]`
end

function logging.errors.root_already_destroyed()
	return "Root was already destroyed before"
end

function logging.errors.root_user_errored()
	return "Root function errored [root_fn_error]"
end

function logging.errors.interval_user_yielded()
	return "Interval yielded [interval_fn_yielded]"
end

function logging.errors.interval_user_errored(err: string)
	return `Interval function errored: {err} [interval_fn_errored]`
end

function logging.errors.graph_effect_errored(err: string)
	return `Reactive function errored {err} [effect_fn_errored]`
end

function logging.errors.graph_effect_yielded()
	return "Reactive effect function yielded [effect_fn_yielded]"
end

function logging.errors.graph_nil_in_deferred()
	return "Internal graph reference was nil"
end

function logging.errors.graph_recursive_dependency_depeqco()
	return "a recursive dependency has been found"
end

function logging.errors.graph_recursive_dependency_coeqnost()
	return "a recursive dependency has been found"
end

function logging.errors.graph_scope_assertion_failed()
	return `SCOPE ASSERTION FAILED: {debug.info(2, "n")}:{debug.info(2, "l")}`
end

function logging.errors.graph_stable_parent_assertion_failed()
	return `STABLE PARENT ASSERTION FAILED: {debug.info(2, "n")}:{debug.info(2, "l")}`
end

function logging.errors.graph_cant_call_while_parent_scope_reactive(func_name: string)
	return `Can't call fluid.{func_name} while the current scope is reactive`
end

function logging.errors.unknown(str: string)
	return `Unknown: {str}`
end

function logging.errors.fluid_assert()
	return "fluid internal assertion failed"
end

return logging
