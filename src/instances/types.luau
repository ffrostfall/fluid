local action = require("./action")

export type function Merge(base: type, overrides: type): type
	local properties = {} :: { [type]: type }
	local keys = {} :: { [string]: type }
	local source = base

	for index = 1, 2 do
		for key, property in source:properties() do
			local name = key:value() :: string
			local previous = keys[name]

			if previous then
				properties[previous] = nil
			end

			properties[key] = property.read
			keys[name] = key
		end
		source = overrides
	end

	return types.newtable(properties, overrides:indexer() or source:indexer())
end

-- Classes Roblox allows as pseudo-instances in style sheets
export type PseudoInstances = {
	StyleQuery: StyleQuery,
	UIAspectRatioConstraint: UIAspectRatioConstraint,
	UITextSizeConstraint: UITextSizeConstraint,
	UISizeConstraint: UISizeConstraint,
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
}

export type Instances = Merge<PseudoInstances, {
	PyramidHandleAdornment: PyramidHandleAdornment,
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
	UIDragDetector: UIDragDetector,
	ViewportCamera: ViewportCamera,
	ViewportFrame: ViewportFrame,
	VideoDisplay: VideoDisplay,
	VideoFrame: VideoFrame,
	WireframeHandleAdornment: WireframeHandleAdornment,
	WorldModel: WorldModel,
	Wire: Wire,
}>

type instance = Instance

export type function GetInstance(class_name: type, instances: type): type
	if not class_name:is("singleton") then
		return instance
	end

	return instances:readproperty(class_name) or instance
end

type UnknownConnectCallback = (...any) -> ()

type Signal = RBXScriptSignal

type function get_connect(v: type): type?
	local connect = v:readproperty(types.singleton("Connect"))

	if connect and connect:is("function") then
		local head = connect:parameters().head

		if not head then
			return nil
		end
		local callback = head[2]

		if callback and callback:is("function") then
			return callback
		end
	end

	return nil
end

export type function is_signal(v: type): type?
	if v == Signal and v.tag == "extern" then
		return UnknownConnectCallback
	-- luau lsp types RBXScriptSignals as tables
	elseif v.tag == "table" then
		local connect = get_connect(v)

		if connect then
			return connect
		end

		-- i cba to test if this is needed or not
		local metatable = v:metatable()

		if metatable then
			connect = get_connect(metatable)

			if connect then
				return connect
			end
		end
	end

	return nil
end

type Action = action.Identity

export type function get_read_only_instance_properties(): { type }
	return table.freeze({
		types.singleton("RobloxLocked"),
		types.singleton("ClassName"),
		types.singleton("UniqueId"),
	})
end

export type function PropertiesFor(object: type): type
	-- support for fake generic constraints ie types like T & Instance
	if object.tag == "intersection" then
		local components = object:components()

		if #components == 2 then
			object = components[1]
		else
			error("cannot provide an intersection type with more than 2 components to PropertiesFor")
		end
	end

	if object.tag == "singleton" then
		object = GetInstance(object, Instances)
	elseif not object:issubtypeof(instance) then
		error("Cannot get properties of a non Instance type")
	end

	local read_only_properties = get_read_only_instance_properties()
	local head_table = {}
	local args_table = { head = head_table }
	local properties = {} :: { [type]: type }
	local current = object :: type

	while current do
		for property, value in current:properties() do
			if table.find(read_only_properties, property) then
				continue
			end

			local value_read = value.read :: type
			local callback = is_signal(value_read)

			if callback then
				properties[property] = types.optional(callback)
			elseif value_read.tag == "function" or value_read.tag == "intersection" then
				continue
			elseif value.write then
				head_table[1] = value_read

				--stylua: ignore
				properties[property] = types.optional(
					types.unionof(types.newfunction(nil, args_table :: any), value.write)
				)
			end
		end

		current = current:readparent()
	end

	properties = types.newtable(properties)

	-- Functions returning a child can return an array of children, or alike functions, nested to any level
	local function_returns_child = types.newfunction()
	local child_only_union = types.unionof(function_returns_child, instance)

	local nested_table_or_function_or_child = types.newtable()
	local nested_child_union = types.unionof(child_only_union, nested_table_or_function_or_child)
	nested_table_or_function_or_child:setreadindexer(types.number, nested_child_union)
	function_returns_child:setreturns({ nested_child_union })

	local full_union = types.unionof(child_only_union, Action, properties)
	properties:setreadindexer(types.number, types.optional(full_union))

	return properties
end

return nil
