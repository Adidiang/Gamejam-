extends SceneTree
const Roster = preload("res://tests/fixtures/roster_fixture.gd")

const Model = preload("res://scripts/game_model.gd")
const SkillFixture = preload("res://tests/fixtures/skill_fixture.gd")
var failures := 0
var checks := 0
var presented: Array[int] = []

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
	var initial: Dictionary = Model.select_project(Roster.fresh(), "工作测试", "act", "modern", 1).state
	initial.members[0].role = 0
	initial.members[1].role = 1
	initial.members[2].role = 2
	initial.members[3].role = 3
	initial.work.b = 30.0
	var result := Model.advance_work(initial, 1, 1)
	check(result.ok, "准备阶段允许下一回合")
	check(initial.month == 1 and initial.work.g == 0.0, "结算不修改输入状态")
	var factors: Array = []
	for id in 4:
		factors.append(Model.duty_output_factor(initial, id))
	check(is_equal_approx(result.state.work.g, 17.0 * factors[0] + 16.0 * factors[2]), "玩法与音乐岗位产出经转换单元后计入游戏性")
	check(is_equal_approx(result.state.work.p, 28.0 * factors[1] + 36.0 * factors[2]), "美术与音乐岗位产出经转换单元后计入表现力")
	check(result.state.work.keys() == ["g", "i", "p", "b"], "作品属性只有游戏性、创新性、表现力与 Bug")
	check(is_equal_approx(result.state.work.b, 30.0 + 1.0 * factors[0] - 10.0 * factors[3]), "新增 Bug 与岗位修复同时结算")
	check(is_equal_approx(result.report.contributions[3].repair, 10.0 * factors[3]), "修复贡献保留能力值并经过转换单元")
	var gameplay_only: Dictionary = initial.duplicate(true)
	for id in range(1, gameplay_only.members.size()):
		gameplay_only.members[id].recruited = false
	for stats in [[30, 10, 0, 0], [10, 10, 0, 0], [10, 19, 0, 0]]:
		Model.DEFINITIONS[0].stats = stats
		var no_bugs := Model.advance_work(gameplay_only, 1, 1)
		check(no_bugs.report.contributions[0].b == 0.0 and no_bugs.state.work.b == 30.0, "玩法 Bug 增量为负、零或取整为零时不产生也不修复 Bug")
	Model.DEFINITIONS[0].stats = [10, 20, 30, 40]
	## 转换单元：系数始终落在 0.5～1.5，同种子可复现，不同事件各不相同。
	var unit_values: Array = []
	var in_range := true
	for index in 200:
		var value: float = Model.output_factor("unit-%d" % index)
		in_range = in_range and value >= 0.5 and value <= 1.5
		unit_values.append(value)
	check(in_range, "转换系数始终落在 0.5～1.5")
	check(is_equal_approx(unit_values[0], Model.output_factor("unit-0")), "同一事件重复结算得到同一系数")
	check(unit_values.min() < 0.9 and unit_values.max() > 1.1, "系数在区间内波动而不是常数")
	check(is_equal_approx(Model.transform_output({"g": 10.0, "b": -2.0}, 1.5).g, 15.0) and is_equal_approx(Model.transform_output({"g": 10.0, "b": -2.0}, 1.5).b, -3.0), "整份产出乘同一系数，负数（Bug 削减）同样保留")
	check(is_equal_approx(Model.transform_output({"g": 17.0}, 0.9104193242).g, 15.4771), "转换结果量化到 4 位小数")
	check(result.state.members[0].affinity == 0, "下一回合不自动邀约")
	check(not Model.advance_work(result.state, 1, 1).ok, "旧月份请求被拒绝")
	initial.phase = "report"
	check(not Model.advance_work(initial, 1, 1).ok, "报告阶段拒绝工作结算")
	initial.phase = "setup"
	initial.month = 12
	result = Model.advance_work(initial, 1, 12)
	check(result.state.year == 2 and result.state.month == 1 and result.report.month == 12, "跨年日历及结算月份")
	var scene = load("res://scenes/interface_shell.tscn").instantiate()
	root.add_child(scene)
	for frame in 4:
		await process_frame
	scene.state = Model.select_project(Roster.fresh(), "工作测试", "act", "modern", 1).state
	for id in 4:
		scene.state.members[id].role = id
	scene.show_main()
	check(scene.inspiration_label.text == "灵感 2", "时间下方显示初始全局灵感")
	check(scene.inspiration_label.get_global_rect().position.y >= scene.time_label.get_global_rect().end.y, "灵感显示在时间下方")
	scene.open_schedule()
	await process_frame
	var panel = scene.work_panel
	panel.member_presented.connect(func(id: int): presented.append(id))
	await click(scene.duty_panel.next_turn_button.get_global_rect().get_center())
	await process_frame
	check(not scene.duty_panel.visible and panel.visible, "点击后排期关闭、工作界面打开")
	check(scene.time_label.text == "第1年2月" and panel.title_label.text.contains("第1年1月"), "日历推进、工作报告标注刚结算月份")
	check(scene.state.inspiration == 3 and scene.inspiration_label.text == "灵感 3", "每月获得灵感并刷新主界面余额")
	check(panel.report.inspiration_delta == 1 and panel.report.inspiration == 3, "工作报告使用真实灵感余额及增量")
	check(panel.playing and panel.finish_button.disabled, "播放时不能提前关闭")
	var snapshot: Dictionary = scene.state.duplicate(true)
	scene.duty_panel.next_turn_button.pressed.emit()
	scene.open_schedule()
	scene.open_character("a")
	check(scene.state == snapshot and not scene.duty_panel.visible and not scene.character_screen.visible, "连续点击和其他入口不重复结算、不打开下层界面")
	var started := Time.get_ticks_msec()
	var saw_second_reveal := false
	var reveal_kept_scroll := true
	var saw_second_scroll := false
	var scroll_had_complete_results := true
	## 展示文本取自本回合真实贡献，避免写死数值；表现力列现在也会出现在成员行里。
	var member0_line := "游戏性  %+d" % floori(float(panel.report.contributions[0].g))
	var member1_line := "表现力  %+d" % floori(float(panel.report.contributions[1].p))
	while panel.playing and Time.get_ticks_msec() - started < 35000:
		await process_frame
		if panel.current_member == 1:
			if panel.animation.get_total_elapsed_time() < 0.8:
				saw_second_reveal = true
				reveal_kept_scroll = reveal_kept_scroll and panel.scroll.scroll_vertical == 0
			if panel.scroll.scroll_vertical > 0:
				saw_second_scroll = true
				scroll_had_complete_results = scroll_had_complete_results and panel.value_labels[0].text.contains(member0_line) and panel.value_labels[1].text.contains(member1_line) and is_equal_approx(panel.cards[1].modulate.a, 1.0)
	check(saw_second_reveal and reveal_kept_scroll, "下一人的成果展示过程中保持原滚动位置")
	check(saw_second_scroll and scroll_had_complete_results, "滚动开始时上下两人的成果都已完整显示")
	check(not panel.playing and presented == range(Model.DEFINITIONS.size()), "全员按顺序自动播放完成")
	check(panel.scroll.scroll_vertical > 0, "自动滚动到后续头像")
	check(panel.value_labels[0].text.contains(member0_line), "展示数据来自真实贡献")
	check(not panel.finish_button.disabled, "全员完成后允许返回")
	## 底部汇总只报本回合全员总计，不再报作品累计。
	var totals := {"g": 0.0, "i": 0.0, "p": 0.0, "b": 0.0, "repair": 0.0}
	for key in ["g", "i", "p", "b", "repair"]:
		for contribution in panel.report.contributions:
			totals[key] = float(totals[key]) + float(contribution[key])
	check(panel.summary_label.text.contains("本月总计") and not panel.summary_label.text.contains("作品累计"), "底部汇总改为本回合全员总计")
	check(panel.summary_label.text.contains("游戏性 %+d" % floori(float(totals.g))) and panel.summary_label.text.contains("表现力 %+d" % floori(float(totals.p))), "总计数值来自全员贡献相加")
	check(panel.summary_label.text.contains("修复能力 %+d" % floori(float(totals.repair))) and panel.summary_label.text.contains("当前灵感 %d" % int(panel.report.inspiration)), "总计保留修复口径与灵感信息")
	var original_report: Dictionary = panel.report
	panel.report = original_report.duplicate(true)
	panel.report.contributions[0].g = 1.9
	for contribution in panel.report.contributions:
		contribution.b = 0.0
	panel.report.contributions[1].g = 1.9
	panel.report.contributions[2].g = 0.0
	panel.report.contributions[3].g = 0.0
	var display_snapshot: Dictionary = panel.report.duplicate(true)
	panel._show_values(0.5, 0)
	check(panel.value_labels[0].text.contains("游戏性  +0") and not panel.value_labels[0].text.contains("Bug"), "递增动画向下取整，零 Bug 产出不显示")
	panel._show_values(1.0, 0)
	check(panel.value_labels[0].text.contains("游戏性  +1") and not panel.value_labels[0].text.contains("Bug"), "完整产出向下取整，零 Bug 产出不显示")
	check(not panel._month_summary_text().contains("Bug"), "全员零 Bug 产出时汇总不显示 Bug")
	check(panel._month_summary_text().contains("游戏性 +3"), "先合计真实小数再取整，不把成员显示值相加")
	check(panel.report == display_snapshot and scene.state == snapshot, "动画与汇总显示保留报告和模型真实数值")
	panel.report = original_report
	panel._show_values(1.0, 0)
	check(panel.value_labels[0].text.contains("Bug  +"), "正数 Bug 产出仍正常显示")
	for resolution in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		for frame in 4:
			await process_frame
		check(scene.get_global_rect().encloses(panel.finish_button.get_global_rect()), "不同分辨率下返回按钮在画面内")
		check(panel.scroll.size.y > 210, "不同分辨率下至少能完整看到一位成员")
	root.size = Vector2i(1440, 900)
	for frame in 4:
		await process_frame
	if DisplayServer.get_name() != "headless":
		await process_frame
		root.get_texture().get_image().save_png("res://qa/monthly_work.png")
	panel.finish_button.pressed.emit()
	check(not panel.visible and scene.main_screen.visible, "返回主界面")
	if DisplayServer.get_name() != "headless":
		await process_frame
		root.get_texture().get_image().save_png("res://qa/main_resources.png")
	scene.open_schedule()
	scene.duty_panel.next_turn_button.pressed.emit()
	await process_frame
	check(scene.state.month == 3 and panel.current_member == 0, "下一月可再次结算，播放从第一人重置")
	check(scene.inspiration_label.text == "灵感 4", "再次结算灵感继续累计")
	scene.queue_free()
	await process_frame
	Model.DEFINITIONS = definitions
	SkillFixture.restore(skill_definitions)
	print("Monthly work UI: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func click(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame
