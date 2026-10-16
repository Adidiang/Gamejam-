extends Control
## 年初加入事件：按模型给出的角色显示文本，确认后由界面外层提交入社。
signal confirmed(character_id: String)
const PAPER := Color("fffdf7")
const INK := Color("203e42")
const TEAL := Color("2a6965")
var character_id := ""
var title_label: Label
var body_label: Label
var confirm_button: Button
var dialog: PanelContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dimmer := ColorRect.new()
	dimmer.color = Color(0.04, 0.10, 0.12, 0.85)
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dimmer)
	dialog = PanelContainer.new()
	dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dialog.anchor_left = 0.18
	dialog.anchor_top = 0.15
	dialog.anchor_right = 0.82
	dialog.anchor_bottom = 0.85
	var style := StyleBoxFlat.new()
	style.bg_color = PAPER
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_content_margin(side, 28)
	dialog.add_theme_stylebox_override("panel", style)
	add_child(dialog)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 20)
	dialog.add_child(column)
	title_label = Label.new()
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.add_theme_font_size_override("font_size", 32)
	title_label.add_theme_color_override("font_color", INK)
	column.add_child(title_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	body_label = Label.new()
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_label.add_theme_font_size_override("font_size", 24)
	body_label.add_theme_color_override("font_color", INK)
	scroll.add_child(body_label)
	confirm_button = Button.new()
	confirm_button.text = "确认加入"
	confirm_button.custom_minimum_size = Vector2(200, 56)
	confirm_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	var button_style := StyleBoxFlat.new()
	button_style.bg_color = TEAL
	confirm_button.add_theme_stylebox_override("normal", button_style)
	confirm_button.add_theme_color_override("font_color", PAPER)
	confirm_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	confirm_button.pressed.connect(func():
		if visible: confirmed.emit(character_id))
	column.add_child(confirm_button)
	hide()

func open(definition: Dictionary) -> void:
	character_id = definition.id
	title_label.text = "%s 加入社团" % definition.name
	var text: String = definition.get("join_text", "")
	body_label.text = "加入文本" if text.strip_edges().is_empty() else text
	show()
	confirm_button.grab_focus()
