local action = require("./action")

export type Instances = {
	PyramidHandleAdornment: PyramidHandleAdornment,
	ParticleEmitter2D: ParticleEmitter2D,
	ParticleEmitter: ParticleEmitter,
	AudioChannelSplitter: AudioChannelSplitter,
	AudioPitchShifter: AudioPitchShifter,
	AudioDeviceOutput: AudioDeviceOutput,
	AudioChannelMixer: AudioChannelMixer,
	AudioTextToSpeech: AudioTextToSpeech,
	AudioDeviceInput: AudioDeviceInput,
	AudioDistortion: AudioDistortion,
	AudioCompressor: AudioCompressor,
	AudioEqualizer: AudioEqualizer,
	AudioAnalyzer: AudioAnalyzer,
	AudioListener: AudioListener,
	AudioRecorder: AudioRecorder,
	AudioLimiter: AudioLimiter,
	AudioFlanger: AudioFlanger,
	AudioEmitter: AudioEmitter,
	AudioPlayer: AudioPlayer,
	AudioReverb: AudioReverb,
	AudioFilter: AudioFilter,
	ArcHandles: ArcHandles,
	AudioFader: AudioFader,
	AudioEcho: AudioEcho,
	AdGui: AdGui,
	BoxHandleAdornment: BoxHandleAdornment,
	BillboardGui: BillboardGui,
	BlurEffect: BlurEffect,
	CylinderHandleAdornment: CylinderHandleAdornment,
	ConeHandleAdornment: ConeHandleAdornment,
	CanvasGroup: CanvasGroup,
	Camera: Camera,
	DialogChoice: DialogChoice,
	DragDetector: DragDetector,
	Dialog: Dialog,
	Folder: Folder,
	Frame: Frame,
	Highlight: Highlight,
	Handles: Handles,
	ImageHandLeAdornment: ImageHandleAdornment,
	InputActionLabel: InputActionLabel,
	ImageButton: ImageButton,
	ImageLabel: ImageLabel,
	LineHandleAdornment: LineHandleAdornment,
	ProximityPrompt: ProximityPrompt,
	Path3D: Path3D,
	Path2D: Path2D,
	Part: Part,
	SphereHandLeAdornment: SphereHandleAdornment,
	SelectionSphere: SelectionSphere,
	ScrollingFrame: ScrollingFrame,
	SelectionBox: SelectionBox,
	StyleDerive: StyleDerive,
	StyleQuery: StyleQuery,
	SurfaceGui: SurfaceGui,
	StyleSheet: StyleSheet,
	SoundGroup: SoundGroup,
	StyleLink: StyleLink,
	ScreenGui: ScreenGui,
	StyleBase: StyleBase,
	StyleRule: StyleRule,
	Sound: Sound,
	TextButton: TextButton,
	TextLabel: TextLabel,
	TextBox: TextBox,
	UIAspectRatioConstraint: UIAspectRatioConstraint,
	UITextSizeConstraint: UITextSizeConstraint,
	UISizeConstraint: UISizeConstraint,
	UIDragDetector: UIDragDetector,
	UITableLayout: UITableLayout,
	UIPageLayout: UIPageLayout,
	UIGridLayout: UIGridLayout,
	UIListLayout: UIListLayout,
	UIGradient: UIGradient,
	UIFlexItem: UIFlexItem,
	UIPadding: UIPadding,
	UIStroke: UIStroke,
	UICorner: UICorner,
	UIShadow: UIShadow,
	UIScale: UIScale,
	UIBlur: UIBlur,
	ViewportCamera: ViewportCamera,
	ViewportFrame: ViewportFrame,
	VideoDisplay: VideoDisplay,
	VideoFrame: VideoFrame,
	WireframeHandleAdornment: WireframeHandleAdornment,
	WorldModel: WorldModel,
	Wire: Wire,
}

type Action = action.Identity

type instance = Instance

export type function get_instance(type_instance: type, instances: type, _instance: type): type
	if type_instance.tag == "singleton" then
		return instances:readproperty(type_instance) or _instance
	-- this is here so passing PropertiesFor a type like any because of a type solver issue,
	-- or passing it any or unknown in a prototype class will still work
	elseif type_instance == types.unknown or type_instance == types.any then
		return _instance
	elseif type_instance:issubtypeof(_instance) then
		return type_instance
	end

	error(
		`Can't convert type '{type_instance}' into an Instance type because it's not 'unknown', 'any', a ClassName string singleton, or a subtype of '{_instance}'`
	)
end

export type function GetInstance(type_instance: type): type
	return get_instance(type_instance, Instances, instance)
end

export type function get_read_only_instance_properties(): { type }
	return table.freeze({
		types.singleton("RobloxLocked"),
		types.singleton("ClassName"),
		types.singleton("UniqueId"),
	})
end

export type function PropertiesFor(type_instance: type): type
	-- uses the string values of the property name instead of the type instances
	-- as luau currently doesn't have singleton type userdatas setup to be the same if their value is the same
	local default_properties = {} :: { [string]: type }
	local type_tag = type_instance.tag

	-- dealing with intersections like this to support "generic constraints" ie T & { Name: "Head" }
	-- and also for providing default properties to an instance ie Frame & { Name: "Divider" },
	-- or nested default properties ie (Frame & { Name: "Divider" }) & (Frame & { Parent: ScreenGui })
	if type_tag == "intersection" then
		local components = type_instance:components()
		local total_components = #components
		local class: type?

		while total_components > 0 do
			local component = components[total_components]
			total_components -= 1

			local component_tag = component.tag

			if component_tag == "intersection" then
				for _, inner_component in component:components() do
					total_components += 1
					components[total_components] = inner_component
				end
				continue
			elseif component_tag == "table" then
				for property, value in component:properties() do
					local value_type = value.write or value.read

					if value_type then
						local key = property:value() :: string
						local default_value = default_properties[key]

						default_properties[key] = if default_value
							then types.unionof(default_value, value_type)
							else value_type
					end
				end
				continue
			end

			-- doing this to support generics in the cases of like prototype metatables
			-- local prototype = {} :: ClassPrototype<any>
			if component == types.any or component == types.unknown then
				component = instance
			elseif not component:issubtypeof(instance) then
				--stylua: ignore
				error(`Expected component to be a properties table or '{instance}', but got '{component}'`)
			end

			if component == instance or not class then
				class = component
			elseif class ~= instance then
				-- the component's class could be any class, so we're getting their closest common ancestor as the class to get properties for
				-- to avoid issues with properties being allowed that don't exist on the instance that is having its properties set
				while not component:issubtypeof(class) do
					class = class:readparent() or instance
				end
			end
		end

		if not class then
			error("No class found in the intersection provided")
		end
		type_instance = class
	else
		type_instance = get_instance(type_instance, Instances, instance)
	end

	local read_only_properties = get_read_only_instance_properties()
	local head_table = {}
	local args_table = { head = head_table }
	local properties = {} :: { [type]: type }
	local current = type_instance :: type

	while current do
		for property, value in current:properties() do
			if table.find(read_only_properties, property) then
				continue
			end

			local write_value = value.write :: type
			local read_value = value.read :: type
			-- doing it like this because roblox may actually make their types more accurate,
			-- as callbacks on instances can't be read to get the callback, but they're typed as if they can be read
			local value_tag = ((read_value or write_value) :: type).tag

			-- TODO: special case functions when instance methods get marked as read only, as instances can have callback properties
			-- such as RemoteFunction.OnServerInvoke
			if value_tag == "function" or value_tag == "intersection" then
				continue
			end

			local connect: type

			if value_tag == "extern" then
				-- iterating :properties() here because as of writing doing the following doesn't work
				-- because type userdatas aren't the same even if they have the same value and also because extern type userdatas don't have :readproperty()
				-- connect = t:properties()[types.singleton("Connect")].read
				for key, value in read_value:properties() do
					if key:value() == "Connect" then
						connect = value.read or value.write :: any
						break
					end
				end
			-- luau lsp types RBXScriptSignals as tables
			elseif value_tag == "table" then
				connect = read_value:readproperty(types.singleton("Connect")) :: any
			end

			local property_value: type

			if connect then
				property_value = types.optional(connect:parameters().head[2])
			elseif write_value then
				head_table[1] = read_value

				--stylua: ignore
				property_value = types.optional(types.unionof(types.newfunction(nil, args_table :: any), write_value))
				local property_name = property:value() :: string
				local default_value = default_properties[property_name]

				if default_value then
					if not default_value:issubtypeof(write_value) then
						--stylua: ignore
						error(`Expected default value provided for property '{property_name}' to be '{write_value}', but got '{default_value}' via one of the tables in the intersection provided`)
					end
					property_value = types.unionof(property_value, default_value)
				end
			end

			properties[property] = property_value
		end

		current = current:readparent()
	end

	properties = types.newtable(properties)

	-- TODO: Use a read only indexer when released to properly accept children which are subtypes of `Instance`
	-- Functions returning a child can return an array of children, or alike functions, nested to any level
	local function_returns_child = types.newfunction()
	local child_only_union = types.unionof(function_returns_child, instance)

	local nested_table_or_function_or_child = types.newtable()
	local nested_child_union = types.unionof(child_only_union, nested_table_or_function_or_child)
	nested_table_or_function_or_child:setindexer(types.number, nested_child_union)
	function_returns_child:setreturns({ nested_child_union })

	local full_union = types.unionof(child_only_union, Action, properties)
	properties:setindexer(types.number, types.optional(full_union))

	return properties
end

return nil
