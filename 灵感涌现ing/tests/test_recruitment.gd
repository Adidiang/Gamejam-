extends SceneTree
## 正式空社团开局、年初招募与事件顺序；不使用已入社阵容样本。
const Model = preload("res://scripts/game_model.gd")
const Table = preload("res://scripts/character_table.gd")
const Skills = preload("res://scripts/skills/skill_table.gd")
const Runner = preload("res://scripts/skills/skill_runner.gd")
const Context = preload("res://scripts/skills/skill_context.gd")
const Store = preload("res://scripts/save_store.gd")
const WorkView = preload("res://scripts/monthly_work_panel.gd")
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func year_end(state: Dictionary) -> Dictionary:
	var next := state
	while int(next.month) <= 12:
		var result := Model.advance_work(next, int(next.year), int(next.month))
		check(result.ok, "Calendar advances with the current recruited roster")
		if not result.ok: return next
		next = result.state
		check(Model.valid_state(next), "Recruitment state remains valid after monthly settlement")
		if int(next.month) == 1: return next
	return next

func confirm_all(state: Dictionary) -> Dictionary:
	var next := state
	for id in Model.pending_recruits(state):
		var result := Model.confirm_recruit(next, id)
		check(result.ok, "Selected member joins once through the event")
		if result.ok: next = result.state
	return next

func _run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1440, 900)
	var originals: Array = Model.DEFINITIONS.duplicate(true)
	var initial := Model.fresh()
	check(initial.members.size() == 10 and Model.recruited_ids(initial).is_empty(), "All ten characters start unrecruited")
	check(Model.valid_state(initial), "Empty-club initial state is valid")
	check(Model.DEFINITIONS.all(func(row: Dictionary): return row.join_text == ""), "All join texts are initially blank")
	check(Model.DEFINITIONS.slice(1).all(func(row: Dictionary): return row.genre.is_empty() and row.topic.is_empty()), "Placeholder preferences remain unconfigured")
	var invalid := Table.table.duplicate(true)
	invalid.characters[0].join_text = 1
	check(not Table.validate(invalid).is_empty(), "Join text must be a string")
	var selected := Model.select_project(initial, "第一年", "rpg", "fantasy", 1)
	var state: Dictionary = selected.state
	check(state.members.all(func(member: Dictionary): return member.affinity == 0), "Matching unrecruited characters gain no project affinity")
	check(Model.available_tasks(state).is_empty(), "Empty club cannot perform tasks")
	check(not Model.execute_task(state, 0, "art_concept", 1, 1).ok and not Model.execute_invite(state, 0, 1, 1).ok, "Unrecruited characters cannot perform tasks or invitations")
	check(Model.assign(state, 0, 3) == state and Model.learn(state, 0, 1) == state, "Unrecruited characters cannot change duties or learn")
	var unlocked := state.duplicate(true)
	unlocked.members[0].affinity = 50
	check(not Runner.active(unlocked, 0, Model.DEFINITIONS[0].skills[0]), "Even unlocked skills do not activate before recruitment")
	var turn := Model.advance_work(state, 1, 1)
	check(turn.state.work == {"g": 0.0, "i": 0.0, "p": 0.0, "b": 0.0} and turn.report.skill_events.is_empty(), "Empty club produces no work or skill effects")
	check(turn.state.inspiration == 3 and turn.state.month == 2, "Empty club still earns monthly inspiration and advances time")
	var empty_view := WorkView.new()
	root.add_child(empty_view)
	empty_view.open(turn.report)
	check(not empty_view.playing and not empty_view.visible, "An empty work report skips playback safely")
	empty_view.queue_free()
	var pending := year_end(state)
	check(Model.pending_recruits(pending) == ["a"] and Model.recruited_ids(pending).is_empty(), "Only sheep qualifies from the previous year's fantasy game and waits for confirmation")
	check(pending.inspiration == 14 and pending.members[0].affinity == 0, "Entire first year has no staff or advance affinity")
	check(not Model.select_project(pending, "提前立项", "act", "modern", 2).ok, "New project selection waits for recruitment events")
	check(not Model.confirm_recruit(pending, "b").ok, "Wrong character cannot confirm an event")
	check(Store.save_run(pending, "res://qa/recruitment_pending.json") == OK, "Pending recruitment can be saved")
	var loaded := Store.load_run("res://qa/recruitment_pending.json")
	check(not loaded.is_empty() and loaded.run_id == pending.run_id and loaded.recruitment["2"].selected == pending.recruitment["2"].selected and int(loaded.recruitment["2"].confirmed) == 0 and Model.pending_recruits(loaded) == ["a"], "Save reload preserves the exact pending selection")
	var joined := confirm_all(loaded)
	check(Model.recruited_ids(joined) == [0] and joined.members[0].affinity == 0, "Confirmation recruits the member at the table's initial affinity")
	check(not Model.confirm_recruit(joined, "a").ok and Model.valid_state(joined), "Repeated confirmation is rejected")
	var second := Model.select_project(joined, "第二年", "rpg", "fantasy", 2)
	check(second.ok and second.state.members[0].affinity == 10 and second.state.members[1].affinity == 0, "Only recruited members receive later project affinity")
	var team := Context.new(second.state)
	check(team.targets("team") == ["a"], "Team skill targets exclude all unrecruited characters")
	# 强制绵羊睡着并习得成长技能，确认未招募者不吃团队成长。
	var original_skill = Skills.skills.a_skill_1
	Skills.skills.a_skill_1 = original_skill.duplicate(true)
	for trigger in Skills.skills.a_skill_1.triggers: trigger.params.probability = 1.0
	var growing: Dictionary = second.state.duplicate(true)
	growing.members[0].affinity = 20
	growing.members[0].learned_skills = ["a_skill_2"]
	var growth := Model.advance_work(growing, 2, 1)
	check(growth.state.members[0].ability_growth[1] == 10 and growth.state.members.slice(1).all(func(member: Dictionary): return member.ability_growth[1] == 0), "Team growth affects recruited characters only")
	Skills.skills.a_skill_1 = original_skill
	# 没有候选人时仍完成当年的空招募记录。
	var none := year_end(Model.select_project(Model.fresh(), "无匹配", "act", "modern", 1).state)
	check(Model.pending_recruits(none).is_empty() and none.recruitment["2"].selected.is_empty(), "No matching preference means no joining event")
	# 两人命中与多人抽选；匹配两项仍只占一个候选名额。
	for row in Model.DEFINITIONS:
		row.genre = ""
		row.topic = ""
	Model.DEFINITIONS[0].genre = "RPG"
	Model.DEFINITIONS[0].topic = "奇幻"
	Model.DEFINITIONS[1].topic = "奇幻"
	var pair := year_end(Model.select_project(Model.fresh(), "两人匹配", "rpg", "fantasy", 1).state)
	check(Model.pending_recruits(pair).size() == 2 and "a" in Model.pending_recruits(pair) and "b" in Model.pending_recruits(pair), "Exactly two eligible characters both join without duplication")
	var first_id: String = Model.pending_recruits(pair)[0]
	var partial: Dictionary = Model.confirm_recruit(pair, first_id).state
	check(Store.save_run(partial, "res://qa/recruitment_partial.json") == OK, "Partially confirmed recruitment can be saved")
	var resumed := Store.load_run("res://qa/recruitment_partial.json")
	check(Model.pending_recruits(resumed) == Model.pending_recruits(pair).slice(1) and Model.recruited_ids(resumed).size() == 1, "Reload resumes at the remaining joining window")
	check(not Model.confirm_recruit(resumed, first_id).ok, "Reload cannot repeat an already confirmed joining event")
	for row in Model.DEFINITIONS: row.topic = "奇幻"
	var seeded := Model.fresh()
	seeded.run_id = "recruitment-repeatability"
	var many_start: Dictionary = Model.select_project(seeded, "多人匹配", "rpg", "fantasy", 1).state
	var many := year_end(many_start)
	var replay := year_end(many_start)
	check(many == replay and Model.pending_recruits(many).size() == 2, "More than two candidates yields two stable random choices")
	var choices: Dictionary = {}
	for sample in 12:
		var trial := Model.fresh()
		trial.run_id = "recruitment-sample-%d" % sample
		trial = Model.select_project(trial, "抽选样本", "rpg", "fantasy", 1).state
		trial.month = 12
		var drawn := Model.advance_work(trial, 1, 12)
		choices[JSON.stringify(Model.pending_recruits(drawn.state))] = true
	check(choices.size() > 1, "Random selection varies across games instead of always taking the first two")
	var many_joined := confirm_all(many)
	var history := year_end(Model.select_project(many_joined, "只有现代", "act", "modern", 2).state)
	check(Model.pending_recruits(history).is_empty(), "An older fantasy project cannot attract candidates after last year's modern project")
	var again := year_end(Model.select_project(history, "再做奇幻", "rpg", "fantasy", 3).state)
	check(Model.pending_recruits(again).size() == 2 and Model.pending_recruits(again).all(func(id: String): return id not in many.recruitment["2"].selected), "Already recruited characters never enter the lottery again")
	var damaged := many.duplicate(true)
	damaged.recruitment["2"].selected[1] = damaged.recruitment["2"].selected[0]
	check(not Model.valid_state(damaged), "Duplicate recruitment choices fail save validation")
	damaged = many.duplicate(true)
	damaged.members[0].recruited = "yes"
	check(not Model.valid_state(damaged), "Invalid recruitment flags fail save validation")
	# 使用真实新局与年末界面，验证加入窗口早于次年立项，且逐个读取角色文本。
	Model.DEFINITIONS[0].join_text = "我想加入这个社团！\n一起做游戏吧。"
	Model.DEFINITIONS[1].join_text = ""
	var scene = load("res://scenes/interface_shell.tscn").instantiate()
	root.add_child(scene)
	scene.state = Model.fresh()
	scene.open_game_selection()
	check(Model.recruited_ids(scene.state).is_empty(), "Explicit empty-club state remains supported")
	scene.game_selection.topic_buttons[0].pressed.emit()
	check(not scene.game_selection.affinity_label.text.contains("+10"), "Project preview does not promise affinity to unrecruited members")
	scene._select_project("空社团首作", "rpg", "fantasy", 1)
	check(scene.character_buttons.all(func(button: Button): return not button.visible), "Main screen hides every unrecruited character without removing their nodes")
	scene.open_character("a")
	check(not scene.character_screen.visible, "Unavailable character cannot open a member page")
	scene.open_schedule()
	check(scene.duty_panel.tokens.all(func(token): return not token.visible) and not scene.duty_panel.next_turn_button.disabled, "Empty schedule hides all staff and still allows advancing")
	for month in range(1, 13):
		if not scene.duty_panel.visible: scene.open_schedule()
		scene._next_turn()
		check(not scene.work_panel.visible and not scene.work_panel.playing, "Empty monthly work playback is skipped")
	check(scene.award_screen.visible and not scene.recruitment_panel.visible and not scene.game_selection.visible, "Year-end awards appear before recruitment")
	# 用两名候选人的真实存档覆盖刚结束的状态以独立验证两次窗口。
	scene.state = pair.duplicate(true)
	scene.award_screen.continue_button.pressed.emit()
	check(scene.recruitment_panel.visible and not scene.game_selection.visible, "New-year recruitment window appears before project selection")
	for index in 2:
		var id: String = Model.pending_recruits(scene.state)[0]
		var member_id: int = Table.initial_ids().find(id)
		var expected: String = Model.DEFINITIONS[member_id].join_text
		check(scene.recruitment_panel.body_label.text == ("加入文本" if expected.is_empty() else expected), "Event displays that character's own join text or exact fallback")
		check(scene.recruitment_panel.title_label.text.contains(Model.DEFINITIONS[member_id].name), "Joining window identifies the character")
		scene.open_schedule()
		scene.open_character(id)
		check(not scene.duty_panel.visible and not scene.character_screen.visible, "Joining event blocks lower interfaces")
		for resolution in [Vector2i(1280, 720), Vector2i(900, 700), Vector2i(1920, 1080)]:
			root.size = resolution
			for frame in 3: await process_frame
			check(scene.get_global_rect().encloses(scene.recruitment_panel.dialog.get_global_rect()), "Join dialog fits the viewport")
			check(scene.recruitment_panel.dialog.get_global_rect().encloses(scene.recruitment_panel.confirm_button.get_global_rect()), "Join confirmation remains within the dialog")
			if DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://qa/recruitment_%s_%d.png" % [id, resolution.x])
		if expected.is_empty():
			var blank: Dictionary = Model.DEFINITIONS[member_id].duplicate(true)
			blank.join_text = "  \n\t"
			scene.recruitment_panel.open(blank)
			check(scene.recruitment_panel.body_label.text == "加入文本", "Whitespace-only join text uses the same exact fallback")
		scene.recruitment_panel.confirm_button.pressed.emit()
	check(not scene.recruitment_panel.visible and scene.game_selection.visible and Model.recruited_ids(scene.state).size() == 2, "After both confirmations, project selection opens with both new members")
	scene._select_project("新社员的作品", "rpg", "fantasy", 2)
	check(scene.character_buttons[0].visible and scene.character_buttons[1].visible and not scene.character_buttons[2].visible, "Main screen shows only the two recruited members")
	scene.open_schedule()
	check(scene.duty_panel.tokens[0].visible and scene.duty_panel.tokens[1].visible and not scene.duty_panel.tokens[2].visible, "Schedule also shows only recruited staff")
	scene.duty_panel.close()
	var sparse: Dictionary = scene.state.duplicate(true)
	sparse.members[0].recruited = false
	sparse.members[1].recruited = false
	sparse.members[9].recruited = true
	var sparse_turn := Model.advance_work(sparse, 2, 1)
	var sparse_view := WorkView.new()
	root.add_child(sparse_view)
	sparse_view.open(sparse_turn.report)
	await process_frame
	check(sparse_view.active_members == [9] and sparse_view.current_member == 9 and not sparse_view.cards[0].visible and sparse_view.cards[9].visible, "Monthly playback preserves sparse stable IDs and skips unavailable characters")
	if sparse_view.animation != null: sparse_view.animation.kill()
	sparse_view.queue_free()
	scene.queue_free()
	Model.DEFINITIONS = originals
	print("RECRUITMENT_TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
