local action_metatable_symbol = table.freeze({})

export type Identity = {
	callback: (inst: Instance) -> (),

	__ACTION_SYMBOL: {},
}

local action = {
	symbol = action_metatable_symbol,
}

function action.is_action(action): boolean
	return type(action) == "table" and action.__ACTION_SYMBOL ~= nil
end

function action.create(callback: (inst: Instance) -> ()): Identity
	return {
		callback = callback,

		__ACTION_SYMBOL = action_metatable_symbol,
	}
end

return action
