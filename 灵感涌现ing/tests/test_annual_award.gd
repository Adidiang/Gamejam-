extends SceneTree
## 年度评奖检查：BUG灾难 概率与特质折半、奖项门槛与顺序、年度档案与跨年清空、评奖界面播放。
## 评奖判定与分数在 ClubGame 年末结算时完成，界面只负责依次展示，本测试同时覆盖两处。

const Model = preload("res://scripts/game_model.gd")
const SkillFixture = preload("res://tests/fixtures/skill_fixture.gd")
var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func near(a: float, b: float) -> bool:
	return absf(a - b) < 0.00001

func award_ids(awards: Array) -> Array:
	return awards.map(func(award: Dictionary): return award.id)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var skill_definitions := SkillFixture.without_effects()
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1440, 900)
	var definitions: Array = Model.DEFINITIONS.duplicate(true)
	for id in 4:
		Model.DEFINITIONS[id].stats = [0.0, 0.0, 0.0, 0.0]
	check(near(Model.bug_disaster_probability(0.0), 0.0) and near(Model.bug_disaster_probability(20.0), 0.0), "20 只 Bug 以内不判定")
	check(near(Model.bug_disaster_probability(20.9), 0.0) and near(Model.bug_disaster_probability(21.0), 0.01), "小数向下取整后 21 只对应 1%")
	check(near(Model.bug_disaster_probability(50.0), 0.30) and near(Model.bug_disaster_probability(99.0), 0.79), "21～100 与概率一一对应")
	check(near(Model.bug_disaster_probability(100.0), 0.80) and near(Model.bug_disaster_probability(101.0), 0.80) and near(Model.bug_disaster_probability(1000.0), 0.80), "超过 100 恒为 80%")

	var work := {"g": 600.0, "i": 1000.0, "p": 400.0, "b": 0.0}
	var points: Dictionary = Model.annual_score(work)
	check(near(points.g, 600.0) and near(points.i, 1000.0) and near(points.p, 400.0), "年度分项直接取作品属性")
	var full := {"g": 6000.0, "i": 4000.0, "p": 4000.0, "bonus": 0.0}
	var awards: Array = Model.annual_awards(Model.finalize_annual_score(full, false))
	check(award_ids(awards) == ["best_game_nomination", "best_art", "best_game"], "达标作品同时获得三个奖项并按顺序排列")
	check(Model.award_reward(awards) == 100, "三个奖项灵感奖励为 20 + 30 + 50")
	var only_nomination: Array = Model.annual_awards(Model.finalize_annual_score({"g": 1500.0, "i": 1000.0, "p": 600.0, "bonus": 0.0}, false))
	check(award_ids(only_nomination) == ["best_game_nomination"], "三项之和达到 3000 只获得提名")
	check(Model.annual_awards(Model.finalize_annual_score({"g": 1500.0, "i": 1000.0, "p": 400.0, "bonus": 0.0}, false)).is_empty(), "三项之和不足 3000 不获奖")
	check(award_ids(Model.annual_awards(Model.finalize_annual_score({"g": 3000.0, "i": 3000.0, "p": 4000.0, "bonus": 0.0}, false))) == ["best_game_nomination", "best_art"], "表现力达标但游戏性加创新性不足 10000 时不获最佳游戏")
	check("best_game" in award_ids(Model.annual_awards(Model.finalize_annual_score({"g": 6000.0, "i": 4000.0, "p": 2000.0, "bonus": 0.0}, false))), "游戏性加创新性达到 10000 且表现力达到 2000 获最佳游戏")
	var ruined: Dictionary = Model.finalize_annual_score(full, true)
	check(near(ruined.total, 7000.0) and near(ruined.pair, 5000.0) and near(ruined.p, 2000.0) and near(ruined.factor, 0.5), "BUG灾难 把各分项与各项之和各减半一次")
	check(ruined.trait == "BUG灾难" and award_ids(Model.annual_awards(ruined)) == ["best_game_nomination"], "折半后只剩提名，拿不到最佳美术与最佳游戏")

	## 用有限次尝试找到命中 80% 判定的作品，验证灾难从判定到归档的完整路径。
	var disaster_state: Dictionary = {}
	for attempt in 60:
		var candidate: Dictionary = Model.select_project(Model.fresh(), "灾难测试", "act", "fantasy", 1).state
		candidate.month = 12
		candidate.work = {"g": 6000.0, "i": 4000.0, "p": 2000.0, "b": 100.0}
		if Model.bug_disaster_roll(candidate):
			disaster_state = candidate
			break
	check(not disaster_state.is_empty(), "80% 判定在有限次尝试内可以命中")
	var repeated := Model.advance_work(disaster_state, 1, 12)
	var again := Model.advance_work(disaster_state, 1, 12)
	check(repeated.ok and JSON.stringify(repeated.report.annual) == JSON.stringify(again.report.annual), "同一作品不会重抽 BUG灾难 与奖项")
	var annual: Dictionary = repeated.report.annual
	check(annual.bug_disaster and annual.trait == "BUG灾难" and near(annual.bug_probability, 0.8), "命中后作品获得特质 BUG灾难")
	check(near(annual.score.total, 6000.0) and near(annual.score.pair, 5000.0) and near(annual.score.p, 1000.0), "灾难评分等于原分数与各项之和各 ×0.5")
	check(award_ids(annual.awards) == ["best_game_nomination"] and annual.reward == 20, "灾难后只剩提名及其 20 灵感")
	check(repeated.state.inspiration == disaster_state.inspiration + 1 + 20, "年末灵感 = 每月灵感 + 奖项奖励")
	check(near(annual.work.g, 6000.0) and near(annual.work.b, 100.0), "年度档案保留本年作品快照")
	var healthy: Array = Model.annual_awards(Model.finalize_annual_score(Model.annual_score(annual.work), false))
	check(award_ids(healthy) == ["best_game_nomination", "best_game"], "同一作品没有灾难时会拿到提名与最佳游戏")
	check(near(repeated.state.work.g, 0.0) and near(repeated.state.work.b, 0.0) and near(repeated.state.work.p, 0.0), "跨年后新作品产出与 Bug 从零开始")
	check(Model.valid_state(repeated.state) and Model.needs_project_selection(repeated.state), "评奖后状态可存档并等待次年立项")

	var good: Dictionary = Model.select_project(Model.fresh(), "无灾难", "rpg", "sci_fi", 1).state
	good.month = 12
	good.work = {"g": 6000.0, "i": 4000.0, "p": 4000.0, "b": 0.0}
	var good_result := Model.advance_work(good, 1, 12)
	check(not good_result.report.annual.bug_disaster and good_result.report.annual.trait == "" and near(good_result.report.annual.bug_probability, 0.0), "20 只 Bug 以内不会触发 BUG灾难")
	check(near(good_result.report.annual.score.p, 4000.0) and near(good_result.report.annual.score.pair, 10000.0) and good_result.report.annual.awards.size() == 3 and good_result.report.annual.reward == 100, "无灾难达标作品同获三奖并发放 100 灵感")
	var second: Dictionary = Model.select_project(good_result.state, "第二年作品", "act", "fantasy", 2).state
	check(Model.project_for_year(second, 1).title == "无灾难" and Model.project_for_year(second).title == "第二年作品", "两年作品档案独立")
	check(near(Model.annual_result_for_year(second, 1).score.total, 14000.0) and Model.annual_result_for_year(second, 1).awards.size() == 3, "第一年评奖结果保留在年度档案")
	check(Model.valid_state(JSON.parse_string(JSON.stringify(second))), "评奖档案 JSON 往返后仍有效")
	var missing: Dictionary = second.duplicate(true)
	missing.annual_results.erase("1")
	check(not Model.valid_state(missing), "缺少已结算年度的评奖档案会被拒绝")
	var broken: Dictionary = second.duplicate(true)
	broken.annual_results["1"].awards[0].id = "unknown_award"
	check(not Model.valid_state(broken), "评奖档案中的非法奖项被拒绝")

	Model.DEFINITIONS[0].stats = [10.0, 100.0, 20.0, 10.0]
	var task_state: Dictionary = Model.select_project(Model.fresh(), "美术任务", "act", "modern", 1).state
	var task_factor := Model.task_output_factor(task_state, 0, "art_concept")
	var executed := Model.execute_task(task_state, 0, "art_concept", 1, 1)
	check(executed.ok and absf(float(executed.state.work.p) - 120.0 * task_factor) < 0.0001, "美术概念设计经转换单元后写入表现力")
	var repeat := Model.execute_task(executed.state, 0, "art_concept", 1, 1)
	check(not repeat.ok and absf(float(executed.state.work.p) - 120.0 * task_factor) < 0.0001, "同年重复任务被拒绝且不重复累计")
	Model.DEFINITIONS[0].stats = [0.0, 0.0, 0.0, 0.0]

	var scene = load("res://scenes/interface_shell.tscn").instantiate()
	root.add_child(scene)
	for frame in 4:
		await process_frame
	var opening: Dictionary = Model.select_project(Model.fresh(), "评奖界面测试", "act", "fantasy", 1).state
	opening.month = 12
	opening.work = {"g": 6000.0, "i": 4000.0, "p": 4000.0, "b": 0.0}
	scene.state = opening
	scene.show_main()
	await process_frame
	scene.open_schedule()
	await process_frame
	scene.duty_panel.next_turn_button.pressed.emit()
	await process_frame
	check(scene.work_panel.visible and not scene.award_screen.visible, "十二月结算先展示工作报告")
	var award = scene.award_screen
	var started := Time.get_ticks_msec()
	while scene.work_panel.playing and Time.get_ticks_msec() - started < 15000:
		await process_frame
	scene.work_panel.finish_button.pressed.emit()
	await process_frame
	check(award.visible and not scene.work_panel.visible and award.steps.size() == 3, "工作确认后自动打开评奖界面，只保留获奖页")
	check(award.step_title.text == "最佳游戏提名" and award.progress_label.text == "第 1 / 3 步", "按顺序从最佳游戏提名开始弹出")
	check(award.step_body.text == "灵感 +20", "获奖页只显示奖项与对应灵感")
	scene.open_schedule()
	scene.open_character("a")
	check(not scene.duty_panel.visible and not scene.character_screen.visible, "评奖期间不能打开排期或人物页")
	award.continue_button.pressed.emit()
	await process_frame
	check(award.step_title.text == "最佳美术" and award.step_body.text == "灵感 +30", "第二步展示最佳美术及对应灵感")
	award.continue_button.pressed.emit()
	await process_frame
	check(award.step_title.text == "最佳游戏" and award.step_body.text == "灵感 +50" and award.continue_button.text == "进入下一年", "第三步展示最佳游戏及对应灵感")
	for resolution in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		for frame in 4:
			await process_frame
		check(scene.get_global_rect().encloses(award.continue_button.get_global_rect()), "%s 下评奖按钮在画面内" % resolution)
		check(award.get_global_rect().encloses(award.card.get_global_rect()), "%s 下奖项卡片在画面内" % resolution)
	root.size = Vector2i(1440, 900)
	for frame in 4:
		await process_frame
	await create_timer(0.35).timeout
	if DisplayServer.get_name() != "headless":
		await process_frame
		root.get_texture().get_image().save_png("res://qa/annual_award.png")
	award.continue_button.pressed.emit()
	await process_frame
	check(not award.visible and scene.game_selection.visible and scene.game_selection.selection_year == 2, "评奖结束后进入次年选择页")
	check(scene.inspiration_label.text == "灵感 %d" % int(scene.state.inspiration) and scene.state.work.g == 0.0, "结算后主界面显示新灵感与新作品归零")

	var sample: Dictionary = award.annual.duplicate(true)
	sample.bug_disaster = true
	sample.trait = "BUG灾难"
	sample.bug_probability = 0.8
	sample.score.trait = "BUG灾难"
	sample.score.factor = 0.5
	sample.score.total = 7000.0
	sample.score.pair = 5000.0
	sample.work.b = 100.0
	award.open(sample)
	await process_frame
	check(award.step_title.text == "「BUG灾难」" and award.steps.size() == 4, "命中灾难时先弹出 BUG灾难 提示")
	check(award.step_body.text.contains("收到玩家反映，大量BUG造成了灾难性的体验......"), "灾难提示使用指定文本")
	check(award.step_body.text.contains("特质「BUG灾难」") and not award.step_body.text.contains("触发概率"), "灾难提示只显示特质与分数折半")
	award.close()
	await process_frame
	check(not award.visible, "评奖界面可以关闭")
	scene.queue_free()
	await process_frame
	Model.DEFINITIONS = definitions
	SkillFixture.restore(skill_definitions)
	print("Annual award: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
