extends SceneTree
const Roster = preload("res://tests/fixtures/roster_fixture.gd")

const Table = preload("res://scripts/character_table.gd")
const Model = preload("res://scripts/game_model.gd")
const Sheet = preload("res://scripts/member_sheet.gd")
const Skills = preload("res://scripts/skills/skill_table.gd")
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
	check(Table.validate(Table.table).is_empty(), "Production character table is valid")
	check(Table.initial_ids() == ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"], "Exactly ten active characters in scene order")
	var initial := Roster.fresh()
	for index in Model.DEFINITIONS.size():
		check(initial.members[index].id == Table.initial_ids()[index], "Stable ID connects initial state to table")
		check(initial.members[index].affinity == Model.DEFINITIONS[index].affinity, "Initial affinity comes from table")
	check(Model.valid_state(initial), "Ten-member fresh state passes save validation")
	var last_definition: Dictionary = Model.DEFINITIONS[9].duplicate(true)
	Model.DEFINITIONS[9].stats = [10.0, 0.0, 0.0, 0.0]
	Model.DEFINITIONS[9].topic = "现代"
	var expanded: Dictionary = Model.select_project(initial, "十人测试", "act", "modern", 1).state
	check(expanded.members[9].affinity == 10, "Last member receives project preference affinity")
	expanded = Model.assign(expanded, 9, 3)
	check(expanded.members[9].role == 3, "Last member can change duties")
	var expanded_turn := Model.advance_work(expanded, 1, 1)
	check(expanded_turn.report.contributions.size() == 10 and expanded_turn.report.contributions[9].repair > 0, "Last member contributes to monthly work")
	var invited := Model.execute_invite(expanded_turn.state, 9, 1, 2)
	check(invited.ok and invited.state.members[9].affinity == 20, "Last member can be invited independently")
	check(Model.valid_state(JSON.parse_string(JSON.stringify(invited.state))), "Ten-member state survives JSON save round trip")
	var last_skill_id: String = last_definition.skills[1].skill_id
	var last_skill = Skills.skills[last_skill_id]
	var paid_skill = last_skill.duplicate(true)
	paid_skill.display_name = "末位员工测试技能"
	paid_skill.acquisition = "inspiration"
	paid_skill.inspiration_cost = 1
	Skills.skills[last_skill_id] = paid_skill
	var learned := Model.learn(invited.state, 9, 1)
	check(learned.members[9].learned_skills == [last_skill_id] and learned.members[0].learned_skills.is_empty(), "Last member learns skills independently")
	Skills.skills[last_skill_id] = last_skill
	Model.DEFINITIONS[9] = last_definition
	var invalid := Table.table.duplicate(true)
	invalid.characters[1].id = invalid.characters[0].id
	check(not Table.validate(invalid).is_empty(), "Duplicate character ID is rejected")
	invalid = Table.table.duplicate(true)
	invalid.initial_members[0] = "missing"
	check(not Table.validate(invalid).is_empty(), "Unknown active ID is rejected")
	invalid = Table.table.duplicate(true)
	invalid.characters[0].attributes.programming = -1
	check(not Table.validate(invalid).is_empty(), "Negative ability is rejected")
	invalid = Table.table.duplicate(true)
	invalid.characters[0].affinity = Table.AFFINITY_MAX + 1
	check(not Table.validate(invalid).is_empty(), "Affinity above the cap is rejected")
	invalid = Table.table.duplicate(true)
	invalid.characters[0].skills.pop_back()
	check(not Table.validate(invalid).is_empty(), "Missing skill slot is rejected")
	invalid = Table.table.duplicate(true)
	invalid.characters[0].skills.append({"skill_id": "b_skill_1", "unlock_affinity": 100})
	check(not Table.validate(invalid).is_empty(), "Extra fourth skill slot is rejected")
	invalid = Table.table.duplicate(true)
	invalid.characters[0].skills[1].unlock_affinity = 40
	check(not Table.validate(invalid).is_empty(), "Design document skill thresholds are enforced")
	invalid = Table.table.duplicate(true)
	invalid.characters[0].portrait = "D:/external.png"
	check(not Table.validate(invalid).is_empty(), "External portrait path is rejected")

	# 在 qa 中建立独立样本，正式人物表不会被测试修改。
	var sample := Table.table.duplicate(true)
	var extra: Dictionary = sample.characters[0].duplicate(true)
	extra.id = "test_member"
	extra.name = "新人物测试"
	extra.attributes = {"programming": 10, "imagination": 4, "art": 6, "music": 2}
	extra.affinity = 0
	extra.preferred_genre = "ACT"
	extra.preferred_topic = "奇幻"
	var fixture_skill = Skills.skills[extra.skills[0].skill_id].duplicate(true)
	fixture_skill.display_name = "测试技能"
	fixture_skill.description = "测试说明，仅用于确认人物表内容能显示。"
	fixture_skill.quip = "这是测试吐槽。"
	extra.other_modifiers = "测试修正说明"
	extra.portrait = "res://assets/icon.svg"
	sample.characters.append(extra)
	sample.initial_members[0] = extra.id
	check(Table.validate(sample).is_empty(), "Additional character can replace one active slot")
	var file := FileAccess.open("res://qa/characters_fixture.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(sample))
	file.close()
	var original_table := Table.table
	var original_skills := Skills.skills
	Skills.skills = original_skills.duplicate()
	Skills.skills[extra.skills[0].skill_id] = fixture_skill
	var original_definitions := Model.DEFINITIONS
	Table.table = Table.load_table("res://qa/characters_fixture.json")
	Model.DEFINITIONS = Table.definitions()
	var state := Roster.fresh()
	check(state.members[0].id == extra.id, "Replacement selected by ID, independent of table row order")
	check(Model.DEFINITIONS[0].stats == [10.0, 4.0, 6.0, 2.0], "Named attributes map in design order")
	var sheet := Sheet.new()
	root.add_child(sheet)
	sheet.display_member(state, 0, extra.id)
	check(sheet.title_label.text.contains(extra.name), "Filled name appears in member page")
	check(sheet.preference_label.text.contains("ACT") and sheet.preference_label.text.contains("奇幻"), "Preferences appear in member page")
	check(sheet.skill_names[0].text.contains(fixture_skill.display_name), "Filled skill name appears")
	check(sheet.skill_descriptions[0].text == fixture_skill.description, "Filled skill description appears")
	check(sheet.modifiers_label.text.contains(extra.other_modifiers), "Other modifiers appear as description")
	check(sheet.portrait_view.texture != null and not sheet.portrait_placeholder.visible, "Configured texture replaces portrait placeholder")
	state.members[0].affinity = Table.AFFINITY_MAX
	sheet.display_member(state, 0, extra.id)
	check(sheet.affinity_bar.value == Table.AFFINITY_MAX and sheet.affinity_bar.max_value == Table.AFFINITY_MAX, "Affinity bar uses state and fixed cap")
	check(is_equal_approx(float(sheet.stat_base_values[0].text), 10.0), "Base value is the table attribute")
	check(is_equal_approx(float(sheet.stat_final_values[0].text), 15.0), "Final value applies the one-percent affinity bonus")
	check(sheet.stat_final_values[0].get_theme_color("font_color") == Sheet.GROWTH, "Final value uses the growth color")
	state.members[0].ability_growth[0] = 0.9
	var display_snapshot := state.duplicate(true)
	sheet.display_member(state, 0, extra.id)
	check(sheet.stat_base_values[0].text == "10" and sheet.stat_final_values[0].text == "16", "Base and final attributes independently floor their actual values")
	check(state == display_snapshot and is_equal_approx(Model.ability(state, 0)[0], 16.35), "Member display preserves fractional growth and ability calculation")
	check(sheet.skill_statuses[2].text.contains("50 好感度解锁") and sheet.skill_quips[0].text == fixture_skill.quip, "Threshold status refreshes with affinity")
	Model.DEFINITIONS[0].portrait = ""
	sheet.display_member(state, 0, extra.id)
	check(sheet.portrait_view.texture == null and sheet.portrait_placeholder.visible, "Empty portrait clears previous character texture")
	state.members[0].affinity = 30
	state = Model.select_project(state, "偏好测试", "act", "fantasy", 1).state
	check(state.members[0].affinity == mini(Table.AFFINITY_MAX, 30 + 2 * Model.PREFERENCE_AFFINITY), "Matched preferences raise affinity on project selection")
	var capped := Roster.fresh()
	capped.members[0].affinity = Table.AFFINITY_MAX
	capped = Model.select_project(capped, "封顶测试", "act", "fantasy", 1).state
	check(capped.members[0].affinity == Table.AFFINITY_MAX, "Preference bonus cannot exceed the affinity cap")
	Table.table = original_table
	Skills.skills = original_skills
	Model.DEFINITIONS = original_definitions
	var scene = load("res://scenes/interface_shell.tscn").instantiate()
	root.add_child(scene)
	scene.state = Model.select_project(Roster.fresh(), "十人界面", "act", "modern", 1).state
	scene.show_main()
	check(scene.character_buttons.size() == 10, "Main screen exposes ten editable character buttons")
	for index in range(4, 10):
		var button: Button = scene.character_buttons[index]
		check(button.name == "Character" + str(Table.initial_ids()[index]).to_upper(), "New button maps to the matching scene node")
		check(button.has_node("Portrait"), "New character reserves an editable portrait node")
		button.pressed.emit()
		check(scene.character_screen.visible and scene.selected_character == Table.initial_ids()[index], "New character button opens its own member page")
		scene.close_character()
	scene.queue_free()
	sheet.queue_free()
	print("CHARACTER_TABLE_TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
