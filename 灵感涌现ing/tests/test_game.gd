extends SceneTree
const Model = preload("res://scripts/game_model.gd")
const Store = preload("res://scripts/save_store.gd")
const SkillTable = preload("res://scripts/skills/skill_table.gd")
var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func close_to(a: float, b: float) -> bool:
	return absf(a - b) < 0.00001

func _init() -> void:
	# 规则测试使用独立的空白人物样本，允许策划自由修改正式人物表。
	var original_definitions: Array = Model.DEFINITIONS
	var original_skills := SkillTable.skills
	SkillTable.skills = original_skills.duplicate()
	for skill_id in SkillTable.skills:
		SkillTable.skills[skill_id] = original_skills[skill_id].duplicate(true)
		SkillTable.skills[skill_id].display_name = ""
		SkillTable.skills[skill_id].triggers = []
	Model.DEFINITIONS = original_definitions.duplicate(true)
	for definition in Model.DEFINITIONS:
		definition.stats = [0.0, 0.0, 0.0, 0.0]
		definition.affinity = 0
		definition.genre = ""
		definition.topic = ""
	var state: Dictionary = Model.begin(Model.fresh(), "测试游戏", 1, 1)
	check(state.members.all(func(member: Dictionary): return member.affinity == 0), "Empty preferences grant no affinity")
	check(Model.begin(state, "again", 0, 0) == state, "Repeated project confirmation is rejected")
	for member in state.members:
		member.affinity = 0
	state.work.b = 13.0
	var snapshot: String = JSON.stringify(state)
	var resolved: Dictionary = Model.resolve(state, 0, 5, 1)
	check(JSON.stringify(state) == snapshot, "Preview must not mutate original or nested state")
	check(close_to(resolved.state.work.g, 0), "Cleared programming and imagination produce no gameplay")
	check(close_to(resolved.state.work.i, 0), "Cleared imagination produces no innovation")
	check(close_to(resolved.state.work.v, 0) and close_to(resolved.state.work.m, 0), "Cleared art and music produce no output")
	check(close_to(resolved.state.work.b, 13), "Cleared programming cannot repair bugs")
	check(not Model.resolve(resolved.state, 0, 5, 1).ok, "Duplicate commit cannot run in report phase")
	var next: Dictionary = Model.acknowledge(resolved.state)
	check(not Model.resolve(next, 0, 5, 1).ok, "Stale turn ID is rejected")
	check(int(next.month) == 2, "Acknowledgement advances exactly one month")
	check(Model.acknowledge(next) == next, "Repeated report acknowledgement does nothing")
	check(Model.efficiency(0) == 1 and Model.efficiency(12) == 1 and Model.efficiency(100000) == 1, "Bug never reduces efficiency")
	var resource_state := Model.fresh()
	var earned := Model.gain_inspiration(resource_state, 7)
	check(earned.inspiration == 9 and resource_state.inspiration == 2, "Global resource gain is isolated")
	var spent := Model.spend_inspiration(earned, 4)
	check(spent.inspiration == 5 and earned.inspiration == 9 and spent.month == 1, "Global spending preserves month and input")
	check(Model.spend_inspiration(spent, 6) == spent and Model.spend_inspiration(spent, -1) == spent, "Overspend and negative costs rejected")
	check(Model.gain_inspiration(spent, -1) == spent, "Negative gains rejected")
	check(Model.gain_inspiration(earned, 10000).inspiration == Model.INSPIRATION.maximum, "Global resource uses defined cap")
	check(Model.valid_state(JSON.parse_string(JSON.stringify(spent))), "Global resource remains save compatible")
	check(close_to(Model.performance({"v": 80.0, "m": 0.0}), 40), "Unbalanced performance")
	check(close_to(Model.performance({"v": 40.0, "m": 40.0}), 80), "Balanced performance")
	var fresh: Dictionary = Model.begin(Model.fresh(), "技能检查", 0, 2)
	fresh.members[0].affinity = 19
	fresh.inspiration = 99
	check(Model.learn(fresh, 0).members[0].learned_skills.is_empty(), "Empty skill cannot learn")
	fresh.members[0].affinity = 20
	fresh.inspiration = 5
	check(Model.learn(fresh, 0).members[0].learned_skills.is_empty(), "Empty skill cannot learn")
	fresh.inspiration = 6
	var learned: Dictionary = Model.learn(fresh, 0)
	check(learned.members[0].learned_skills.is_empty() and learned.inspiration == 6 and learned.month == 1, "Empty skill cannot be purchased or consume resources")
	check(Model.assign(fresh, 0, -1) == fresh and Model.assign(fresh, 4, 0) == fresh, "Invalid assignment rejected")
	var setup_state: Dictionary = Model.fresh()
	var assigned: Dictionary = Model.assign(setup_state, 0, 3)
	check(int(assigned.members[0].role) == 3, "Setup phase can adjust duty before the project starts")
	check(int(setup_state.members[0].role) == 0, "Duty adjustment does not mutate the input state")
	var reported: Dictionary = Model.begin(Model.fresh(), "职责检查", 0, 0)
	reported.phase = "report"
	check(int(Model.assign(reported, 0, 3).members[0].role) == 0, "Report phase rejects duty changes")
	fresh.members[0].affinity = 45
	check(Model.invite_gain(fresh, 0) == 5, "Affinity capped at 50")
	for definition in Model.DEFINITIONS:
		definition.stats = [10.0, 10.0, 10.0, 10.0]
	var growth: Dictionary = Model.fresh()
	growth.members[0].affinity = 50
	check(close_to(Model.base_ability(0)[0], 10.0), "Base ability keeps the table attribute")
	check(close_to(Model.ability_bonus(growth, 0), 0.5), "Every affinity point grants one percent")
	check(close_to(Model.ability(growth, 0)[0], 15.0), "Final ability multiplies the base value once")
	growth.members[0].affinity = 0
	check(close_to(Model.ability(growth, 0)[0], 10.0), "Zero affinity keeps the base value")
	for definition in Model.DEFINITIONS:
		definition.stats = [0.0, 0.0, 0.0, 0.0]
	fresh.members[0].affinity = 0
	fresh.last_invite = 0
	check(Model.invite_gain(fresh, 0) == 10, "Repeated invite still grants ten affinity")
	fresh.last_invite = -1
	check(Model.invite_gain(fresh, 0) == 10, "Invite always grants ten affinity regardless of previous action")
	var best: Dictionary = Model.score({"g": 210, "i": 210, "v": 105, "m": 105, "b": 5})
	check(best.best and close_to(best.total, 100), "Best game threshold ignores bugs")
	check(Model.score({"g": 210, "i": 210, "v": 105, "m": 105, "b": 100000}) == best, "Bug has no scoring or award effect")
	check(Model.score({"g": 0, "i": 0, "v": 0, "m": 0, "b": 100}).total == 0, "Score is not negative")
	var playtest_low := Model.begin(Model.fresh(), "试玩奖励", 0, 0)
	playtest_low.month = 4
	var playtest_high := playtest_low.duplicate(true)
	playtest_high.work.b = 100000.0
	var low_result := Model.resolve(playtest_low, 0, 0, 4)
	var high_result := Model.resolve(playtest_high, 0, 0, 4)
	check(low_result.report.targets == high_result.report.targets and low_result.state.inspiration == high_result.state.inspiration, "Bug never changes playtest rewards or global resource gains")
	var run: Dictionary = Model.begin(Model.fresh(), "完整流程", 2, 2)
	for month in range(1, 13):
		var turn: Dictionary = Model.resolve(run, 0 if month % 3 == 0 else 1, 5 if month % 3 == 0 else 2, month)
		check(turn.ok, "Turn " + str(month) + " resolves")
		check(Model.valid_state(turn.state), "Report save is valid in month " + str(month))
		if month == 4 or month == 8:
			check(turn.report.targets.size() == 3 and turn.report.bonus_inspiration <= 3, "Playtest only rewards three quality attributes")
		run = Model.acknowledge(turn.state)
	check(run.phase == "ending" and run.month == 12 and run.history.size() == 12, "Twelve turns finish the game")
	check(not Model.resolve(run, 0, 0, 12).ok, "Cannot play thirteenth turn")
	check(Model.valid_state(JSON.parse_string(JSON.stringify(run))), "JSON round trip")
	var damaged: Dictionary = run.duplicate(true)
	damaged.version = 1
	check(not Model.valid_state(damaged), "Old character saves are rejected")
	damaged = run.duplicate(true)
	damaged.members[0].id = "unknown"
	check(not Model.valid_state(damaged), "Character identity mismatch is rejected")
	damaged = run.duplicate(true)
	damaged.members[0].role = 0.5
	check(not Model.valid_state(damaged), "Fractional role rejected")
	damaged = run.duplicate(true)
	damaged.members[0].affinity = Model.AFFINITY_MAX + 1
	check(not Model.valid_state(damaged), "Affinity above the cap is rejected")
	damaged = run.duplicate(true)
	damaged.members[0].affinity = -1
	check(not Model.valid_state(damaged), "Negative affinity is rejected")
	damaged = run.duplicate(true)
	damaged.history[0].work.b = "invalid"
	check(not Model.valid_state(damaged), "Malformed nested save rejected")
	var save_path := "res://qa/test_save.json"
	check(Store.save_run(run, save_path) == OK, "Save first version")
	check(not Store.load_run(save_path).is_empty(), "Load valid save")
	check(Store.save_run(run, save_path) == OK, "Save replaces existing file safely")
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	file.store_string("broken data")
	file.close()
	check(Store.load_run(save_path).phase == "ending", "Damaged primary save falls back to backup")
	print("MODEL_TESTS: %d checks, %d failures" % [checks, failures])
	Model.DEFINITIONS = original_definitions
	SkillTable.skills = original_skills
	quit(1 if failures > 0 else 0)
