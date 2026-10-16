extends Control
## 调试面板：改当前作品属性、在本年内跳到更晚的月份、切换全员满好感。
## 与工作分配表同一套写法：根节点不拦截输入，压暗的遮罩挡住身后的主界面。
## 面板只发出请求，是否真的生效由 DebugTools 决定，主界面回传结果后刷新显示；
## 正式版关闭 debug_config.gd 的总开关后，这个界面不会被创建。

signal closed
signal work_requested(key: String, mode: String, amount: float)
signal month_requested(month: int)
signal affinity_requested(on: bool)

const Tools = preload("res://scripts/debug/debug_tools.gd")
const NumberDisplay = preload("res://scripts/number_display.gd")

const PAPER := Color("fffdf7")
const INK := Color("203e42")
const TEAL := Color("2a6965")
const GOLD := Color("efc56c")
const MUTED := Color("72817a")

const DIALOG_SIZE := Vector2(980, 760)
const TITLE := "调试"
const HINT := "只在开发版可用。跳月份不会结算中间月份，跨年与回退已被禁止；正式版请在 scripts/debug/debug_config.gd 关闭总开关。"

var dialog: PanelContainer
var dimmer: ColorRect
var status_label: Label
var year_label: Label
var month_input: LineEdit
var jump_button: Button
var december_button: Button
var affinity_check: CheckBox
var close_button: Button
var work_inputs: Dictionary = {}
var work_add_buttons: Dictionary = {}
var work_set_buttons: Dictionary = {}

func _ready() -> void:
	# 根节点不拦截输入；遮罩和对话框负责挡住身后的主界面。
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process_input(true)
	dimmer = ColorRect.new()
	dimmer.name = "Dimmer"
	dimmer.color = Color(0, 0, 0, 0.45)
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dimmer)
	dialog = PanelContainer.new()
	dialog.name = "Dialog"
	dialog.anchor_left = 0.5
	dialog.anchor_top = 0.5
	dialog.anchor_right = 0.5
	dialog.anchor_bottom = 0.5
	dialog.offset_left = -DIALOG_SIZE.x * 0.5
	dialog.offset_top = -DIALOG_SIZE.y * 0.5
	dialog.offset_right = DIALOG_SIZE.x * 0.5
	dialog.offset_bottom = DIALOG_SIZE.y * 0.5
	dialog.grow_horizontal = Control.GROW_DIRECTION_BOTH
	dialog.grow_vertical = Control.GROW_DIRECTION_BOTH
	dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	dialog.add_theme_stylebox_override("panel", _style(PAPER, INK, 3))
	add_child(dialog)
	_build_body()
	visible = false

func open(state: Dictionary, full_affinity: bool) -> void:
	## 每次打开都清掉上次输入的月份与提示，避免误按到旧数值。
	month_input.text = ""
	show_state(state, full_affinity)
	set_status("")
	visible = true
	month_input.grab_focus()

func show_state(state: Dictionary, full_affinity: bool) -> void:
	## 属性输入框按统一规则显示当前值；只格式化文字，不修改真实状态。
	var values := Tools.work_values(state)
	for key in Tools.WORK_KEYS:
		if work_inputs.has(key):
			(work_inputs[key] as LineEdit).text = NumberDisplay.text(float(values[key]))
	year_label.text = "第 %d 年" % int(state.year)
	month_input.placeholder_text = "当前 %d 月" % int(state.month)
	# 用 no_signal 版本回填，避免刷新显示时又触发一次开关请求。
	affinity_check.set_pressed_no_signal(full_affinity)

func set_status(text: String) -> void:
	status_label.text = text

func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()

func _build_body() -> void:
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	dialog.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	column.add_child(_label(TITLE, 30, INK))
	var hint := _label(HINT, 17, MUTED)
	hint.name = "Hint"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)
	_build_work_rows(column)
	_build_time_row(column)
	_build_affinity_row(column)
	status_label = _label("", 18, TEAL)
	status_label.name = "StatusLabel"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(status_label)
	close_button = _button("关闭", 180)
	close_button.name = "CloseButton"
	close_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	close_button.pressed.connect(close)
	column.add_child(close_button)

func _build_work_rows(column: VBoxContainer) -> void:
	column.add_child(_label("当前作品属性", 22, TEAL))
	for key in Tools.WORK_KEYS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		column.add_child(row)
		var name_label := _label(Tools.WORK_NAMES[key], 20)
		name_label.custom_minimum_size.x = 96
		row.add_child(name_label)
		var input := _line_edit("WorkInput" + key, 200.0)
		input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		input.tooltip_text = "点「增加」在当前值上叠加，点「设为」直接替换；结果限制在 0～%d。" % int(Tools.WORK_MAXIMUM)
		input.text_submitted.connect(func(_text: String): _request_work(key, "add"))
		row.add_child(input)
		work_inputs[key] = input
		var add_button := _button("增加", 110)
		add_button.name = "WorkAdd" + key
		add_button.pressed.connect(func(): _request_work(key, "add"))
		row.add_child(add_button)
		work_add_buttons[key] = add_button
		var set_button := _button("设为", 110)
		set_button.name = "WorkSet" + key
		set_button.pressed.connect(func(): _request_work(key, "set"))
		row.add_child(set_button)
		work_set_buttons[key] = set_button

func _build_time_row(column: VBoxContainer) -> void:
	column.add_child(_label("当前时间", 22, TEAL))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)
	year_label = _label("第 1 年", 20)
	year_label.name = "YearLabel"
	year_label.custom_minimum_size.x = 110
	row.add_child(year_label)
	row.add_child(_label("跳到", 20, MUTED))
	month_input = _line_edit("MonthInput", 160.0)
	month_input.tooltip_text = "只填本年更晚的月份（1～12）。年份由当前进度决定，这里不能改，也不会跨年。"
	month_input.text_submitted.connect(func(_text: String): _request_month())
	row.add_child(month_input)
	row.add_child(_label("月", 20, MUTED))
	jump_button = _button("跳转", 110)
	jump_button.name = "JumpButton"
	jump_button.pressed.connect(_request_month)
	row.add_child(jump_button)
	december_button = _button("跳到 12 月", 170)
	december_button.name = "DecemberButton"
	december_button.pressed.connect(func(): month_requested.emit(Tools.MONTHS_IN_YEAR))
	row.add_child(december_button)

func _build_affinity_row(column: VBoxContainer) -> void:
	column.add_child(_label("全员满好感", 22, TEAL))
	affinity_check = CheckBox.new()
	affinity_check.name = "AffinityCheck"
	affinity_check.text = "全员满好感模式（打开面板时套用，所有人按好感上限 %d 计算）" % Tools.AFFINITY_MAXIMUM
	affinity_check.add_theme_font_size_override("font_size", 20)
	# 勾选后的 CheckBox 走的是「pressed」状态，只改 font_color 不够，
	# 默认主题的浅色按下字色会让说明文字在浅色面板上完全看不见。
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		affinity_check.add_theme_color_override(state, INK)
	affinity_check.tooltip_text = "临时把好感写成上限，便于测试满增幅与技能解锁；关闭后按开启前记录的值恢复。"
	affinity_check.toggled.connect(func(on: bool): affinity_requested.emit(on))
	column.add_child(affinity_check)
	var hint := _label("关闭后按开启前记录的值恢复；满好感只影响能力增幅与技能解锁门槛，习得费用不变、也不会免费习得技能。", 17, MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)

func _request_work(key: String, mode: String) -> void:
	work_requested.emit(key, mode, _amount((work_inputs[key] as LineEdit).text))

func _request_month() -> void:
	## 非法输入统一交给 DebugTools 给提示，这里只把文本转成月份候选值。
	var text := month_input.text.strip_edges()
	month_requested.emit(int(text) if text.is_valid_int() else 0)

func _amount(text: String) -> float:
	## 不能直接 to_float：空串与乱填都会变成 0，那会被当成合法的「设为 0」。
	var trimmed := text.strip_edges()
	return trimmed.to_float() if trimmed.is_valid_float() else NAN

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.is_action("ui_cancel"):
			close()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed and button.button_index == MOUSE_BUTTON_LEFT and not _inside_dialog(button.position):
			# 点击界面外的部分：回到主界面。
			close()
			get_viewport().set_input_as_handled()

func _inside_dialog(viewport_point: Vector2) -> bool:
	var rect := dialog.get_global_rect()
	return viewport_point.x >= rect.position.x and viewport_point.x <= rect.position.x + rect.size.x \
		and viewport_point.y >= rect.position.y and viewport_point.y <= rect.position.y + rect.size.y

func _line_edit(node_name: String, width: float) -> LineEdit:
	## 输入框也走面板的纸色风格；默认主题的深灰底在浅色面板上很突兀。
	var input := LineEdit.new()
	input.name = node_name
	input.custom_minimum_size = Vector2(width, 44)
	input.add_theme_font_size_override("font_size", 20)
	input.add_theme_color_override("font_color", INK)
	input.add_theme_color_override("caret_color", INK)
	input.add_theme_color_override("font_placeholder_color", MUTED)
	input.add_theme_stylebox_override("normal", _input_style(INK, 2))
	input.add_theme_stylebox_override("focus", _input_style(GOLD, 3))
	return input

func _input_style(border: Color, width: int) -> StyleBoxFlat:
	var style := _style(PAPER, border, width)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	return style

func _label(text: String, font_size: int, color: Color = INK) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _button(text: String, min_width: float) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(min_width, 44)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_stylebox_override("normal", _style(TEAL, TEAL, 2))
	button.add_theme_stylebox_override("hover", _style(TEAL.lightened(0.12), GOLD, 2))
	button.add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, GOLD, 3))
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(key, PAPER)
	return button

func _style(fill: Color, border: Color, width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	return style



