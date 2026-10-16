extends SceneTree
const Roster = preload("res://tests/fixtures/roster_fixture.gd")
const Model = preload("res://scripts/game_model.gd")
const Catalog = preload("res://scripts/game_catalog.gd")
const Store = preload("res://scripts/save_store.gd")
const SkillDefinition = preload("res://scripts/skills/skill_definition.gd")
const SkillTable = preload("res://scripts/skills/skill_table.gd")
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
	var initial := Roster.fresh()
	check(Model.valid_state(initial) and Model.needs_project_selection(initial), "年初待选择状态可存档")
	check(not Model.advance_work(initial, 1, 1).ok and Model.available_tasks(initial).is_empty() and not Model.execute_invite(initial, 0, 1, 1).ok, "未选择作品时拒绝工作和行动")
	for bad in [["  ", "act", "fantasy"], ["名字", "unknown", "fantasy"], ["名字", "act", "unknown"], ["多\n行", "act", "fantasy"]]:
		check(not Model.select_project(initial, bad[0], bad[1], bad[2], 1).ok, "拒绝无效作品资料")
	check(not Model.select_project(initial, "名字", "act", "fantasy", 2).ok, "拒绝过期年份")
	var long_title := "自由输入的很长的游戏名字 / 中文 English 2026 · 星海与纸飞机"
	var result := Model.select_project(initial, "  " + long_title + "  ", "narrative", "sci_fi", 1)
	check(result.ok and initial.annual_projects.is_empty() and initial.phase == "setup", "确认不修改输入状态")
	var state: Dictionary = result.state
	var first := Model.project_for_year(state)
	check(first.title == long_title and first.genre_id == "narrative" and first.topic_id == "sci_fi", "保留完整名字与稳定 ID，不截断或保存按钮序号")
	check(not Model.select_project(state, "重复", "act", "fantasy", 1).ok, "当年确认不可重复或覆盖")
	first.title = "修改副本"
	check(Model.project_for_year(state).title == long_title, "读取作品返回隔离副本")
	var metadata := Model._metadata(state)
	check(metadata.title == long_title and metadata.genre == "剧情向" and metadata.topic == "科幻" and metadata.genre_id == "narrative", "技能统一读取当年作品及类型题材")
	check(Model.valid_state(JSON.parse_string(JSON.stringify(state))), "JSON 往返后档案仍有效")
	check(Store.save_run(state, "res://qa/annual_project.json") == OK, "现有存档层保存作品档案")
	var loaded := Store.load_run("res://qa/annual_project.json")
	check(Model.valid_state(loaded) and loaded.annual_projects == JSON.parse_string(JSON.stringify(state.annual_projects)), "现有存档层完整恢复作品档案")
	var corrupted := state.duplicate(true)
	corrupted.annual_projects["1"].genre_id = "missing"
	check(not Model.valid_state(corrupted), "损坏存档中的非法 ID 被拒绝")
	corrupted = state.duplicate(true)
	corrupted.annual_project_schema = 2
	check(not Model.valid_state(corrupted), "未知档案版本被拒绝")
	corrupted = state.duplicate(true)
	corrupted.annual_projects["1"].id = "other-run"
	check(not Model.valid_state(corrupted), "错误的作品标识被拒绝")
	state.month = 12
	state.work.g = 42.0
	state.members[0].affinity = 20
	result = Model.advance_work(state, 1, 12)
	check(result.ok and result.report.project.title == long_title and Model.needs_project_selection(result.state), "十二月报告保留旧作品，次年待选择")
	state = result.state
	check(Model.valid_state(state), "跨年等待选择也能存档")
	result = Model.select_project(state, "次年游戏", "rpg", "historical", 2)
	state = result.state
	check(Model.project_for_year(state, 1).title == long_title and Model.project_for_year(state).title == "次年游戏", "两年作品档案独立保留")
	var finished: Dictionary = Model.annual_result_for_year(state, 1)
	check(finished.work.g >= 42.0 and finished.project.title == long_title, "跨年后第一年作品与产出归档到年度评奖记录")
	check(state.work.g == 0.0 and state.members[0].affinity == 20, "新作品产出从零开始，好感与档案保留")
	check(Store.save_run(state, "res://qa/annual_project.json") == OK, "多年度档案保存")
	loaded = Store.load_run("res://qa/annual_project.json")
	check(Model.valid_state(loaded) and loaded.annual_projects == JSON.parse_string(JSON.stringify(state.annual_projects)), "多年度档案恢复")
	for year in [2, 3]:
		state.month = 12
		state = Model.advance_work(state, year, 12).state
		state = Model.select_project(state, "第%d年游戏" % (year + 1), "strategy", "modern", year + 1).state
	check(Model.valid_state(state) and state.annual_projects.size() == 4, "当前未接入三年结束流程，日历继续时档案仍有效")
	var skill_state := state.duplicate(true)
	skill_state.skill_runtime.temporary.append({"owner_id": Model.DEFINITIONS[0].id,
		"skill_id": Model.DEFINITIONS[0].skills[0].skill_id, "name": "临时效果", "quip": "",
		"target": "work", "apply_hook": "DUTY_BEFORE", "params": {"field": "g", "operation": "add", "amount": 1.0},
		"year": 4, "month": 1, "duration": "year"})
	check(Model.valid_state(skill_state), "年度档案的存档校验允许当前年份的临时技能效果")
	var skill_id: String = Model.DEFINITIONS[0].skills[0].skill_id
	var skill_row := {"id": skill_id, "name": "年度作品识别", "description": "", "quip": "",
		"acquisition": "auto", "inspiration_cost": 0, "triggers": [{"hook": "PROJECT_AFTER",
		"conditions": {"genre_id": "narrative", "topic_id": "sci_fi"}, "target": "shared", "frequency": "year",
		"effect_id": "numeric_modifier", "params": {"field": "inspiration", "operation": "add", "amount": 3.0}, "priority": 0}]}
	check(SkillDefinition.validate(skill_row).is_empty(), "技能配置接受稳定的类型题材 ID")
	var original_skill = SkillTable.skills[skill_id]
	SkillTable.skills[skill_id] = SkillDefinition.from_row(skill_row)
	var matching: Dictionary = Model.select_project(Roster.fresh(), "条件测试", "narrative", "sci_fi", 1).state
	check(matching.inspiration == 5 and not matching.skill_log.is_empty(), "立项技能实际按类型题材 ID 触发")
	var not_matching: Dictionary = Model.select_project(Roster.fresh(), "条件测试", "narrative", "fantasy", 1).state
	check(not_matching.inspiration == 2, "不匹配题材时不触发立项技能")
	check(not Model.select_project(matching, "重复确认", "narrative", "sci_fi", 1).ok and matching.inspiration == 5, "重复确认不能重复发放立项技能收益")
	matching.month = 12
	matching = Model.advance_work(matching, 1, 12).state
	matching = Model.select_project(matching, "次年条件测试", "narrative", "sci_fi", 2).state
	check(matching.inspiration == 9, "次年立项重新触发年度技能且共用全局灵感")
	SkillTable.skills[skill_id] = original_skill
	skill_row.triggers[0].conditions.genre_id = "unknown"
	check(not SkillDefinition.validate(skill_row).is_empty(), "技能配置中的非法类型 ID 被拒绝")
	for genre in Catalog.GENRES:
		for topic in Catalog.TOPICS:
			check(Model.select_project(Roster.fresh(), "组合", genre.id, topic.id, 1).ok, "6×5 种组合全部有效")
	var scene = load("res://scenes/interface_shell.tscn").instantiate()
	root.add_child(scene)
	for frame in 4:
		await process_frame
	check(scene.start_screen.visible and not scene.game_selection.visible, "初始保留开始页")
	Roster.select_starting_pair(scene)
	scene.start_button.pressed.emit()
	Roster.recruit_all(scene.state)
	scene.open_game_selection()
	await process_frame
	var screen = scene.game_selection
	check(screen.visible and not scene.main_screen.visible and screen.get_global_rect() == scene.get_global_rect(), "开始游戏进入全屏选择页")
	check(screen.genre_buttons.size() == 6 and screen.topic_buttons.size() == 5, "显示指定的全部选项")
	check(screen.confirm_button.disabled, "空白草稿不可确认")
	screen.title_input.text = "  UI 测试游戏  "
	screen.title_input.text_changed.emit(screen.title_input.text)
	screen.genre_buttons[0].pressed.emit()
	screen.topic_buttons[4].pressed.emit()
	screen.genre_buttons[5].pressed.emit()
	check(screen.genre_buttons[5].button_pressed and not screen.genre_buttons[0].button_pressed, "类型只能单选且可切换")
	check(not screen.confirm_button.disabled and screen.preview_label.text.contains("剧情向") and screen.preview_label.text.contains("惊悚"), "预览实时刷新并允许确认")
	## 立项好感预览：人物 a 的题材偏好为“奇幻、科幻”，b／c／d 未填写偏好。
	screen.topic_buttons[0].pressed.emit()
	check(screen.affinity_label.text.contains(Model.DEFINITIONS[0].name) and screen.affinity_label.text.contains("+%d" % Model.PREFERENCE_AFFINITY), "选择命中偏好的题材时实时显示加好感的成员与增量")
	check(screen.affinity_label.text.contains("题材") and not screen.affinity_label.text.contains(Model.DEFINITIONS[1].name), "只列出命中偏好的成员并说明命中来源")
	screen.topic_buttons[4].pressed.emit()
	check(screen.affinity_label.text.contains("没有成员命中"), "未命中偏好时明确提示无人加好感")
	for resolution in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(900, 700)]:
		root.size = resolution
		for frame in 5:
			await process_frame
		check(scene.get_global_rect().encloses(screen.title_input.get_global_rect()), "多分辨率下输入框可见")
		check(scene.get_global_rect().encloses(screen.confirm_button.get_global_rect()), "多分辨率下确认按钮可见")
		for button in screen.genre_buttons + screen.topic_buttons:
			check(scene.get_global_rect().encloses(button.get_global_rect()), "多分辨率下选项不溢出")
	root.size = Vector2i(1440, 900)
	for frame in 5:
		await process_frame
	if DisplayServer.get_name() != "headless":
		await process_frame
		root.get_texture().get_image().save_png("res://qa/game_selection.png")
	screen.confirm_button.pressed.emit()
	await process_frame
	check(scene.main_screen.visible and not screen.visible and Model.project_for_year(scene.state).title == "UI 测试游戏", "确认写入模型并进入主界面")
	var snapshot: Dictionary = scene.state.duplicate(true)
	screen.confirm_button.pressed.emit()
	check(scene.state == snapshot, "隐藏界面的重复请求不生效")
	scene.state.month = 12
	scene.open_schedule()
	scene.duty_panel.next_turn_button.pressed.emit()
	await process_frame
	check(scene.work_panel.visible and not screen.visible and scene.work_panel.report.project.title == "UI 测试游戏", "跨年先展示十二月旧作品工作报告")
	# 等真实播放结束，避免跳过生产流程。
	var started := Time.get_ticks_msec()
	while scene.work_panel.playing and Time.get_ticks_msec() - started < 35000:
		await process_frame
	scene.work_panel.finish_button.pressed.emit()
	await process_frame
	var award = scene.award_screen
	check(award.visible and not screen.visible and award.step_title.text == "本年度未获奖" and award.step_body.text.is_empty(), "工作确认后进入评奖界面，未获奖不显示灵感")
	check(Model.annual_result_for_year(scene.state, 1).project.title == "UI 测试游戏", "评奖结果写入年度档案")
	check(award.steps.size() == 1 and award.continue_button.text == "进入下一年", "未获奖只有一页评奖界面")
	## 把人物 a 顶到上限，验证次年选择页按上限显示真实增量。
	scene.state.members[0].affinity = Model.AFFINITY_MAX
	award.continue_button.pressed.emit()
	await process_frame
	check(not award.visible and screen.visible and not scene.main_screen.visible and screen.selection_year == 2, "评奖结束后自动进入次年选择界面")
	check(screen.title_input.text.is_empty() and screen.genre_id.is_empty() and screen.topic_id.is_empty() and screen.confirm_button.disabled, "次年草稿清空，不沿用旧作品资料")
	scene.open_schedule()
	scene.open_character("a")
	check(not scene.duty_panel.visible and not scene.character_screen.visible, "年初未确认不可绕过选择页")
	## 满好感成员不会再加偏好好感：预览要按上限如实标注，避免“显示 +10、实际 +0”。
	screen.topic_buttons[0].pressed.emit()
	check(screen.affinity_label.text.contains("好感已满") and not screen.affinity_label.text.contains(Model.DEFINITIONS[0].name + " +"), "满好感成员的偏好奖励在预览中标注为已满")
	var capped_screen = load("res://scripts/game_selection_screen.gd").new()
	root.add_child(capped_screen)
	capped_screen.open(2, [Model.AFFINITY_MAX - 5, 0, 0, 0], [true, true, true, true])
	capped_screen.topic_buttons[0].pressed.emit()
	check(capped_screen.affinity_label.text.contains("+5") and capped_screen.affinity_label.text.contains("受上限 %d 限制" % Model.AFFINITY_MAX), "接近上限时预览显示上限内的真实增量")
	capped_screen.queue_free()
	screen.title_input.text = "第二年的游戏"
	screen.title_input.text_changed.emit(screen.title_input.text)
	screen.genre_buttons[2].pressed.emit()
	screen.topic_buttons[0].pressed.emit()
	screen.confirm_button.pressed.emit()
	check(scene.main_screen.visible and scene.state.year == 2 and Model.project_for_year(scene.state, 1).title == "UI 测试游戏", "次年确认进入主界面并保留第一年档案")
	scene.queue_free()
	await process_frame
	print("Game selection: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
