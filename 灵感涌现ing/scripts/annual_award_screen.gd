extends Control
## 年末评奖界面：先展示 BUG灾难 判定，再按顺序弹出本年所得奖项，最后结算灵感奖励。
## 判定概率、分数与奖项都在 ClubGame 年末结算时就已确定并写入状态；
## 这里只按顺序展示，不重新抽取、不改写作品数据，重复打开也不会再次发奖。

signal closed

const Model = preload("res://scripts/game_model.gd")
const Catalog = preload("res://scripts/game_catalog.gd")
const PAPER := Color("fffdf7")
const INK := Color("203e42")
const TEAL := Color("2a6965")
const GOLD := Color("c99a2e")
const MUTED := Color("72817a")
const WARN := Color("a8442c")

var annual: Dictionary = {}
var steps: Array = []
var step_index := -1
var margin: MarginContainer
var title_label: Label
var subtitle_label: Label
var card: PanelContainer
var kind_label: Label
var step_title: Label
var step_body: Label
var scroll: ScrollContainer
var progress_label: Label
var continue_button: Button
var reveal: Tween

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
	title_label = _label("年度评奖", 34, PAPER)
	column.add_child(title_label)
	subtitle_label = _label("", 20, Color("c1d0c5"))
	column.add_child(subtitle_label)
	card = PanelContainer.new()
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _box(PAPER, PAPER, 32))
	column.add_child(card)
	var card_column := VBoxContainer.new()
	card_column.add_theme_constant_override("separation", 14)
	card.add_child(card_column)
	kind_label = _label("", 20, GOLD)
	card_column.add_child(kind_label)
	step_title = _label("", 34)
	step_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_column.add_child(step_title)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card_column.add_child(scroll)
	step_body = _label("", 23)
	step_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	step_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(step_body)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 20)
	column.add_child(bottom)
	progress_label = _label("", 20, Color("c1d0c5"))
	progress_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom.add_child(progress_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(spacer)
	continue_button = Button.new()
	continue_button.text = "继续"
	continue_button.custom_minimum_size = Vector2(220, 56)
	continue_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	continue_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	continue_button.add_theme_font_size_override("font_size", 24)
	continue_button.add_theme_stylebox_override("normal", _box(TEAL, TEAL, 12))
	continue_button.add_theme_stylebox_override("hover", _box(TEAL.lightened(0.1), GOLD, 12))
	continue_button.add_theme_stylebox_override("focus", _box(TEAL.lightened(0.1), GOLD, 12))
	continue_button.add_theme_color_override("font_color", PAPER)
	continue_button.add_theme_color_override("font_hover_color", PAPER)
	continue_button.add_theme_color_override("font_focus_color", PAPER)
	continue_button.pressed.connect(_advance)
	bottom.add_child(continue_button)
	resized.connect(_layout)
	_layout()
	hide()

func open(annual_result: Dictionary) -> void:
	annual = annual_result.duplicate(true)
	steps = _build_steps()
	step_index = -1
	title_label.text = "年度评奖 · 第 %d 年" % int(annual.get("year", 1))
	subtitle_label.text = _subtitle()
	show()
	continue_button.release_focus()
	_advance()

## 页面只包含 BUG灾难 提示（命中时）与逐个弹出的所获奖项；没有奖项时只有一页未获奖。
func _build_steps() -> Array:
	var awards: Array = annual.get("awards", [])
	var result: Array = []
	if bool(annual.get("bug_disaster", false)):
		result.append({"kind": "突发评价", "title": "「%s」" % Model.BUG_DISASTER.name, "body": _disaster_body(), "tone": WARN})
	if awards.is_empty():
		result.append({"kind": "评选结果", "title": "本年度未获奖", "body": "", "tone": MUTED})
	else:
		for award in awards:
			result.append({"kind": "获奖", "title": str(award.name), "body": "灵感 +%d" % int(award.get("reward", 0)), "tone": GOLD})
	return result

func _advance() -> void:
	if not visible:
		return
	step_index += 1
	if step_index >= steps.size():
		close()
		return
	_display(steps[step_index])

func _display(step: Dictionary) -> void:
	var tone: Color = step.tone
	kind_label.text = step.kind
	kind_label.add_theme_color_override("font_color", tone)
	step_title.text = step.title
	step_title.add_theme_color_override("font_color", tone)
	step_body.text = step.body
	progress_label.text = "第 %d / %d 步" % [step_index + 1, steps.size()]
	continue_button.text = "进入下一年" if step_index + 1 >= steps.size() else "继续"
	scroll.scroll_vertical = 0
	continue_button.grab_focus()
	if reveal != null:
		reveal.kill()
	card.modulate.a = 0.0
	reveal = create_tween()
	reveal.tween_property(card, "modulate:a", 1.0, 0.25)

func close() -> void:
	if not visible:
		return
	if reveal != null:
		reveal.kill()
	hide()
	closed.emit()

func _subtitle() -> String:
	var project: Dictionary = annual.get("project", {})
	var title: String = str(project.get("title", ""))
	if title.is_empty():
		return "本年度作品"
	var genre := Catalog.display_name(Catalog.GENRES, str(project.get("genre_id", "")))
	var topic := Catalog.display_name(Catalog.TOPICS, str(project.get("topic_id", "")))
	return "「%s」 · %s / %s" % [title, genre if not genre.is_empty() else "未选类型", topic if not topic.is_empty() else "未选题材"]

func _disaster_body() -> String:
	return "%s\n\n%s" % [Model.BUG_DISASTER.message, Model.BUG_DISASTER.detail]

func _layout() -> void:
	if margin == null:
		return
	var padding := int(clampf(size.x * 0.05, 20, 72))
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, padding)

func _label(text: String, font_size: int, color: Color = INK) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _box(fill: Color, border: Color, padding: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(2)
	box.set_corner_radius_all(14)
	box.set_content_margin_all(padding)
	return box
