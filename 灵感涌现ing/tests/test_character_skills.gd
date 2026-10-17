extends SceneTree
const Model = preload("res://scripts/game_model.gd")
const Rules = preload("res://scripts/skills/character_rules.gd")
const Table = preload("res://scripts/skills/skill_table.gd")
const TaskPanel = preload("res://scripts/task_assignment_panel.gd")
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func near(a: float, b: float) -> bool:
	return absf(a - b) < 0.001

func ready(ids: Array) -> Dictionary:
	var state := Model.fresh()
	state.run_id = "ten-characters"
	for id in ids: state.members[id].recruited = true
	state = Model.select_project(state, "角色技能测试", "act", "modern", 1).state
	state.inspiration = 1000
	return state

func learn(state: Dictionary, id: int, slot: int) -> Dictionary:
	state.members[id].affinity = 50
	return Model.learn(state, id, slot)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	check(Model.DEFINITIONS.size() == 10 and Table.skills.size() == 30, "Ten characters and thirty skills loaded")
	for definition in Model.DEFINITIONS:
		check(not definition.name.is_empty() and float(definition.stats.reduce(func(a, b): return a + b)) > 0, "Every character has name and abilities")
		for slot in definition.skills: check(not Table.skills[slot.skill_id].display_name.is_empty(), "Every skill has production data")
	var s := ready([1, 3])
	s.members[1].affinity = 0
	var invited := Model.execute_invite(s, 1, 1, 1)
	check(invited.state.members[1].affinity == 15, "Bubble invite gains fifteen")
	s = learn(s, 1, 1)
	s.members[3].affinity = 10
	var result := Model.execute_task(s, 1, "memory_share", 1, 1)
	check(result.ok and result.state.members[3].affinity == 50, "Memory task equalizes lowest member")
	check(not Model.execute_task(s, 3, "memory_share", 1, 1).ok, "Exclusive task cannot be executed by another member")
	s = learn(s, 1, 2)
	check(s.extra_recruitment, "Bubble arms recruitment bonus immediately")
	s.month = 12
	s.annual_projects["1"].genre_id = "rpg"
	s.annual_projects["1"].topic_id = "fantasy"
	result = Model.advance_work(s, 1, 12)
	check(result.state.recruitment["2"].selected.size() == 3 and not result.state.extra_recruitment, "Next recruitment selects three and consumes bonus")
	check(Model.valid_state(JSON.parse_string(JSON.stringify(result.state))), "Three-recruit archive survives JSON validation")
	s = ready([2, 7])
	s.members[7].affinity = 0
	s = learn(s, 2, 1)
	check("h_skill_2" in s.members[7].learned_skills and Rules.has_skill(s, Model.DEFINITIONS, 7, 1), "Concerto bypasses affinity and cost")
	check(s.inspiration == 990, "Concerto charges only initiating skill")
	s = learn(s, 2, 2)
	check(s.project_traits.creatures == 5 and "h_skill_3" in s.members[7].learned_skills, "Shared third skill grants five creatures once")
	Rules.sync(s, Model.DEFINITIONS)
	check(s.project_traits.creatures == 5, "Repeated synchronization does not repeat learning reward")
	result = Model.execute_task(s, 2, "art_concept", 1, 1)
	check(result.state.members[2].ability_growth[3] == 5 and result.state.project_traits.creatures == 7, "Pumpkin task permanently grows music and adds creatures")
	var base := Model.transform_output({"p": Model.ability(s, 2)[1] + Model.ability(s, 2)[2]}, Model.task_output_factor(s, 2, "art_concept"))
	check(near(result.report.task_delta.p, base.p * 1.5), "Pumpkin presentation bonus queries current creatures")
	s = Model.advance_work(result.state, 1, 1).state
	check(s.members[7].character_runtime.creature_stats == 7, "Bat caches creatures at month start")
	var white := Model.base_ability(7, s)
	Rules.sync(s, Model.DEFINITIONS, true)
	check(Model.base_ability(7, s) == white, "Bat white values do not accumulate on repeated refresh")
	result = Model.execute_task(s, 7, "sound_conduction", 1, 2)
	var bat_stats := Model.ability(s, 7)
	var expected := Model.transform_output({"g": 7.0 * (bat_stats[0] + bat_stats[3]) * 0.5}, Model.task_output_factor(s, 7, "sound_conduction"))
	check(near(result.report.task_delta.g, expected.g) and near(result.report.task_delta.p, expected.g), "Bat sound task applies ability converter once")
	s = ready([2])
	s = learn(s, 2, 2)
	s.members[7].recruited = true
	Rules.sync(s, Model.DEFINITIONS)
	check(s.project_traits.creatures == 5 and Rules.has_skill(s, Model.DEFINITIONS, 7, 2), "Late recruitment synchronizes learned skills")
	s = ready([3])
	s.work.b = 200
	s.character_month = ""
	Rules.sync(s, Model.DEFINITIONS, true)
	check(near(Model.ability(s, 3)[0], 270), "Mouse monthly BUG ability bonus appears in effective values")
	s.work.b = 0
	check(near(Model.ability(s, 3)[0], 270), "Mouse bonus remains fixed until next month")
	s = learn(s, 3, 1)
	s = learn(s, 3, 2)
	s.work.b = 23
	result = Model.execute_task(s, 3, "restructure", 1, 1)
	check(result.state.work.b == 0 and near(result.report.task_delta.g, 23), "Mouse restructuring awards actual repaired BUG, never over-repair")
	s.members[3].role = 3
	result = Model.advance_work(s, 1, 1)
	check(near(result.report.contributions[3].g, 23), "Mouse monthly repair also awards gameplay")
	s = ready([4, 1])
	check(near(Model.ability(s, 4)[0], 95) and near(Model.ability(s, 4)[1], 25), "Computer swaps lookup values")
	Rules.grow(s, Model.DEFINITIONS, 4, 1, 10)
	check(near(Model.base_ability(4, s)[1], 105) and near(Model.ability(s, 4)[0], 105), "Computer growth writes original stat before lookup swap")
	s = learn(s, 4, 1)
	s.members[4].role = 3
	s.work.b = 1000
	var basic := Model.advance_work(s, 1, 1)
	s = learn(s, 4, 2)
	result = Model.advance_work(s, 1, 1)
	check(near(result.report.contributions[4].repair, basic.report.contributions[4].repair * 1.66), "Computer six hands increases repair 66 percent")
	var growth := float(result.state.members[4].ability_growth[0]) + float(result.state.members[1].ability_growth[0])
	check(near(growth, 5), "Repair event grants one random teammate five programming")
	check(JSON.stringify(result) == JSON.stringify(Model.advance_work(s, 1, 1)), "Preview and commit share deterministic growth")
	s = ready([5, 1])
	s = learn(s, 5, 0)
	s = learn(s, 5, 1)
	s.work.p = 123
	s.action_steps = 0
	result = Model.execute_task(s, 5, "stylize", 1, 1)
	check(result.ok and result.state.action_steps == 0 and near(result.report.task_delta.i, 123), "Dragonfly can use free task with no action balance; copies presentation exactly")
	check(not Rules.free_task(result.state, Model.DEFINITIONS, 5), "Free task consumed once")
	check(not Model.execute_task(result.state, 5, "art_concept", 1, 1).ok, "Second task requires an action")
	s = learn(s, 5, 2)
	check(near(Model.ability(s, 5)[2], 250), "Dragonfly art adds affinity plus 20 percent plus imagination bonus")
	s = ready([6])
	check(s.members[6].ability_growth[2] == 2 and s.project_traits.creatures == 1, "Butterfly grows art and creature in first month")
	s = learn(s, 6, 1)
	s = learn(s, 6, 2)
	s.project_traits.manuscripts = 3
	s.project_traits.creatures = 4
	result = Model.execute_task(s, 6, "dream_real", 1, 1)
	check(result.state.project_traits.manuscripts == 6 and result.state.project_traits.creatures == 8 and result.report.inspiration_delta == 1, "Butterfly doubles both traits and adds fixed inspiration")
	result = Model.advance_work(s, 1, 1)
	check(result.report.inspiration_delta == 2 and result.state.project_traits.creatures == 5, "Butterfly monthly inspiration plus next-month creature")
	s = ready([8])
	s = learn(s, 8, 0)
	check(s.members[8].ability_growth[1] == 60, "Crow wisdom auto unlocks once at twenty affinity")
	Rules.sync(s, Model.DEFINITIONS)
	check(s.members[8].ability_growth[1] == 60, "Crow wisdom cannot repeatedly grant permanent stats")
	s.members[8].role = 0
	result = Model.advance_work(s, 1, 1)
	check(result.state.project_traits.manuscripts == int(floorf(result.report.contributions[8].i / 100.0)), "Crow turns innovation into manuscripts with fractional carry")
	s = learn(s, 8, 2)
	result = Model.execute_task(s, 8, "shared_world", 1, 1)
	check(near(result.report.task_delta.i, 0) and near(result.report.task_delta.p, 0), "Crow first project has no previous world to inherit")
	s.work.i = 222
	s.work.p = 333
	s.project_traits.manuscripts = 4
	s.month = 12
	s = Model.advance_work(s, 1, 12).state
	while not Model.pending_recruits(s).is_empty(): s = Model.confirm_recruit(s, Model.pending_recruits(s)[0]).state
	s = Model.select_project(s, "第二部", "act", "modern", 2).state
	var archived: Dictionary = s.annual_results["1"]
	result = Model.execute_task(s, 8, "shared_world", 2, 1)
	check(near(result.report.task_delta.i, archived.work.i) and near(result.report.task_delta.p, archived.work.p), "Crow inherits previous actual work values")
	check(result.state.project_traits.manuscripts >= archived.project_traits.manuscripts, "Crow inherits archived manuscripts")
	check(Model.valid_state(JSON.parse_string(JSON.stringify(result.state))), "Cross-year character runtime survives JSON validation")
	s = ready([9, 1])
	s.members[9].affinity = 0
	s.inspiration = 0
	s = Model.learn(s, 9, 2)
	check(s.inspiration == 50 and "j_skill_3" in s.members[9].learned_skills, "Angel third skill available at zero affinity grants fifty inspiration")
	s = Model.learn(s, 9, 2)
	check(s.inspiration == 50, "Angel reward cannot be claimed twice")
	s = learn(s, 9, 1)
	s.members[9].role = 0
	var saw_drunk := false
	var saw_tipsy := false
	for attempt in 24:
		s.run_id = "angel-%d" % attempt
		s.annual_projects["1"].id = "%s:project:1" % s.run_id
		result = Model.advance_work(s, 1, 1)
		var stats := Model.ability(s, 9)
		var is_drunk := Rules.drunk(s, 9)
		var brain: float = stats[1] * (1.5 if is_drunk else 1.0)
		var raw := Model.transform_output({"i": 1.2 * brain, "b": maxf(0, floorf((brain - stats[0]) * 0.1))}, Model.duty_output_factor(s, 9))
		check(near(result.report.contributions[9].i, raw.i * (1.0 if is_drunk else 2.0)), "Angel temporary brain/tipsy innovation calculation")
		check(near(result.report.contributions[9].b, raw.b * (3.0 if is_drunk else 2.0) + (5 if is_drunk else 0)), "Angel BUG buffs sum before extra five")
		check(near(result.state.members[9].ability_growth[1], 0), "Drunken brain does not become permanent growth")
		if is_drunk:
			saw_drunk = true
			check(result.state.members[1].ability_growth[0] == -5 and result.state.members[1].ability_growth[1] == 10, "Angel gift affects another recruited member")
		else: saw_tipsy = true
	check(saw_drunk and saw_tipsy, "Both exclusive alcohol states exercised")
	check(Model.valid_state(JSON.parse_string(JSON.stringify(result.state))), "Negative growth down to nonnegative base saves correctly")
	# 三年实际循环：所有技能同时存在，跨年后状态仍能存档，来源快照保持不变。
	s = ready([0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
	for id in 10:
		s.members[id].affinity = 50
		for slot in 3: s = Model.learn(s, id, slot)
	for turn in 36:
		if Model.needs_project_selection(s): s = Model.select_project(s, "组合测试%d" % s.year, "rpg", "fantasy", s.year).state
		var before := JSON.stringify(s)
		var actor := turn % 10
		var available := Model.available_tasks(s, actor)
		if not available.is_empty():
			result = Model.execute_task(s, actor, available[-1].id, s.year, s.month)
			check(JSON.stringify(s) == before, "Task preview never mutates source state")
			s = result.state
			check(Model.valid_state(JSON.parse_string(JSON.stringify(s))), "Combined character task state validates")
		if int(s.month) == 1:
			check(Rules.free_task(s, Model.DEFINITIONS, 5), "Dragonfly annual free task refreshes")
		var monthly := Model.advance_work(s, s.year, s.month)
		check(monthly.ok and Model.valid_state(JSON.parse_string(JSON.stringify(monthly.state))), "Combined roster survives monthly settlement and archive")
		s = monthly.state
	check(s.year == 4 and s.annual_results.size() == 3, "All thirty skills finish three complete projects")
	s = learn(ready([5, 6]), 5, 0)
	s = learn(s, 5, 1)
	s = learn(s, 6, 1)
	result = Model.execute_task(s, 5, "stylize", 1, 1)
	check(result.state.action_steps == 1, "Free task preserves a still-unused regular action")
	result = Model.execute_task(result.state, 6, "art_concept", 1, 1)
	check(result.ok and result.report.inspiration_delta == 1, "Second action in same month still executes its skills")
	s = ready([3])
	s.work.b = 100000
	s.character_month = ""
	Rules.sync(s, Model.DEFINITIONS, true)
	check(near(s.members[3].character_runtime.bug_bonus, 100), "Mouse hidden percentage cap applies")
	s = ready([9])
	s = learn(s, 9, 1)
	s.members[9].role = 0
	result = Model.advance_work(s, 1, 1)
	check(result.ok and result.state.members[9].ability_growth[1] == 0, "Angel with no teammates never gifts itself")
	var panel := TaskPanel.new()
	root.add_child(panel)
	s = learn(ready([3, 1]), 3, 2)
	panel.open(s, 3)
	check(panel.task_buttons.size() == 2 and panel.task_buttons[1].text.contains("系统重构"), "Mouse exclusive task is reachable in live UI")
	panel.open(s, 1)
	check(panel.task_buttons.size() == 1, "Other member UI hides exclusive task")
	panel.queue_free()
	print("CHARACTER_SKILLS_TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
