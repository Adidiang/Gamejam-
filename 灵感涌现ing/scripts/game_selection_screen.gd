extends Control
## 只维护未确认的表单草稿；确认后由 ClubGame 校验并写入年度作品档案。
signal project_requested(title: String, genre_id: String, topic_id: String, year: int)
const Catalog = preload("res://scripts/game_catalog.gd")
const Model = preload("res://scripts/game_model.gd")
const PAPER := Color("fffdf7")
const INK := Color("203e42")
const TEAL := Color("2a6965")
const GOLD := Color("efc56c")
const MUTED := Color("72817a")
var title_input: LineEdit
var year_label: Label
var preview_label: Label
var affinity_label: Label
var hint_label: Label
var confirm_button: Button
var genre_buttons: Array[Button] = []
var topic_buttons: Array[Button] = []
var genre_id := ""
var topic_id := ""
var selection_year := 1
## 打开选择页时读入的好感度快照：预览要在上限内显示本次真实增益。
var affinities: Array = []
var sidebar: PanelContainer
var genre_grid: GridContainer
var topic_grid: GridContainer
var margin: MarginContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var background := ColorRect.new()
	background.color = Color("f0ede5")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 36)
	margin.add_child(row)
	sidebar = PanelContainer.new()
	sidebar.custom_minimum_size.x = 300
	sidebar.add_theme_stylebox_override("panel", _box(INK, INK, 28))
	row.add_child(sidebar)
	var side_column := VBoxContainer.new()
	side_column.add_theme_constant_override("separation", 20)
	sidebar.add_child(side_column)
	side_column.add_child(_label("灵感涌现 ing", 30, PAPER))
	side_column.add_child(_label("年度游戏设计", 20, GOLD))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side_column.add_child(spacer)
	var slogan := _label("一个名字，\n一个新的世界。", 32, PAPER)
	side_column.add_child(slogan)
	var note := _label("和社团一起，\n把今年的灵感做成游戏。", 20, Color("c1d0c5"))
	side_column.add_child(note)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 14)
	scroll.add_child(column)
	year_label = _label("", 20, TEAL)
	column.add_child(year_label)
	column.add_child(_label("设计今年的游戏", 38))
	column.add_child(_label("起个名字，再选择一种类型和一种题材。", 20, MUTED))
	column.add_child(_label("01  游戏名字", 23))
	title_input = LineEdit.new()
	title_input.custom_minimum_size.y = 62
	title_input.placeholder_text = "自由输入你的游戏名字"
	title_input.clear_button_enabled = true
	title_input.add_theme_color_override("font_color", INK)
	title_input.add_theme_color_override("font_placeholder_color", MUTED)
	title_input.add_theme_color_override("caret_color", TEAL)
	title_input.add_theme_stylebox_override("normal", _box(PAPER, Color("dcded1"), 14))
	title_input.add_theme_stylebox_override("focus", _box(PAPER, TEAL, 14))
	title_input.text_changed.connect(func(_text: String): _refresh())
	column.add_child(title_input)
	column.add_child(_label("02  游戏类型", 23))
	genre_grid = _choices(column, Catalog.GENRES, genre_buttons, true)
	column.add_child(_label("03  游戏题材", 23))
	topic_grid = _choices(column, Catalog.TOPICS, topic_buttons, false)
	var preview := PanelContainer.new()
	preview.add_theme_stylebox_override("panel", _box(Color("e6e9dd"), Color("e6e9dd"), 18))
	column.add_child(preview)
	var preview_column := VBoxContainer.new()
	preview_column.add_theme_constant_override("separation", 8)
	preview.add_child(preview_column)
	preview_label = _label("", 22)
	preview_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	preview_column.add_child(preview_label)
	## 立项好感预览：只显示本次选择会加好感的成员，判定交给模型。
	affinity_label = _label("", 21)
	affinity_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_column.add_child(affinity_label)
	hint_label = _label("", 18, MUTED)
	column.add_child(hint_label)
	confirm_button = Button.new()
	confirm_button.text = "确认，开始今年的开发"
	confirm_button.custom_minimum_size.y = 62
	_style_choice(confirm_button)
	confirm_button.add_theme_stylebox_override("normal", _box(TEAL, TEAL, 14))
	confirm_button.add_theme_color_override("font_color", PAPER)
	confirm_button.pressed.connect(_submit)
	column.add_child(confirm_button)
	resized.connect(_layout)
	_layout()
	hide()

func _choices(parent: VBoxContainer, options: Array, buttons: Array[Button], is_genre: bool) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 3 if is_genre else 5
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	parent.add_child(grid)
	for option in options:
		var button := Button.new()
		button.text = option.name
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 60
		button.add_theme_font_size_override("font_size", 23)
		_style_choice(button)
		button.pressed.connect(func():
			if is_genre:
				genre_id = option.id
			else:
				topic_id = option.id
			_refresh())
		grid.add_child(button)
		buttons.append(button)
	return grid

func open(year: int, current_affinities: Array = []) -> void:
	selection_year = year
	affinities.clear()
	for value in current_affinities:
		affinities.append(int(value))
	genre_id = ""
	topic_id = ""
	title_input.text = ""
	year_label.text = "第 %d 年  /  新的作品" % year
	_refresh()
	show()
	title_input.grab_focus()

func _refresh() -> void:
	for index in genre_buttons.size():
		genre_buttons[index].set_pressed_no_signal(Catalog.GENRES[index].id == genre_id)
	for index in topic_buttons.size():
		topic_buttons[index].set_pressed_no_signal(Catalog.TOPICS[index].id == topic_id)
	var title := title_input.text.strip_edges()
	preview_label.text = "%s\n%s  ·  %s" % ["等待命名" if title.is_empty() else title,
		"未选类型" if genre_id.is_empty() else Catalog.display_name(Catalog.GENRES, genre_id),
		"未选题材" if topic_id.is_empty() else Catalog.display_name(Catalog.TOPICS, topic_id)]
	confirm_button.disabled = title.is_empty() or genre_id.is_empty() or topic_id.is_empty()
	hint_label.text = "请填写名字，并选好类型和题材。" if confirm_button.disabled else "准备好了，开始今年的开发吧。"
	_refresh_affinity()

## 立项好感预览：实时列出因偏好命中而加好感的成员；匹配、上限与真实增量都由模型规则决定。
func _refresh_affinity() -> void:
	var genre_name := Catalog.display_name(Catalog.GENRES, genre_id)
	var topic_name := Catalog.display_name(Catalog.TOPICS, topic_id)
	if genre_name.is_empty() and topic_name.is_empty():
		_set_affinity_text("立项好感：选好类型与题材后，这里显示谁会加好感。", MUTED)
		return
	var matched: Array[String] = []
	for index in Model.DEFINITIONS.size():
		var definition: Dictionary = Model.DEFINITIONS[index]
		var genre_gain := Model.preference_bonus(index, genre_id, "")
		var topic_gain := Model.preference_bonus(index, "", topic_id)
		var total := genre_gain + topic_gain
		if total <= 0:
			continue
		var current := current_affinity(index)
		var gain := clampi(current + total, 0, Model.AFFINITY_MAX) - current
		if gain <= 0:
			matched.append("%s 好感已满（%d/%d）" % [definition.name, current, Model.AFFINITY_MAX])
			continue
		var reasons: Array[String] = []
		if genre_gain > 0:
			reasons.append("类型 %s +%d" % [genre_name, genre_gain])
		if topic_gain > 0:
			reasons.append("题材 %s +%d" % [topic_name, topic_gain])
		if gain < total:
			reasons.append("受上限 %d 限制" % Model.AFFINITY_MAX)
		matched.append("%s +%d（%s）" % [definition.name, gain, "、".join(reasons)])
	if matched.is_empty():
		_set_affinity_text("立项好感：没有成员命中本次类型与题材。", MUTED)
		return
	_set_affinity_text("立项好感：" + "　".join(matched), TEAL)

## 选择页停留期间不能执行任何行动，所以好感度只在打开时读一次。
func current_affinity(index: int) -> int:
	return int(affinities[index]) if index < affinities.size() else 0

func _set_affinity_text(text: String, color: Color) -> void:
	affinity_label.text = text
	affinity_label.add_theme_color_override("font_color", color)

func _submit() -> void:
	if not visible or confirm_button.disabled:
		return
	project_requested.emit(title_input.text, genre_id, topic_id, selection_year)

func _layout() -> void:
	if margin == null:
		return
	var padding := int(clampf(size.x * 0.035, 20, 56))
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, padding)
	sidebar.visible = size.x >= 1080
	topic_grid.columns = 5 if size.x >= 1250 else 3

func _label(text: String, font_size: int, color: Color = INK) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _style_choice(button: Button) -> void:
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_stylebox_override("normal", _box(PAPER, Color("dcded1"), 12))
	button.add_theme_stylebox_override("hover", _box(Color("dce9df"), TEAL, 12))
	button.add_theme_stylebox_override("pressed", _box(TEAL, TEAL, 12))
	button.add_theme_stylebox_override("hover_pressed", _box(TEAL.lightened(0.08), TEAL, 12))
	button.add_theme_stylebox_override("disabled", _box(Color("dedfd6"), Color("dedfd6"), 12))
	button.add_theme_stylebox_override("focus", _box(Color.TRANSPARENT, GOLD, 0))
	for key in ["font_color", "font_hover_color", "font_focus_color"]:
		button.add_theme_color_override(key, INK)
	for key in ["font_pressed_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(key, PAPER)
	button.add_theme_color_override("font_disabled_color", MUTED)

func _box(fill: Color, border: Color, padding: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(2)
	box.set_corner_radius_all(10)
	box.set_content_margin_all(padding)
	return box
