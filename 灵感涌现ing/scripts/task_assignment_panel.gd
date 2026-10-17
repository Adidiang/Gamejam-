extends Control
## 右侧任务列表；全屏透明输入层使外侧点击只返回人物页。
signal task_requested(task_id: String)
signal closed
const Model = preload("res://scripts/game_model.gd")
var panel: PanelContainer
var tasks_column: VBoxContainer
var task_buttons: Array[Button] = []
var pending := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_outside_input)
	panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.anchor_left = 0.64
	panel.anchor_top = 0.10
	panel.anchor_right = 0.97
	panel.anchor_bottom = 0.94
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var box := StyleBoxFlat.new()
	box.bg_color = Color("fffdf7")
	box.border_color = Color("2a6965")
	box.set_border_width_all(2)
	box.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", box)
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	panel.add_child(column)
	var title := Label.new()
	title.text = "分配任务"
	title.add_theme_color_override("font_color", Color("203e42"))
	column.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	tasks_column = VBoxContainer.new()
	tasks_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(tasks_column)
	hide()

func open(state: Dictionary, member_id: int = -1) -> void:
	pending = false
	for child in tasks_column.get_children():
		tasks_column.remove_child(child)
		child.queue_free()
	task_buttons.clear()
	for task in Model.available_tasks(state, member_id):
		var button := Button.new()
		button.text = "%s\n消耗 %d 行动步数 · 每年一次" % [task.name, 0 if Model.Characters.free_task(state, Model.DEFINITIONS, member_id) else task.cost]
		button.custom_minimum_size.y = 96
		button.add_theme_font_size_override("font_size", 20)
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.tooltip_text = task.get("description", "无前置。使用增幅后的属性：\n表现力＝脑洞＋美术\n创新性＝表现力×系数\n系数＝脑洞÷max(美术, 1)，限制在 0.1～2（仅此任务）")
		var button_style := StyleBoxFlat.new()
		button_style.bg_color = Color("2a6965")
		button.add_theme_stylebox_override("normal", button_style)
		var hover_style := button_style.duplicate() as StyleBoxFlat
		hover_style.bg_color = Color("357e79")
		button.add_theme_stylebox_override("hover", hover_style)
		for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			button.add_theme_color_override(key, Color("fffdf7"))
		button.pressed.connect(func():
			if not pending:
				pending = true
				task_requested.emit(task.id))
		tasks_column.add_child(button)
		task_buttons.append(button)
	if task_buttons.is_empty():
		var empty := Label.new()
		empty.text = "本年暂无可用任务"
		empty.add_theme_color_override("font_color", Color("203e42"))
		tasks_column.add_child(empty)
	show()
	if not task_buttons.is_empty():
		task_buttons[0].grab_focus()

func close() -> void:
	if pending:
		return
	hide()
	closed.emit()

func _outside_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if not panel.get_rect().has_point(event.position):
			accept_event()
			close()

func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
