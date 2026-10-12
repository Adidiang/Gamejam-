extends Control
## 工作分配表里的角色圆形：显示人物编号、记录自身位置，并提供圆形命中判断。
## 只做这些事；拿起状态、落点判断和职责提交都由 DutyAssignmentPanel 处理。

const PAPER := Color("fffdf7")
const INK := Color("203e42")
const TEAL := Color("2a6965")
const GOLD := Color("efc56c")
const HIGHLIGHT := Color("fff2d4")
const DIAMETER := 72.0

var member_id := 0
var member_text := ""
var home_position := Vector2.ZERO

var _style: StyleBoxFlat
var _label: Label

func setup(id: int, text: String, hint: String) -> void:
	member_id = id
	member_text = text
	name = "MemberToken" + text
	custom_minimum_size = Vector2(DIAMETER, DIAMETER)
	size = Vector2(DIAMETER, DIAMETER)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip_text = hint
	var circle := Panel.new()
	circle.name = "Circle"
	circle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style = StyleBoxFlat.new()
	_style.bg_color = PAPER
	_style.border_color = TEAL
	_style.set_border_width_all(2)
	_style.set_corner_radius_all(int(DIAMETER * 0.5))
	circle.add_theme_stylebox_override("panel", _style)
	add_child(circle)
	_label = Label.new()
	_label.name = "Caption"
	_label.text = text
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 24)
	_label.add_theme_color_override("font_color", INK)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_label)

func covers(viewport_point: Vector2) -> bool:
	## 圆形命中：只有圆形内部才算命中，方框四角不算；参数与 get_global_rect() 同为视口坐标。
	var rect := get_global_rect()
	return viewport_point.distance_to(rect.get_center()) <= rect.size.x * 0.5

func set_highlight(active: bool) -> void:
	_style.border_color = GOLD if active else TEAL
	_style.bg_color = HIGHLIGHT if active else PAPER
