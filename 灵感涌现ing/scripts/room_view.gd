extends Control
## 活动室代码绘制；人物立绘仅从新人物表读取。
signal member_clicked(id: int)
var portrait := false
var member_id := 0
var selected := 0
var month := 1
var roles: Array = [0, 0, 1, 2]
var ticks := 0.0
var animate := true
const COLORS := [Color("c8d5cd"), Color("c8d5cd"), Color("c8d5cd"), Color("c8d5cd")]
const INK := Color("264549")
const Model = preload("res://scripts/game_model.gd")
const CharacterTable = preload("res://scripts/character_table.gd")
var portraits: Array[Texture2D] = []

func _ready() -> void:
	for definition in Model.DEFINITIONS:
		portraits.append(CharacterTable.portrait_texture(definition.portrait))
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE if portrait else Control.MOUSE_FILTER_STOP

func _process(delta: float) -> void:
	if animate:
		ticks += delta
		queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var point: Vector2 = event.position / size * Vector2(890, 280)
		for id in range(4):
			if Rect2(75 + id * 210, 125, 150, 140).has_point(point):
				member_clicked.emit(id)
		accept_event()

func box(rect: Rect2, color: Color, radius: float = 8.0) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = int(radius)
	style.corner_radius_top_right = int(radius)
	style.corner_radius_bottom_left = int(radius)
	style.corner_radius_bottom_right = int(radius)
	draw_style_box(style, rect)

func _draw() -> void:
	if size.x <= 0 or size.y <= 0:
		return
	if portrait:
		draw_set_transform(Vector2.ZERO, 0, size / Vector2(100, 100))
		box(Rect2(0, 0, 100, 100), COLORS[member_id].lightened(0.6), 18)
		person(Vector2(50, 51), member_id, 1.35)
		return
	draw_set_transform(Vector2.ZERO, 0, size / Vector2(890, 280))
	box(Rect2(0, 0, 890, 280), Color("e1d7bd"), 18)
	draw_rect(Rect2(0, 177, 890, 103), Color("c4b69b"))
	draw_line(Vector2(0, 177), Vector2(890, 177), Color("9eac9e"), 5)
	for x in range(-100, 1000, 96):
		draw_line(Vector2(x, 177), Vector2(x - 90, 280), Color("b3a38b"), 1)
	for y in [210, 249]:
		draw_line(Vector2(0, y), Vector2(890, y), Color("b3a38b"), 1)
	# A sunlit window and a changing sky as the release approaches.
	box(Rect2(42, 18, 224, 137), INK, 9)
	var sky := Color("acc9c5").lerp(Color("dcab8d"), float(month - 1) / 18.0)
	draw_rect(Rect2(50, 26, 208, 121), sky)
	draw_circle(Vector2(209, 60), 23, Color("fff0b5"))
	for x in range(53, 257, 31):
		var h := 18.0 + fmod(float(x * 7), 43.0)
		draw_rect(Rect2(x, 147 - h, 24, h), Color("7e9f9b"))
	draw_line(Vector2(153, 22), Vector2(153, 153), INK, 6)
	draw_line(Vector2(46, 96), Vector2(262, 96), INK, 5)
	draw_colored_polygon(PackedVector2Array([Vector2(51, 148), Vector2(262, 148), Vector2(399, 280), Vector2(142, 280)]), Color(1.0, 0.92, 0.65, 0.16))
	# Pinboard, notes, sketches.
	box(Rect2(319, 27, 235, 107), Color("8a6c52"), 5)
	box(Rect2(326, 34, 221, 93), Color("b29472"), 2)
	for i in range(5):
		var xx := 338.0 + i * 40
		var yy := 46.0 + (i % 2) * 19
		draw_rect(Rect2(xx, yy, 30, 41), [Color("f9efc2"), Color("cadacc"), Color("f0c6b8")][i % 3])
		draw_circle(Vector2(xx + 15, yy + 3), 2.5, INK)
		for j in range(3):
			draw_line(Vector2(xx + 5, yy + 15 + j * 7), Vector2(xx + 22, yy + 15 + j * 7), Color("acaa97"), 1)
	# Shelf and a tiny trophy.
	box(Rect2(603, 39, 176, 12), INK, 3)
	for i in range(7):
		draw_rect(Rect2(615 + i * 13, 11 + (i % 3) * 3, 10, 28 - (i % 3) * 3), COLORS[i % 4])
	draw_rect(Rect2(733, 26, 18, 9), Color("dfb557"))
	draw_circle(Vector2(742, 18), 12, Color("edc877"))
	draw_rect(Rect2(739, 23, 6, 17), Color("edc877"))
	# Wall clock.
	draw_circle(Vector2(821, 54), 24, INK)
	draw_circle(Vector2(821, 54), 20, Color("f9f3e2"))
	draw_line(Vector2(821, 54), Vector2(821, 41), INK, 2)
	draw_line(Vector2(821, 54), Vector2(832, 58), INK, 2)
	# Shared desks and four original club members.
	for id in range(4):
		var xx := 145.0 + id * 210
		var bob := sin(ticks * 2.0 + id) * 1.5 if selected == id else 0.0
		box(Rect2(xx - 36, 176, 71, 83), INK.lightened(0.13), 18)
		person(Vector2(xx, 162 + bob), id, 0.9)
		box(Rect2(xx - 77, 213, 157, 15), Color("876c52"), 5)
		box(Rect2(xx - 81, 204, 165, 13), Color("f3e1b5"), 5)
		draw_rect(Rect2(xx - 68, 225, 8, 51), Color("766b58"))
		draw_rect(Rect2(xx + 60, 225, 8, 51), Color("766b58"))
		box(Rect2(xx - 35, 177, 68, 39), INK, 4)
		box(Rect2(xx - 30, 182, 58, 29), COLORS[id].darkened(0.15), 2)
		if roles[id] == 0 or roles[id] == 3:
			for line in range(3):
				draw_line(Vector2(xx - 24, 188 + line * 7), Vector2(xx + 3 + line * 6, 188 + line * 7), Color("d4e9cf"), 2)
		elif roles[id] == 1:
			draw_circle(Vector2(xx - 10, 195), 8, Color("eedaa8"))
			draw_colored_polygon(PackedVector2Array([Vector2(xx - 8, 207), Vector2(xx + 8, 189), Vector2(xx + 23, 207)]), Color("d5a0a4"))
		else:
			for line in range(7):
				var h := 5.0 + absf(sin(line * 1.7)) * 14
				draw_line(Vector2(xx - 20 + line * 7, 197 - h / 2), Vector2(xx - 20 + line * 7, 197 + h / 2), Color("f9e3d2"), 3)
		draw_rect(Rect2(xx - 40, 212, 78, 4), Color("497071"))
		box(Rect2(xx + 48, 189, 15, 18), COLORS[id], 3)
		if selected == id:
			draw_colored_polygon(PackedVector2Array([Vector2(xx - 6, 103 + bob), Vector2(xx + 6, 103 + bob), Vector2(xx, 113 + bob)]), Color("f5c75e"))
	# Plant near the door.
	box(Rect2(15, 224, 31, 39), Color("c48361"), 5)
	for leaf in range(5):
		var tip := Vector2(15 + leaf * 7, 180 + (leaf % 2) * 17)
		draw_line(Vector2(30, 231), tip, Color("507964"), 3)
		draw_circle(tip, 9, Color("60836b"))

func person(center: Vector2, id: int, scale_factor: float) -> void:
	var bounds := Rect2(center + Vector2(-26, -30) * scale_factor, Vector2(52, 86) * scale_factor)
	var texture: Texture2D = portraits[id]
	if texture == null:
		box(bounds, Color("c8d5cd"), 2)
		return
	var texture_size := texture.get_size()
	var ratio := minf(bounds.size.x / texture_size.x, bounds.size.y / texture_size.y)
	var display_size := texture_size * ratio
	draw_texture_rect(texture, Rect2(bounds.position + (bounds.size - display_size) / 2, display_size), false)
