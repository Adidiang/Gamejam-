extends Control
## 开始页的两名初始员工草稿；确认开始前不改游戏状态。
signal selection_changed
const Model = preload("res://scripts/game_model.gd")
const Table = preload("res://scripts/character_table.gd")
const PAPER := Color("fffdf7")
const INK := Color("203e42")
const TEAL := Color("2a6965")
const GOLD := Color("efc56c")
var selected_ids: Array[String] = ["", ""]
var slot_buttons: Array[Button] = []
var option_buttons: Array[Button] = []
var picker: Control
var dialog: PanelContainer
var grid: GridContainer
var close_button: Button
var active_slot := -1

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := Label.new()
	title.text = "选择两名初始员工"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", INK)
	title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title.anchor_left = 0.1
	title.anchor_right = 0.9
	title.anchor_top = 0.15
	title.anchor_bottom = 0.23
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.anchor_left = 0.27
	row.anchor_right = 0.73
	row.anchor_top = 0.28
	row.anchor_bottom = 0.65
	row.add_theme_constant_override("separation", 28)
	add_child(row)
	for index in 2:
		var button := _card()
		button.name = "StartingMember%d" % (index + 1)
		button.pressed.connect(open_slot.bind(index))
		row.add_child(button)
		slot_buttons.append(button)
		_fill_card(button, -1)
	_build_picker()

func _build_picker() -> void:
	picker = Control.new()
	picker.name = "EmployeePicker"
	picker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(picker)
	var dimmer := ColorRect.new()
	dimmer.color = Color(0.04, 0.10, 0.12, 0.7)
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	picker.add_child(dimmer)
	dialog = PanelContainer.new()
	dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dialog.anchor_left = 0.08
	dialog.anchor_right = 0.92
	dialog.anchor_top = 0.10
	dialog.anchor_bottom = 0.90
	dialog.add_theme_stylebox_override("panel", _box(PAPER, Color("dcded1"), 24))
	picker.add_child(dialog)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	dialog.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := Label.new()
	title.text = "选择员工"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", INK)
	header.add_child(title)
	close_button = Button.new()
	close_button.text = "关闭"
	close_button.pressed.connect(close_picker)
	header.add_child(close_button)
	grid = GridContainer.new()
	grid.columns = 5
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	column.add_child(grid)
	for member_id in Model.DEFINITIONS.size():
		var button := _card()
		button.pressed.connect(choose.bind(str(Model.DEFINITIONS[member_id].id)))
		grid.add_child(button)
		_fill_card(button, member_id)
		option_buttons.append(button)
	picker.hide()

func _card() -> Button:
	var button := Button.new()
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_stylebox_override("normal", _box(PAPER, Color("b8c7be")))
	button.add_theme_stylebox_override("hover", _box(Color("edf3eb"), TEAL))
	button.add_theme_stylebox_override("focus", _box(PAPER, GOLD))
	button.add_theme_stylebox_override("pressed", _box(Color("e0ece2"), TEAL))
	button.add_theme_stylebox_override("disabled", _box(Color("e6e7e1"), Color("d2d5cc")))
	var portrait := TextureRect.new()
	portrait.name = "Portrait"
	portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portrait.offset_left = 10
	portrait.offset_top = 10
	portrait.offset_right = -10
	portrait.offset_bottom = -42
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(portrait)
	var label := Label.new()
	label.name = "MemberName"
	label.anchor_left = 0.0
	label.anchor_right = 1.0
	label.anchor_top = 1.0
	label.anchor_bottom = 1.0
	label.offset_left = 6
	label.offset_right = -6
	label.offset_top = -38
	label.offset_bottom = -4
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", INK)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(label)
	return button

func _fill_card(button: Button, member_id: int) -> void:
	var portrait := button.get_node("Portrait") as TextureRect
	var label := button.get_node("MemberName") as Label
	portrait.texture = null if member_id < 0 else Table.portrait_texture(Model.DEFINITIONS[member_id].portrait)
	label.text = "选择员工" if member_id < 0 else str(Model.DEFINITIONS[member_id].name)

func is_complete() -> bool:
	var ids := Table.initial_ids()
	return selected_ids.size() == 2 and selected_ids[0] in ids and selected_ids[1] in ids and selected_ids[0] != selected_ids[1]

func open_slot(index: int) -> void:
	if index < 0 or index >= 2 or not is_visible_in_tree(): return
	active_slot = index
	var other := selected_ids[1 - index]
	for member_id in option_buttons.size():
		var button := option_buttons[member_id]
		button.disabled = Model.DEFINITIONS[member_id].id == other
		button.modulate.a = 0.35 if button.disabled else 1.0
	picker.show()
	for button in option_buttons:
		if not button.disabled:
			button.grab_focus()
			break

func choose(character_id: String) -> void:
	if active_slot < 0 or not picker.visible or not is_visible_in_tree(): return
	var ids := Table.initial_ids()
	var member_id := ids.find(character_id)
	if member_id < 0 or character_id == selected_ids[1 - active_slot]: return
	selected_ids[active_slot] = character_id
	_fill_card(slot_buttons[active_slot], member_id)
	close_picker()
	selection_changed.emit()

func close_picker() -> void:
	picker.hide()
	if active_slot >= 0: slot_buttons[active_slot].grab_focus()
	active_slot = -1

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not picker.visible: return
	if event is InputEventKey and event.is_action_pressed("ui_cancel"):
		close_picker()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not dialog.get_global_rect().has_point(event.position):
		close_picker()
		get_viewport().set_input_as_handled()

func _box(fill: Color, border: Color, margin: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_content_margin(side, margin)
	return style
