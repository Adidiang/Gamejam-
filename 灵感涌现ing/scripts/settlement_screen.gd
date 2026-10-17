extends Control
## 两页终局：年度作品回顾与三年总分排行榜。只展示快照，不改写游戏状态。
signal return_requested

const Model = preload("res://scripts/game_model.gd")
const Catalog = preload("res://scripts/game_catalog.gd")
const Ranking = preload("res://scripts/settlement_ranking.gd")
const Numbers = preload("res://scripts/number_display.gd")
const PAPER := Color("fffdf7")
const INK := Color("203e42")
const TEAL := Color("2a6965")
const GOLD := Color("efc56c")
const MUTED := Color("b9ccc5")

var summary: Dictionary = {}
var rankings: Array = []
var page_index := 0
var margin: MarginContainer
var title_label: Label
var total_label: Label
var subtitle_label: Label
var page_label: Label
var scroll: ScrollContainer
var content: VBoxContainer
var tabs: Array[Button] = []
var previous_button: Button
var next_button: Button
var return_button: Button
var project_cards: Array[Control] = []
var ranking_rows: Array[Control] = []
var player_row: Control
var config_missing := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var background := ColorRect.new()
	background.color = Color("12272b")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var heading := HBoxContainer.new()
	column.add_child(heading)
	title_label = _label("三年 · 灵感成集", 34, PAPER)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title_label)
	total_label = _label("", 28, GOLD)
	heading.add_child(total_label)
	subtitle_label = _label("", 18, MUTED)
	column.add_child(subtitle_label)
	var navigation := HBoxContainer.new()
	navigation.add_theme_constant_override("separation", 12)
	column.add_child(navigation)
	for index in 2:
		var tab := _button(["01  作品回顾", "02  排行榜"][index])
		tab.pressed.connect(_show_page.bind(index))
		navigation.add_child(tab)
		tabs.append(tab)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	column.add_child(bottom)
	page_label = _label("", 18, MUTED)
	page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom.add_child(page_label)
	previous_button = _button("上一页")
	previous_button.pressed.connect(_show_page.bind(0))
	bottom.add_child(previous_button)
	next_button = _button("查看排行榜 →")
	next_button.pressed.connect(_show_page.bind(1))
	bottom.add_child(next_button)
	return_button = _button("返回开始界面")
	return_button.pressed.connect(func():
		if visible: return_requested.emit())
	bottom.add_child(return_button)
	resized.connect(_layout)
	_layout()
	hide()

func open(state: Dictionary) -> void:
	var result := Model.settlement_summary(state)
	if result.is_empty(): return
	summary = result
	var staff := Ranking.load_entries()
	config_missing = staff.is_empty()
	rankings = Ranking.build(float(summary.total), staff)
	total_label.text = "三年总分  " + Numbers.text(float(summary.total))
	show()
	_show_page(0)

func _show_page(index: int) -> void:
	if summary.is_empty() or index not in [0, 1]: return
	page_index = index
	content.add_theme_constant_override("separation", 12 if index == 0 else 8)
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	project_cards.clear()
	ranking_rows.clear()
	player_row = null
	if index == 0:
		subtitle_label.text = "每年得分 = 游戏性 + 创新性 + 表现力 − 10 × Bug"
		for project in summary.projects: _add_project(project)
	else:
		var player_rank := 1
		for row in rankings:
			if row.is_player: player_rank = int(row.rank)
		subtitle_label.text = "你 · 第 %d 名    /    按三年总分从高到低排列，同分并列" % player_rank
		if config_missing: content.add_child(_label("制作组成绩暂不可用，当前仅显示你的成绩。", 18, GOLD))
		var header := HBoxContainer.new()
		header.add_child(_fixed_label("名次", 80, MUTED))
		var name_header := _label("名字", 18, MUTED)
		name_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(name_header)
		header.add_child(_fixed_label("三年总分", 180, MUTED, HORIZONTAL_ALIGNMENT_RIGHT))
		content.add_child(header)
		for row in rankings: _add_ranking(row)
	page_label.text = "第 %d / 2 页" % (index + 1)
	previous_button.visible = index == 1
	next_button.visible = index == 0
	return_button.visible = index == 1
	for tab_index in tabs.size():
		tabs[tab_index].disabled = tab_index == index
	scroll.scroll_vertical = 0
	(next_button if index == 0 else previous_button).grab_focus()

func _add_project(entry: Dictionary) -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _box(PAPER, PAPER, 16))
	content.add_child(card)
	project_cards.append(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	card.add_child(column)
	var profile: Dictionary = entry.project
	var title := _label("第 %d 年  ·  「%s」" % [entry.year, profile.title], 24)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(title)
	column.add_child(_label("%s / %s" % [Catalog.display_name(Catalog.GENRES, profile.genre_id), Catalog.display_name(Catalog.TOPICS, profile.topic_id)], 18, TEAL))
	var work: Dictionary = entry.work
	var details := _label("游戏性 %s    创新性 %s    表现力 %s    Bug %s" % [Numbers.text(work.g), Numbers.text(work.i), Numbers.text(work.p), Numbers.text(work.b)], 20)
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(details)
	column.add_child(_label("项目得分  " + Numbers.text(float(entry.score)), 24, TEAL))

func _add_ranking(entry: Dictionary) -> void:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _box(GOLD if entry.is_player else PAPER, GOLD if entry.is_player else PAPER, 8))
	content.add_child(row)
	ranking_rows.append(row)
	if entry.is_player: player_row = row
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	row.add_child(line)
	line.add_child(_fixed_label("%02d" % int(entry.rank), 64, TEAL))
	var name_label := _label(entry.name, 20)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(name_label)
	line.add_child(_fixed_label(Numbers.text(float(entry.score)), 164, INK, HORIZONTAL_ALIGNMENT_RIGHT))

func _layout() -> void:
	if margin == null: return
	var padding := int(clampf(size.x * 0.04, 20, 56))
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, padding)

func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(200, 48)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 20)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, _box(TEAL if state != "disabled" else GOLD, GOLD, 8))
		button.add_theme_color_override("font_" + ("color" if state == "normal" else state + "_color"), INK if state == "disabled" else PAPER)
	return button

func _label(text: String, font_size: int, color: Color = INK) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _fixed_label(text: String, width: float, color: Color, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := _label(text, 20, color)
	label.custom_minimum_size.x = width
	label.horizontal_alignment = alignment
	return label

func _box(fill: Color, border: Color, padding: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(10)
	box.set_content_margin_all(padding)
	return box
