extends SceneTree
## 工作分配表界面检查：真实鼠标事件驱动的拖动与“点击拿起再点击放下”、圆心落点判定、
## 无效落点回退、阶段限制、以及不同分辨率下的布局。

const Model = preload("res://scripts/game_model.gd")
var checks := 0
var failures := 0
var scene
var panel
var last_point := Vector2.ZERO

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1440, 900)
	scene = load("res://scenes/interface_shell.tscn").instantiate()
	root.add_child(scene)
	for frame in 3:
		await process_frame
	check(scene.time_label.text == "第1年1月", "主界面显示第 x 年 x 月")
	var time_rect: Rect2 = scene.time_label.get_global_rect()
	check(time_rect.get_center().x > scene.size.x * 0.5 and time_rect.get_center().y < scene.size.y * 0.25, "时间显示在主界面右上角")
	var schedule_rect: Rect2 = scene.schedule_button.get_global_rect()
	check(schedule_rect.get_center().x > scene.size.x * 0.5 and schedule_rect.get_center().y > scene.size.y * 0.75, "排期按钮在主界面右下角")
	scene.state.year = 3
	scene.state.month = 12
	scene.refresh_time()
	check(scene.time_label.text == "第3年12月", "时间跟随游戏状态，而不是系统时间")
	scene.state = Model.fresh()
	scene.refresh_time()
	check(scene.time_label.text == "第1年1月", "重新开局后时间回到第一年一月")
	scene.start_button.pressed.emit()
	scene._select_project("职责测试", "act", "fantasy", 1)
	await process_frame

	panel = scene.duty_panel
	check(not panel.visible, "职责调整界面默认不显示")
	await click(center(scene.schedule_button))
	check(panel.visible, "点击排期按钮进入职责调整界面")
	check(scene.main_screen.visible, "职责调整界面打开时主界面仍在背后显示")
	check(panel.dimmer.visible and panel.dimmer.size == scene.size, "遮罩铺满整个主界面用来调低亮度")
	var dialog_rect: Rect2 = panel.dialog.get_global_rect()
	check(dialog_rect.size.x < scene.size.x and dialog_rect.size.y < scene.size.y, "职责调整界面不占满全屏")
	check(scene.get_global_rect().encloses(dialog_rect), "职责调整界面完整位于画面内")
	check(not dialog_rect.has_point(Vector2(20.0, 20.0)), "界面外仍然留有主界面区域")
	for frame in 3:
		await process_frame
	check(panel.slot_boxes.size() == 4 and panel.tokens.size() == 4, "四个职责方框，每位角色一个圆形")
	var titles: Array = []
	for index in 4:
		titles.append(panel.slot_titles[index].text)
		check(panel.slot_titles[index].get_global_rect().end.y <= panel.slot_boxes[index].get_global_rect().position.y + 0.5, "职责名称显示在方框上方")
	check(titles == Model.ROLES, "方框上方的名称就是四项职责")
	for index in 4:
		check(inside(panel.tokens[index], panel.slot_boxes[int(scene.state.members[index].role)]), "圆形按当前职责落在对应方框内")

	var token_a = panel.tokens[0]
	var before_a: Vector2 = token_a.get_global_rect().get_center()
	await press(before_a)
	check(panel.is_holding(), "在圆形上按下即拿起该角色")
	await move(center(panel.slot_boxes[1]))
	check(panel.is_holding(), "拖动过程中角色保持拿起")
	await release(center(panel.slot_boxes[1]))
	check(not panel.is_holding(), "松开后放下角色")
	check(int(scene.state.members[0].role) == 1, "圆心落在美术方框内会调整职责")
	check(panel.role_of_token[0] == 1, "界面显示与游戏状态一致")
	check(inside(token_a, panel.slot_boxes[1]), "调整成功后圆形停在落点")
	check(int(scene.state.month) == 1 and scene.state.phase == "ready", "调整职责不消耗回合，也不改变已确认立项的阶段")

	var token_b = panel.tokens[1]
	var before_b: Vector2 = token_b.get_global_rect().get_center()
	await press(before_b)
	await move(gap_point())
	await release(gap_point())
	check(int(scene.state.members[1].role) == 0, "圆心落在方框外不会改变职责")
	check(close_to(token_b.get_global_rect().get_center(), before_b), "圆心落在方框外时圆形回到拿起前的位置")

	var token_c = panel.tokens[2]
	await click(token_c.get_global_rect().get_center())
	check(panel.is_holding(), "点击一次即可拿起角色，不必按住")
	await move(center(panel.slot_boxes[3]))
	check(panel.is_holding(), "拿起后移动仍然保持拿起")
	await click(center(panel.slot_boxes[3]))
	check(not panel.is_holding() and int(scene.state.members[2].role) == 3, "再次点击放下并调整职责")
	check(inside(token_c, panel.slot_boxes[3]), "点击方式调整后圆形停在落点")

	var token_d = panel.tokens[3]
	await click(token_d.get_global_rect().position + Vector2(3.0, 3.0))
	check(not panel.is_holding(), "方框四角不算圆形命中，不会拿起角色")
	check(panel.visible, "界面内部的无效点击不会关闭职责调整界面")

	await click(Vector2(20.0, 20.0))
	check(not panel.visible, "点击非本界面的部分回到主界面")
	check(scene.main_screen.visible, "返回后仍是主界面")

	await click(center(scene.schedule_button))
	check(panel.visible, "可以再次打开职责调整界面")
	for frame in 3:
		await process_frame
	for index in 4:
		check(panel.role_of_token[index] == int(scene.state.members[index].role), "重新打开后界面读取真实职责")
		check(inside(panel.tokens[index], panel.slot_boxes[int(scene.state.members[index].role)]), "重新打开后圆形回到所属方框内")

	var token_b_again = panel.tokens[1]
	await press(token_b_again.get_global_rect().get_center())
	await move(center(panel.slot_boxes[1]))
	await release(center(panel.slot_boxes[1]))
	check(int(scene.state.members[1].role) == 1, "同一职责可以容纳多名角色")
	await click(center(scene.schedule_button))
	check(not panel.visible, "界面外的点击同样可以关闭")
	await click(center(scene.schedule_button))
	for frame in 3:
		await process_frame
	check(panel.role_of_token[0] == 1 and panel.role_of_token[1] == 1, "同框关系随游戏状态保留")
	check(inside(panel.tokens[0], panel.slot_boxes[1]) and inside(panel.tokens[1], panel.slot_boxes[1]), "同框角色都落在方框内")
	check(not panel.tokens[0].get_global_rect().intersects(panel.tokens[1].get_global_rect()), "同框多名角色用网格错开，互不重叠")

	scene.state.phase = "report"
	var role_d: int = int(scene.state.members[3].role)
	var before_d: Vector2 = panel.tokens[3].get_global_rect().get_center()
	await press(before_d)
	await move(center(panel.slot_boxes[0]))
	await release(center(panel.slot_boxes[0]))
	check(int(scene.state.members[3].role) == role_d, "报告阶段不会改变职责")
	check(close_to(panel.tokens[3].get_global_rect().get_center(), before_d), "被拒绝的调整回到拿起前的位置")
	scene.state.phase = "ready"

	await press(panel.tokens[0].get_global_rect().get_center())
	check(panel.is_holding(), "取消前角色处于拿起状态")
	await cancel()
	check(not panel.is_holding(), "取消后不再持有角色")
	check(panel.visible, "取消拿起不会关闭职责调整界面")

	for dimensions in [Vector2i(1440, 900), Vector2i(1920, 1080), Vector2i(2560, 1080)]:
		root.size = dimensions
		for frame in 3:
			await process_frame
		var rect: Rect2 = panel.dialog.get_global_rect()
		check(scene.get_global_rect().encloses(rect), "职责调整界面不超出视口 %s" % dimensions)
		check(rect.size.x < scene.size.x and rect.size.y < scene.size.y, "各分辨率下界面都不占满全屏 %s" % dimensions)
		check(not rect.has_point(Vector2(20.0, 20.0)), "各分辨率下界面外仍可点击主界面 %s" % dimensions)
		for index in 4:
			check(inside(panel.tokens[index], panel.slot_boxes[int(scene.state.members[index].role)]), "各分辨率下圆形仍在所属方框内 %s" % dimensions)

	scene.queue_free()
	print("DUTY_ASSIGNMENT_UI_TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func center(node) -> Vector2:
	return node.get_global_rect().get_center()

func inside(node, box) -> bool:
	return box.get_global_rect().has_point(node.get_global_rect().get_center())

func close_to(a: Vector2, b: Vector2) -> bool:
	return a.distance_to(b) < 1.0

func gap_point() -> Vector2:
	## 界面内部、四个方框之外的位置：状态文字所在区域。
	return panel.status_label.get_global_rect().get_center()

func click(point: Vector2) -> void:
	await press(point)
	await release(point)

func press(point: Vector2) -> void:
	await _push_button(point, true)

func release(point: Vector2) -> void:
	await _push_button(point, false)

func cancel() -> void:
	await process_frame
	var event := InputEventMouseButton.new()
	event.position = last_point
	event.global_position = last_point
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	root.push_input(event, true)
	await process_frame

func move(point: Vector2) -> void:
	await process_frame
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = point - last_point
	last_point = point
	root.push_input(event, true)
	await process_frame

func _push_button(point: Vector2, pressed: bool) -> void:
	await process_frame
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	last_point = point
	root.push_input(event, true)
	await process_frame
