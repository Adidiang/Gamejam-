extends SceneTree
const Roster = preload("res://tests/fixtures/roster_fixture.gd")
const Model = preload("res://scripts/game_model.gd")
const SkillFixture = preload("res://tests/fixtures/skill_fixture.gd")
const SkillTable = preload("res://scripts/skills/skill_table.gd")
const SkillDefinition = preload("res://scripts/skills/skill_definition.gd")
var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func quantized(value: float) -> float:
	## 转换单元把产出量化到 OUTPUT_DECIMALS 位小数；断言按同一规则取值，
	## 否则小数值（如 3.0）的量化误差会超过 is_equal_approx 的 1e-5 相对容差而偶发失败。
	var scale := pow(10.0, float(Model.OUTPUT_DECIMALS))
	return roundf(value * scale) / scale

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var skill_definitions := SkillFixture.without_effects()
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1440, 900)
	var definitions: Array = Model.DEFINITIONS.duplicate(true)
	Model.DEFINITIONS[0].stats = [10, 20, 30, 40]
	var initial: Dictionary = Model.select_project(Roster.fresh(), "任务检查", "act", "modern", 1).state
	var factor := Model.task_output_factor(initial, 0, "art_concept")
	var result := Model.execute_task(initial, 0, "art_concept", 1, 1)
	check(result.ok, "无前置任务可直接执行")
	check(initial.month == 1 and initial.action_steps == 1 and not initial.has("completed_tasks"), "执行不修改输入状态且初始一步")
	check(is_equal_approx(result.report.task_delta.p, 50.0 * factor), "表现力等于脑洞加美术并经过转换单元")
	check(is_equal_approx(result.report.task_delta.i, 50.0 * 20.0 / 30.0 * factor), "创新性使用脑洞美术比值")
	check(result.state.year == 1 and result.state.month == 1 and result.state.action_steps == 0 and result.state.inspiration == 2, "任务只消费行动步数，不推进月份或获得月灵感")
	check(result.report.delta.g == 0 and result.report.delta.b == 0 and float(result.report.delta.p) > 0, "任务只产出表现力与创新性，不结算职责")
	check(result.report.inspiration_delta == 0 and not result.report.has("contributions"), "任务报告不包含月灵感或职责贡献")
	check(Model.available_tasks(result.state).is_empty(), "全社团本年任务只执行一次")
	check(not Model.execute_task(result.state, 1, "art_concept", 1, 1).ok, "换人不能重复执行")
	check(not Model.execute_task(initial, 0, "art_concept", 1, 2).ok, "陈旧年月不能提交")
	var exhausted: Dictionary = initial.duplicate(true)
	exhausted.action_steps = 0
	check(not Model.execute_task(exhausted, 0, "art_concept", 1, 1).ok and exhausted.work.i == 0, "无步数时模型直接拒绝未做过的任务")
	var advanced := Model.advance_work(result.state, 1, 1)
	check(advanced.ok and advanced.state.month == 2 and advanced.state.action_steps == 1 and advanced.state.inspiration == 3, "排期推进月份、获得灵感并恢复步数")
	check(advanced.report.contributions.size() == Model.DEFINITIONS.size() and is_equal_approx(advanced.report.work.g, 17.0 * Model.duty_output_factor(result.state, 0)), "职责仅在排期结算一次")
	check(Model.available_tasks(advanced.state).is_empty(), "步数恢复不改变年度已完成任务记录")
	var skipped := Model.advance_work(initial, 1, 1)
	check(skipped.ok and skipped.state.action_steps == 1, "未行动也可推进月份，步数不累计")
	check(not Model.execute_task(initial, -1, "art_concept", 1, 1).ok, "拒绝无效成员")
	check(not Model.execute_task(initial, 0, "invalid", 1, 1).ok, "拒绝不存在任务")
	check(Model.valid_state(result.state), "新增次数及表现力状态可校验")
	var invalid: Dictionary = result.state.duplicate(true)
	invalid.completed_tasks["1"].append("art_concept")
	check(not Model.valid_state(invalid), "拒绝重复任务记录")
	for invalid_steps in [-1, 2, 0.5]:
		invalid = initial.duplicate(true)
		invalid.action_steps = invalid_steps
		check(not Model.valid_state(invalid), "拒绝非法回合行动步数")
	var legacy := initial.duplicate(true)
	legacy.erase("action_steps")
	check(not Model.valid_state(legacy), "缺少行动步数的状态被拒绝")
	initial.members[0].affinity = 50
	result = Model.execute_task(initial, 0, "art_concept", 1, 1)
	check(is_equal_approx(result.report.task_delta.p, 75.0 * factor), "任务使用好感增幅后的属性")
	Model.DEFINITIONS[0].stats = [0, 20, 0, 0]
	result = Model.execute_task(initial, 0, "art_concept", 1, 1)
	check(is_equal_approx(result.report.task_delta.i, 60.0 * factor), "零美术分母取 1，系数最高为 2")
	Model.DEFINITIONS[0].stats = [0, 1, 100, 0]
	result = Model.execute_task(initial, 0, "art_concept", 1, 1)
	check(is_equal_approx(result.report.task_delta.i, 151.5 * 0.1 * factor), "脑洞美术比值低于 0.1 时取下限")
	Model.DEFINITIONS[0].stats = [0, 0, 20, 0]
	result = Model.execute_task(initial, 0, "art_concept", 1, 1)
	check(is_equal_approx(result.report.task_delta.i, quantized(3.0 * factor)), "零脑洞且美术非零时同样使用 0.1 下限")
	for stats in [[0, 2, 1, 0], [0, 1, 10, 0]]:
		Model.DEFINITIONS[0].stats = stats
		result = Model.execute_task(initial, 0, "art_concept", 1, 1)
		check(absf(float(result.report.task_delta.i) - float(result.report.task_delta.p) * float(stats[1]) / float(stats[2])) < 0.001, "系数上下边界保持原值")
	Model.DEFINITIONS[0].stats = [0, 0, 0, 0]
	result = Model.execute_task(initial, 0, "art_concept", 1, 1)
	check(result.report.task_delta.i == 0 and result.report.task_delta.p == 0, "全零属性得到有限零产出")
	initial.month = 12
	result = Model.execute_task(initial, 0, "art_concept", 1, 12)
	check(result.state.year == 1 and result.state.month == 12 and result.state.action_steps == 0, "十二月执行任务也不跨年")
	advanced = Model.advance_work(result.state, 1, 12)
	check(advanced.state.year == 2 and advanced.state.month == 1 and advanced.state.action_steps == 1, "排期跨年后恢复行动步数")
	check(Model.available_tasks(advanced.state).is_empty(), "跨年尚未立项时没有可执行任务")
	var second_year: Dictionary = Model.select_project(advanced.state, "第二年", "act", "modern", 2).state
	check(Model.available_tasks(second_year).size() == 1, "次年立项后任务次数恢复")
	initial.phase = "report"
	check(not Model.execute_task(initial, 0, "art_concept", 1, 12).ok, "报告阶段不能执行任务")
	Model.DEFINITIONS = definitions
	# 使用正式属性的基础产出作对照，避免假设人物表始终为零能力。
	var baseline: Dictionary = Model.select_project(Roster.fresh(), "任务对照", "act", "modern", 1).state
	var base_task := Model.execute_task(baseline, 0, "art_concept", 1, 1)
	var base_factor := Model.task_output_factor(baseline, 0, "art_concept")
	var slot_id: String = Model.DEFINITIONS[0].skills[0].skill_id
	var original_skill = SkillTable.skills[slot_id]
	var skill_row := {"id": slot_id, "name": "任务测试技能", "description": "测试", "quip": "任务完成",
		"acquisition": "auto", "inspiration_cost": 0, "triggers": [
			{"hook": "ACTION_BEFORE", "conditions": {"action_kind": "task", "actor_is_owner": true},
			"target": "work", "frequency": "year", "effect_id": "numeric_modifier", "params": {"field": "i", "operation": "add", "amount": 5}, "priority": 0},
			{"hook": "ACTION_AFTER", "conditions": {"action_kind": "task"}, "target": "owner", "frequency": "event",
			"effect_id": "numeric_modifier", "params": {"field": "affinity", "operation": "add", "amount": 2}, "priority": 0}]}
	check(SkillDefinition.validate(skill_row).is_empty(), "任务技能配置合法")
	SkillTable.skills[slot_id] = SkillDefinition.from_row(skill_row)
	var matched: Dictionary = Model.select_project(Roster.fresh(), "任务技能", "act", "modern", 1).state
	result = Model.execute_task(matched, 0, "art_concept", 1, 1)
	# 转换单元在 ACTION_BEFORE 之前，对比时先把基础产出还原到同系数基准再加技能加成。
	var expected_i: float = base_task.report.task_delta.i / base_factor * Model.task_output_factor(matched, 0, "art_concept") + 5.0
	check(is_equal_approx(result.report.task_delta.i, expected_i) and result.state.members[0].affinity == base_task.state.members[0].affinity + 2 and result.report.skill_events.size() == 2, "任务前后技能生效并进入结果报告")
	check(result.report.skill_events.all(func(record: Dictionary): return record.hook in ["ACTION_BEFORE", "ACTION_AFTER"]), "任务仅触发任务阶段技能")
	SkillTable.skills[slot_id] = original_skill
	var scene = load("res://scenes/interface_shell.tscn").instantiate()
	root.add_child(scene)
	for frame in 4:
		await process_frame
	scene.state = Model.select_project(Roster.fresh(), "任务界面测试", "act", "modern", 1).state
	scene.show_main()
	scene.open_character("a")
	await click(scene.member_sheet.task_button.get_global_rect().get_center())
	check(scene.task_panel.visible and scene.character_screen.visible, "人物页保持显示并打开任务列表")
	var snapshot: Dictionary = scene.state.duplicate(true)
	await click(scene.close_button.get_global_rect().get_center())
	check(not scene.task_panel.visible and scene.character_screen.visible and scene.state == snapshot, "点击外侧只回退人物页，不点穿关闭按钮")
	scene.open_tasks()
	if DisplayServer.get_name() != "headless":
		await process_frame
		root.get_texture().get_image().save_png("res://qa/task_assignment.png")
	await click(scene.task_panel.task_buttons[0].get_global_rect().get_center())
	var confirm = root.get_node("TextConfirm")
	check(confirm.screen.visible and scene.task_panel.visible, "调用通用确认框并保留任务列表")
	await click(confirm.cancel_button.get_global_rect().get_center())
	check(not confirm.screen.visible and scene.task_panel.visible and scene.state == snapshot and scene.state.action_steps == 1, "取消只关闭确认框，不消费行动")
	await click(scene.task_panel.task_buttons[0].get_global_rect().get_center())
	await click(confirm.confirm_button.get_global_rect().get_center())
	var execution = scene.task_execution
	check(not scene.task_panel.visible and execution.visible and not confirm.screen.visible, "确认后关闭两个选择界面并打开执行界面")
	check(scene.state.month == 1 and scene.state.action_steps == 0 and execution.playing and execution.results_label.text.is_empty(), "执行只消耗一步，月份保持且右侧空白")
	check(execution.progress.value < 100 and execution.finish_button.disabled, "真实进度条且播放中禁止提前关闭")
	var elapsed := Time.get_ticks_msec()
	await create_timer(0.35).timeout
	check(execution.progress.value > 0 and execution.progress.value < 100 and execution.results_label.text.is_empty(), "进度中间值存在，结果尚未显示")
	if DisplayServer.get_name() != "headless":
		root.get_texture().get_image().save_png("res://qa/task_progress.png")
	scene.open_schedule()
	scene.open_character("b")
	scene._next_turn()
	check(scene.state.month == 1 and scene.state.action_steps == 0 and not scene.duty_panel.visible, "播放期间挡住其他入口和重复结算")
	while execution.playing and Time.get_ticks_msec() - elapsed < 2000:
		await process_frame
	check(not execution.playing and execution.progress.value == 100 and execution.results_label.text.contains("表现力"), "一秒后展示任务结果")
	check(not execution.results_label.text.contains("全员职责") and not execution.results_label.text.contains("灵感") and not execution.results_label.text.contains("游戏性"), "只展示任务产出，不展示职责或月灵感")
	check(Time.get_ticks_msec() - elapsed >= 900 and not execution.finish_button.disabled, "进度持续约一秒")
	var original_report: Dictionary = execution.report
	execution.report = original_report.duplicate(true)
	execution.report.task_delta = {"p": 1.9999, "i": 0.9999, "g": 0.0, "b": -1.2}
	var display_snapshot: Dictionary = execution.report.duplicate(true)
	var state_snapshot: Dictionary = scene.state.duplicate(true)
	execution._show_results()
	check(execution.results_label.text.contains("表现力 +1\n创新性 +0\nBug -2"), "任务结果对正负小数统一向下取整")
	check(execution.report == display_snapshot and scene.state == state_snapshot, "任务结果显示不修改报告或模型数值")
	execution.report = original_report
	execution._show_results()
	if DisplayServer.get_name() != "headless":
		await process_frame
		root.get_texture().get_image().save_png("res://qa/task_results.png")
	for resolution in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		for frame in 4:
			await process_frame
		check(scene.get_global_rect().encloses(execution.finish_button.get_global_rect()), "执行界面确认按钮不超出屏幕")
	await click(execution.finish_button.get_global_rect().get_center())
	check(not execution.visible and scene.main_screen.visible, "执行确认返回主界面")
	scene.open_character("b")
	var task_button: Button = scene.member_sheet.task_button
	var exhausted_style := task_button.get_theme_stylebox("normal") as StyleBoxFlat
	check(exhausted_style.bg_color == Color("a4aaa4") and not scene.member_sheet.task_notice.visible, "所有成员无步数时分配任务按钮变灰，步数不显示")
	await click(task_button.get_global_rect().get_center())
	check(not scene.task_panel.visible and scene.member_sheet.task_notice.visible and scene.member_sheet.task_notice_label.text == "本回合已行动", "灰色按钮点击弹出本回合已行动小框")
	if DisplayServer.get_name() != "headless":
		await process_frame
		root.get_texture().get_image().save_png("res://qa/task_no_actions.png")
	check(scene.state.action_steps == 0 and scene.state.month == 1, "提示不消费余额或推进月份")
	await click(scene.member_sheet.task_notice_box.get_global_rect().get_center())
	check(not scene.member_sheet.task_notice.visible, "点击小框立即关闭")
	await click(task_button.get_global_rect().get_center())
	await create_timer(1.0).timeout
	check(scene.member_sheet.task_notice.visible, "两秒内小框保持显示")
	# 重复请求只复用一个提示框并重新计时。
	scene.member_sheet.show_action_notice()
	await create_timer(1.2).timeout
	check(scene.member_sheet.task_notice.visible, "重复弹出重置两秒计时，旧计时不会提前关闭")
	await create_timer(0.9).timeout
	check(not scene.member_sheet.task_notice.visible, "两秒后自动关闭小框")
	await click(task_button.get_global_rect().get_center())
	await click(scene.close_button.get_global_rect().get_center())
	check(not scene.member_sheet.task_notice.visible and scene.character_screen.visible, "点击框外关闭提示且不穿透到人物页关闭按钮")
	await click(task_button.get_global_rect().get_center())
	scene.close_character()
	check(not scene.member_sheet.task_notice.visible and scene.member_sheet.task_notice_timer.is_stopped(), "离开人物页关闭提示并停止计时")
	scene.open_schedule()
	await process_frame
	await click(scene.duty_panel.next_turn_button.get_global_rect().get_center())
	check(scene.state.month == 2 and scene.state.action_steps == 1 and scene.state.inspiration == 3, "通过排期正常进入下一回合并恢复步数")
	while scene.work_panel.playing:
		await process_frame
	scene.work_panel.close()
	scene.open_character("b")
	exhausted_style = task_button.get_theme_stylebox("normal") as StyleBoxFlat
	check(exhausted_style.bg_color == Color("2a6965") and not scene.member_sheet.task_notice.visible, "下一回合按钮恢复颜色并清除提示")
	await click(task_button.get_global_rect().get_center())
	check(scene.task_panel.visible and scene.task_panel.task_buttons.is_empty(), "步数恢复后允许打开列表，已完成年度任务仍隐藏")
	scene.task_panel.close()
	scene.state.year = 2
	scene.state.month = 1
	scene.state.action_steps = 1
	var next_year := Model.select_project(scene.state, "第二年", "act", "modern", 2)
	check(next_year.ok, "次年开始新的年度作品")
	scene.state = next_year.state
	scene.open_tasks()
	check(scene.task_panel.task_buttons.size() == 1, "新年重新显示任务")
	await click(scene.task_panel.task_buttons[0].get_global_rect().get_center())
	await click(confirm.confirm_button.get_global_rect().get_center())
	check(execution.playing and execution.progress.value < 100 and execution.results_label.text.is_empty(), "再次执行重置进度与右侧结果")
	while execution.playing:
		await process_frame
	await click(execution.finish_button.get_global_rect().get_center())
	scene.open_schedule()
	scene.duty_panel.next_turn_button.pressed.emit()
	check(scene.work_panel.report.work.has("p"), "下一回合职责结算保留任务表现力")
	scene.queue_free()
	await process_frame
	SkillFixture.restore(skill_definitions)
	print("Task assignment: %d checks, %d failures" % [checks, failures])
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
