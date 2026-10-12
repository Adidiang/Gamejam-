extends SceneTree
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
	for member_id in 4:
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

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	originals = Model.DEFINITIONS
	original_skills = Table.skills
	var production: Variant = JSON.parse_string(FileAccess.get_file_as_string(Table.PATH))
	check(Table.validate(production).is_empty(), "Production skill table validates")
	for member in originals:
		check(member.skills.map(func(slot: Dictionary): return int(slot.unlock_affinity)) == [0, 20, 50], "Three skill thresholds")
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
	var fresh := Model.fresh()
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
		var test := Model.fresh()
		test.inspiration = 20
		var threshold: int = Model.DEFINITIONS[0].skills[slot].unlock_affinity
		test.members[0].affinity = threshold - 1
		check(Model.learn(test, 0, slot) == test, "Paid skill locked below affinity threshold")
		test.members[0].affinity = threshold
		var bought := Model.learn(test, 0, slot)
		check(bought.inspiration == 20 - slot - 1 and bought.members[0].learned_skills.size() == 1, "Paid skill learned at exact threshold")
		bought.phase = "report"
		check(Model.learn(bought, 0, 0) == bought, "Learning is rejected during a report")
	reset_fixture()
	install(0, 0, "自动技能", [])
	fresh = Model.fresh()
	check(Runner.active(fresh, 0, Model.DEFINITIONS[0].skills[0]), "Skill 1 automatically active at zero affinity")
	check(Model.learn(fresh, 0, 0) == fresh, "Automatic skill never consumes inspiration")
	for slot in range(1, Model.SKILL_SLOTS):
		install(0, slot, "自动门槛", [])
		fresh.members[0].affinity = int(Model.DEFINITIONS[0].skills[slot].unlock_affinity) - 1
		check(not Runner.active(fresh, 0, Model.DEFINITIONS[0].skills[slot]), "Auto skill inactive below threshold")
		fresh.members[0].affinity += 1
		check(Runner.active(fresh, 0, Model.DEFINITIONS[0].skills[slot]), "Auto skill active at threshold")
	reset_fixture()
	install(0, 0, "立项技能", [trigger("PROJECT_BEFORE", "owner", "affinity", 5), trigger("PROJECT_AFTER", "shared", "inspiration", 3), trigger("PROJECT_AFTER", "work", "g", 2)])
	fresh = Model.fresh()
	var begun := Model.begin(fresh, "测试", 0, 0)
	check(begun.members[0].affinity == 5 and begun.inspiration == 5 and begun.work.g == 2, "Project before and after effects apply")
	check(fresh.inspiration == 2 and fresh.members[0].affinity == 0 and fresh.skill_runtime.counts.is_empty(), "Project preview is isolated")
	check(begun.skill_log.size() == 3, "Project effects emit source records")
	check(Model.begin(begun, "重复", 0, 0) == begun, "Project effects cannot be submitted twice")
	reset_fixture()
	install(0, 0, "任务技能", [trigger("ACTION_BEFORE", "work", "g", 10, "add", {"action_kind": "task", "actor_is_owner": true}), trigger("ACTION_AFTER", "work", "i", 3, "add", {"action_kind": "task"})])
	begun = Model.begin(Model.fresh(), "任务", 0, 0)
	var snapshot := JSON.stringify(begun)
	var turn := Model.resolve(begun, 0, 1, 1)
	check(near(turn.state.work.g, 10) and near(turn.state.work.i, 3), "Action pre and post effects apply")
	check(JSON.stringify(begun) == snapshot, "Preview does not consume real event or frequency state")
	var same_turn := Model.resolve(begun, 0, 1, 1)
	check(JSON.stringify(turn) == JSON.stringify(same_turn), "Preview and commit have identical deterministic results")
	var invite := Model.resolve(begun, 0, 0, 1)
	check(invite.state.work.g == 0 and invite.state.work.i == 0, "Task-only skill does not trigger on invitation")
	var other_actor := Model.resolve(begun, 1, 1, 1)
	check(other_actor.state.work.g == 0 and other_actor.state.work.i == 3, "Owner and actor are distinct")
	check(not Model.resolve(turn.state, 0, 1, 1).ok, "Duplicate month submit is rejected")
	reset_fixture()
	install(0, 1, "刚解锁", [trigger("ACTION_BEFORE", "work", "g", 99), trigger("ACTION_AFTER", "work", "g", 2)])
	begun = Model.begin(Model.fresh(), "解锁时机", 0, 0)
	begun.members[0].affinity = 19
	turn = Model.resolve(begun, 0, 0, 1)
	check(turn.state.work.g == 2 and turn.report.skill_events.size() == 1, "Newly unlocked auto skill applies only to later phases")
	reset_fixture()
	install(0, 0, "全队职责", [trigger("DUTY_BEFORE", "team", "g", 1), trigger("DUTY_AFTER", "work", "b", -1)])
	install(1, 0, "职责倍率", [trigger("DUTY_BEFORE", "team", "g", 0.5, "percent")])
	install(2, 0, "另一倍率", [trigger("DUTY_BEFORE", "team", "g", 0.5, "percent")])
	begun = Model.begin(Model.fresh(), "职责", 0, 0)
	turn = Model.resolve(begun, 0, 0, 1)
	check(turn.state.work.g == 8, "Team effect applied once; percentages add before multiplying")
	check(turn.state.work.b == 0, "Bug reductions cannot create negative bugs")
	check(turn.report.skill_events.size() == 4, "Duties collect each source once, outside member loop")
	reset_fixture()
	install(0, 0, "频次", [trigger("ACTION_AFTER", "shared", "inspiration", 1, "add", {}, "year")])
	begun = Model.begin(Model.fresh(), "频次", 0, 0)
	turn = Model.resolve(begun, 0, 0, 1)
	var second := Model.resolve(Model.acknowledge(turn.state), 0, 0, 2)
	check(turn.report.skill_events.size() == 1 and second.report.skill_events.is_empty(), "Year-limited effect triggers once across months")
	check(Model.valid_state(JSON.parse_string(JSON.stringify(turn.state))), "Skill runtime survives JSON round trip")
	check(Store.save_run(turn.state, "res://qa/skill_save.json") == OK, "Skill runtime saved")
	var restored := Store.load_run("res://qa/skill_save.json")
	var restored_second := Model.resolve(Model.acknowledge(restored), 0, 0, 2)
	check(restored_second.report.skill_events.is_empty(), "Load does not reset frequency usage")
	for frequency in ["event", "month", "year", "run"]:
		reset_fixture()
		install(0, 0, "限次范围", [trigger("ACTION_AFTER", "shared", "inspiration", 1, "add", {}, frequency)])
		begun = Model.begin(Model.fresh(), "周期", 0, 0)
		turn = Model.resolve(begun, 0, 0, 1)
		second = Model.resolve(Model.acknowledge(turn.state), 0, 0, 2)
		check(second.report.skill_events.size() == (1 if frequency in ["event", "month"] else 0), "Frequency behavior across months: " + frequency)
		var next_year := Model.acknowledge(second.state)
		next_year.year = 2
		var third := Model.resolve(next_year, 0, 0, 3)
		check(third.report.skill_events.size() == (0 if frequency == "run" else 1), "Frequency behavior across year IDs: " + frequency)
		var empty_plan := Model._plan(third.state)
		var replay := Runner.run(third.state, Model.DEFINITIONS, "ACTION_AFTER", Model._metadata(third.state, 0, 0), empty_plan)
		check(replay.records.is_empty() and replay.plan.inspiration == 0, "Same stage event cannot replay: " + frequency)
	reset_fixture()
	var temporary := trigger("ACTION_AFTER", "team", "g", 2)
	temporary.effect_id = "temporary_modifier"
	temporary.frequency = "year"
	temporary.params.apply_hook = "DUTY_BEFORE"
	temporary.params.duration = "month"
	install(0, 0, "临时修正", [temporary])
	begun = Model.begin(Model.fresh(), "临时", 0, 0)
	turn = Model.resolve(begun, 0, 0, 1)
	second = Model.resolve(Model.acknowledge(turn.state), 0, 0, 2)
	check(turn.state.work.g == 8 and second.state.work.g == 8, "Month modifier applies to later duties then expires")
	check(Model.valid_state(JSON.parse_string(JSON.stringify(turn.state))), "Temporary modifier is serializable")
	reset_fixture()
	install(0, 0, "年度评分", [trigger("AWARD_BEFORE", "score", "bonus", 10), trigger("AWARD_AFTER", "shared", "inspiration", 4, "add", {"award_best": true})])
	begun = Model.begin(Model.fresh(), "评奖", 0, 0)
	begun.month = 12
	begun.work = {"g": 147.0, "i": 147.0, "v": 73.5, "m": 73.5, "b": 0.0}
	begun.work.b = 100000.0
	turn = Model.resolve(begun, 0, 0, 12)
	check(near(turn.report.score.total, 80) and turn.report.score.best, "Score bonus participates in award eligibility")
	check(turn.report.bonus_inspiration == 14 and turn.report.skill_events.size() == 2, "Award-after reward sees finalized award")
	check(turn.state.work.g == 147, "Award bonus does not permanently rewrite work attributes")
	check(Model.valid_state(JSON.parse_string(JSON.stringify(turn.state))), "Award skill report validates")
	begun.month = 4
	var playtest := Model.resolve(begun, 0, 0, 4)
	check(playtest.report.skill_events.is_empty(), "Monthly playtest is not annual award")
	var damaged: Dictionary = turn.state.duplicate(true)
	damaged.members[0].learned_skills = ["unknown"]
	check(not Model.valid_state(damaged), "Unknown learned skill ID rejected")
	damaged = turn.state.duplicate(true)
	damaged.skill_runtime.counts = {"bad": 0.5}
	check(not Model.valid_state(damaged), "Malformed usage counter rejected")
	damaged = turn.state.duplicate(true)
	damaged.report.skill_events[0].name = 12
	check(not Model.valid_state(damaged), "Malformed skill report rejected")
	Model.DEFINITIONS = originals
	Table.skills = original_skills
	print("SKILL_TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
