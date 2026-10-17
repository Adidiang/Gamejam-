extends SceneTree
const Roster = preload("res://tests/fixtures/roster_fixture.gd")
const Model = preload("res://scripts/game_model.gd")
const Table = preload("res://scripts/skills/skill_table.gd")
const Definition = preload("res://scripts/skills/skill_definition.gd")
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1440, 900)
	var original := Table.skills
	Table.skills = original.duplicate()
	var slots: Array = Model.DEFINITIONS[0].skills
	for index in Model.SKILL_SLOTS:
		Table.skills[slots[index].skill_id] = Definition.from_row({"id": slots[index].skill_id,
			"name": "界面测试技能 %d" % (index + 1), "description": "这段技能介绍用于检查独立文本、自动生效和灵感习得按钮。",
			"quip": "这是角色的吐槽。", "acquisition": "inspiration" if index == 1 else "auto",
			"inspiration_cost": 2 if index == 1 else 0, "triggers": []})
	var scene = load("res://scenes/interface_shell.tscn").instantiate()
	root.add_child(scene)
	scene.state = Model.select_project(Roster.fresh(), "技能界面测试", "act", "modern", 1).state
	scene.state.members[0].affinity = 20
	scene.show_main()
	scene.character_buttons[0].pressed.emit()
	var sheet = scene.member_sheet
	check(sheet.skill_names.size() == Model.SKILL_SLOTS and sheet.skill_quips.size() == Model.SKILL_SLOTS, "Three complete skill presentation slots")
	check(sheet.skill_names[0].text.contains("界面测试技能 1"), "Skill name is displayed")
	check(sheet.skill_descriptions[0].text.contains("技能介绍") and sheet.skill_quips[0].text == "这是角色的吐槽。", "Description and quip are separate texts")
	check(sheet.skill_statuses[0].text.contains("自动生效") and not sheet.skill_buttons[0].visible, "Automatic zero-affinity skill has no purchase button")
	check(sheet.skill_buttons[1].visible and not sheet.skill_buttons[1].disabled and sheet.skill_buttons[1].text.contains("2 灵感"), "Affordable unlocked skill has configured-cost button")
	for frame in 3: await process_frame
	await capture("skills-before-learning")
	var month: int = scene.state.month
	sheet.skill_buttons[1].pressed.emit()
	check(scene.state.inspiration == 8 and scene.state.month == month, "Button deducts configured inspiration without a month")
	check(scene.inspiration_label.text == "灵感 8", "Main balance refreshes after shared resource consumption")
	check(slots[1].skill_id in scene.state.members[0].learned_skills, "UI records the correct skill ID")
	check(sheet.skill_buttons[1].disabled and sheet.skill_statuses[1].text.contains("已习得"), "UI refreshes learning state")
	check(sheet.inspiration_label.text.contains("灵感 8"), "Shared inspiration balance refreshes")
	sheet.skill_buttons[1].pressed.emit()
	check(scene.state.inspiration == 8 and scene.state.members[0].learned_skills.size() == 1, "Duplicate signal does not double-charge")
	await capture("skills-after-learning")
	scene.close_button.pressed.emit()
	scene.character_buttons[1].pressed.emit()
	check(scene.state.members[1].learned_skills.is_empty(), "Other character learning state is isolated")
	scene.close_button.pressed.emit()
	scene.state = Model.select_project(Roster.fresh(), "技能界面测试", "act", "modern", 1).state
	scene.state.members[0].affinity = 19
	scene.character_buttons[0].pressed.emit()
	check(sheet.skill_buttons[1].disabled and sheet.skill_statuses[1].text.contains("未解锁"), "Locked paid skill is disabled")
	scene.state.members[0].affinity = 20
	scene.state.inspiration = 1
	scene.open_character(Model.DEFINITIONS[0].id)
	check(sheet.skill_buttons[1].disabled, "Insufficient inspiration disables purchase")
	scene.state.phase = "report"
	scene.state.inspiration = 10
	scene.open_character(Model.DEFINITIONS[0].id)
	check(sheet.skill_buttons[1].disabled, "Report phase cannot purchase through UI")
	for dimensions in [Vector2i(1440, 900), Vector2i(1920, 1080), Vector2i(2560, 1080)]:
		root.size = dimensions
		for frame in 3: await process_frame
		check(scene.get_global_rect().encloses(sheet.get_global_rect()), "Skill panel fits viewport")
		check(not sheet.get_global_rect().intersects(scene.close_button.get_global_rect()), "Skill panel does not cover close button")
	Table.skills = original
	scene.queue_free()
	print("SKILL_UI_TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://qa/%s.png" % label)
