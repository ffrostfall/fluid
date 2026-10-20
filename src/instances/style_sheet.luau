local action = require("./action")
local cleanup = require("../reactive/cleanup")
local graph = require("../reactive/graph")
local instance_types = require("./types")
local tags = require("../utils/tags")

type PseduoInstanceNames = keyof<instance_types.PseudoInstances>

type Action = action.Identity
type Instances = instance_types.Instances
type PseudoInstances = instance_types.PseudoInstances
type RobloxStyleSheet = StyleSheet
type RobloxGuiObject = GuiObject
type RobloxInstance = Instance
type RobloxTweenInfo = TweenInfo
type RobloxSignal = RBXScriptSignal
type RobloxStyleQuery = StyleQuery

type RuntimeSheet = {
	read instance: RobloxStyleSheet,
	read _queries: { [string]: true? },
}

-- `::StyleQuery` pseudo-instances take their conditions as properties
type QueryConditions = {
	AspectRatioRange: NumberRange,
	MaxSize: Vector2,
	MinSize: Vector2,
	PreferredInput: Enum.PreferredInput,
	PreferredTextSize: Enum.PreferredTextSize,
	ReducedMotionEnabled: boolean,
	ViewportDisplaySize: Enum.DisplaySize,
}

local BUILTIN_QUERIES = table.freeze({
	PreferredInputKeyboardAndMouse = true,
	PreferredInputGamepad = true,
	PreferredInputTouch = true,
	PreferredInputMicroGamepad = true,
	ViewportDisplaySizeSmall = true,
	ViewportDisplaySizeMedium = true,
	ViewportDisplaySizeLarge = true,
	PreferredTextSizeMedium = true,
	PreferredTextSizeLarge = true,
	PreferredTextSizeLarger = true,
	PreferredTextSizeLargest = true,
	ReducedMotionEnabledTrue = true,
	ReducedMotionEnabledFalse = true,
})

type BuiltInQueries = typeof(BUILTIN_QUERIES)

-- this is not the most accurate type, but it suffices
type Props = {
	_transitions: { [string]: TweenInfo | string }?,
	_queries: { [string]: Props }?,
	_conditions: Props?,
	_priority: number?,
	[string | number]: PseudoInstance | any,
}

export type PseudoInstance<Selector = string> = {
	read selector: Selector,
	read props: Props,
}

type function VALIDATE_STRINGLETON(s: type, pattern: string): type
	if not (s.tag == "singleton" and type(s:value()) == "string") or s:value() == "" then
		error(string.format(pattern, s), 0)
	end
	return s
end

type function TokenRefs(tokens: type): { [string]: type }
	local refs = {} :: { [string]: type }

	for key, property in tokens:properties() do
		local token_type = property.read
		if token_type then
			-- equal types aren't the same userdata, so types are keyed by what tostring gives for them
			local type_name = tostring(token_type)
			local reference = types.singleton("$" .. (key:value() :: string))
			local existing = refs[type_name]
			refs[type_name] = if existing then types.unionof(existing, reference) else reference
		end
	end

	local indexer = tokens:indexer()
	if indexer then
		refs[tostring(indexer.readresult)] = types.string
	end

	return refs
end

type function StyleValue(value: type, refs: { [string]: type }): type
	local value_refs = refs[tostring(value)]
	return types.optional(if value_refs then types.unionof(value, value_refs) else value)
end

type function parse_selector(selector: string, queries: { [string]: type }): ({ type }, { string }?)
	-- lowercase, because roblox matches gui states case-insensitively
	local GUI_STATES = table.freeze({ "idle", "hover", "press", "noninteractable" })
	-- pseudo-instances roblox allows under each pseudo-instance; pseudo-instances missing from this list can't have any
	local PSEUDO_INSTANCE_CHILDREN = table.freeze({
		UIGridLayout = table.freeze({ "UIAspectRatioConstraint", "UISizeConstraint" }),
		UIShadow = table.freeze({ "UIGradient" }),
		UIStroke = table.freeze({ "UIGradient" }),
	}) :: { [string]: { string } }

	local BYTE = string.byte

	local GREATER = BYTE(">")
	local SPACE = BYTE(" ")
	local COMMA = BYTE(",")
	local COLON = BYTE(":")
	local OPEN = BYTE("[")
	local HASH = BYTE("#")
	local DOT = BYTE(".")
	local AT = BYTE("@")

	local has_inserted_gui_object = false
	local instances = {} :: { type }
	local children: { string }?
	local length = #selector
	local position = 1

	local function FAIL(at: number, message: string)
		-- starting the error with a newline so the "TypeError: 'ParseSelector' type function errored at runtime:" isn't on the same line as the error
		-- for better readability
		error(`\n{message} at position {at}\n\t{selector}\n\t{string.rep(" ", at - 1)}^`, 0)
	end

	local function SKIP_WHITESPACE()
		local char = BYTE(selector, position)

		if char and char <= SPACE then
			local next_char = BYTE(selector, position + 1)

			if char == SPACE and not (next_char and next_char <= SPACE) then
				position += 1
			elseif char <= SPACE then
				position = string.find(selector, "%S", position) or length + 1
			end
		end
	end

	local function SKIP_COMBINATOR(): string
		local combinator = if BYTE(selector, position + 1) == GREATER then ">>" else ">"
		position += #combinator
		SKIP_WHITESPACE()
		return combinator
	end

	local function READ_IDENTIFIER(): string?
		local identifier = string.match(selector, "^[%w_%-]+", position)
		if identifier then
			position += #identifier
		end
		return identifier
	end

	-- skips a one character sigil like `.` or `#`, and returns the identifier that has to come right after it
	local function parse_after_sigil(message: string): string?
		position += 1
		local start = position
		local identifier = READ_IDENTIFIER()

		if not identifier then
			FAIL(start, message)
		end
		return identifier
	end

	local function parse_state()
		position += 1
		local start = position
		local state = READ_IDENTIFIER()

		if not state then
			FAIL(start, "':' has to be followed by a GuiState, like 'Hover'")
		elseif not table.find(GUI_STATES, string.lower(state)) then
			FAIL(start, `'{state}' is not a valid GuiState`)
		end
	end

	local function parse_query()
		position += 1
		local start = position
		local name = READ_IDENTIFIER()

		if not name then
			FAIL(start, "'@' has to be followed by a query name")
		elseif not queries[name] then
			FAIL(start, `query '{name}' does not exist, add it with :query()`)
		end
	end

	-- only another `::Class` can follow a pseudo-instance, so they always end an element. Returns the instance and
	-- class of the last one
	local function parse_pseudo_instances(): (type?, string?)
		local instance: type? = nil
		local pseudo: string? = nil
		-- the pseudo-instances Roblox allows under the last one
		local allowed: { string }? = nil
		local current: number? = nil

		repeat
			position += 2
			SKIP_WHITESPACE()

			local class_start = position
			local class_name = READ_IDENTIFIER()
			local pseudo_instance = if class_name
				then PseudoInstances:readproperty(types.singleton(class_name))
				else nil

			if not class_name then
				FAIL(class_start, "'::' has to be followed by a ClassName")
			elseif not pseudo_instance then
				FAIL(class_start, `class '{class_name}' is not a valid pseudo-instance`)
			elseif pseudo and not (allowed and table.find(allowed, class_name)) then
				FAIL(class_start, `class '{class_name}' is not a valid pseudo-instance child for class '{pseudo}'`)
			else
				instance, pseudo, allowed = pseudo_instance, class_name, PSEUDO_INSTANCE_CHILDREN[class_name]
			end

			SKIP_WHITESPACE()
			current = BYTE(selector, position)
		until not (current == COLON and BYTE(selector, position + 1) == COLON)

		if current == GREATER then
			FAIL(position, `pseudo-instance '{pseudo}' cannot have children`)
		elseif current and current ~= COMMA then
			FAIL(
				position,
				if allowed
					then `pseudo-instance '{pseudo}' can only be followed by '::{table.concat(allowed, "' or '::")}'`
					else `pseudo-instance '{pseudo}' cannot be followed by anything`
			)
		end

		return instance, pseudo
	end

	-- whitespace doesn't separate elements, so an element goes on until a `,` or a `>` combinator.
	-- returns the instance the element styles if it's known, and the pseudo-instance class it ends in
	local function element(combinator: string?): (type?, string?)
		local start = position
		local instance: type? = nil
		-- the class and name the element matches, since it can only match one of each
		local element_class: string?, element_name: string? = nil, nil

		while true do
			SKIP_WHITESPACE()
			local current = BYTE(selector, position)

			if not current or current == COMMA or current == GREATER then
				break
			elseif current == COLON and BYTE(selector, position + 1) == COLON then
				if combinator and position == start then
					FAIL(position, `a pseudo-instance cannot come right after '{combinator}'`)
				end
				return parse_pseudo_instances()
			elseif current == HASH then
				local name_start = position
				local name = parse_after_sigil("'#' has to be followed by a name")
				if element_name then
					FAIL(
						name_start,
						`name '{name}' cannot be used with name '{element_name}', put '>' or '>>' between them`
					)
				end
				element_name = name
			elseif current == DOT then
				parse_after_sigil("'.' has to be followed by a tag")
			elseif current == COLON then
				parse_state()
			elseif current == AT then
				parse_query()
			elseif current == OPEN then
				FAIL(position, "property filters are not supported")
			else
				local class_start = position
				local class_name = READ_IDENTIFIER()

				if not class_name then
					FAIL(class_start, `character '{string.char(current)}' is not valid in a selector`)
				elseif element_class then
					FAIL(
						class_start,
						`class '{class_name}' cannot be used with class '{element_class}', put '>' or '>>' between them`
					)
				else
					instance = Instances:readproperty(types.singleton(class_name))
					element_class = class_name
				end
			end
		end

		if position == start then
			FAIL(position, `'{combinator}' has to be followed by a selector`)
		end
		return instance, nil
	end

	SKIP_WHITESPACE()
	if position > length then
		FAIL(1, `selector '{selector}' is only whitespace`)
	end

	while position <= length do
		local current = BYTE(selector, position)

		if current == COMMA then
			FAIL(position, "',' has to come after a selector")
		end

		local instance, pseudo = element(if current == GREATER then SKIP_COMBINATOR() else nil)

		while BYTE(selector, position) == GREATER do
			instance, pseudo = element(SKIP_COMBINATOR())
		end

		--stylua: ignore
		if (not instance) and (not has_inserted_gui_object) then
			has_inserted_gui_object = true
			instance = RobloxGuiObject
		end

		table.insert(instances, instance)

		-- rules only take the pseudo-instances that can go under every pseudo-instance its selectors end in
		if pseudo then
			local allowed = PSEUDO_INSTANCE_CHILDREN[pseudo]

			if children then
				local both = {}

				if allowed then
					for _, class_name in children do
						if table.find(allowed, class_name) then
							table.insert(both, class_name)
						end
					end
				end
				children = both
			else
				children = allowed or {}
			end
		end

		-- a `,` starts the next selector
		if position <= length then
			position += 1
			SKIP_WHITESPACE()

			if position > length then
				FAIL(position, "',' has to be followed by a selector")
			end
		end
	end

	return instances, children
end

type function StyleProperties(selector: type, tokens: type, queries: type): type
	local selector_value = VALIDATE_STRINGLETON(selector, "type %* is not a valid selector string"):value() :: string
	-- TODO: when luau allows use instance_types.get_read_only_properties so this table doesn't have to exist in 2 places
	local read_only_properties = table.freeze({
		types.singleton("RobloxLocked"),
		types.singleton("ClassName"),
		types.singleton("UniqueId"),
	})

	-- every query that `@Name` selectors and `_queries` can use
	local query_keys = {} :: { [string]: type }
	local source = BuiltInQueries
	for i = 1, 2 do
		for key in source:properties() do
			query_keys[key:value() :: string] = key
		end
		source = queries
	end

	-- rules can't reference instances, so Parent and other instance properties are left out.
	local instance_value = types.optional(RobloxInstance)
	local instance_values = {} :: { [string]: boolean }
	-- selector lists merge properties by name
	local keys = {} :: { [string]: type }
	local values = {} :: { [string]: type }

	local function add(property: type, value: type)
		local name = property:value() :: string
		local previous = values[name]
		if not previous then
			keys[name] = property
			values[name] = value
		elseif previous ~= value then
			values[name] = types.intersectionof(previous, value)
		end
	end

	local styled, pseudo_children = parse_selector(selector_value, query_keys)

	for _, instance in styled do
		if instance == RobloxStyleQuery then
			for property, condition in QueryConditions:properties() do
				add(property, condition.read :: type)
			end
		end

		local current: type? = instance

		while current do
			for property, value in current:properties() do
				local value_write = value.write
				local value_read = value.read

				if
					not value_read
					or not value_write
					or value_read.tag == "function"
					or value_read.tag == "intersection"
					or value_read == RobloxSignal
					or table.find(read_only_properties, property)
				then
					continue
				end

				-- ignoring luau-lsp RBXScriptSignals, because luau-lsp uses table types for RBXScriptSignals
				if value_read:is("table") then
					local connect = value_read:readproperty(types.singleton("Connect"))
					if connect and connect:is("function") then
						continue
					end
				end

				local value_name = tostring(value_write)
				local is_instance = instance_values[value_name]

				if is_instance == nil then
					is_instance = value_write:issubtypeof(instance_value)
					instance_values[value_name] = is_instance
				end

				if not is_instance then
					add(property, value_write)
				end
			end

			current = current:readparent()
		end
	end

	local refs = TokenRefs(tokens)
	local transition = StyleValue(RobloxTweenInfo, refs)
	local transitions = {}
	local style = {}

	for name, key in keys do
		style[key] = StyleValue(values[name], refs)
		transitions[key] = transition
	end

	transitions[types.singleton("_default")] = transition
	-- this does nothing for pseudo instances, but id rather just allow it incase roblox does have it do something in future
	style[types.singleton("_priority")] = types.optional(types.number)
	style[types.singleton("_transitions")] = types.optional(types.newtable(transitions))

	-- the array part holds the pseudo-instance children for the rule; which can be any pseudo-instance unless the
	-- selector ends in one, which in that case only the pseudo-instances allowed under it can be children
	local pseudo_instance

	if pseudo_children then
		-- pseudo_children can be one of the frozen PSEUDO_INSTANCE_CHILDREN arrays, so the selectors go in a new array
		local selectors = {}
		for index, class_name in pseudo_children do
			selectors[index] = types.singleton("::" .. class_name)
		end

		pseudo_instance = PseudoInstance(types.unionof(table.unpack(selectors)))
	elseif pseudo_children == false then
		-- nothing is allowed under most pseudo-instances, like UICorner
		pseudo_instance = types.never
	else
		-- including string because fluid might not always have a complete list of every Pseudo instance
		pseudo_instance = PseudoInstance(types.unionof(PseduoInstanceNames, types.string))
	end

	local pseudo_instances_indexer = {
		writeresult = pseudo_instance,
		readresult = pseudo_instance,
		index = types.number,
	}
	local props = types.newtable(style, pseudo_instances_indexer)

	-- pseudo-instances can't contain queries
	if pseudo_children ~= nil then
		return props
	end

	-- queries scoped to a rule take the same props, plus the conditions for their own StyleQuery
	style[types.singleton("_conditions")] = QueryConditionValues(refs)
	local scoped_query_rule = types.newtable(style, pseudo_instances_indexer)
	local query_rule = types.optional(props)
	local query_rules = {} :: { [type]: type }

	for _, key in query_keys do
		query_rules[key] = query_rule
	end

	local queries_type = types.optional(types.newtable(query_rules, {
		writeresult = scoped_query_rule,
		readresult = scoped_query_rule,
		index = types.string,
	}))
	props:setproperty(types.singleton("_queries"), queries_type)
	scoped_query_rule:setproperty(types.singleton("_queries"), queries_type)
	return props
end

type function QueryConditionValues(refs: { [string]: type }): type
	local conditions = {}

	for key, condition in QueryConditions:properties() do
		conditions[key] = StyleValue(condition.read :: type, refs)
	end
	return types.newtable(conditions)
end

type function QueryConditionsFor(tokens: type): type
	return QueryConditionValues(TokenRefs(tokens))
end

type function TagsFrom(selector: type): type
	selector = VALIDATE_STRINGLETON(selector, "type '%*' is not a valid selector string")
	local true_singleton = types.singleton(true)
	local tags = {} :: { [type]: type }

	for name in string.gmatch(selector:value() :: string, "%.([%w_%-]+)") do
		tags[types.singleton(name)] = true_singleton
	end
	return types.newtable(tags)
end

type function QueryFrom(name: type): type
	name = VALIDATE_STRINGLETON(name, "type %* is not a valid query name")
	return types.newtable({ [name] = types.singleton(true) })
end

type function PseudoSelector(class_name: type): type
	--stylua: ignore
	local name = VALIDATE_STRINGLETON(class_name, "type %* is not a valid pseudo-instance class name string"):value() :: string

	if not PseudoInstances:readproperty(class_name) then
		error(`class '{name}' is not a valid pseudo-instance`, 0)
	end
	return types.singleton("::" .. name)
end

type SheetData<Tokens, Tags, Queries> = {
	read instance: RobloxStyleSheet,
	read _queries: Queries,
	read __I_DO_NOT_EXIST_AT_RUNTIME: {
		read tokens: Tokens,
		read tags: Tags,
	},
}

type TypeOnly<Self> = index<Self, "__I_DO_NOT_EXIST_AT_RUNTIME">
type TokensOf<Self> = index<TypeOnly<Self>, "tokens">
type TagsOf<Self> = index<TypeOnly<Self>, "tags">
type QueriesOf<Self> = index<Self, "_queries">
type TagValue<Self> = keyof<TagsOf<Self>> | () -> keyof<TagsOf<Self>>?

type TokenState<Self, NewTokens> = SheetData<
	instance_types.Merge<TokensOf<Self>, NewTokens>,
	TagsOf<Self>,
	QueriesOf<Self>
>
type QueryState<Self, Name> = SheetData<
	TokensOf<Self>,
	TagsOf<Self>,
	instance_types.Merge<QueriesOf<Self>, QueryFrom<Name>>
>
type DerivedState<Self, Other> = SheetData<
	instance_types.Merge<TokensOf<Other>, TokensOf<Self>>,
	instance_types.Merge<TagsOf<Self>, TagsOf<Other>>,
	instance_types.Merge<QueriesOf<Self>, QueriesOf<Other>>
>
type RuleState<Self, Selector> = SheetData<
	TokensOf<Self>,
	instance_types.Merge<TagsOf<Self>, TagsFrom<Selector>>,
	QueriesOf<Self>
>

-- string generics are unioned with "" because otherwise luau widens them to `string`,
type SheetPrototype = {
	__index: SheetPrototype,
	tags: <Self>(self: Self, tags: { TagValue<Self> }) -> Action,
	link: (self: RuntimeSheet) -> Action,
	tokens: <Self, NewTokens>(
		self: Self,
		tokens: NewTokens
	) -> setmetatable<TokenState<Self, NewTokens>, SheetPrototype>,
	query: <Self, Name>(
		self: Self,
		name: Name | ""
	) -> (conditions: QueryConditionsFor<TokensOf<Self>>) -> setmetatable<QueryState<Self, Name>, SheetPrototype>,
	derive: <Self, Other>(self: Self, from: Other) -> setmetatable<DerivedState<Self, Other>, SheetPrototype>,
	-- doesn't do any type function shenanigans because its meant to be used at runtime, for stuff like theme switching
	underive: <Self>(self: Self, from: RuntimeSheet) -> Self,
	pseudo: <Self, ClassName>(
		self: Self,
		class_name: ClassName | PseduoInstanceNames
	) -> (
		props: StyleProperties<PseudoSelector<ClassName>, TokensOf<Self>, QueriesOf<Self>>
	) -> PseudoInstance<PseudoSelector<ClassName>>,
	rule: <Self, Selector>(
		self: Self,
		selector: Selector | ""
	) -> (
		props: StyleProperties<Selector, TokensOf<Self>, QueriesOf<Self>>
	) -> setmetatable<RuleState<Self, Selector>, SheetPrototype>,
}

export type Sheet<Tokens = {}, Tags = {}, Queries = {}> = setmetatable<SheetData<Tokens, Tags, Queries>, SheetPrototype>

local function create_query(parent: Instance, selector: string, name: string, conditions: { [string]: any })
	local instance = Instance.new("StyleRule")
	instance.Selector = selector
	instance.Name = name
	instance:SetProperties(conditions)
	instance.Parent = parent
end

local function create_rule(
	parent: Instance,
	selector: string,
	props: Props,
	known_queries: { [string]: true? },
	is_pseudo: boolean?
)
	local rule = Instance.new("StyleRule")
	rule.Selector = selector
	rule.Name = selector

	local priority = props._priority
	if priority then
		rule.Priority = priority
		props._priority = nil
	end

	local transitions = props._transitions
	if transitions then
		for property, transition in transitions do
			if property == "_default" then
				rule:SetDefaultPropertyTransition(transition)
			else
				rule:SetPropertyTransition(property, transition)
			end
		end
		props._transitions = nil
	end

	local queries = props._queries
	if queries then
		-- roblox gives queries under pseudo-instances a SelectorError
		if is_pseudo then
			error("pseudo-instances cannot have queries")
		elseif string.find(selector, "::", 1, true) then
			error(
				`rule '{selector}' cannot have queries since it ends in a pseudo-instance, create the pseudo-instance using StyleSheet:pseudo() in the properties of the rule instead`
			)
		end

		for name, query_props in queries do
			local conditions = query_props._conditions

			if conditions then
				-- a StyleQuery pseudo-instance under this rule only exists on the instances this rule styles
				create_query(rule, `::StyleQuery #{name}`, name, conditions)
			elseif not ((BUILTIN_QUERIES :: any)[name] or known_queries[name]) then
				error(`query '{name}' does not exist, add it with :query() or set _queries.{name}._conditions`)
			end

			create_rule(rule, "@" .. name, query_props, known_queries)
		end
		props._queries = nil
	end

	for i = #props, 1, -1 do
		local pseudo_instance = props[i] :: PseudoInstance
		create_rule(rule, pseudo_instance.selector, pseudo_instance.props, known_queries)
		-- :SetProperties() will error if its given a mixed table
		props[i] = nil
	end

	rule:SetProperties(props)
	rule.Parent = parent
end

local style_sheet_prototype = {}
style_sheet_prototype.__index = style_sheet_prototype

function style_sheet_prototype.tags(_self: RuntimeSheet, selected_tags: { string | () -> string? })
	return tags(selected_tags)
end

function style_sheet_prototype.tokens(self: RuntimeSheet, tokens: { [string]: unknown })
	local instance = self.instance

	for token_name, value in tokens do
		instance:SetAttribute(token_name, value)
	end
	return self
end

function style_sheet_prototype.rule(self: RuntimeSheet, selector: string)
	return function(props: Props)
		create_rule(self.instance, selector, props, self._queries)
		return self
	end
end

function style_sheet_prototype.pseudo(_self: RuntimeSheet, class_name: string)
	return function(props: Props): PseudoInstance
		return table.freeze({ selector = "::" .. class_name, props = props })
	end
end

function style_sheet_prototype.query(self: RuntimeSheet, name: string)
	return function(conditions: Props)
		-- a StyleQuery only activates under the instance it checks, so every GuiObject gets it as a pseudo-instance
		-- because its the easiest way to do a global style query
		-- #{name} is what names that pseudo-instance so @{name} selectors match it
		create_query(self.instance, `GuiObject::StyleQuery #{name}`, name, conditions)
		self._queries[name] = true
		return self
	end
end

function style_sheet_prototype.derive(self: RuntimeSheet, other: RuntimeSheet)
	local instance = self.instance
	local derives = instance:GetDerives()
	table.insert(derives, other.instance)
	instance:SetDerives(derives)

	-- derived sheets bring their queries along, so their names are valid here too
	local queries = self._queries
	for name in other._queries do
		queries[name] = true
	end
	return self
end

function style_sheet_prototype.underive(self: RuntimeSheet, other: RuntimeSheet)
	local instance = self.instance
	local derives = instance:GetDerives()
	local index = table.find(derives, other.instance)
	local total_derives = #derives

	if index then
		derives[index], derives[total_derives] = derives[total_derives], nil
		instance:SetDerives(derives)
	end
	return self
end

function style_sheet_prototype.link(self: RuntimeSheet)
	return action.create(function(instance)
		graph.assert_scope()
		local link = Instance.new("StyleLink")
		link.StyleSheet = self.instance
		link.Parent = instance
		cleanup(link)
	end)
end

local function style_sheet(name: string, parent: Instance): Sheet<{}, {}, {}>
	local instance = Instance.new("StyleSheet")
	instance.Name = name

	-- deferring parenting as to avoid datamodel change tracking whilst the style sheet is being built
	task.defer(function(instance: Instance, parent: Instance)
		instance.Parent = parent
	end, instance, parent)

	return table.freeze(setmetatable({
		instance = instance,
		_queries = {},
	}, style_sheet_prototype)) :: any
end

table.freeze(style_sheet_prototype)
return style_sheet
