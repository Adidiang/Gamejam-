extends SceneTree
const Model = preload("res://scripts/game_model.gd")
const DebugConfig = preload("res://scripts/debug/debug_config.gd")
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
	var previous_debug: bool = DebugConfig.ENABLED
	DebugConfig.ENABLED = false
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
	var previous_time_scale := Engine.time_scale
	Engine.time_scale = 20.0
	await assigned_skill_buttons(scene)
	await dragonfly_free_task(scene)
	await bat_shared_learning(scene)
	await crow_auto_learning(scene)
	await angel_reward_and_work(scene)
	# 蝴蝶依赖手稿／小生物系统，按分工约定最后联调。
	await butterfly_task(scene)
	Engine.time_scale = previous_time_scale
	DebugConfig.ENABLED = previous_debug
	scene.queue_free()
	await process_frame
	print("CHARACTER_UI_TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func prepare(scene: Control, ids: Array, affinity: int = 50, inspiration: int = 500) -> void:
	var started := Model.start_with_members(ids)
	var selected := Model.select_project(started.state, "分工角色联调", "act", "modern", 1)
	var state: Dictionary = selected.state
	for id in Model.recruited_ids(state): state.members[id].affinity = affinity
	state.inspiration = inspiration
	Model.Characters.sync(state, Model.DEFINITIONS)
	scene.state = state
	scene.pending_annual = {}
	scene.show_main()
	await settle()

func open_member(scene: Control, id: int) -> void:
	scene.character_buttons[id].pressed.emit()
	await settle()
	check(scene.character_screen.visible and scene.member_sheet.selected_member == id, "Character entry opens the correct live member sheet")

func finish_panel(panel: Control) -> bool:
	var deadline := Time.get_ticks_msec() + 6000
	while panel.playing and Time.get_ticks_msec() < deadline: await process_frame
	var finished: bool = not panel.playing and not panel.finish_button.disabled
	check(finished, "Committed result animation finishes and enables confirmation")
	if finished:
		panel.finish_button.pressed.emit()
		await settle()
	return finished

func confirm_task(scene: Control, title: String) -> bool:
	scene.member_sheet.task_button.pressed.emit()
	await settle()
	var selected: Button = null
	for button in scene.task_panel.task_buttons:
		if button.text.contains(title): selected = button
	check(selected != null, "Owned exclusive task is reachable from its member sheet")
	if selected == null: return false
	selected.pressed.emit()
	await settle()
	var confirm = root.get_node("TextConfirm")
	check(confirm.screen.visible, "Exclusive task opens confirmation before spending an action")
	confirm.confirm_button.pressed.emit()
	await settle()
	return await finish_panel(scene.task_execution)

func assigned_skill_buttons(scene: Control) -> void:
	# 六人先验收；蝴蝶留到全部依赖检查后。同时检查自动技能与真实学习信号。
	for id in [3, 4, 5, 7, 8, 9]:
		await prepare(scene, [Model.DEFINITIONS[id].id, "c" if id == 7 else "a"])
		await open_member(scene, id)
		for slot in 3:
			var skill_id: String = Model.DEFINITIONS[id].skills[slot].skill_id
			var skill = Model.SkillTable.skills[skill_id]
			check(scene.member_sheet.skill_names[slot].text.contains(skill.display_name), "Assigned role displays configured skill name")
			var status: String = scene.member_sheet.skill_statuses[slot].text
			check(not status.contains("机制待实现") and not status.contains("内容待填写"), "Assigned skill has no implementation placeholder")
			if skill.acquisition == "auto":
				check(not scene.member_sheet.skill_buttons[slot].visible, "Automatic skill has no paid learning button")
				continue
			var balance: int = scene.state.inspiration
			check(not scene.member_sheet.skill_buttons[slot].disabled, "Unlocked skill can be learned from its real button")
			scene.member_sheet.skill_buttons[slot].pressed.emit()
			await settle()
			check(skill_id in scene.state.members[id].learned_skills and scene.state.inspiration == balance - skill.inspiration_cost, "Learning signal applies the selected skill and its exact cost or reward")
			check(scene.member_sheet.skill_buttons[slot].disabled and scene.member_sheet.skill_buttons[slot].text == "已习得", "Learned skill cannot be bought repeatedly")
		check(Model.valid_state(scene.state), "Live learning leaves a serializable valid state")
		scene.close_character()

func dragonfly_free_task(scene: Control) -> void:
	await prepare(scene, ["f", "a"])
	await open_member(scene, 5)
	for slot in [0, 1]: scene.member_sheet.skill_buttons[slot].pressed.emit()
	# 先用掉正常行动，再验证 UI 不会把仍有免费任务的蜻蜓挡在人物页。
	scene.member_sheet.invite_button.pressed.emit()
	await settle()
	root.get_node("TextConfirm").confirm_button.pressed.emit()
	await settle()
	if not await finish_panel(scene.task_execution): return
	check(scene.state.action_steps == 0, "Invitation consumes normal action without consuming dragonfly task quota")
	scene.state.work.p = 123.25
	await open_member(scene, 5)
	if not await confirm_task(scene, "风格化"): return
	check(scene.state.action_steps == 0 and not Model.Characters.free_task(scene.state, Model.DEFINITIONS, 5), "Zero-balance free task consumes only its annual quota")
	check(is_equal_approx(float(scene.state.work.i), 123.25), "Live stylize task copies presentation without random conversion")
	check(scene.innovation_label.text.contains("123"), "Main HUD refreshes after exclusive task")
	await open_member(scene, 5)
	scene.member_sheet.task_button.pressed.emit()
	await settle()
	check(not scene.task_panel.visible and scene.member_sheet.task_notice.visible, "Further task is blocked after free and normal actions are exhausted")
	scene.close_character()

func bat_shared_learning(scene: Control) -> void:
	await prepare(scene, ["h", "c"])
	scene.state.members[2].affinity = 0
	await open_member(scene, 7)
	for slot in [1, 2]: scene.member_sheet.skill_buttons[slot].pressed.emit()
	await settle()
	check("c_skill_2" in scene.state.members[2].learned_skills and "c_skill_3" in scene.state.members[2].learned_skills, "Bat learning synchronizes pumpkin despite low affinity")
	check(scene.state.inspiration == 445 and scene.state.project_traits.creatures == 5, "Shared learning charges only the initiating member and grants five creatures once")
	if not await confirm_task(scene, "声音传导构建"): return
	check(scene.state.work.g > 0 and scene.state.work.p > 0, "Bat exclusive task writes both attributes through the live flow")
	check(scene.trait_labels.creatures.text == "5", "Creature counter remains synchronized with actual state")

func crow_auto_learning(scene: Control) -> void:
	await prepare(scene, ["i", "a"], 10)
	await open_member(scene, 8)
	check(scene.state.members[8].ability_growth[1] == 0, "Crow wisdom remains locked before twenty affinity")
	scene.member_sheet.invite_button.pressed.emit()
	await settle()
	root.get_node("TextConfirm").confirm_button.pressed.emit()
	await settle()
	if not await finish_panel(scene.task_execution): return
	check(scene.state.members[8].affinity == 20 and scene.state.members[8].ability_growth[1] == 60, "Invitation across twenty affinity grants crow wisdom once")
	check(scene.state.inspiration == 500, "Crow automatic learning does not charge inspiration")
	await open_member(scene, 8)
	check(scene.member_sheet.skill_statuses[1].text.contains("自动生效") and not scene.member_sheet.skill_buttons[1].visible, "Automatic unlock is reflected in the live member sheet")
	scene.member_sheet.skill_buttons[0].pressed.emit()
	check(scene.state.members[8].ability_growth[1] == 60, "Subsequent learning does not repeat crow permanent growth")
	scene.close_character()

func angel_reward_and_work(scene: Control) -> void:
	await prepare(scene, ["j", "d"], 0, 0)
	await open_member(scene, 9)
	check(not scene.member_sheet.skill_buttons[2].disabled and scene.member_sheet.skill_buttons[2].text.contains("获得 50"), "Angel reward is claimable at zero affinity and zero inspiration")
	scene.member_sheet.skill_buttons[2].pressed.emit()
	await settle()
	check(scene.state.inspiration == 50 and scene.member_sheet.modifiers_label.text.contains("BUG 产出 +100%"), "Claim updates shared balance and permanent modifier display")
	scene.member_sheet.skill_buttons[2].pressed.emit()
	check(scene.state.inspiration == 50, "Repeated claim signal cannot grant another reward")
	scene.state.members[9].affinity = 20
	scene.member_sheet.display_member(scene.state, 9, "j")
	scene.member_sheet.skill_buttons[1].pressed.emit()
	scene.state.members[9].role = 0
	for attempt in 64:
		scene.state.run_id = "live-angel-%d" % attempt
		if Model.Characters.drunk(scene.state, 9): break
	scene.state.annual_projects["1"].id = "%s:project:1" % scene.state.run_id
	scene.close_character()
	scene.schedule_button.pressed.emit()
	await settle()
	scene._next_turn()
	await settle()
	if not await finish_panel(scene.work_panel): return
	check(scene.work_panel.value_labels[9].text.contains("喝醉了") and scene.work_panel.value_labels[9].text.contains("程序-5，脑洞+10"), "Work result displays drunken state and named teammate gift")
	check(scene.state.members[3].ability_growth[0] == -5 and scene.state.members[3].ability_growth[1] == 10, "Work flow commits angel gift to another member's white stats")
	check(Model.valid_state(scene.state), "Angel work flow produces a valid state")

func butterfly_task(scene: Control) -> void:
	await prepare(scene, ["g", "a"])
	await open_member(scene, 6)
	for slot in [1, 2]: scene.member_sheet.skill_buttons[slot].pressed.emit()
	scene.state.project_traits.manuscripts = 3
	scene.state.project_traits.creatures = 4
	var balance: int = scene.state.inspiration
	if not await confirm_task(scene, "绘梦成真"): return
	check(scene.state.project_traits.manuscripts == 6 and scene.state.project_traits.creatures == 8, "Butterfly live task doubles only manuscripts and creatures")
	check(scene.trait_labels.manuscripts.text == "6" and scene.trait_labels.creatures.text == "8", "Both main HUD trait counters refresh after butterfly task")
	check(scene.state.inspiration == balance + 1 and scene.task_execution.results_label.text.contains("灵感 +1"), "Butterfly fixed task inspiration appears in committed state and result display")
	await capture("assigned_characters_verified")
