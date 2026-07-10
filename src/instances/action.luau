const action_metatable_symbol = table.freeze({})

export type Identity = setmetatable<{
	callback: (inst: Instance) -> (),
	priority: number,
}, typeof(action_metatable_symbol)>

const action = {
	metatable = action_metatable_symbol,
}

function action.is_action(action: unknown): boolean
	return type(action) == "table" and (getmetatable(action) == action_metatable_symbol)
end

function action.create(callback: (inst: Instance) -> (), priority: number?): Identity
	return setmetatable({
		callback = callback,
		priority = priority or 1,
	}, action_metatable_symbol)
end

return action
