-- exists so we
local action_metatable_symbol = table.freeze({})

export type Indentity = setmetatable<{
	callback: (inst: Instance) -> (),
	priority: number,
}, typeof(action_metatable_symbol)>

local action = {
	metatable = action_metatable_symbol,
}

function action.is_action(action: {} & unknown): boolean
	return getmetatable(action) :: any == action_metatable_symbol
end

function action.create(
	callback: (inst: Instance) -> (),
	priority: number?
): Indentity
	return setmetatable({
		callback = callback,
		priority = priority or 1,
	}, action_metatable_symbol)
end

return action
