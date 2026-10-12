extends CanvasLayer
## 通用文本确认框：把一段文本作为参数传入，界面在屏幕中央弹出确认框，
## 正文是这段文本，下方固定是「取消」（左）和「确认」（右）两个按钮。
## 调用方式：if await TextConfirm.ask("要问玩家的文本"): ...
## 点「确认」返回 true；点「取消」或按 Esc 返回 false。
## 界面只负责提问和返回结果，不修改任何游戏数据；同时发起的多个请求按顺序依次显示。
## 打开期间暂停场景树、结束时还原，避免点击或按键穿透到下层界面。

const PAPER := Color("fffdf7")
const INK := Color("203e42")
const TEAL := Color("2a6965")
const GOLD := Color("efc56c")
const BORDER := Color("dcded1")
const SHADE := Color(0, 0, 0, 0.45)

const CANVAS_LAYER := 100
const DIALOG_WIDTH := 720.0
const DIALOG_MARGIN := 28.0
const DIALOG_SEPARATION := 20.0
const BUTTON_WIDTH := 176.0
const BUTTON_HEIGHT := 52.0
const BUTTON_SEPARATION := 24
## 正文高度按文本行数计算，短文本收窄、长文本封顶后交给滚动条。
const MIN_BODY_HEIGHT := 96.0
const MAX_BODY_HEIGHT := 320.0
const BODY_CHROME := DIALOG_MARGIN * 2.0 + DIALOG_SEPARATION + BUTTON_HEIGHT
const FONT_SIZE := 24
const BODY_FONT_SIZE := 24
const CANCEL_TEXT := "取消"
const CONFIRM_TEXT := "确认"
const FONT_NAMES := "Microsoft YaHei,Noto Sans CJK SC,sans-serif"

var screen: Control
var dimmer: ColorRect
var dialog: PanelContainer
var body: ScrollContainer
var text_label: Label
var cancel_button: Button
var confirm_button: Button

var _font: Font
var _requests: Array[Dictionary] = []
var _active := false
var _pause_taken := false
var _previous_paused := false
var _previous_focus: Control = null

func _ready() -> void:
	## 作为全局单例时默认只搭好界面、不显示，等 ask() 打开。
	layer = CANVAS_LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_input(true)
	_build()

func _build() -> void:
	var ui_font := SystemFont.new()
	ui_font.font_names = PackedStringArray(FONT_NAMES.split(","))
	_font = ui_font
	var ui_theme := Theme.new()
	ui_theme.default_font = ui_font
	ui_theme.default_font_size = FONT_SIZE
	screen = Control.new()
	screen.name = "Screen"
	screen.theme = ui_theme
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.visible = false
	add_child(screen)
	dimmer = ColorRect.new()
	dimmer.name = "Dimmer"
	dimmer.color = SHADE
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	screen.add_child(dimmer)
	dialog = PanelContainer.new()
	dialog.name = "Dialog"
	dialog.anchor_left = 0.5
	dialog.anchor_top = 0.5
	dialog.anchor_right = 0.5
	dialog.anchor_bottom = 0.5
	dialog.grow_horizontal = Control.GROW_DIRECTION_BOTH
	dialog.grow_vertical = Control.GROW_DIRECTION_BOTH
	dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	dialog.add_theme_stylebox_override("panel", _box(PAPER, BORDER, 2))
	screen.add_child(dialog)
	_build_body()

func _build_body() -> void:
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, int(DIALOG_MARGIN))
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialog.add_child(margin)
	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", int(DIALOG_SEPARATION))
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)
	# 正文放在锚定满格的滚动层里，这样长文本只让正文滚动，不会把确认框撑出画面。
	var body_wrap := Control.new()
	body_wrap.name = "BodyWrap"
	body_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(body_wrap)
	body = ScrollContainer.new()
	body.name = "Body"
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.mouse_filter = Control.MOUSE_FILTER_STOP
	body_wrap.add_child(body)
	text_label = Label.new()
	text_label.name = "TextLabel"
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_label.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
	text_label.add_theme_color_override("font_color", INK)
	text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(text_label)
	var row := HBoxContainer.new()
	row.name = "ButtonRow"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", BUTTON_SEPARATION)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(row)
	cancel_button = _make_button(CANCEL_TEXT, "CancelButton", false)
	cancel_button.pressed.connect(_answer.bind(false))
	row.add_child(cancel_button)
	confirm_button = _make_button(CONFIRM_TEXT, "ConfirmButton", true)
	confirm_button.pressed.connect(_answer.bind(true))
	row.add_child(confirm_button)

func _make_button(text: String, node_name: String, filled: bool) -> Button:
	## 与主界面一致的按钮样式：确认是实心，取消是描边。
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size = Vector2(BUTTON_WIDTH, BUTTON_HEIGHT)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var base := TEAL if filled else PAPER
	button.add_theme_stylebox_override("normal", _box(base, INK if not filled else TEAL, 2))
	button.add_theme_stylebox_override("hover", _box(base.darkened(0.06), TEAL, 3))
	button.add_theme_stylebox_override("pressed", _box(base.darkened(0.12), TEAL, 3))
	button.add_theme_stylebox_override("focus", _box(Color.TRANSPARENT, GOLD, 3))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, PAPER if filled else INK)
	return button

func ask(text: String) -> bool:
	## 弹出确认框并等待玩家选择：点确认返回 true，点取消或按 Esc 返回 false。
	## 同一时间只显示一条；上一条还没回复时，新请求先排队，依次显示、各自收到自己的结果。
	if not is_inside_tree():
		push_warning("文本确认框不在场景树中，本次按取消处理。")
		return false
	var tree := _tree()
	if tree == null:
		push_warning("文本确认框找不到场景树，本次按取消处理。")
		return false
	var request := {"text": text, "done": false, "accepted": false}
	_requests.append(request)
	if not _active:
		_activate_next()
	while not request.done:
		# 用逐帧等待而不是 await 信号，多个请求同时等待时不会互相串结果。
		await tree.process_frame
	return bool(request.accepted)

func is_open() -> bool:
	## 当前是否已经弹着确认框（还在排队的请求也算在显示流程里）。
	return screen.visible

func _activate_next() -> void:
	if _requests.is_empty():
		_deactivate()
		return
	if not _active:
		_active = true
		_begin_modal()
	_show(String(_requests[0]["text"]))

func _show(text: String) -> void:
	text_label.text = text
	_resize_dialog(text)
	screen.visible = true
	cancel_button.grab_focus()

func _resize_dialog(text: String) -> void:
	## 宽度固定，高度跟着文本行数走：短文本收窄，长文本封顶后由滚动条查看。
	var body_height := clampf(_text_height(text), MIN_BODY_HEIGHT, MAX_BODY_HEIGHT)
	var height := body_height + BODY_CHROME
	dialog.offset_left = -DIALOG_WIDTH * 0.5
	dialog.offset_top = -height * 0.5
	dialog.offset_right = DIALOG_WIDTH * 0.5
	dialog.offset_bottom = height * 0.5

func _text_height(text: String) -> float:
	## 按正文可用宽度量一次换行后的高度；量不出来时退回最小高度。
	if _font == null:
		return MIN_BODY_HEIGHT
	return _font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT,
		DIALOG_WIDTH - DIALOG_MARGIN * 2.0, BODY_FONT_SIZE).y

func _answer(accepted: bool) -> void:
	## 当前请求结束，交给调用方；还有排队的请求就接着显示。
	if _requests.is_empty():
		return
	var request: Dictionary = _requests.pop_front()
	request.done = true
	request.accepted = accepted
	_activate_next()

func _begin_modal() -> void:
	## 记下打开前的暂停与焦点状态，关闭时还原。
	var tree := _tree()
	if tree != null and not _pause_taken:
		_previous_paused = tree.paused
		tree.paused = true
		_pause_taken = true
	var viewport := get_viewport()
	if viewport != null:
		_previous_focus = viewport.gui_get_focus_owner()

func _deactivate() -> void:
	_active = false
	screen.visible = false
	if _pause_taken:
		var tree := _tree()
		if tree != null:
			tree.paused = _previous_paused
		_pause_taken = false
	if is_instance_valid(_previous_focus) and _previous_focus.is_inside_tree():
		_previous_focus.grab_focus()
	_previous_focus = null

func _input(event: InputEvent) -> void:
	if not is_open():
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.is_action("ui_cancel"):
			_answer(false)
			get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	## 被释放或移出场景树时，没回复的请求一律按取消处理，避免调用方一直等待。
	for request in _requests:
		request.done = true
	_requests.clear()
	_deactivate()

func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree

func _box(fill: Color, border: Color, width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(width)
	return box
