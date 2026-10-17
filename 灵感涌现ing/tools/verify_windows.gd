extends SceneTree
## Run against the exported executable, or the editor with --main-pack.
## The JSON report distinguishes native Release from editor/pack verification.
const Model = preload("res://scripts/game_model.gd")
const SkillTable = preload("res://scripts/skills/skill_table.gd")
const DebugTools = preload("res://scripts/debug/debug_tools.gd")
const DebugConfig = preload("res://scripts/debug/debug_config.gd")
var checks := 0
var failures: Array[String] = []
var report_path := ""

func _initialize() -> void:
	print("PACK_FLOW_BEGIN editor=%s debug=%s" % [OS.has_feature("editor"), OS.is_debug_build()])
	var args := OS.get_cmdline_user_args()
	for index in range(args.size() - 1):
		if args[index] == "--report-path": report_path = args[index + 1]
	_run.call_deferred()

func check(value: bool, message: String) -> bool:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)
	return value

func frames(count: int = 4) -> void:
	for frame in count: await process_frame

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless" or report_path.is_empty(): return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(report_path.get_base_dir().path_join(name + ".png"))

func wait_for_panel(panel: Control) -> bool:
	var deadline := Time.get_ticks_msec() + 6000
	while panel.playing and Time.get_ticks_msec() < deadline:
		await process_frame
	return check(not panel.playing and not panel.finish_button.disabled, "Result animation finishes and allows confirmation")

func choose_project(scene: Control, title: String) -> void:
	scene.game_selection.title_input.text = title
	scene.game_selection.genre_buttons[0].pressed.emit()
	scene.game_selection.topic_buttons[2].pressed.emit()
	await frames()
	check(not scene.game_selection.confirm_button.disabled, "Valid project can be confirmed")
	scene.game_selection.confirm_button.pressed.emit()
	await frames()

func _run() -> void:
	if OS.has_feature("editor"):
		DebugConfig.ENABLED = false
	else:
		check(not OS.is_debug_build(), "Uses release export template")
	check(not DebugTools.enabled(), "Flow check uses normal gameplay with debug disabled")
	check(Model.DEFINITIONS.size() == 10 and SkillTable.skills.size() == 30, "Pack contains ten characters and thirty skills")
	check(FileAccess.file_exists("res://data/characters.json") and FileAccess.file_exists("res://data/skills.json"), "Pack contains runtime JSON data")
	check(not FileAccess.file_exists("res://tests/test_game.gd") and not FileAccess.file_exists("res://tools/build_windows.ps1"), "Pack excludes development tests and build scripts")
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 720)
	var scene: Control = load("res://scenes/interface_shell.tscn").instantiate()
	root.add_child(scene)
	await frames()
	check(scene.start_screen.visible and scene.debug_button == null, "Starts at selection screen without debug UI")
	await capture("windows_start")
	for index in 2:
		scene.starting_roster.open_slot(index)
		scene.starting_roster.choose("a" if index == 0 else "b")
	scene.start_button.pressed.emit()
	await frames()
	check(scene.game_selection.visible and Model.recruited_ids(scene.state).size() == 2, "Start button recruits the selected pair and opens project selection")
	await choose_project(scene, "Windows 试玩验证")
	check(scene.main_screen.visible and scene.state.year == 1 and scene.state.month == 1, "Project confirmation enters first month")
	check(scene.state.members[0].affinity < 50 and scene.state.members[1].affinity < 50, "Release does not apply debug full affinity")
	await capture("windows_main")
	scene.open_character("b")
	await frames()
	check(scene.member_sheet.title_label.text.contains(Model.DEFINITIONS[1].name), "Character page reads bundled character data")
	await capture("windows_character")
	var affinity := int(scene.state.members[1].affinity)
	scene.member_sheet.invite_button.pressed.emit()
	await frames()
	var confirm = root.get_node("TextConfirm")
	confirm.confirm_button.pressed.emit()
	await frames()
	if not await wait_for_panel(scene.task_execution):
		finish(scene)
		return
	scene.task_execution.finish_button.pressed.emit()
	await frames()
	check(scene.state.members[1].affinity == mini(50, affinity + 15) and scene.state.action_steps == 0, "Bubble invitation applies skill bonus and consumes one action")
	for month in range(1, 13):
		print("PACK_FLOW_MONTH %d" % month)
		scene.open_schedule()
		scene._next_turn()
		await frames()
		if not await wait_for_panel(scene.work_panel):
			finish(scene)
			return
		check(Model.valid_state(scene.state), "Monthly state remains valid in exported build")
		scene.work_panel.finish_button.pressed.emit()
		await frames()
	check(scene.award_screen.visible and scene.state.annual_results.has("1"), "Twelfth month archives project and opens annual awards")
	await capture("windows_awards")
	var deadline := Time.get_ticks_msec() + 10000
	while scene.award_screen.visible and Time.get_ticks_msec() < deadline:
		if not scene.award_screen.continue_button.disabled: scene.award_screen.continue_button.pressed.emit()
		await frames()
	check(not scene.award_screen.visible, "Annual award flow can be completed")
	for recruit in 3:
		if not scene.recruitment_panel.visible: break
		scene.recruitment_panel.confirm_button.pressed.emit()
		await frames()
	check(scene.game_selection.visible and scene.state.year == 2, "After awards and recruitment the second project can be selected")
	await choose_project(scene, "Windows 第二年")
	check(scene.main_screen.visible and Model.valid_state(scene.state), "Second year returns to playable main screen")
	finish(scene)

func finish(scene: Control) -> void:
	var report := {"checks": checks, "failures": failures,
		"verification_mode": "exported_pack_with_editor_runtime" if OS.has_feature("editor") else "native_release",
		"release_build": not OS.is_debug_build(),
		"engine": Engine.get_version_info().string, "project_year": int(scene.state.year),
		"characters": Model.DEFINITIONS.size(), "skills": SkillTable.skills.size()}
	if not report_path.is_empty():
		var file := FileAccess.open(report_path, FileAccess.WRITE)
		if file == null:
			push_error("Cannot write release verification report")
			quit(1)
			return
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("EXPORTED_PACK_FLOW: %d checks, %d failures" % [checks, failures.size()])
	scene.queue_free()
	quit(1 if not failures.is_empty() else 0)
