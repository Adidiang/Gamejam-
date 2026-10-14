extends SceneTree
const Model = preload("res://scripts/game_model.gd")
const Skills = preload("res://scripts/skills/skill_table.gd")
const Definition = preload("res://scripts/skills/skill_definition.gd")
const Store = preload("res://scripts/save_store.gd")
const Sheet = preload("res://scripts/member_sheet.gd")
const TaskView = preload("res://scripts/task_execution_panel.gd")
const WorkView = preload("res://scripts/monthly_work_panel.gd")
var checks := 0
var failures := 0
var rows: Array
var source_characters: String
var source_skills: String
var original_definitions: Array
var original_skills: Dictionary

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func near(a: float, b: float) -> bool:
	return absf(a - b) < 0.00001

func same_json(a: Variant, b: Variant) -> bool:
	# JSON 读档会把整数解析为浮点数；比较保存语义，而非内存数值类型。
	return JSON.stringify(JSON.parse_string(JSON.stringify(a))) == JSON.stringify(JSON.parse_string(JSON.stringify(b)))

func probability(chance: float) -> void:
	var row: Dictionary = rows[0].duplicate(true)
	for trigger in row.triggers: trigger.params.probability = chance
	Skills.skills[row.id] = Definition.from_row(row)

func ready(learned: bool = true) -> Dictionary:
	var state: Dictionary = Model.select_project(Model.fresh(), "梦境测试", "rpg", "fantasy", 1).state
	if learned:
		state.members[0].affinity = 50
		state.inspiration = 100
		state = Model.learn(state, 0, 1)
		state = Model.learn(state, 0, 2)
	return state

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1440, 900)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://qa"))
	source_characters = FileAccess.get_file_as_string("res://data/characters.json")
	source_skills = FileAccess.get_file_as_string("res://data/skills.json")
	rows = JSON.parse_string(source_skills).skills
	original_definitions = Model.DEFINITIONS
	original_skills = Skills.skills
	Model.DEFINITIONS = original_definitions.duplicate(true)
	Skills.skills = original_skills.duplicate()
	# 其他社员有非零能力，才能验证只取消绵羊自己的工作。
	Model.DEFINITIONS[1].stats = [4.0, 10.0, 5.0, 3.0]
	Model.DEFINITIONS[2].stats = [2.0, 3.0, 5.0, 5.0]
	Model.DEFINITIONS[3].stats = [1.0, 1.0, 1.0, 1.0]
	check(rows[0].acquisition == "auto" and rows[0].inspiration_cost == 0, "White daydream is free and automatic")
	check(rows[1].acquisition == "inspiration" and rows[1].inspiration_cost == 10, "Dream narration costs ten inspiration")
	check(rows[2].acquisition == "inspiration" and rows[2].inspiration_cost == 20, "Dreamer costs twenty inspiration")
	check(Model.DEFINITIONS[0].skills.map(func(slot: Dictionary): return int(slot.unlock_affinity)) == [0, 20, 50], "Confirmed thresholds are zero/twenty/fifty")
	check(rows[0].triggers.all(func(trigger: Dictionary): return trigger.params.probability == 0.5), "Production sleep probability is fifty percent")
	var state := ready(false)
	state.members[0].affinity = 20
	state.inspiration = 9
	check(Model.learn(state, 0, 1) == state, "Insufficient inspiration does not buy narration")
	state.inspiration = 10
	var bought := Model.learn(state, 0, 1)
	check(bought.inspiration == 0 and "a_skill_2" in bought.members[0].learned_skills, "Narration purchase charges exact cost")
	check(Model.learn(bought, 0, 1) == bought, "Buying a learned skill twice does not charge")
	state = ready(false)
	state.inspiration = 20
	state.members[0].affinity = 49
	check(Model.learn(state, 0, 2) == state, "Dreamer is locked at forty-nine affinity")
	state.members[0].affinity = 50
	check(Model.learn(state, 0, 2).inspiration == 0, "Dreamer is purchasable at fifty affinity")

	probability(1.0)
	state = ready(false)
	var snapshot := JSON.stringify(state)
	var asleep := Model.execute_task(state, 0, "art_concept", 1, 1)
	check(asleep.ok and asleep.report.sleeping_member_ids == ["a"], "Own task can sleep")
	check(near(asleep.report.task_delta.p, 0) and near(asleep.report.task_delta.i, 0), "Sleeping task cancels its output")
	check(asleep.state.action_steps == 0 and asleep.state.month == 1, "Sleep spends action step without advancing month")
	check(asleep.state.get("completed_tasks", {}).is_empty(), "Sleep does not consume annual task opportunity")
	check(JSON.stringify(state) == snapshot, "Task preview leaves input state untouched")
	check(not Model.execute_task(asleep.state, 0, "art_concept", 1, 1).ok, "Sleeping task cannot bypass spent step")
	check(near(Model.base_ability(0, asleep.state)[1], 100), "Unlearned narration gives no growth")
	check(asleep.state.skill_runtime.get("next_task_double", {}).is_empty(), "Unlearned dreamer gives no flag")
	var next_month := Model.advance_work(asleep.state, 1, 1)
	check(next_month.ok and next_month.state.action_steps == 1, "Next month restores exactly one step")
	check(Model.available_tasks(next_month.state).size() == 1, "Sleeping annual task can be retried next month")
	check(next_month.report.inspiration_delta == 1, "Sleeping worker does not cancel shared monthly inspiration")
	var other := Model.execute_task(ready(), 1, "art_concept", 1, 1)
	check(other.ok and other.report.sleeping_member_ids.is_empty(), "Sheep does not cancel another member's task")
	check(other.state.completed_tasks["1"] == ["art_concept"], "Successful task consumes annual opportunity")
	var invitation := Model.execute_invite(ready(), 0, 1, 1)
	check(invitation.ok and invitation.report.sleeping_member_ids.is_empty(), "Invitations cannot trigger sleep")
	check(near(Model.base_ability(0, invitation.state)[1], 100), "Invitation cannot grant sleep growth")

	state = ready()
	var awake_work: Dictionary
	probability(0.0)
	awake_work = Model.advance_work(state, 1, 1)
	probability(1.0)
	var sleep_work := Model.advance_work(state, 1, 1)
	check(sleep_work.report.contributions[0].values().all(func(value): return is_zero_approx(float(value))), "Sleep cancels all of owner's duty fields including bugs and repair")
	check(sleep_work.report.contributions[1] == awake_work.report.contributions[1], "Other members' duties remain intact")
	check(sleep_work.report.contributions[2] == awake_work.report.contributions[2], "Art worker is not cancelled with sheep")
	check(near(Model.base_ability(0, sleep_work.state)[1], 110), "Sleep adds ten to owner's local base imagination")
	check(near(Model.base_ability(1, sleep_work.state)[1], 15), "Sleep adds five to another member's local base imagination")
	check(near(Model.ability(sleep_work.state, 0)[1], 165), "Affinity multiplies grown base once")
	check(near(Model.DEFINITIONS[0].stats[1], 100), "Growth never mutates character definition")
	check(sleep_work.state.skill_runtime.has("next_task_double"), "Learned dreamer arms a project flag after sleep")
	check(Model.valid_state(sleep_work.state), "Growth and flag produce a valid save state")
	check(near(Model.base_ability(0, awake_work.state)[1], 100), "Awake duties grant no sleep growth")
	check(awake_work.state.skill_runtime.get("next_task_double", {}).is_empty(), "Awake duties do not arm dreamer")
	var pending: Dictionary = sleep_work.state.skill_runtime.next_task_double.duplicate(true)
	var twice := Model.advance_work(sleep_work.state, 1, 2)
	check(twice.state.skill_runtime.next_task_double == pending, "Repeated sleep cannot stack pending task doubles")
	check(near(Model.base_ability(0, twice.state)[1], 120) and near(Model.base_ability(1, twice.state)[1], 20), "Repeated sleep grants permanent growth once per event")
	check(twice.state.skill_log.filter(func(record): return record.skill_id == "a_skill_3").is_empty(), "Existing pending flag is not awarded again")

	var retry := Model.execute_task(sleep_work.state, 0, "art_concept", 1, 2)
	check(retry.report.sleeping_member_ids == ["a"] and retry.state.skill_runtime.next_task_double == pending, "Sleeping task preserves an existing double flag")
	check(retry.state.get("completed_tasks", {}).is_empty(), "Flagged sleeping task still preserves annual opportunity")
	probability(0.0)
	var recovered := Model.advance_work(retry.state, 1, 2)
	var plain: Dictionary = recovered.state.duplicate(true)
	plain.skill_runtime.erase("next_task_double")
	var normal_task := Model.execute_task(plain, 1, "art_concept", 1, 3)
	var doubled_task := Model.execute_task(recovered.state, 1, "art_concept", 1, 3)
	check(near(doubled_task.report.task_delta.p, normal_task.report.task_delta.p * 2), "Any member can consume doubled performance output")
	check(near(doubled_task.report.task_delta.i, normal_task.report.task_delta.i * 2), "Innovation output is doubled once")
	check(doubled_task.report.task_multiplier == 2 and not doubled_task.state.skill_runtime.has("next_task_double"), "Successful task consumes the one-shot flag")
	check(doubled_task.state.action_steps == 0 and doubled_task.state.completed_tasks["1"] == ["art_concept"], "Double does not refund action or annual task cost")
	var invited := Model.execute_invite(sleep_work.state, 1, 1, 2)
	check(invited.state.skill_runtime.next_task_double == pending, "Inviting another member does not consume task double")

	# 任务后置额外作品产出及灵感也翻倍，好感和永久能力不翻倍。
	var bonus := {"id": "b_skill_1", "name": "测试任务奖励", "description": "测试", "quip": "", "acquisition": "auto", "inspiration_cost": 0, "triggers": []}
	for data in [["work", "g", 3], ["work", "b", 2], ["shared", "inspiration", 4], ["owner", "affinity", 2]]:
		bonus.triggers.append({"hook": "ACTION_AFTER", "conditions": {"action_kind": "task", "actor_is_owner": true}, "target": data[0], "frequency": "event", "effect_id": "numeric_modifier", "params": {"field": data[1], "operation": "add", "amount": data[2]}, "priority": 0})
	check(Definition.validate(bonus).is_empty(), "Task bonus fixture uses legal framework triggers")
	Skills.skills["b_skill_1"] = Definition.from_row(bonus)
	var all_outputs := Model.execute_task(sleep_work.state, 1, "art_concept", 1, 2)
	check(near(all_outputs.report.task_delta.g, 6) and near(all_outputs.report.task_delta.b, 4), "Other work attributes from task-after effects double too")
	check(all_outputs.report.inspiration_delta == 8, "Task inspiration reward is doubled")
	check(all_outputs.state.members[1].affinity == 2, "Task affinity reward is not doubled")
	# 其他前后置加成不能让已经睡着的任务重新产生输出。
	var cancel_bonus: Dictionary = rows[0].duplicate(true)
	for trigger in cancel_bonus.triggers: trigger.params.probability = 1.0
	for data in [["ACTION_BEFORE", "work", "g", 5], ["ACTION_AFTER", "work", "g", 7], ["ACTION_AFTER", "shared", "inspiration", 3]]:
		cancel_bonus.triggers.append({"hook": data[0], "conditions": {"action_kind": "task", "actor_is_owner": true}, "target": data[1], "frequency": "event", "effect_id": "numeric_modifier", "params": {"field": data[2], "operation": "add", "amount": data[3]}, "priority": 50})
	check(Definition.validate(cancel_bonus).is_empty(), "Cancellation fixture uses valid output fields")
	Skills.skills["a_skill_1"] = Definition.from_row(cancel_bonus)
	var cancelled_bonus := Model.execute_task(ready(false), 0, "art_concept", 1, 1)
	check(near(cancelled_bonus.report.task_delta.g, 0) and near(cancelled_bonus.report.task_delta.p, 0) and near(cancelled_bonus.report.task_delta.i, 0), "Sleep cancels extra task output at both phases")
	check(cancelled_bonus.report.inspiration_delta == 0, "Sleeping task does not receive task-after inspiration bonus")
	probability(0.0)
	check(Store.save_run(sleep_work.state, "res://qa/sheep_save.json") == OK, "Growth and project flag save successfully")
	var loaded := Store.load_run("res://qa/sheep_save.json")
	check(not loaded.is_empty() and same_json(loaded.skill_runtime.next_task_double, pending), "Pending flag survives save/load")
	check(near(Model.base_ability(0, loaded)[1], 110), "Permanent local growth survives save/load")
	var reloaded := Model.execute_task(loaded, 1, "art_concept", 1, 2)
	## 读档后浮点末位可能有一格误差，比较语义值与技能运行记录即可。
	check(reloaded.ok and near(reloaded.report.task_delta.p, all_outputs.report.task_delta.p) and near(reloaded.report.task_delta.i, all_outputs.report.task_delta.i) and reloaded.report.task_multiplier == all_outputs.report.task_multiplier and same_json(reloaded.state.skill_runtime, all_outputs.state.skill_runtime), "Reload does not change task double result")
	var december: Dictionary = sleep_work.state.duplicate(true)
	december.month = 12
	var new_year := Model.advance_work(december, 1, 12)
	check(new_year.state.year == 2 and not new_year.state.skill_runtime.has("next_task_double"), "New project year expires old project's flag")
	check(near(Model.base_ability(0, new_year.state)[1], 110), "Year change preserves this run's permanent growth")
	check(Model.needs_project_selection(new_year.state), "Sheep effects do not bypass annual project selection")
	check(Model.valid_state(new_year.state), "New-year state with grown members remains valid")
	var separate := ready()
	check(near(Model.base_ability(0, separate)[1], 100) and not separate.skill_runtime.has("next_task_double"), "A new run has neither inherited growth nor pending flags")

	probability(0.5)
	state = ready()
	state.run_id = "sheep-preview-and-save-test"
	state.annual_projects["1"].id = state.run_id + ":project:1"
	snapshot = JSON.stringify(state)
	var first := Model.execute_task(state, 0, "art_concept", 1, 1)
	check(JSON.stringify(first) == JSON.stringify(Model.execute_task(state, 0, "art_concept", 1, 1)), "Actual fifty-percent outcome is identical in preview and commit")
	var roundtrip: Dictionary = JSON.parse_string(JSON.stringify(state))
	check(same_json(first, Model.execute_task(roundtrip, 0, "art_concept", 1, 1)), "Saved RNG identity reproduces the outcome")
	check(JSON.stringify(state) == snapshot, "Random preview does not change incoming state")
	check(not Model.execute_task(first.state, 0, "art_concept", 1, 1).ok, "Repeated commit cannot duplicate random growth")
	var damaged: Dictionary = sleep_work.state.duplicate(true)
	damaged.members[0].ability_growth[1] = -1
	check(not Model.valid_state(damaged), "Negative permanent growth is rejected by save validation")
	damaged = sleep_work.state.duplicate(true)
	damaged.skill_runtime.next_task_double.owner_id = "missing"
	check(not Model.valid_state(damaged), "Unknown flag owner is rejected")
	damaged = sleep_work.state.duplicate(true)
	damaged.skill_log[0].outcomes[0].kind = "arbitrary_state_change"
	check(not Model.valid_state(damaged), "Unknown outcome cannot enter a valid save")
	var legacy := ready(false)
	for member in legacy.members: member.erase("ability_growth")
	check(Model.valid_state(legacy) and near(Model.base_ability(0, legacy)[1], 100), "Existing saves without growth fields retain zero-growth defaults")

	# 用户能看见三技能的真实结果，而非只有后台数值变化。
	var sheet := Sheet.new()
	root.add_child(sheet)
	sheet.display_member(sleep_work.state, 0, "a")
	check(near(float(sheet.stat_base_values[1].text), 110) and near(float(sheet.stat_final_values[1].text), 165), "Member sheet refreshes base and final grown imagination")
	check(sheet.skill_descriptions[0].text.contains("50%") and sheet.skill_buttons[1].text == "已习得", "Real description and learned fee state appear")
	sheet.queue_free()
	probability(1.0)
	var task_sleep := Model.execute_task(ready(), 0, "art_concept", 1, 1)
	var task_view := TaskView.new()
	root.add_child(task_view)
	task_view.open(task_sleep.report)
	var deadline := Time.get_ticks_msec() + 3000
	while task_view.playing and Time.get_ticks_msec() < deadline: await process_frame
	check(not task_view.playing and near(task_view.progress.value, 100), "Real task display finishes its progress before showing results")
	check(task_view.results_label.text.contains("睡着") and task_view.results_label.text.contains("年度任务次数保留"), "Task feedback explains sleep and retained annual chance")
	check(task_view.results_label.text.contains("脑洞白值 +10.0") and task_view.results_label.text.contains("脑洞白值 +5.0"), "Task feedback shows owner and team growth")
	check(task_view.results_label.text.contains("下一次任务产出翻倍"), "Task sleep reports the newly armed dreamer effect")
	await screenshot("sheep_task_sleep")
	task_view.queue_free()
	await process_frame
	var work_view := WorkView.new()
	root.add_child(work_view)
	work_view.open(sleep_work.report)
	deadline = Time.get_ticks_msec() + 15000
	while work_view.playing and Time.get_ticks_msec() < deadline: await process_frame
	check(work_view.value_labels[0].text.contains("睡着") and work_view.summary_label.text.contains("脑洞白值 +10.0"), "Monthly work feedback shows sleep and growth")
	check(not work_view.playing and work_view.value_labels[0].text.contains("下一次任务产出翻倍"), "Real monthly display finishes and reports the armed effect")
	work_view.scroll.scroll_vertical = 0
	await screenshot("sheep_monthly_sleep")
	root.size = Vector2i(1280, 720)
	for frame in 4: await process_frame
	check(work_view.get_global_rect().encloses(work_view.finish_button.get_global_rect()) and work_view.scroll.size.y >= 210, "Growth summary leaves work list and confirmation usable at 1280x720")
	await screenshot("sheep_monthly_sleep_1280")
	work_view.queue_free()
	await process_frame
	check(FileAccess.get_file_as_string("res://data/characters.json") == source_characters and FileAccess.get_file_as_string("res://data/skills.json") == source_skills, "Tests do not rewrite production data")
	Model.DEFINITIONS = original_definitions
	Skills.skills = original_skills
	print("SHEEP_SKILL_TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func screenshot(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://qa/%s.png" % label)
