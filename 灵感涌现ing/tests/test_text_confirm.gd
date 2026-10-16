extends SceneTree
const Roster = preload("res://tests/fixtures/roster_fixture.gd")
## 通用文本确认框检查：文本作为参数、取消在左／确认在右、返回值、Esc、排队、
## 长文本滚动、分辨率自适应，以及打开期间不穿透到下层界面。

var checks := 0
var failures := 0
var scene
var popup
var answers: Array = []
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
	# 调用方拿到的就是这个全局单例，测试直接用它，不用另造一份。
	popup = root.get_node_or_null("TextConfirm")
	check(popup != null, "确认框已注册为全局单例，任何脚本都能调用")
	if popup == null:
		print("TEXT_CONFIRM_TESTS: %d checks, %d failures" % [checks, failures])
		quit(1)
		return
	await frames(3)
	check(popup.has_method("ask"), "可以用 TextConfirm.ask(文本) 调用")
	check(not popup.is_open(), "确认框默认不显示")
	check(popup is CanvasLayer and popup.layer >= 100, "确认框画在主界面之上")
	check(popup.process_mode == Node.PROCESS_MODE_ALWAYS, "暂停时确认框仍然接收输入")

	var short_text := "确认框测试：点确认返回 true。"
	ask(short_text)
	await frames(3)
	check(popup.is_open(), "调用 ask 后弹出确认框")
	check(popup.text_label.text == short_text, "正文显示传入的文本")
	check(popup.cancel_button.text == "取消" and popup.confirm_button.text == "确认", "下方是确认和取消两个按钮")
	var text_rect: Rect2 = popup.text_label.get_global_rect()
	var cancel_rect: Rect2 = popup.cancel_button.get_global_rect()
	var confirm_rect: Rect2 = popup.confirm_button.get_global_rect()
	var dialog_rect: Rect2 = popup.dialog.get_global_rect()
	check(cancel_rect.get_center().x < confirm_rect.get_center().x, "确认按钮在取消按钮右侧")
	check(cancel_rect.get_center().y > text_rect.get_center().y and confirm_rect.get_center().y > text_rect.get_center().y,
		"两个按钮都在文本下方")
	check(dialog_rect.encloses(cancel_rect) and dialog_rect.encloses(confirm_rect), "两个按钮都在确认框内")
	check(dialog_rect.size.x < scene.size.x and dialog_rect.size.y < scene.size.y, "确认框不占满全屏")
	check(scene.get_global_rect().encloses(dialog_rect), "确认框完整位于画面内")
	check(popup.dimmer.visible and popup.dimmer.size == scene.size, "遮罩铺满整个画面用来调低亮度")
	check(paused, "确认框打开时暂停下层界面")
	check(root.gui_get_focus_owner() == popup.cancel_button, "默认焦点在取消按钮")
	check(not popup.body.get_v_scroll_bar().visible, "短文本不需要滚动")
	await capture("text-confirm-short")

	await click(center(popup.confirm_button))
	await frames(3)
	check(answers.size() == 1 and answers[0] == true, "点确认返回 true")
	check(not popup.is_open(), "选择之后关闭确认框")
	check(not paused, "关闭后恢复下层界面")
	check(root.gui_get_focus_owner() == scene.starting_roster.slot_buttons[0], "关闭后焦点回到打开前的控件")

	Roster.select_starting_pair(scene)
	scene.start_button.pressed.emit()
	Roster.recruit_all(scene.state)
	scene.open_game_selection()
	scene._select_project("确认框测试", "act", "fantasy", 1)
	await frames(2)
	check(scene.main_screen.visible, "进入主界面")
	check(not scene.character_screen.visible, "人物资料页默认不显示")

	# 打开排期界面并拿起一名角色：确认框打开时点界面外、按 Esc 都不该动到下层的排期界面。
	await click(center(scene.schedule_button))
	await frames(2)
	check(scene.duty_panel.visible, "排期界面已打开")
	await press(center(scene.duty_panel.tokens[0]))
	check(scene.duty_panel.is_holding(), "排期界面已经拿起一名角色")

	ask("确认框打开时，点击界面外不穿透。")
	await frames(3)
	check(popup.is_open(), "确认框已打开")
	await click(Vector2(20.0, 20.0))
	await frames(3)
	check(popup.is_open(), "点遮罩不会关闭确认框")
	check(scene.duty_panel.visible, "确认框打开时点界面外不会关掉下层界面")
	check(scene.duty_panel.is_holding(), "确认框打开时下层界面不响应鼠标")
	await escape()
	await frames(3)
	check(answers.size() == 2 and answers[1] == false, "按 Esc 返回 false")
	check(not popup.is_open(), "Esc 后关闭确认框")
	check(scene.duty_panel.visible, "Esc 只关掉确认框，下层界面还在")
	check(scene.duty_panel.is_holding(), "Esc 不会顺手取消下层界面拿起的角色")
	check(not paused, "Esc 后恢复下层界面")

	await right_click()
	await frames(2)
	check(not scene.duty_panel.is_holding(), "确认框关闭后右键仍能取消拿起")
	await click(Vector2(20.0, 20.0))
	await frames(2)
	check(not scene.duty_panel.visible, "确认框关闭后点界面外能回到主界面")

	# 同时发起两个请求：按顺序显示，各自只收到自己的结果。
	ask("第一个请求。")
	ask("第二个请求。")
	await frames(3)
	check(popup.text_label.text == "第一个请求。", "同时发起多个请求时先显示第一个")
	await click(center(popup.confirm_button))
	await frames(3)
	check(answers.size() == 3 and answers[2] == true, "第一个请求只收到自己的结果")
	check(popup.is_open() and popup.text_label.text == "第二个请求。", "第一个结束后接着显示第二个")
	await click(center(popup.cancel_button))
	await frames(3)
	check(answers.size() == 4 and answers[3] == false, "第二个请求返回 false")
	check(not popup.is_open(), "全部请求结束后关闭确认框")
	check(not paused, "全部请求结束后恢复下层界面")

	# 确认框盖住主界面时，点人物入口同样不该穿透。
	ask("确认框打开时，点人物入口不穿透。")
	await frames(3)
	await click(center(scene.character_buttons[0]))
	await frames(3)
	check(not scene.character_screen.visible, "确认框打开时点主界面不会穿透")
	check(scene.main_screen.visible, "主界面仍在")
	check(popup.is_open(), "点主界面不会关掉确认框")
	await click(center(popup.cancel_button))
	await frames(3)
	check(answers.size() == 5 and answers[4] == false, "点取消返回 false")
	check(not paused, "取消后恢复下层界面")

	# 长文本：高度封顶、按钮仍在框内、正文可以滚动。
	var long_text: String = "这是一段很长的确认文本，用来检查滚动条和高度上限。".repeat(20)
	ask(long_text)
	await frames(3)
	check(popup.text_label.text == long_text, "长文本完整传给正文")
	var long_rect: Rect2 = popup.dialog.get_global_rect()
	check(long_rect.size.y <= popup.MAX_BODY_HEIGHT + popup.BODY_CHROME + 1.0, "长文本时确认框高度有上限")
	check(long_rect.size.x < scene.size.x and long_rect.size.y < scene.size.y, "长文本时确认框不占满全屏")
	check(scene.get_global_rect().encloses(long_rect), "长文本时确认框完整位于画面内")
	check(long_rect.encloses(popup.cancel_button.get_global_rect()), "长文本时按钮仍然留在框内")
	check(popup.body.get_v_scroll_bar().visible, "超过上限的长文本可以滚动查看")
	await capture("text-confirm-long")
	await click(center(popup.cancel_button))
	await frames(3)
	check(answers.size() == 6 and answers[5] == false, "长文本取消返回 false")

	# 分辨率自适应：换分辨率后仍在画面内，按钮顺序不变。
	ask("分辨率检查。")
	await frames(3)
	for dimensions in [Vector2i(1440, 900), Vector2i(1920, 1080), Vector2i(2560, 1080)]:
		root.size = dimensions
		await frames(3)
		var rect: Rect2 = popup.dialog.get_global_rect()
		check(scene.get_global_rect().encloses(rect), "确认框不超出视口 %s" % dimensions)
		check(rect.size.x < scene.size.x and rect.size.y < scene.size.y, "各分辨率下确认框都不占满全屏 %s" % dimensions)
		check(rect.encloses(popup.cancel_button.get_global_rect()) and rect.encloses(popup.confirm_button.get_global_rect()),
			"各分辨率下两个按钮都在确认框内 %s" % dimensions)
		check(popup.cancel_button.get_global_rect().get_center().x < popup.confirm_button.get_global_rect().get_center().x,
			"各分辨率下确认都在取消右侧 %s" % dimensions)
	root.size = Vector2i(1440, 900)
	await frames(3)
	await click(center(popup.cancel_button))
	await frames(3)
	check(answers.size() == 7 and answers[6] == false, "分辨率检查后点取消返回 false")

	# 不在场景树里调用时按取消处理，不会让调用方一直等。
	root.remove_child(popup)
	var outside: bool = await popup.ask("不在场景树中的确认框。")
	check(outside == false, "不在场景树时 ask 直接返回 false")
	check(not paused and not popup.is_open(), "测试结束时没有残留的暂停或弹窗")
	root.add_child(popup)
	check(not popup.is_open(), "放回场景树后仍是关闭状态")

	scene.queue_free()
	print("TEXT_CONFIRM_TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func ask(text: String) -> void:
	answers.append(await popup.ask(text))

func frames(count: int) -> void:
	for frame in count:
		await process_frame

func center(node) -> Vector2:
	return node.get_global_rect().get_center()

func click(point: Vector2) -> void:
	await press(point)
	await release(point)

func press(point: Vector2) -> void:
	await push_button(point, true)

func release(point: Vector2) -> void:
	await push_button(point, false)

func right_click() -> void:
	await push_mouse(last_point, MOUSE_BUTTON_RIGHT, true)

func escape() -> void:
	await process_frame
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	root.push_input(event, true)
	await process_frame

func push_button(point: Vector2, pressed: bool) -> void:
	await push_mouse(point, MOUSE_BUTTON_LEFT, pressed)
	last_point = point

func push_mouse(point: Vector2, button: int, pressed: bool) -> void:
	await process_frame
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = button
	event.pressed = pressed
	root.push_input(event, true)
	await process_frame

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://qa/%s.png" % label)

