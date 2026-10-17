extends SceneTree
const Model = preload("res://scripts/game_model.gd")
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func settle() -> void:
	for frame in 5: await process_frame

func capture(file: String) -> void:
	await settle()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://qa/" + file + ".png")

func _run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1440, 900)
	var scene = load("res://scenes/interface_shell.tscn").instantiate()
	root.add_child(scene)
	await settle()
	scene.starting_roster.open_slot(0)
	await capture("ten_characters_roster")
	scene.starting_roster.close_picker()
	var state := Model.fresh()
	for member in state.members: member.recruited = true
	state = Model.select_project(state, "十位伙伴的作品", "act", "modern", 1).state
	state.inspiration = 1000
	for id in 10:
		state.members[id].affinity = 50
		for slot in 3: state = Model.learn(state, id, slot)
	state.project_traits.manuscripts = 12
	state.project_traits.creatures = 18
	scene.state = state
	scene.show_main()
	for resolution in [Vector2i(1440, 900), Vector2i(1280, 720)]:
		root.size = resolution
		await settle()
		for key in scene.trait_labels:
			check(scene.trait_labels[key].text == str(state.project_traits[key]), "Project badge displays actual trait count")
			check(scene.status_panel.get_global_rect().encloses(scene.trait_labels[key].get_global_rect()), "Trait count stays inside HUD")
		await capture("ten_characters_main_%d" % resolution.x)
		for id in [3, 7, 9]:
			scene.open_character(Model.DEFINITIONS[id].id)
			await settle()
			check(scene.member_sheet.title_label.text.contains(Model.DEFINITIONS[id].name), "Character details use complete names")
			if id == 9: check(scene.member_sheet.modifiers_label.text.contains("BUG 产出 +100%"), "Permanent angel BUG buff shown")
			if id == 7:
				scene.open_tasks()
				await settle()
				check(scene.task_panel.task_buttons.any(func(button: Button): return button.text.contains("声音传导构建")), "Bat task reachable via real character button")
				await capture("ten_characters_tasks_%d" % resolution.x)
				scene.task_panel.close()
			else: await capture("ten_characters_member_%d_%d" % [id, resolution.x])
			scene.close_character()
	scene.state = Model.fresh()
	for member in scene.state.members: member.recruited = true
	scene.open_game_selection()
	scene.game_selection.title_input.text = "偏好预览"
	scene.game_selection.genre_buttons[2].pressed.emit()
	scene.game_selection.topic_buttons[0].pressed.emit()
	await settle()
	check(scene.get_global_rect().encloses(scene.game_selection.confirm_button.get_global_rect()), "Full roster preference preview keeps confirm accessible")
	await capture("ten_characters_selection")
	scene.queue_free()
	await process_frame
	print("CHARACTER_UI_TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
