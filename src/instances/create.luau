local bind = require("./bind")

type Instances = {
	Folder: Folder,
	BillboardGui: BillboardGui,
	CanvasGroup: CanvasGroup,
	Frame: Frame,
	ImageButton: ImageButton,
	ImageLabel: ImageLabel,
	ScreenGui: ScreenGui,
	ScrollingFrame: ScrollingFrame,
	SurfaceGui: SurfaceGui,
	TextBox: TextBox,
	TextButton: TextButton,
	TextLabel: TextLabel,
	UIAspectRatioConstraint: UIAspectRatioConstraint,
	UICorner: UICorner,
	UIGradient: UIGradient,
	UIGridLayout: UIGridLayout,
	UIListLayout: UIListLayout,
	UIPadding: UIPadding,
	UIPageLayout: UIPageLayout,
	UIScale: UIScale,
	UISizeConstraint: UISizeConstraint,
	UIStroke: UIStroke,
	UIFlexItem: UIFlexItem,
	UITableLayout: UITableLayout,
	UITextSizeConstraint: UITextSizeConstraint,
	VideoFrame: VideoFrame,
	ViewportFrame: ViewportFrame,
	UIDragDetector: UIDragDetector,
	ProximityPrompt: ProximityPrompt,
	Part: Part,
	WorldModel: WorldModel,
	Camera: Camera,
}

type function GetProperties(instance, instancetype)
	local properties = types.newtable()

	local function is_signal(value: type): false | type
		if not (value:is("class") or value:is("table")) then
			return false
		end

		for key, value in value:properties() do
			if
				key:value() == "Connect"
				and value.read
				and value.read.tag == "function"
			then
				return value.read
			end
		end

		return false
	end

	local function insert(object)
		if object:readparent() == nil then
			return
		end
		for key, value in object:properties() do
			local is_a_signal = is_signal(value.read)
			if is_a_signal and value.read:is("table") then -- luau-lsp
				local connect_fn = is_a_signal
				local params = connect_fn:parameters()
				if params.head then
					table.remove(params.head, 1)
				end
			elseif
				value.read:is("function") or value.read:is("intersection")
			then
				continue
			elseif value.write then
				local type = types.optional(
					types.unionof(
						types.newfunction({}, { head = { value.read } }),
						value.write :: any
					)
				)

				properties:setproperty(key :: any, type)
			end
		end

		insert(object:readparent())
	end
	insert(instance)

	local action = types.newtable({
		[types.singleton("priority")] = { read = types.number },
		[types.singleton("callback")] = {
			read = types.newfunction({ head = { instancetype } }),
		},
	} :: any)

	local function_returns_child = types.newfunction()
	local nested_table_or_function_or_child = types.newtable()
	local union = types.unionof(
		instancetype,
		function_returns_child,
		nested_table_or_function_or_child
	)

	nested_table_or_function_or_child:setindexer(types.number, union)
	function_returns_child:setreturns({ union })

	properties:setindexer(
		types.number,
		types.optional(
			types.unionof(
				action,
				instancetype,
				function_returns_child,
				properties
			)
		)
	)

	return properties
end

type function GetInstance(instance_name, instances, instancetype)
	if not instance_name:is("singleton") then
		return instancetype
	end

	for key, value in instances:properties() do
		if (key :: type):value() == instance_name:value() then
			return value.read
		end
	end

	return instancetype
end

local function try_create_inst(class_name: string): Instance
	local success, result = pcall(Instance.new, class_name)
	if not success then
		-- error at the location of the create call
		error(`Instance class "{class_name}" does not exist`, 3)
	end

	return result
end

local function create<Class>(
	class_name: Class
): (
	GetProperties<GetInstance<Class, Instances, Instance>, Instance>
) -> GetInstance<Class, Instances, Instance>
	return function(props: GetProperties<
		GetInstance<Class, Instances, Instance>,
		Instance
	>): GetInstance<Class, Instances, Instance>
		return bind(try_create_inst(class_name), props :: any) :: any
	end
end

return create
