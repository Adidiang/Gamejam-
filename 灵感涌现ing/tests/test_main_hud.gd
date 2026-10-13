extends SceneTree
## 主界面下方属性栏检查：显示当前作品的名字、类型题材，以及游戏性、创新性、表现力与 Bug 的模型真值；
## 属性栏位于画面下方、不遮挡右下角排期按钮与人物入口，多分辨率下仍在画面内，
## 并且排期按钮保持可点击。

const Model = preload("res://scripts/game_model.gd")
const SkillFixture = preload("res://tests/fixtures/skill_fixture.gd")
var checks := 0
var failures := 0
var scene

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var skill_definitions := SkillFixture.without_effects()
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1440, 900)
	var definitions: Array = Model.DEFINITIONS.duplicate(true)
	for id in 4:
		Model.DEFINITIONS[id].stats = [10, 20, 30, 40]
	scene = load("res://scenes/interface_shell.tscn").instantiate()
	root.add_child(scene)
	for frame in 4:
		await process_frame
	scene.state = Model.fresh()
	for id in 4:
		scene.state.members[id].role = id
	scene.show_main()
	await process_frame
	check(scene.status_panel.visible, "主界面显示属性栏")
	check(scene.gameplay_label.text == "游戏性 0.0" and scene.innovation_label.text == "创新性 0.0"
		and scene.presentation_label.text == "表现力 0.0" and scene.bug_label.text == "Bug 0.0", "开局四项属性均为零")
	check(scene.project_label.text == "「未命名的灵感」 · 动作 / 科幻", "旧原型状态回退显示作品名与类型题材")

	var selection := Model.select_project(Model.fresh_annual(), "星尘回响", "narrative", "fantasy", 1)
	check(selection.ok, "年度作品档案可以立项")
	scene.state = selection.state
	for id in 4:
		scene.state.members[id].role = id
	scene.show_main()
	await process_frame
	check(scene.main_screen.visible, "立项后进入主界面")
	check(scene.project_label.text == "「星尘回响」 · 剧情向 / 奇幻", "属性栏显示当年作品的名字与类型题材")
	check(scene.gameplay_label.text == "游戏性 0.0" and scene.bug_label.text == "Bug 0.0", "新作品的属性从零开始")
	var status_rect: Rect2 = scene.status_panel.get_global_rect()
	check(status_rect.size.x > 0.0 and status_rect.size.y > 0.0, "属性栏有可见尺寸")
	check(status_rect.encloses(scene.project_label.get_global_rect()), "作品行在属性栏内")
	check(status_rect.size.x >= scene.status_column.get_combined_minimum_size().x
		and status_rect.size.y >= scene.status_column.get_combined_minimum_size().y, "属性栏放得下作品行与四项属性")
	check(status_rect.get_center().y > scene.size.y * 0.75, "属性栏位于主界面下方")
	check(scene.get_global_rect().encloses(status_rect), "属性栏完整位于画面内")
	check(status_rect.end.x <= scene.schedule_button.get_global_rect().position.x, "属性栏排在排期按钮左侧")
	check(not status_rect.intersects(scene.schedule_button.get_global_rect()), "属性栏不遮挡排期按钮")
	await click(scene.schedule_button.get_global_rect().get_center())
	check(scene.duty_panel.visible and scene.main_screen.visible, "属性栏不拦截排期按钮点击")
	scene.duty_panel.close()
	await process_frame
	scene.open_schedule()
	await process_frame
	scene.duty_panel.next_turn_button.pressed.emit()
	await process_frame
	check(scene.state.month == 2, "下一回合推进月份")
	var work: Dictionary = scene.state.work
	check(float(work.g) > 0.0 and float(work.b) >= 0.0, "结算产出非零且 Bug 以零为下限")
	check(scene.gameplay_label.text == "游戏性 %.1f" % float(work.g), "属性栏显示结算后的游戏性")
	check(scene.innovation_label.text == "创新性 %.1f" % float(work.i), "属性栏显示结算后的创新性")
	check(scene.presentation_label.text == "表现力 %.1f" % Model.performance(work), "属性栏显示模型推导的表现力")
	check(scene.bug_label.text == "Bug %.1f" % float(work.b), "属性栏显示累计 Bug")

	var before_presentation := Model.performance(work)
	var executed := Model.execute_task(scene.state, 0, "art_concept", 1, 2)
	check(executed.ok and float(executed.state.work.get("p", 0.0)) > 0.0, "本年任务产出写入直接表现力")
	scene.state = executed.state
	scene.refresh_time()
	check(scene.presentation_label.text == "表现力 %.1f" % Model.performance(scene.state.work), "任务产出后刷新属性栏表现力")
	check(Model.performance(scene.state.work) > before_presentation, "任务产出让表现力上升")

	for resolution in [Vector2i(1280, 720), Vector2i(1440, 900), Vector2i(1920, 1080)]:
		root.size = resolution
		for frame in 4:
			await process_frame
		var rect: Rect2 = scene.status_panel.get_global_rect()
		check(scene.get_global_rect().encloses(rect), "%s 下属性栏完整位于画面内" % resolution)
		check(rect.get_center().y > scene.size.y * 0.75, "%s 下属性栏仍在主界面下方" % resolution)
		check(not rect.intersects(scene.schedule_button.get_global_rect()), "%s 下属性栏不遮挡排期按钮" % resolution)
		for label in [scene.project_label, scene.gameplay_label, scene.innovation_label, scene.presentation_label, scene.bug_label]:
			check(label.visible and rect.encloses(label.get_global_rect()), "%s 下作品行与四项属性文字都在属性栏内" % resolution)
		for button in scene.character_buttons:
			check(not rect.intersects(button.get_global_rect()), "%s 下属性栏不遮挡人物入口" % resolution)
		if resolution == Vector2i(1280, 720):
			check(status_gap(rect) >= 8.0, "1280×720 下属性栏与排期按钮仍有间距")
	root.size = Vector2i(1440, 900)
	for frame in 4:
		await process_frame
	var deadline := Time.get_ticks_msec() + 15000
	while scene.work_panel.playing and Time.get_ticks_msec() < deadline:
		await process_frame
	scene.work_panel.close()
	await process_frame
	check(not scene.work_panel.visible and scene.main_screen.visible, "工作展示结束后回到主界面")
	await click(scene.schedule_button.get_global_rect().get_center())
	check(scene.duty_panel.visible, "多分辨率来回切换后排期按钮仍可点击")
	scene.duty_panel.close()
	await process_frame
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://qa/main_hud.png")
		# 最小分辨率下属性栏与排期按钮的间距最紧，留一张截图方便人工核对。
		root.size = Vector2i(1280, 720)
		for frame in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://qa/main_hud_1280.png")
	scene.queue_free()
	await process_frame
	Model.DEFINITIONS = definitions
	SkillFixture.restore(skill_definitions)
	print("Main screen HUD: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func status_gap(rect: Rect2) -> float:
	## 属性栏右边界到排期按钮左边界之间的水平间距。
	return scene.schedule_button.get_global_rect().position.x - rect.end.x

func click(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame
