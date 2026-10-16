extends SceneTree
const Model = preload("res://scripts/game_model.gd")
const Store = preload("res://scripts/save_store.gd")
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
	for ids in [[], ["a"], ["a", "b", "c"], ["a", "a"], ["a", "missing"], [1, "b"]]:
		check(not Model.start_with_members(ids).ok, "Model rejects incomplete, duplicate, and invalid starting rosters")
	var original := Model.fresh()
	var begun := Model.start_with_members(["a", "j"])
	check(begun.ok and Model.recruited_ids(begun.state) == [0, 9], "Only the two selected employees join at game creation")
	check(Model.valid_state(begun.state) and Model.recruited_ids(original).is_empty(), "Starting roster preserves valid saves and the empty-state factory")
	check(begun.state.members.all(func(member: Dictionary): return member.affinity == 0), "Initial recruitment grants no extra affinity")
	check(Store.save_run(begun.state, "res://qa/starting_roster.json") == OK, "Starting roster can be saved")
	check(Model.recruited_ids(Store.load_run("res://qa/starting_roster.json")) == [0, 9], "Save reload preserves both starting employees")
	var scene = load("res://scenes/interface_shell.tscn").instantiate()
	root.add_child(scene)
	await frames(3)
	var chooser = scene.starting_roster
	var snapshot: Dictionary = scene.state.duplicate(true)
	check(scene.start_screen.visible and chooser.slot_buttons.size() == 2 and scene.start_button.disabled, "Start screen has two empty selectors and waits for both choices")
	scene.start_button.pressed.emit()
	check(scene.state == snapshot and scene.start_screen.visible and not scene.game_selection.visible, "Incomplete roster cannot start even through a direct signal")
	await click(chooser.slot_buttons[0])
	check(chooser.picker.visible and chooser.active_slot == 0 and chooser.grid.columns == 5 and chooser.option_buttons.size() == 10, "Clicking a selector opens all ten employees in a five-column grid")
	check(chooser.picker.find_children("*", "ScrollContainer", true, false).is_empty(), "Employee chooser has no scrolling container")
	for index in 10:
		var button: Button = chooser.option_buttons[index]
		check(button.get_child_count() == 2 and button.get_node("MemberName").text == Model.DEFINITIONS[index].name, "Each employee card contains only portrait and name")
		check((button.get_node("Portrait").texture != null) == (index < 3), "Existing portraits load and unconfigured portraits stay empty")
	await click(chooser.option_buttons[1])
	check(chooser.selected_ids == ["b", ""] and not chooser.picker.visible and scene.start_button.disabled, "First choice fills its box without starting the game")
	check(scene.state == snapshot, "Choosing staff edits only the start-screen draft")
	await click(chooser.slot_buttons[1])
	check(chooser.option_buttons[1].disabled and chooser.option_buttons[1].modulate.a < 1.0, "Employee selected in the other box is visibly disabled")
	chooser.option_buttons[1].pressed.emit()
	check(chooser.selected_ids == ["b", ""] and chooser.picker.visible, "Duplicate choice is rejected even if a disabled button signal is emitted")
	await click(chooser.option_buttons[9])
	check(chooser.selected_ids == ["b", "j"] and not scene.start_button.disabled, "Two distinct employees enable starting")
	await click(chooser.slot_buttons[0])
	check(chooser.option_buttons[9].disabled and not chooser.option_buttons[1].disabled, "A box may keep its own selection but cannot take the other box's employee")
	await click(chooser.option_buttons[2])
	await click(chooser.slot_buttons[1])
	check(not chooser.option_buttons[1].disabled and chooser.option_buttons[2].disabled, "Replacing a selection releases the previous employee immediately")
	var draft: Array = chooser.selected_ids.duplicate()
	await click(chooser.close_button)
	check(chooser.selected_ids == draft and not chooser.picker.visible, "Closing chooser preserves both selections")
	await click(chooser.slot_buttons[0])
	await click_point(Vector2(8, 8))
	check(not chooser.picker.visible and chooser.selected_ids == draft, "Clicking outside closes the chooser without changing selections")
	await click(chooser.slot_buttons[0])
	var cancel := InputEventKey.new()
	cancel.keycode = KEY_ESCAPE
	cancel.pressed = true
	root.push_input(cancel, true)
	await frames(2)
	check(not chooser.picker.visible and chooser.selected_ids == draft, "Escape cancels the chooser")
	for resolution in [Vector2i(1280, 720), Vector2i(900, 700), Vector2i(1440, 900), Vector2i(1920, 1080)]:
		root.size = resolution
		await frames(4)
		var viewport: Rect2 = scene.get_global_rect()
		for slot in chooser.slot_buttons:
			check(viewport.encloses(slot.get_global_rect()) and not slot.get_global_rect().intersects(scene.start_button.get_global_rect()), "Selection boxes fit without covering the start button")
		await click(chooser.slot_buttons[0])
		check(viewport.encloses(chooser.dialog.get_global_rect()), "Employee picker fits the viewport")
		for button in chooser.option_buttons:
			check(button.visible and chooser.dialog.get_global_rect().grow(0.5).encloses(button.get_global_rect()), "All ten employees fit simultaneously without scrolling")
			var portrait: Rect2 = button.get_node("Portrait").get_global_rect()
			var name: Rect2 = button.get_node("MemberName").get_global_rect()
			check(button.get_global_rect().encloses(portrait) and button.get_global_rect().encloses(name) and portrait.end.y <= name.position.y, "Portrait and name remain within each compact card")
		await capture("starting_roster_picker_%d" % resolution.x)
		chooser.close_picker()
	# 启动时直接加入所选两人，首年立项仍正常结算已加入者的偏好好感。
	chooser.open_slot(0)
	chooser.choose("a")
	chooser.open_slot(1)
	chooser.choose("j")
	await capture("starting_roster_selected")
	await click(scene.start_button)
	check(scene.game_selection.visible and not scene.start_screen.visible and Model.recruited_ids(scene.state) == [0, 9], "Start button commits the selected pair before opening project selection")
	check(not scene.recruitment_panel.visible and Model.pending_recruits(scene.state).is_empty(), "Starting employees join directly without a new-year joining window")
	scene._select_project("双人开局", "rpg", "fantasy", 1)
	check(scene.state.members[0].affinity == 10 and scene.state.members[9].affinity == 0, "Starting employees participate in first-year project preferences")
	check(scene.character_buttons[0].visible and scene.character_buttons[9].visible and not scene.character_buttons[1].visible, "Main screen shows exactly the starting pair")
	scene.open_schedule()
	check(scene.duty_panel.tokens[0].visible and scene.duty_panel.tokens[9].visible and not scene.duty_panel.tokens[1].visible, "Starting employees are available for duties")
	check(Model.assign(scene.state, 9, 3).members[9].role == 3, "Last employee can work immediately after being selected")
	var definitions: Array = Model.DEFINITIONS.duplicate(true)
	for definition in Model.DEFINITIONS: definition.topic = "奇幻"
	var end_year: Dictionary = scene.state.duplicate(true)
	end_year.month = 12
	var next_year := Model.advance_work(end_year, 1, 12)
	check(Model.pending_recruits(next_year.state).size() == 2 and Model.pending_recruits(next_year.state).all(func(id: String): return id not in ["a", "j"]), "Later recruitment automatically excludes the starting employees")
	check(Model.valid_state(next_year.state), "Starting pair and later recruitment coexist in a valid saved state")
	Model.DEFINITIONS = definitions
	scene.queue_free()
	print("STARTING_ROSTER_TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func frames(count: int) -> void:
	for frame in count: await process_frame

func click(button: Control) -> void:
	await click_point(button.get_global_rect().get_center())

func click_point(point: Vector2) -> void:
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event, true)
		await frames(2)

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://qa/%s.png" % label)
