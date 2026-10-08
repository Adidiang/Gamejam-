extends SceneTree
const Model = preload("res://scripts/game_model.gd")
const Store = preload("res://scripts/save_store.gd")
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
	var state: Dictionary = Model.begin(Model.fresh(), "测试游戏", 1, 1)
	check(state.members[1].affinity == 12 and state.members[2].affinity == 6, "Theme preference applied exactly once")
	check(Model.begin(state, "again", 0, 0) == state, "Repeated project confirmation is rejected")
	for member in state.members:
		member.affinity = 0
	state.work.b = 13.0
	var snapshot: String = JSON.stringify(state)
	var resolved: Dictionary = Model.resolve(state, 0, 5, 1)
	check(JSON.stringify(state) == snapshot, "Preview must not mutate original or nested state")
	check(close_to(resolved.state.work.g, 11.4), "Worked example gameplay")
	check(close_to(resolved.state.work.i, 9.6), "Worked example innovation")
	check(close_to(resolved.state.work.v, 7.2) and close_to(resolved.state.work.m, 7.2), "Worked example visual and music")
	check(close_to(resolved.state.work.b, 3.2), "Testing happens before automatic development")
	check(not Model.resolve(resolved.state, 0, 5, 1).ok, "Duplicate commit cannot run in report phase")
	var next: Dictionary = Model.acknowledge(resolved.state)
	check(not Model.resolve(next, 0, 5, 1).ok, "Stale turn ID is rejected")
	check(int(next.month) == 2, "Acknowledgement advances exactly one month")
	check(Model.acknowledge(next) == next, "Repeated report acknowledgement does nothing")
	check(Model.efficiency(11.999) == 1 and Model.efficiency(12) == 0.85 and Model.efficiency(24) == 0.7, "Bug boundaries")
	check(close_to(Model.performance({"v": 80.0, "m": 0.0}), 40), "Unbalanced performance")
	check(close_to(Model.performance({"v": 40.0, "m": 40.0}), 80), "Balanced performance")
	var fresh: Dictionary = Model.begin(Model.fresh(), "技能检查", 0, 2)
	fresh.members[0].affinity = 19
	fresh.inspiration = 99
	check(not Model.learn(fresh, 0).members[0].learned, "Affinity 19 cannot learn")
	fresh.members[0].affinity = 20
	fresh.inspiration = 5
	check(not Model.learn(fresh, 0).members[0].learned, "Not enough inspiration")
	fresh.inspiration = 6
	var learned: Dictionary = Model.learn(fresh, 0)
	check(learned.members[0].learned and learned.inspiration == 0 and learned.month == 1, "Learning costs six inspiration and no turn")
	check(Model.learn(learned, 0) == learned, "Cannot buy skill twice")
	learned = Model.assign(learned, 0, 3)
	learned.work.b = 30.0
	var skilled: Dictionary = Model.resolve(learned, 1, 0, 1)
	check(close_to(skilled.report.contributions[0].repair, 1.5 * 8 * 1.08 * 1.2), "Specialist repair is boosted and not reduced by bugs")
	check(Model.assign(fresh, 0, -1) == fresh and Model.assign(fresh, 4, 0) == fresh, "Invalid assignment rejected")
	fresh.members[0].affinity = 95
	check(Model.invite_gain(fresh, 0) == 5, "Affinity capped at 100")
	fresh.members[0].affinity = 0
	fresh.last_invite = 0
	check(Model.invite_gain(fresh, 0) == 6, "Repeated invite reduced")
	fresh.last_invite = -1
	check(Model.invite_gain(fresh, 0) == 12, "Other action resets invite repetition")
	var best: Dictionary = Model.score({"g": 210, "i": 210, "v": 105, "m": 105, "b": 5})
	check(best.best and close_to(best.total, 90), "Best game threshold")
	check(not Model.score({"g": 210, "i": 210, "v": 105, "m": 105, "b": 5.01}).best, "Bug condition is independent of score")
	check(Model.score({"g": 0, "i": 0, "v": 0, "m": 0, "b": 100}).total == 0, "Score is not negative")
	var run: Dictionary = Model.begin(Model.fresh(), "完整流程", 2, 2)
	for month in range(1, 13):
		var turn: Dictionary = Model.resolve(run, 0 if month % 3 == 0 else 1, 5 if month % 3 == 0 else 2, month)
		check(turn.ok, "Turn " + str(month) + " resolves")
		check(Model.valid_state(turn.state), "Report save is valid in month " + str(month))
		if month == 4 or month == 8:
			check(turn.report.targets.size() == 4 and turn.report.bonus_inspiration <= 4, "Playtest rewards bounded")
		run = Model.acknowledge(turn.state)
	check(run.phase == "ending" and run.month == 12 and run.history.size() == 12, "Twelve turns finish the game")
	check(not Model.resolve(run, 0, 0, 12).ok, "Cannot play thirteenth turn")
	check(Model.valid_state(JSON.parse_string(JSON.stringify(run))), "JSON round trip")
	var damaged: Dictionary = run.duplicate(true)
	damaged.members[0].role = 0.5
	check(not Model.valid_state(damaged), "Fractional role rejected")
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
	quit(1 if failures > 0 else 0)
