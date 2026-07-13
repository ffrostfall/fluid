local action_metatable_symbol = table.freeze({})

export type Identity = {
	callback: (inst: Instance) -> (),
	priority: number,

	__ACTION_SYMBOL: {},
}

local action = {
	metatable = action_metatable_symbol,
}

function action.is_action(action): boolean
	return type(action) == "table" and action.__ACTION_SYMBOL ~= nil
end

function action.create(callback: (inst: Instance) -> (), priority: number?): Identity
	return {
		callback = callback,
		priority = priority or 1,

		__ACTION_SYMBOL = action_metatable_symbol,
	}
end

return action
