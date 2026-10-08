extends Control
## Original code-drawn artwork. No external textures or downloads required.
signal member_clicked(id: int)
var portrait := false
var member_id := 0
var selected := 0
var month := 1
var roles: Array = [0, 0, 1, 2]
var ticks := 0.0
var animate := true
const COLORS := [Color("83b9c7"), Color("ecc36d"), Color("a8ba91"), Color("d4a3b3")]
const INK := Color("264549")

func _ready() -> void:
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
	var s := scale_factor
	var skin := Color("efc7a5")
	var hair: Color = [Color("34484b"), Color("895e42"), Color("454738"), Color("514651")][id]
	box(Rect2(center + Vector2(-24, 14) * s, Vector2(48, 43) * s), COLORS[id], 13 * s)
	draw_circle(center + Vector2(0, -8) * s, 24 * s, hair)
	if id == 2:
		box(Rect2(center + Vector2(-26, -7) * s, Vector2(52, 42) * s), hair, 9 * s)
	draw_circle(center, 20 * s, skin)
	draw_colored_polygon(PackedVector2Array([center + Vector2(-22, -7) * s, center + Vector2(-15, -24) * s, center + Vector2(8, -26) * s, center + Vector2(23, -7) * s, center + Vector2(7, -14) * s, center + Vector2(-3, -5) * s, center + Vector2(-5, -15) * s]), hair)
	if id == 1:
		draw_circle(center + Vector2(21, -15) * s, 10 * s, hair)
		draw_circle(center + Vector2(22, -14) * s, 4 * s, Color("e7a66c"))
	if id == 0:
		draw_arc(center + Vector2(-8, 1) * s, 7 * s, 0, TAU, 20, INK, 1.5 * s)
		draw_arc(center + Vector2(8, 1) * s, 7 * s, 0, TAU, 20, INK, 1.5 * s)
		draw_line(center + Vector2(-1, 0) * s, center + Vector2(1, 0) * s, INK, s)
	if id == 3:
		draw_arc(center + Vector2(0, -4) * s, 24 * s, PI, TAU, 24, COLORS[id].darkened(0.4), 5 * s)
		box(Rect2(center + Vector2(-28, -5) * s, Vector2(8, 19) * s), INK, 3)
		box(Rect2(center + Vector2(20, -5) * s, Vector2(8, 19) * s), INK, 3)
	draw_circle(center + Vector2(-8, 1) * s, 1.7 * s, INK)
	draw_circle(center + Vector2(8, 1) * s, 1.7 * s, INK)
	draw_arc(center + Vector2(0, 5) * s, 5 * s, 0.2, PI - 0.2, 12, Color("9a6855"), 1.3 * s)
