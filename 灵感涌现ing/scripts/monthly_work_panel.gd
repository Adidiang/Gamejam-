extends Control
## 结算只在 Model 中发生；这里依次播放已经确定的岗位产出。

signal closed
signal member_presented(member_id: int)

const Model = preload("res://scripts/game_model.gd")
const NumberDisplay = preload("res://scripts/number_display.gd")
const CharacterTable = preload("res://scripts/character_table.gd")
const PAPER := Color("fffdf7")
const INK := Color("203e42")
const TEAL := Color("2a6965")
const GOLD := Color("efc56c")
const KEYS := ["g", "i", "p", "b", "repair"]
const CAPTIONS := ["游戏性", "创新性", "表现力", "Bug", "修复能力"]

var title_label: Label
var progress_label: Label
var summary_label: Label
var scroll: ScrollContainer
var member_list: VBoxContainer
var finish_button: Button
var cards: Array[PanelContainer] = []
var value_labels: Array[Label] = []
var report: Dictionary = {}
var active_members: Array = []
var current_member := -1
var playing := false
var animation: Tween

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dimmer := ColorRect.new()
	dimmer.color = Color(0.04, 0.10, 0.12, 0.88)
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dimmer)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.anchor_left = 0.08
	panel.anchor_top = 0.08
	panel.anchor_right = 0.92
	panel.anchor_bottom = 0.92
	panel.add_theme_stylebox_override("panel", _box(PAPER, PAPER, 32))
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	panel.add_child(column)
	title_label = _label("本月工作", 34)
	column.add_child(title_label)
	progress_label = _label("", 20)
	column.add_child(progress_label)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	member_list = VBoxContainer.new()
	member_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	member_list.add_theme_constant_override("separation", 16)
	scroll.add_child(member_list)
	for id in Model.DEFINITIONS.size():
		_build_card(id)
	summary_label = _label("", 20)
	summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(summary_label)
	finish_button = Button.new()
	finish_button.text = "确认"
	finish_button.custom_minimum_size = Vector2(220, 52)
	finish_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	finish_button.add_theme_stylebox_override("normal", _box(TEAL, TEAL, 10))
	finish_button.add_theme_stylebox_override("hover", _box(TEAL.lightened(0.1), GOLD, 10))
	finish_button.add_theme_color_override("font_color", PAPER)
	finish_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	finish_button.pressed.connect(close)
	column.add_child(finish_button)
	hide()

func _build_card(id: int) -> void:
	var definition: Dictionary = Model.DEFINITIONS[id]
	var card := PanelContainer.new()
	card.name = "Member" + str(id)
	card.custom_minimum_size.y = 210
	card.add_theme_stylebox_override("panel", _box(Color("eef2e9"), Color("dcded1"), 16))
	member_list.add_child(card)
	cards.append(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	card.add_child(row)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 170
	row.add_child(left)
	var portrait := TextureRect.new()
	portrait.custom_minimum_size = Vector2(170, 130)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture = CharacterTable.portrait_texture(definition.portrait)
	left.add_child(portrait)
	if portrait.texture == null:
		portrait.hide()
		var placeholder := _label(definition.id, 54)
		placeholder.custom_minimum_size.y = 130
		placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		left.add_child(placeholder)
	var name_label := _label(definition.id if definition.name.is_empty() else definition.name, 24)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(name_label)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 12)
	row.add_child(right)
	var role_label := _label("等待工作", 24)
	role_label.name = "Role"
	right.add_child(role_label)
	var values := _label("", 23)
	values.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	values.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(values)
	value_labels.append(values)

func open(work_report: Dictionary) -> void:
	if animation != null:
		animation.kill()
	report = work_report.duplicate(true)
	title_label.text = "本月工作 · 第%d年%d月" % [report.year, report.month]
	# 标题对应刚结算的月份，背后的主界面日历已经进入下月。
	summary_label.text = "岗位产出逐人展示\n本轮灵感 %+d · 当前灵感 %d" % [report.inspiration_delta, report.inspiration]
	current_member = -1
	playing = true
	finish_button.disabled = true
	scroll.scroll_vertical = 0
	active_members = Model.recruited_ids({"members": report.members})
	for id in cards.size():
		cards[id].visible = id in active_members
		cards[id].modulate = Color(1, 1, 1, 0.45)
		value_labels[id].text = "等待工作…"
		var role_label := cards[id].find_child("Role", true, false) as Label
		role_label.text = Model.ROLES[int(report.members[id].role)]
	if active_members.is_empty():
		playing = false
		hide()
		closed.emit()
		return
	show()
	finish_button.release_focus()
	_play_member.call_deferred(int(active_members[0]))

func _play_member(id: int) -> void:
	if not visible or not playing:
		return
	current_member = id
	progress_label.text = "正在展示 %d / %d · %s" % [active_members.find(id) + 1, active_members.size(), Model.DEFINITIONS[id].id]
	member_presented.emit(id)
	animation = create_tween()
	var target := mini(roundi(cards[id].position.y), maxi(0, roundi(member_list.size.y - scroll.size.y)))
	# 下一人的数字先展示完，再移动列表；滚动时上一人和当前人均为完整成果。
	animation.tween_method(_show_values.bind(id), 0.0, 1.0, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	animation.parallel().tween_property(cards[id], "modulate:a", 1.0, 0.4)
	animation.tween_property(scroll, "scroll_vertical", target, 0.4).set_trans(Tween.TRANS_SINE)
	animation.tween_interval(0.375)
	var next_index := active_members.find(id) + 1
	if next_index < active_members.size():
		animation.tween_callback(_play_member.bind(int(active_members[next_index])))
	else:
		animation.tween_callback(_finish)

func _show_values(fraction: float, id: int) -> void:
	var contribution: Dictionary = report.contributions[id]
	if Model.DEFINITIONS[id].id in report.get("sleeping_member_ids", []):
		var messages: Array[String] = ["睡着了…", "本月职责产出为0。"]
		for record in report.get("skill_events", []):
			if record.owner_id == Model.DEFINITIONS[id].id:
				## 只显示技能名；吐槽只在人物页的技能介绍里出现。
				messages.append(record.name)
				for outcome in record.get("outcomes", []):
					if outcome.kind == "arm_task_double": messages.append("当前作品的下一次任务产出翻倍。")
		value_labels[id].text = "\n".join(messages)
		return
	var lines: Array[String] = []
	for index in KEYS.size():
		if KEYS[index] == "b" and float(contribution.b) <= 0.0:
			continue
		lines.append("%s  %s" % [CAPTIONS[index], NumberDisplay.text(float(contribution[KEYS[index]]) * fraction, true)])
	lines.append("灵感 %+d" % int(contribution.get("inspiration", 0)))
	value_labels[id].text = "   ·   ".join(lines.slice(0, 3)) + "\n" + "   ·   ".join(lines.slice(3))

## 底部汇总只看本回合全员岗位产出的合计，不显示作品累计（累计值在主界面属性栏）。
func _month_summary_text() -> String:
	var totals := _month_totals()
	var lines: Array[String] = []
	for index in KEYS.size():
		if KEYS[index] == "b" and float(totals.b) <= 0.0:
			continue
		lines.append("%s %s" % [CAPTIONS[index], NumberDisplay.text(float(totals[KEYS[index]]), true)])
	var head := "本月总计：" + "   ·   ".join(lines.slice(0, 3))
	var tail := "   ·   ".join(lines.slice(3, 5))
	return "%s\n%s   ·   本轮灵感 %+d   ·   当前灵感 %d" % [head, tail, report.inspiration_delta, report.inspiration]

## 本回合全体成员的岗位产出逐项相加；修复能力沿用卡片的原始贡献口径。
func _month_totals() -> Dictionary:
	var totals: Dictionary = {}
	for key in KEYS:
		totals[key] = 0.0
	for contribution in report.contributions:
		for key in KEYS:
			totals[key] = float(totals[key]) + float(contribution.get(key, 0.0))
	return totals

func _finish() -> void:
	playing = false
	progress_label.text = "全员工作完成 · %d / %d" % [active_members.size(), active_members.size()]
	summary_label.text = _month_summary_text()
	var growth_messages: Array[String] = []
	for id in report.members.size():
		var before_growth: Array = report.get("members_before", report.members)[id].get("ability_growth", [0.0, 0.0, 0.0, 0.0])
		var after_growth: Array = report.members[id].get("ability_growth", [0.0, 0.0, 0.0, 0.0])
		var gain := float(after_growth[1]) - float(before_growth[1])
		if not is_zero_approx(gain): growth_messages.append("%s 脑洞白值 %s" % [report.members[id].id, NumberDisplay.text(gain, true)])
	if not growth_messages.is_empty(): summary_label.text += "\n" + " · ".join(growth_messages)
	finish_button.disabled = false
	finish_button.grab_focus()

func close() -> void:
	if playing or not visible:
		return
	hide()
	closed.emit()

func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", INK)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _box(fill: Color, border: Color, padding: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = padding
	style.content_margin_top = padding
	style.content_margin_right = padding
	style.content_margin_bottom = padding
	return style
