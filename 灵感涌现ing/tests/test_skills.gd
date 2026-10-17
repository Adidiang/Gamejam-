extends SceneTree
const Roster = preload("res://tests/fixtures/roster_fixture.gd")
## 技能框架测试（新游戏流程）：门槛、习得方式、四个阶段的触发、频次与评奖。
const Model = preload("res://scripts/game_model.gd")
const Table = preload("res://scripts/skills/skill_table.gd")
const Definition = preload("res://scripts/skills/skill_definition.gd")
const Runner = preload("res://scripts/skills/skill_runner.gd")
const Store = preload("res://scripts/save_store.gd")
var checks := 0
var failures := 0
var originals: Array
var original_skills: Dictionary

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func near(a: float, b: float) -> bool:
	return absf(a - b) < 0.00001

func trigger(hook: String, target: String, field: String, amount: float, operation: String = "add", conditions: Dictionary = {}, frequency: String = "event") -> Dictionary:
	return {"hook": hook, "conditions": conditions, "target": target, "frequency": frequency,
		"effect_id": "numeric_modifier", "params": {"field": field, "operation": operation, "amount": amount}, "priority": 0}

func reset_fixture() -> void:
	Model.DEFINITIONS = originals.duplicate(true)
	Table.skills = {}
	for member_id in Model.DEFINITIONS.size():
		var member: Dictionary = Model.DEFINITIONS[member_id]
		member.stats = [0.0, 0.0, 0.0, 0.0]
		member.affinity = 0
		member.genre = ""
		member.topic = ""
		for slot in Model.SKILL_SLOTS:
			install(member_id, slot, "", [])

func install(member_id: int, slot_index: int, name: String, triggers: Array, acquisition: String = "auto", cost: int = 0) -> Dictionary:
	var id: String = Model.DEFINITIONS[member_id].skills[slot_index].skill_id
	var row := {"id": id, "name": name, "description": "测试技能介绍", "quip": "测试吐槽",
		"acquisition": acquisition, "inspiration_cost": cost, "triggers": triggers}
	assert(Definition.validate(row).is_empty(), "Skill fixture validates: " + name)
	Table.skills[id] = Definition.from_row(row)
	return row

## 新游戏从立项开始：偏好已在 reset_fixture 里清空，立项不会附带好感。
func start(title: String = "测试作品") -> Dictionary:
	return Model.select_project(Roster.fresh(), title, "act", "fantasy", 1).state

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	originals = Model.DEFINITIONS
	original_skills = Table.skills
	var production: Variant = JSON.parse_string(FileAccess.get_file_as_string(Table.PATH))
	check(Table.validate(production).is_empty(), "Production skill table validates")
	for member in originals:
		check(member.skills.map(func(slot: Dictionary): return int(slot.unlock_affinity)) == ([0, 20, 0] if member.id == "j" else [0, 20, 50]), "Documented skill thresholds including angel exception")

	## 1. 付费技能配置校验
	reset_fixture()
	var row := install(0, 0, "付费技能", [], "inspiration", 3)
	var bad := row.duplicate(true)
	bad.inspiration_cost = 0
	check(not Definition.validate(bad).is_empty(), "Paid skill requires positive cost")
	bad = row.duplicate(true)
	bad.acquisition = "auto"
	check(not Definition.validate(bad).is_empty(), "Automatic skill cannot charge inspiration")
	bad = row.duplicate(true)
	bad.triggers = [trigger("AWARD_AFTER", "work", "g", 10)]
	check(not Definition.validate(bad).is_empty(), "Award after cannot change completed work")
	bad = row.duplicate(true)
	bad.triggers = [trigger("ACTION_BEFORE", "team", "g", 10)]
	check(not Definition.validate(bad).is_empty(), "Duty-only member output cannot be edited in action phase")

	## 2. 习得：门槛、费用与重复购买
	var fresh := Roster.fresh()
	fresh.inspiration = 2
	check(not Runner.active(fresh, 0, Model.DEFINITIONS[0].skills[0]), "Paid zero-affinity skill needs learning")
	check(Model.learn(fresh, 0, 0) == fresh, "Insufficient inspiration is rejected")
	fresh.inspiration = 5
	var source := JSON.stringify(fresh)
	var learned := Model.learn(fresh, 0, 0)
	check(JSON.stringify(fresh) == source, "Learning leaves input state untouched")
	check(learned.inspiration == 2 and learned.month == fresh.month, "Configured cost is charged without a turn")
	check(Runner.active(learned, 0, Model.DEFINITIONS[0].skills[0]), "Learned paid skill becomes active")
	check(Model.learn(learned, 0, 0) == learned, "Duplicate purchase does not charge again")
	check(learned.members[1].learned_skills.is_empty(), "Learning is isolated per character")
	for slot in range(1, Model.SKILL_SLOTS):
		install(0, slot, "付费门槛", [], "inspiration", slot + 1)
		var test := Roster.fresh()
		test.inspiration = 20
		var threshold: int = Model.DEFINITIONS[0].skills[slot].unlock_affinity
		test.members[0].affinity = threshold - 1
		check(Model.learn(test, 0, slot) == test, "Paid skill locked below affinity threshold")
		test.members[0].affinity = threshold
		var bought := Model.learn(test, 0, slot)
		check(bought.inspiration == 20 - slot - 1 and bought.members[0].learned_skills.size() == 1, "Paid skill learned at exact threshold")

	## 3. 自动技能按好感门槛生效
	reset_fixture()
	install(0, 0, "自动技能", [])
	fresh = Roster.fresh()
	check(Runner.active(fresh, 0, Model.DEFINITIONS[0].skills[0]), "Skill 1 automatically active at zero affinity")
	check(Model.learn(fresh, 0, 0) == fresh, "Automatic skill never consumes inspiration")
	for slot in range(1, Model.SKILL_SLOTS):
		install(0, slot, "自动门槛", [])
		fresh.members[0].affinity = int(Model.DEFINITIONS[0].skills[slot].unlock_affinity) - 1
		check(not Runner.active(fresh, 0, Model.DEFINITIONS[0].skills[slot]), "Auto skill inactive below threshold")
		fresh.members[0].affinity += 1
		check(Runner.active(fresh, 0, Model.DEFINITIONS[0].skills[slot]), "Auto skill active at threshold")

	## 4. 立项阶段：PROJECT_BEFORE／AFTER
	reset_fixture()
	install(0, 0, "立项技能", [trigger("PROJECT_BEFORE", "owner", "affinity", 5), trigger("PROJECT_AFTER", "shared", "inspiration", 3), trigger("PROJECT_AFTER", "work", "g", 2)])
	fresh = Roster.fresh()
	var begun := Model.select_project(fresh, "测试", "act", "fantasy", 1)
	check(begun.ok and begun.state.members[0].affinity == 5 and begun.state.inspiration == 13 and begun.state.work.g == 2, "Project before and after effects apply")
	check(fresh.inspiration == 10 and fresh.members[0].affinity == 0 and fresh.skill_runtime.counts.is_empty(), "Project preview is isolated")
	check(begun.state.skill_log.size() == 3, "Project effects emit source records")
	check(not Model.select_project(begun.state, "重复", "act", "fantasy", 1).ok, "Project effects cannot be submitted twice")

	## 5. 行动阶段：任务与邀约分开，owner 与 actor 分离
	reset_fixture()
	install(0, 0, "任务技能", [trigger("ACTION_BEFORE", "work", "g", 10, "add", {"action_kind": "task", "actor_is_owner": true}), trigger("ACTION_AFTER", "work", "i", 3, "add", {"action_kind": "task"})])
	begun = Model.select_project(Roster.fresh(), "任务", "act", "fantasy", 1)
	var begun_state: Dictionary = begun.state
	var snapshot := JSON.stringify(begun_state)
	var task := Model.execute_task(begun_state, 0, "art_concept", 1, 1)
	check(task.ok and near(task.state.work.g, 10) and near(task.state.work.i, 3), "Action pre and post effects apply")
	check(JSON.stringify(begun_state) == snapshot, "Preview does not consume real event or frequency state")
	var same := Model.execute_task(begun_state, 0, "art_concept", 1, 1)
	check(JSON.stringify(task.report) == JSON.stringify(same.report), "Preview and commit have identical deterministic results")
	var invited := Model.execute_invite(begun_state, 0, 1, 1)
	check(invited.state.work.g == 0 and invited.state.work.i == 0, "Task-only skill does not trigger on invitation")
	var other_actor := Model.execute_task(begun_state, 1, "art_concept", 1, 1)
	check(other_actor.state.work.g == 0 and near(other_actor.state.work.i, 3), "Owner and actor are distinct")
	check(task.state.month == 1 and task.state.year == 1, "Task does not advance the calendar")

	## 6. 解锁时机：行动前不满门槛，行动后达标
	reset_fixture()
	install(0, 1, "刚解锁", [trigger("ACTION_BEFORE", "work", "g", 99), trigger("ACTION_AFTER", "work", "g", 2)])
	begun_state = Model.select_project(Roster.fresh(), "解锁时机", "act", "fantasy", 1).state
	begun_state.members[0].affinity = 19
	var unlocked := Model.execute_invite(begun_state, 0, 1, 1)
	check(unlocked.state.work.g == 2 and unlocked.report.skill_events.size() == 1, "Newly unlocked auto skill applies only to later phases")

	## 7. 职责阶段：全队效果只结算一次，百分比先相加
	reset_fixture()
	install(0, 0, "全队职责", [trigger("DUTY_BEFORE", "team", "g", 1), trigger("DUTY_AFTER", "work", "b", -1)])
	install(1, 0, "职责倍率", [trigger("DUTY_BEFORE", "team", "g", 0.5, "percent")])
	install(2, 0, "另一倍率", [trigger("DUTY_BEFORE", "team", "g", 0.5, "percent")])
	var duty_state: Dictionary = Model.select_project(Roster.fresh(), "职责", "act", "fantasy", 1).state
	var duty := Model.advance_work(duty_state, 1, 1)
	check(duty.state.work.g == 2 * Model.DEFINITIONS.size(), "Team effect applied once; percentages add before multiplying")
	check(duty.state.work.b == 0, "Bug reductions cannot create negative bugs")
	check(duty.report.skill_events.size() == 4, "Duties collect each source once, outside member loop")

	## 8. 频次：event／month／year／run
	reset_fixture()
	install(0, 0, "频次", [trigger("ACTION_AFTER", "shared", "inspiration", 1, "add", {}, "year")])
	var freq_state: Dictionary = Model.select_project(Roster.fresh(), "频次", "act", "fantasy", 1).state
	var turn := Model.execute_invite(freq_state, 0, 1, 1)
	var second := Model.execute_invite(Model.advance_work(turn.state, 1, 1).state, 0, 1, 2)
	check(turn.report.skill_events.size() == 1 and second.report.skill_events.is_empty(), "Year-limited effect triggers once across months")
	check(Model.valid_state(JSON.parse_string(JSON.stringify(turn.state))), "Skill runtime survives JSON round trip")
	check(Store.save_run(turn.state, "res://qa/skill_save.json") == OK, "Skill runtime saved")
	var restored := Store.load_run("res://qa/skill_save.json")
	var restored_second := Model.execute_invite(Model.advance_work(restored, 1, 1).state, 0, 1, 2)
	check(restored_second.report.skill_events.is_empty(), "Load does not reset frequency usage")
	for frequency in ["event", "month", "year", "run"]:
		reset_fixture()
		install(0, 0, "限次范围", [trigger("ACTION_AFTER", "shared", "inspiration", 1, "add", {}, frequency)])
		freq_state = Model.select_project(Roster.fresh(), "周期", "act", "fantasy", 1).state
		turn = Model.execute_invite(freq_state, 0, 1, 1)
		second = Model.execute_invite(Model.advance_work(turn.state, 1, 1).state, 0, 1, 2)
		check(second.report.skill_events.size() == (1 if frequency in ["event", "month"] else 0), "Frequency behavior across months: " + frequency)
		## 手动跨年：把年月推到第二年的 1 月并补上第二年档案，检查年度桶是否重置。
		var year_two: Dictionary = second.state.duplicate(true)
		year_two.year = 2
		year_two.month = 1
		year_two.action_steps = 1
		year_two.annual_projects["2"] = {"id": "%s:project:2" % year_two.run_id, "year": 2, "title": "跨年", "genre_id": "act", "topic_id": "fantasy"}
		var third := Model.execute_invite(year_two, 0, 2, 1)
		check(third.report.skill_events.size() == (0 if frequency == "run" else 1), "Frequency behavior across year IDs: " + frequency)
		var empty_plan := Model._plan(third.state)
		var replay_metadata := Model._metadata(third.state, 0, 0)
		replay_metadata.action_serial = int(third.state.action_serial) - 1
		var replay := Runner.run(third.state, Model.DEFINITIONS, "ACTION_AFTER", replay_metadata, empty_plan)
		check(replay.records.is_empty() and replay.plan.inspiration == 0, "Same stage event cannot replay: " + frequency)

	## 9. 临时修正：建立当月职责修正并在下个月过期
	reset_fixture()
	var temporary := trigger("ACTION_AFTER", "team", "g", 2)
	temporary.effect_id = "temporary_modifier"
	temporary.frequency = "year"
	temporary.params.apply_hook = "DUTY_BEFORE"
	temporary.params.duration = "month"
	install(0, 0, "临时修正", [temporary])
	freq_state = Model.select_project(Roster.fresh(), "临时", "act", "fantasy", 1).state
	turn = Model.execute_invite(freq_state, 0, 1, 1)
	var temp_first := Model.advance_work(turn.state, 1, 1)
	var temp_invite := Model.execute_invite(temp_first.state, 0, 1, 2)
	var temp_second := Model.advance_work(temp_invite.state, 1, 2)
	check(temp_first.state.work.g == 2 * Model.DEFINITIONS.size() and temp_second.state.work.g == 2 * Model.DEFINITIONS.size(), "Month modifier applies to later duties then expires")
	check(Model.valid_state(JSON.parse_string(JSON.stringify(temp_first.state))), "Temporary modifier is serializable")

	## 10. 年度评奖阶段：bonus 参与判定，AWARD_AFTER 追加奖励
	reset_fixture()
	install(0, 0, "年度评分", [trigger("AWARD_BEFORE", "score", "bonus", 10), trigger("AWARD_AFTER", "shared", "inspiration", 4, "add", {"award_best": true})])
	var award_state: Dictionary = Model.select_project(Roster.fresh(), "评奖", "act", "fantasy", 1).state
	award_state.month = 12
	award_state.work = {"g": 6000.0, "i": 4000.0, "p": 4000.0, "b": 0.0}
	var awarded := Model.advance_work(award_state, 1, 12)
	var annual: Dictionary = awarded.report.annual
	check(near(annual.score.total, 14010.0) and annual.awards.size() == 3, "Score bonus participates in award eligibility")
	check(annual.reward == 104 and awarded.report.skill_events.size() == 2, "Award-after reward sees finalized award")
	check(near(annual.work.g, 6000.0) and awarded.state.work.g == 0.0, "Award bonus does not permanently rewrite work attributes")
	check(Model.valid_state(JSON.parse_string(JSON.stringify(awarded.state))), "Award skill report validates")
	reset_fixture()
	install(0, 0, "仅提名", [trigger("AWARD_BEFORE", "score", "bonus", 10)])
	var edge: Dictionary = Model.select_project(Roster.fresh(), "边缘", "act", "fantasy", 1).state
	edge.month = 12
	edge.work = {"g": 1000.0, "i": 1000.0, "p": 995.0, "b": 0.0}
	var edge_result := Model.advance_work(edge, 1, 12)
	check(edge_result.report.annual.awards.size() == 1, "Bonus can turn a below-threshold score into a nomination")

	## 11. 损坏的运行记录与存档字段会被拒绝
	var damaged: Dictionary = awarded.state.duplicate(true)
	damaged.members[0].learned_skills = ["unknown"]
	check(not Model.valid_state(damaged), "Unknown learned skill ID rejected")
	damaged = awarded.state.duplicate(true)
	damaged.skill_runtime.counts = {"bad": 0.5}
	check(not Model.valid_state(damaged), "Malformed usage counter rejected")
	damaged = awarded.state.duplicate(true)
	damaged.skill_log[0].name = 12
	check(not Model.valid_state(damaged), "Malformed skill record rejected")
	Model.DEFINITIONS = originals
	Table.skills = original_skills
	print("SKILL_TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
