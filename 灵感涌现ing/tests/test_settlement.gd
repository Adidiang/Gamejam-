extends SceneTree
## 完整 36 回合终点、独立结算分、排行榜、终局存档与两页实际界面。
const Model = preload("res://scripts/game_model.gd")
const Ranking = preload("res://scripts/settlement_ranking.gd")
const Store = preload("res://scripts/save_store.gd")
const Debug = preload("res://scripts/debug/debug_tools.gd")
const SkillFixture = preload("res://tests/fixtures/skill_fixture.gd")
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
	var skills := SkillFixture.without_effects()
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1440, 900)
	var state := Model.fresh()
	var final_opening: Dictionary = {}
	var turns := 0
	var works := [
		{"g": 100.9, "i": 200.2, "p": 300.4, "b": 10.2},
		{"g": 0.0, "i": 0.0, "p": 0.0, "b": 100.0},
		{"g": 1000.4, "i": 2000.5, "p": 3000.6, "b": 2.3},
	]
	check(Model.settlement_summary(state).is_empty(), "三年未结束时不能生成终局总结")
	for year in range(1, 4):
		state = Model.select_project(state, "第%d年的作品" % year, "rpg", "modern", year).state
		for month in range(1, 13):
			if month == 12: state.work = works[year - 1].duplicate(true)
			if year == 3 and month == 12: final_opening = state.duplicate(true)
			var turn := Model.advance_work(state, year, month)
			check(turn.ok, "第%d年%d月可以推进" % [year, month])
			state = turn.state
			turns += 1
			check(int(state.year) <= 3 and Model.valid_state(state), "回合后状态合法且日历不超过第三年")
	check(turns == 36 and Model.is_finished(state) and state.year == 3 and state.month == 12, "恰好 36 回合停在第三年十二月")
	check(state.annual_projects.size() == 3 and state.annual_results.size() == 3 and not state.recruitment.has("4"), "只有三个项目及结果，不生成第四年招募")
	check(not Model.needs_project_selection(state) and state.action_steps == 0, "终局没有待立项或行动步数")
	var snapshot := JSON.stringify(state)
	check(not Model.advance_work(state, 3, 12).ok and not Model.advance_work(state, 4, 1).ok, "终局重复结算和第四年推进均被拒绝")
	check(not Model.select_project(state, "第四款", "rpg", "fantasy", 4).ok and not Model.select_project(state, "覆盖", "rpg", "fantasy", 3).ok, "终局不能第四年立项或覆盖第三年")
	state.members[0].recruited = true
	check(Model.assign(state, 0, 1) == state and Model.learn(state, 0, 0) == state, "终局拒绝职责调整和技能学习")
	check(not Model.execute_invite(state, 0, 3, 12).ok and not Model.execute_task(state, 0, "art_concept", 3, 12).ok, "终局拒绝邀约和任务")
	check(not Debug.change_work(state, "g", "add", 100).ok and not Debug.jump_month(state, 12).ok and not Debug.set_full_affinity(state, true, []).ok, "终局拒绝调试修改")
	state.members[0].recruited = false
	check(JSON.stringify(state) == snapshot, "被拒绝的操作不改写终局数据")
	var summary := Model.settlement_summary(state)
	check(summary.projects.size() == 3 and absf(summary.projects[0].score - 499.5) < 0.00001, "单项目按原始小数先合计再扣十倍 Bug")
	check(summary.projects[1].score == -1000.0, "负得分不截断为零")
	check(absf(summary.total - 5478.0) < 0.00001, "排行榜总分是三年得分相加，不提前取整")
	summary.projects[0].project.title = "修改副本"
	summary.projects[0].work.g = 0.0
	check(JSON.stringify(state) == snapshot, "结算展示快照与年度档案隔离")
	var altered := state.duplicate(true)
	altered.annual_results["3"].score.total = 999999.0
	altered.annual_results["3"].bug_disaster = true
	check(Model.settlement_summary(altered).total == Model.settlement_summary(state).total, "评奖分、技能 bonus 与灾难折半均不参与总结算")
	check(Store.save_run(state, "res://qa/settlement.json") == OK, "终局可保存")
	var restored := Store.load_run("res://qa/settlement.json")
	check(Model.valid_state(restored) and Model.is_finished(restored) and absf(Model.settlement_summary(restored).total - 5478.0) < 0.00001, "终局 JSON 保存恢复保留全部三年和分数")
	for damage in ["year", "month", "action_steps", "missing_result", "extra_result", "project"]:
		var broken := state.duplicate(true)
		match damage:
			"year": broken.year = 4
			"month": broken.month = 1
			"action_steps": broken.action_steps = 1
			"missing_result": broken.annual_results.erase("3")
			"extra_result": broken.annual_results["4"] = broken.annual_results["3"]
			"project": broken.annual_results["3"].project.title = "不一致"
		check(not Model.valid_state(broken), "拒绝损坏的终局字段：" + damage)

	var staff := Ranking.load_entries()
	check(staff.size() == 9 and Ranking.validation_error(staff).is_empty(), "默认排行榜可填写九个名字与固定分数")
	for index in staff.size():
		staff[index] = {"name": "测试人员%d" % index, "score": float(900 - index * 100)}
	var original_staff := JSON.stringify(staff)
	for total in [1000.0, 550.0, -10.0, 900.0, 550.25]:
		var rows := Ranking.build(total, staff)
		var player_count := 0
		for index in rows.size():
			if rows[index].is_player:
				player_count += 1
				check(rows[index].name == "你" and rows[index].score == total, "玩家始终叫“你”且保留精确总分")
			if index > 0: check(rows[index - 1].score >= rows[index].score, "排行榜按分数降序")
		check(rows.size() == 10 and player_count == 1, "九名制作组加一名玩家且没有重复插入")
	check(Ranking.build(1000, staff)[0].is_player and Ranking.build(-10, staff)[9].is_player, "覆盖玩家第一名和末名")
	var tied := Ranking.build(900, staff)
	check(tied[0].rank == 1 and tied[1].rank == 1 and tied[1].is_player and tied[2].rank == 3, "同分并列并保持录入顺序")
	check(JSON.stringify(staff) == original_staff, "排序不修改预录入数据")
	for bad_score in ["100", true, INF, NAN]:
		var bad := staff.duplicate(true)
		bad[0].score = bad_score
		check(not Ranking.validation_error(bad).is_empty(), "拒绝非数字和无限分数")
	for bad_name in ["", "你", "测试人员1", "空白 ", "换\n行"]:
		var bad := staff.duplicate(true)
		bad[0].name = bad_name
		check(not Ranking.validation_error(bad).is_empty(), "拒绝非法或重复名字")
	check(not Ranking.validation_error(staff.slice(0, 8)).is_empty(), "制作组必须恰好九人")

	var scene = load("res://scenes/interface_shell.tscn").instantiate()
	root.add_child(scene)
	for frame in 4: await process_frame
	scene.state = final_opening
	scene.show_main()
	scene.open_schedule()
	scene.duty_panel.next_turn_button.pressed.emit()
	await process_frame
	check(scene.award_screen.visible and not scene.settlement_screen.visible, "第三年仍然先展示评奖，再进入总结算")
	var award = scene.award_screen
	while award.step_index + 1 < award.steps.size():
		check(award.continue_button.text == "继续", "第三年中途奖项按钮仍为继续")
		award.continue_button.pressed.emit()
	check(award.continue_button.text == "结算", "第三年最后一页把进入下一年变为结算")
	award.continue_button.pressed.emit()
	for frame in 4: await process_frame
	var screen = scene.settlement_screen
	check(screen.visible and screen.page_index == 0 and screen.project_cards.size() == 3, "结算先打开三款作品回顾页")
	check(not scene.main_screen.visible and not scene.game_selection.visible and not scene.recruitment_panel.visible, "终局没有第四年主界面、立项或招募")
	check(screen.total_label.text == "三年总分  5478", "总分显示沿用向下取整规则")
	var final_snapshot := JSON.stringify(scene.state)
	var ceremony: Dictionary = Model.annual_result_for_year(scene.state, 3)
	ceremony.bug_disaster = true
	ceremony.awards = Model.annual_awards({"total": 14000.0, "pair": 10000.0, "p": 4000.0})
	screen.hide()
	award.open(ceremony)
	check(award.steps.size() == 4 and award.continue_button.text == "继续", "第三年灾难加三奖时先正常播放提示")
	while award.step_index + 1 < award.steps.size():
		check(award.continue_button.text == "继续", "第三年中途奖项不提前显示结算")
		award.continue_button.pressed.emit()
	check(award.continue_button.text == "结算", "多奖项播放完才显示结算")
	award.continue_button.pressed.emit()
	check(screen.visible and JSON.stringify(scene.state) == final_snapshot, "重复展示评奖不会再次发奖或修改总结算")
	scene.open_character("a")
	scene.open_schedule()
	scene.open_debug()
	scene._next_turn()
	check(not scene.character_screen.visible and not scene.duty_panel.visible and not scene._debug_open() and JSON.stringify(scene.state) == final_snapshot, "结算期间阻止旧界面和游戏操作")
	for resolution in [Vector2i(1280, 720), Vector2i(1440, 900), Vector2i(1920, 1080)]:
		root.size = resolution
		for page in 2:
			screen._show_page(page)
			for frame in 4: await process_frame
			check(screen.get_global_rect().encloses(screen.scroll.get_global_rect()), "各分辨率结算内容滚动区完整在屏内")
			var button: Button = screen.next_button if page == 0 else screen.return_button
			check(screen.get_global_rect().encloses(button.get_global_rect()), "各分辨率翻页和返回按钮完整在屏内")
			check(screen.content.size.x <= screen.scroll.size.x, "内容不会横向溢出")
			if page == 1: check(screen.ranking_rows.size() == 10 and screen.player_row != null, "第二页恰好十条且高亮玩家")
	var long_summary: Dictionary = screen.summary.duplicate(true)
	long_summary.projects[0].project.title = "很长的项目名字".repeat(30)
	screen.summary = long_summary
	root.size = Vector2i(1280, 720)
	screen._show_page(0)
	for frame in 4: await process_frame
	check(screen.content.size.x <= screen.scroll.size.x and screen.get_global_rect().encloses(screen.next_button.get_global_rect()), "长项目名自动换行，不挤出翻页按钮")
	screen.summary = Model.settlement_summary(scene.state)
	screen.rankings = Ranking.build(-1000.0, staff)
	screen._show_page(1)
	for frame in 4: await process_frame
	screen.scroll.scroll_vertical = 100000
	for frame in 4: await process_frame
	check(screen.scroll.get_global_rect().encloses(screen.player_row.get_global_rect()), "720p 下可以滚动到末名玩家并完整查看")
	screen.rankings = Ranking.build(float(screen.summary.total), Ranking.load_entries())
	root.size = Vector2i(1440, 900)
	for page in 2:
		screen._show_page(page)
		for frame in 4: await process_frame
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://qa/settlement_%d.png" % page)
	screen.previous_button.pressed.emit()
	check(screen.page_index == 0, "排行榜可以返回作品页")
	screen.next_button.pressed.emit()
	check(screen.page_index == 1 and JSON.stringify(scene.state) == final_snapshot, "翻页不改变分数和状态")
	screen.return_button.pressed.emit()
	check(scene.start_screen.visible and not screen.visible and scene.state.year == 1, "排行榜结束后返回开始页，新一局回到第一年")
	scene.queue_free()
	await process_frame
	SkillFixture.restore(skills)
	print("Settlement: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
