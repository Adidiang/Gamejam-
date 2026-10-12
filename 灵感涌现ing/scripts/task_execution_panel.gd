extends Control
## 播放已提交的结果；进度完成之前右侧保持空白。
signal closed
const Model = preload("res://scripts/game_model.gd")
const Characters = preload("res://scripts/character_table.gd")
var progress: ProgressBar
var results_label: Label
var portrait: TextureRect
var placeholder: Label
var title_label: Label
var finish_button: Button
var playing := false
var report: Dictionary = {}
var animation: Tween

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var background := ColorRect.new()
	background.color = Color("fffdf7")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 24)
	margin.add_child(column)
	title_label = _label("", 30)
	column.add_child(title_label)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 32)
	column.add_child(row)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 0.8
	row.add_child(left)
	portrait = TextureRect.new()
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(portrait)
	placeholder = _label("立绘待添加", 28)
	placeholder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	left.add_child(placeholder)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(scroll)
	results_label = _label("", 22)
	results_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	results_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(results_label)
	progress = ProgressBar.new()
	progress.max_value = 100
	progress.show_percentage = false
	progress.custom_minimum_size.y = 26
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("2a6965")
	progress.add_theme_stylebox_override("fill", fill)
	column.add_child(progress)
	finish_button = Button.new()
	finish_button.text = "确认"
	finish_button.custom_minimum_size = Vector2(180, 52)
	finish_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	finish_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var button_style := StyleBoxFlat.new()
	button_style.bg_color = Color("2a6965")
	finish_button.add_theme_stylebox_override("normal", button_style)
	var hover_style := button_style.duplicate() as StyleBoxFlat
	hover_style.bg_color = Color("357e79")
	finish_button.add_theme_stylebox_override("hover", hover_style)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		finish_button.add_theme_color_override(key, Color("fffdf7"))
	finish_button.pressed.connect(close)
	column.add_child(finish_button)
	hide()

func open(task_report: Dictionary) -> void:
	if animation != null:
		animation.kill()
	report = task_report.duplicate(true)
	playing = true
	results_label.text = ""
	progress.value = 0
	finish_button.disabled = true
	title_label.text = "%s · 第%d年%d月" % [report.name, report.year, report.month]
	var definition: Dictionary = Model.DEFINITIONS[int(report.member)]
	portrait.texture = Characters.portrait_texture(definition.portrait)
	portrait.visible = portrait.texture != null
	placeholder.visible = portrait.texture == null
	placeholder.text = "%s\n立绘待添加" % definition.id
	show()
	animation = create_tween()
	animation.tween_property(progress, "value", 100.0, 1.0)
	animation.tween_callback(_show_results)

func _show_results() -> void:
	playing = false
	var invited: bool = report.get("kind", "task") == "invite"
	var lines: Array[String] = ["邀约结果" if invited else "任务产出"]
	if not invited:
		lines.append("表现力 %+.1f\n创新性 %+.1f" % [report.task_delta.p, report.task_delta.i])
	var keys := ["g", "i", "p", "v", "m", "b"] if invited else ["g", "v", "m", "b"]
	var names := ["游戏性", "创新性", "表现力", "视觉", "听觉", "Bug"] if invited else ["游戏性", "视觉", "听觉", "Bug"]
	for index in keys.size():
		if not is_zero_approx(float(report.task_delta[keys[index]])):
			lines.append("%s %+.1f" % [names[index], report.task_delta[keys[index]]])
	if int(report.inspiration_delta) != 0:
		lines.append("灵感 %+d" % report.inspiration_delta)
	for id in report.members.size():
		var gain := int(report.members[id].affinity) - int(report.members_before[id].affinity)
		if gain != 0 or (invited and id == int(report.member)):
			lines.append("%s 好感度 %+d" % [report.members[id].id, gain])
	for record in report.skill_events:
		lines.append("%s · %s%s" % [record.owner_id, record.name, " · " + record.quip if not record.quip.is_empty() else ""])
	results_label.text = "\n".join(lines)
	finish_button.disabled = false
	finish_button.grab_focus()

func close() -> void:
	if playing:
		return
	hide()
	closed.emit()

func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("203e42"))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
