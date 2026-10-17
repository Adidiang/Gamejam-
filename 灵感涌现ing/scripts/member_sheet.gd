extends PanelContainer
## 人物资料、白值与增幅后两列属性、三个技能位；学习按钮仅发送请求，由游戏模型扣费。
signal learn_requested(member_id: int, slot_index: int)
signal task_requested
signal invite_requested

const Model = preload("res://scripts/game_model.gd")
const NumberDisplay = preload("res://scripts/number_display.gd")
const CharacterTable = preload("res://scripts/character_table.gd")
const SkillTable = preload("res://scripts/skills/skill_table.gd")
const SkillRunner = preload("res://scripts/skills/skill_runner.gd")
const STAT_NAMES := ["编程", "脑洞", "美术", "音乐"]
const INK := Color("203e42")
const MUTED := Color("72817a")
const TEAL := Color("2a6965")
## 增幅后的能力用绿色显示，与白值区分。
const GROWTH := Color("2e7d32")

var title_label: Label
var preference_label: Label
var stat_base_values: Array[Label] = []
var stat_final_values: Array[Label] = []
var affinity_label: Label
var affinity_bar: ProgressBar
var skill_statuses: Array[Label] = []
var skill_names: Array[Label] = []
var skill_descriptions: Array[Label] = []
var skill_quips: Array[Label] = []
var skill_buttons: Array[Button] = []
var inspiration_label: Label
var selected_member := 0
var modifiers_label: Label
var portrait_view: TextureRect
var portrait_placeholder: Label
var task_button: Button
var invite_button: Button
var task_notice: Control
var task_notice_box: PanelContainer
var task_notice_label: Label
var task_notice_timer: Timer

func _ready() -> void:
	add_theme_stylebox_override("panel", _style(Color("fffdf7"), Color("dcded1")))
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 24)
	margin.add_child(body)
	var portrait_panel := Panel.new()
	portrait_panel.custom_minimum_size.x = 220
	portrait_panel.add_theme_stylebox_override("panel", _style(Color("f0f2eb"), Color("dcded1")))
	body.add_child(portrait_panel)
	portrait_view = TextureRect.new()
	portrait_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portrait_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_panel.add_child(portrait_view)
	portrait_placeholder = _label("立绘待添加", 20, MUTED)
	portrait_placeholder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portrait_placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	portrait_placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	portrait_panel.add_child(portrait_placeholder)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	body.add_child(column)
	title_label = _label("", 30)
	column.add_child(title_label)
	preference_label = _label("", 20, MUTED)
	column.add_child(preference_label)
	column.add_child(_label("个人能力", 22))
	var stats_panel := PanelContainer.new()
	stats_panel.add_theme_stylebox_override("panel", _style(Color("f0f2eb"), Color("dcded1")))
	stats_panel.tooltip_text = "白值：人物表基础属性，直接增加的数值也计入白值。\n增幅后：白值 × (1 + 百分比增幅合计)，好感每点提供 1% 增幅。"
	column.add_child(stats_panel)
	var stats_margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		stats_margin.add_theme_constant_override("margin_" + side, 12)
	stats_panel.add_child(stats_margin)
	var stats_grid := GridContainer.new()
	stats_grid.columns = 3
	stats_grid.add_theme_constant_override("h_separation", 24)
	stats_grid.add_theme_constant_override("v_separation", 4)
	stats_margin.add_child(stats_grid)
	stats_grid.add_child(_label("属性", 14, MUTED))
	stats_grid.add_child(_label("白值", 14, MUTED))
	stats_grid.add_child(_label("增幅后", 14, MUTED))
	for stat_name in STAT_NAMES:
		var name_label := _label(stat_name, 18, MUTED)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stats_grid.add_child(name_label)
		var base_value := _label("", 24)
		base_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stats_grid.add_child(base_value)
		var final_value := _label("", 24, GROWTH)
		final_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stats_grid.add_child(final_value)
		stat_base_values.append(base_value)
		stat_final_values.append(final_value)
	affinity_label = _label("好感度    0 / %d" % CharacterTable.AFFINITY_MAX, 22)
	column.add_child(affinity_label)
	affinity_bar = ProgressBar.new()
	affinity_bar.min_value = 0
	affinity_bar.max_value = CharacterTable.AFFINITY_MAX
	affinity_bar.value = 0
	affinity_bar.show_percentage = false
	affinity_bar.custom_minimum_size.y = 22
	affinity_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	affinity_bar.add_theme_stylebox_override("background", _style(Color("e6e9dd")))
	affinity_bar.add_theme_stylebox_override("fill", _style(TEAL))
	column.add_child(affinity_bar)
	inspiration_label = _label("技能    灵感 0", 22)
	column.add_child(inspiration_label)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 160
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	column.add_child(scroll)
	var skills_row := GridContainer.new()
	skills_row.columns = 2
	skills_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skills_row.add_theme_constant_override("h_separation", 12)
	skills_row.add_theme_constant_override("v_separation", 12)
	skills_row.add_theme_constant_override("separation", 16)
	scroll.add_child(skills_row)
	for index in Model.SKILL_SLOTS:
		var card := _card(skills_row, 132)
		var skill_name := _label("技能 %d" % (index + 1), 22)
		skill_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(skill_name)
		skill_names.append(skill_name)
		var empty_content := _label("", 16, MUTED)
		empty_content.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_content.max_lines_visible = 3
		empty_content.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		empty_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
		card.add_child(empty_content)
		skill_descriptions.append(empty_content)
		var quip := _label("", 16, MUTED)
		quip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		quip.max_lines_visible = 2
		quip.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		card.add_child(quip)
		skill_quips.append(quip)
		var status := _label("", 16, MUTED)
		status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(status)
		skill_statuses.append(status)
		var button := Button.new()
		button.custom_minimum_size.y = 34
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.add_theme_font_size_override("font_size", 18)
		button.add_theme_stylebox_override("normal", _style(TEAL))
		button.add_theme_stylebox_override("hover", _style(TEAL.lightened(0.1)))
		button.add_theme_stylebox_override("disabled", _style(Color("dcded1")))
		button.add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, Color("efc56c")))
		button.add_theme_color_override("font_color", Color("fffdf7"))
		button.add_theme_color_override("font_disabled_color", INK)
		button.add_theme_color_override("font_hover_color", Color("fffdf7"))
		button.add_theme_color_override("font_pressed_color", Color("fffdf7"))
		button.pressed.connect(_request_learning.bind(index))
		card.add_child(button)
		skill_buttons.append(button)
	modifiers_label = _label("其他修正：未填写", 18, MUTED)
	column.add_child(modifiers_label)
	task_button = Button.new()
	task_button.text = "分配任务"
	task_button.custom_minimum_size.y = 48
	task_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	task_button.add_theme_stylebox_override("normal", _style(TEAL))
	task_button.add_theme_stylebox_override("hover", _style(TEAL.lightened(0.1)))
	task_button.add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, Color("efc56c")))
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		task_button.add_theme_color_override(key, Color("fffdf7"))
	task_button.pressed.connect(func(): task_requested.emit())
	var actions_row := HBoxContainer.new()
	actions_row.add_theme_constant_override("separation", 16)
	column.add_child(actions_row)
	task_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions_row.add_child(task_button)
	invite_button = Button.new()
	invite_button.text = "邀约"
	invite_button.custom_minimum_size.y = 48
	invite_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	invite_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	invite_button.add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, Color("efc56c")))
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		invite_button.add_theme_color_override(key, Color("fffdf7"))
	invite_button.pressed.connect(func(): invite_requested.emit())
	actions_row.add_child(invite_button)
	_build_action_notice()
	visibility_changed.connect(func():
		if not is_visible_in_tree():
			_hide_action_notice())

func display_member(state: Dictionary, member_id: int, character_id: String) -> void:
	selected_member = member_id
	_hide_action_notice()
	var exhausted := Model.action_steps(state) <= 0
	# 耗尽时只变灰，保留点击事件以展示“本回合已行动”。
	for action_button in [task_button, invite_button]:
		exhausted = Model.action_steps(state) <= 0 and not (action_button == task_button and Model.Characters.free_task(state, Model.DEFINITIONS, member_id))
		action_button.disabled = false
		action_button.add_theme_stylebox_override("normal", _style(Color("a4aaa4") if exhausted else TEAL))
		action_button.add_theme_stylebox_override("hover", _style(Color("a4aaa4") if exhausted else TEAL.lightened(0.1)))
		action_button.add_theme_stylebox_override("pressed", _style(Color("a4aaa4") if exhausted else TEAL.darkened(0.1)))
		action_button.tooltip_text = "本回合已行动" if exhausted else action_button.text
	var definition: Dictionary = Model.DEFINITIONS[member_id]
	title_label.text = "%s · %s" % [character_id, definition.name]
	preference_label.text = "喜欢的类型：%s    /    喜欢的题材：%s" % [_filled(definition.genre), _filled(definition.topic)]
	portrait_view.texture = CharacterTable.portrait_texture(definition.portrait)
	portrait_placeholder.visible = portrait_view.texture == null
	modifiers_label.text = "其他修正：" + _filled(definition.other_modifiers)
	if definition.id == "j" and Model.Characters.has_skill(state, Model.DEFINITIONS, member_id, 2): modifiers_label.text = "其他修正：永久 BUG 产出 +100%"
	if definition.id == "e": modifiers_label.text += "\n两个维度：绿值已交换程序与脑洞，成长仍计入原属性。"
	var base_values := Model.base_ability(member_id, state)
	var final_values := Model.ability(state, member_id)
	for index in stat_base_values.size():
		stat_base_values[index].text = NumberDisplay.text(float(base_values[index]))
		stat_final_values[index].text = NumberDisplay.text(float(final_values[index]))
	var affinity := clampi(int(state.members[member_id].affinity), 0, CharacterTable.AFFINITY_MAX)
	affinity_bar.value = affinity
	affinity_label.text = "好感度    %d / %d" % [affinity, CharacterTable.AFFINITY_MAX]
	inspiration_label.text = "技能    灵感 %d" % int(state.inspiration)
	for index in skill_statuses.size():
		var slot: Dictionary = definition.skills[index]
		var skill = SkillTable.skills[slot.skill_id]
		skill_names[index].text = "技能 %d%s" % [index + 1, " · " + skill.display_name if not skill.display_name.is_empty() else ""]
		skill_descriptions[index].text = skill.description
		skill_descriptions[index].visible = not skill.description.is_empty()
		skill_descriptions[index].tooltip_text = skill.description
		skill_quips[index].text = skill.quip
		skill_quips[index].visible = not skill.quip.is_empty()
		skill_quips[index].tooltip_text = skill.quip
		# 仅填写名字的技能先展示占位，避免显示“自动生效”或学习费用。
		if not skill.display_name.is_empty() and skill.description.is_empty() and skill.quip.is_empty() and skill.triggers.is_empty():
			skill_statuses[index].text = "%d 好感度解锁 · 机制待实现" % int(slot.unlock_affinity)
			skill_statuses[index].add_theme_color_override("font_color", MUTED)
			skill_buttons[index].hide()
			continue
		var status := SkillRunner.status(state, member_id, slot)
		skill_statuses[index].text = status.text
		skill_statuses[index].add_theme_color_override("font_color", TEAL if status.active else MUTED)
		skill_buttons[index].visible = skill.acquisition == "inspiration"
		skill_buttons[index].text = "已习得" if status.active else ("习得 · 获得 %d 灵感" % -skill.inspiration_cost if skill.inspiration_cost < 0 else "习得 · %d 灵感" % skill.inspiration_cost)
		skill_buttons[index].disabled = not status.can_learn
		skill_buttons[index].tooltip_text = "习得后立即获得50灵感，同时永久增加BUG产出；只能领取一次。" if skill.inspiration_cost < 0 else "解锁后支付灵感习得，不消耗月份。"

func _request_learning(slot_index: int) -> void:
	learn_requested.emit(selected_member, slot_index)

func show_action_notice() -> void:
	task_notice.show()
	task_notice_timer.start(2.0)

func _build_action_notice() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	task_notice = Control.new()
	task_notice.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	task_notice.mouse_filter = Control.MOUSE_FILTER_STOP
	task_notice.gui_input.connect(_notice_input)
	layer.add_child(task_notice)
	task_notice_box = PanelContainer.new()
	task_notice_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	task_notice_box.offset_left = -170
	task_notice_box.offset_right = 170
	task_notice_box.offset_top = -44
	task_notice_box.offset_bottom = 44
	var box := _style(Color("fffdf7"), TEAL)
	box.set_border_width_all(2)
	box.set_corner_radius_all(8)
	box.set_content_margin_all(20)
	task_notice_box.add_theme_stylebox_override("panel", box)
	task_notice_box.gui_input.connect(_notice_input)
	task_notice.add_child(task_notice_box)
	task_notice_label = _label("本回合已行动", 24)
	task_notice_label.add_theme_font_override("font", get_theme_default_font())
	task_notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	task_notice_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	task_notice_box.add_child(task_notice_label)
	task_notice_timer = Timer.new()
	task_notice_timer.one_shot = true
	task_notice_timer.timeout.connect(_hide_action_notice)
	add_child(task_notice_timer)
	task_notice.hide()

func _notice_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		task_notice.accept_event()
		_hide_action_notice()

func _hide_action_notice() -> void:
	task_notice_timer.stop()
	task_notice.hide()

func _filled(text: String) -> String:
	return text if not text.is_empty() else "未填写"

func _label(text: String, font_size: int, color: Color = INK) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _card(row: Container, height: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size.y = height
	panel.add_theme_stylebox_override("panel", _style(Color("f0f2eb"), Color("dcded1")))
	row.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	return column

func _style(fill: Color, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1 if border.a > 0 else 0)
	return style
