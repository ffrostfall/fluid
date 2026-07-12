--!optimize 1
local dev_mode = true

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
	(warn or print)(text)
end

local logging = {
	__warn_facade = warn_facade,

	errors = {},
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

function logging.errors.inst_prop_nonexistent(inst_class: string, inst_property: string)
	return `Property {inst_property} does not exist on instance {inst_class} [inst_prop_nonexistent]`
end

function logging.errors.inst_class_nonexistent(inst_class: string)
	return `Instance class {inst_class} does not exist [inst_class_nonexistent]`
end

function logging.errors.changed_user_fn_errored() end

function logging.errors.cleanup_invalid_scope()
	return "Cannot use cleanup outside of a reactive/stable scope [cleanup_invalid_scope]"
end

function logging.errors.cleanup_unknown_destructor(value_type: string)
	return `Cannot cleanup the given object {value_type} [cleanup_unknown_destructor]`
end

function logging.errors.root_already_destroyed()
	return "Root was already destroyed before"
end

function logging.errors.root_user_errored() end

function logging.errors.interval_user_yielded() end

function logging.errors.interval_user_errored() end

function logging.errors.graph_effect_errored() end

function logging.errors.graph_effect_yielded() end

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

function logging.errors.likely_internal()
	return "This might be an internal bug."
end

return logging
