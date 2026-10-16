extends SceneTree
const Roster = preload("res://tests/fixtures/roster_fixture.gd")
const Model = preload("res://scripts/game_model.gd")
const SkillTable = preload("res://scripts/skills/skill_table.gd")
const SkillDefinition = preload("res://scripts/skills/skill_definition.gd")
var checks := 0
var failures := 0

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
	var initial: Dictionary = Model.select_project(Roster.fresh(), "邀约测试", "act", "modern", 1).state
	var result := Model.execute_invite(initial, 0, 1, 1)
	check(result.ok and result.state.members[0].affinity == 10, "邀约固定提升十好感")
	check(initial.members[0].affinity == 0 and initial.action_steps == 1, "邀约不修改输入状态")
	check(result.state.action_steps == 0 and result.state.month == 1 and result.state.year == 1, "邀约消费共享一步、不推进日历")
	check(result.state.work == initial.work and result.state.inspiration == initial.inspiration, "邀约不结算职责或月灵感")
	check(not result.state.has("completed_tasks") and result.report.kind == "invite", "邀约不写入年度任务次数")
	check(Model.valid_state(result.state), "邀约状态校验通过")
	check(not Model.execute_invite(result.state, 1, 1, 1).ok, "更换邀约成员不能绕过步数")
	check(not Model.execute_task(result.state, 1, "art_concept", 1, 1).ok, "邀约后不能分配任务")
	var task := Model.execute_task(initial, 0, "art_concept", 1, 1)
	check(not Model.execute_invite(task.state, 1, 1, 1).ok, "任务后不能邀约")
	check(not Model.execute_invite(initial, -1, 1, 1).ok and not Model.execute_invite(initial, Model.DEFINITIONS.size(), 1, 1).ok, "拒绝无效邀约成员")
	check(not Model.execute_invite(initial, 0, 2, 1).ok and not Model.execute_invite(initial, 0, 1, 2).ok, "拒绝陈旧年月")
	for phase in ["report", "ending"]:
		var blocked := initial.duplicate(true)
		blocked.phase = phase
		check(not Model.execute_invite(blocked, 0, 1, 1).ok, "非准备阶段不允许邀约")
	var advanced := Model.advance_work(result.state, 1, 1)
	var repeated := Model.execute_invite(advanced.state, 0, 1, 2)
	check(repeated.ok and repeated.state.members[0].affinity == 20, "下一回合可再次邀约，同人连续邀约仍增加十好感")
	advanced = Model.advance_work(repeated.state, 1, 2)
	var other := Model.execute_invite(advanced.state, 1, 1, 3)
	check(other.ok and other.state.members[1].affinity == 10, "更换邀约成员同样增加十好感")
	advanced = Model.advance_work(task.state, 1, 1)
	check(Model.execute_invite(advanced.state, 0, 1, 2).ok, "已完成年度任务仍可邀约")
	var capped := initial.duplicate(true)
	capped.members[0].affinity = 49
	result = Model.execute_invite(capped, 0, 1, 1)
	check(result.state.members[0].affinity == 50, "邀约好感不超过五十")
	capped.members[0].affinity = 50
	result = Model.execute_invite(capped, 0, 1, 1)
	check(result.ok and result.state.members[0].affinity == 50 and result.state.action_steps == 0, "满好感邀约产出零且正常消费一步")
	var slot_id: String = Model.DEFINITIONS[0].skills[0].skill_id
	var original_skill = SkillTable.skills[slot_id]
	var row := {"id": slot_id, "name": "邀约测试", "description": "测试", "quip": "收到邀约",
		"acquisition": "auto", "inspiration_cost": 0, "triggers": [
			trigger("ACTION_BEFORE", "actor", "affinity", 3, "invite"),
			trigger("ACTION_AFTER", "shared", "inspiration", 2, "invite"),
			trigger("ACTION_BEFORE", "work", "g", 99, "task")]}
	check(SkillDefinition.validate(row).is_empty(), "邀约技能配置有效")
	SkillTable.skills[slot_id] = SkillDefinition.from_row(row)
	result = Model.execute_invite(initial, 0, 1, 1)
	check(result.state.members[0].affinity == 13 and result.report.inspiration_delta == 2 and result.report.skill_events.size() == 2, "邀约固定十点基础产出后技能生效并记入报告")
	check(result.state.work.g == 0, "任务限定技能不触发于邀约")
	SkillTable.skills[slot_id] = original_skill
	var scene = load("res://scenes/interface_shell.tscn").instantiate()
	root.add_child(scene)
	for frame in 4:
		await process_frame
	scene.state = Model.select_project(Roster.fresh(), "邀约界面测试", "act", "modern", 1).state
	scene.show_main()
	scene.open_character("a")
	var button: Button = scene.member_sheet.invite_button
	check(button.text == "邀约" and button.visible, "人物页显示邀约按钮")
	check(is_equal_approx(button.get_global_rect().position.y, scene.member_sheet.task_button.get_global_rect().position.y), "邀约与分配任务按钮同行")
	var snapshot: Dictionary = scene.state.duplicate(true)
	await click(button.get_global_rect().get_center())
	var confirm = root.get_node("TextConfirm")
	check(confirm.screen.visible and confirm.text_label.text.contains("邀约 a"), "邀约使用通用确认框")
	scene.open_invite()
	check(scene.invite_pending and scene.state == snapshot, "重复请求不重复弹窗或结算")
	await click(confirm.cancel_button.get_global_rect().get_center())
	check(not scene.invite_pending and scene.state == snapshot and not confirm.screen.visible and scene.character_screen.visible, "取消邀约不消费步数，返回人物页")
	await click(button.get_global_rect().get_center())
	await click(confirm.confirm_button.get_global_rect().get_center())
	var execution = scene.task_execution
	check(execution.visible and execution.title_label.text.contains("邀约") and execution.playing, "邀约复用任务执行界面")
	check(execution.progress.value < 100 and execution.results_label.text.is_empty() and execution.finish_button.disabled, "邀约进度前右侧空白且不能提前关闭")
	check(scene.state.month == 1 and scene.state.action_steps == 0 and scene.state.members[0].affinity == 10, "确认邀约立即提交一次且不推进月份")
	scene.open_invite()
	scene.open_tasks()
	scene.open_character("b")
	check(scene.state.members[0].affinity == 10 and not scene.task_panel.visible and not confirm.screen.visible, "播放期间阻止重复邀约和其他入口")
	await create_timer(0.35).timeout
	check(execution.progress.value > 0 and execution.progress.value < 100 and execution.results_label.text.is_empty(), "邀约共用真实一秒进度条")
	while execution.playing:
		await process_frame
	check(execution.results_label.text.contains("a 好感度 +10") and not execution.results_label.text.contains("表现力") and not execution.results_label.text.contains("任务产出"), "只展示邀约结果，不显示无关任务产出")
	if DisplayServer.get_name() != "headless":
		await process_frame
		root.get_texture().get_image().save_png("res://qa/invite_results.png")
	await click(execution.finish_button.get_global_rect().get_center())
	scene.open_character("b")
	for action_button in [scene.member_sheet.task_button, button]:
		var style := action_button.get_theme_stylebox("normal") as StyleBoxFlat
		check(style.bg_color == Color("a4aaa4"), "共享步数耗尽后两个按钮都变灰")
	await click(button.get_global_rect().get_center())
	check(scene.member_sheet.task_notice.visible and not confirm.screen.visible, "无步数邀约点击显示已有行动小提示框")
	await click(scene.member_sheet.task_notice_box.get_global_rect().get_center())
	scene.close_character()
	scene.open_schedule()
	await process_frame
	await click(scene.duty_panel.next_turn_button.get_global_rect().get_center())
	check(scene.state.month == 2 and scene.state.action_steps == 1, "邀约后通过排期推进并恢复步数")
	for resolution in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		for frame in 4:
			await process_frame
		check(scene.get_global_rect().encloses(button.get_global_rect()), "各分辨率邀约按钮不超出人物页")
	scene.queue_free()
	await process_frame
	print("Invite: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func trigger(hook: String, target: String, field: String, amount: int, kind: String) -> Dictionary:
	return {"hook": hook, "conditions": {"action_kind": kind}, "target": target, "frequency": "event",
		"effect_id": "numeric_modifier", "params": {"field": field, "operation": "add", "amount": amount}, "priority": 0}

func click(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame
