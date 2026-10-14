extends SceneTree
## 调试功能检查：总开关关闭时不创建任何调试入口、DebugTools 全部拒绝；
## 作品属性修改、年内跳月（回退与跨年拒绝）、全员满好感与恢复按规则生效；
## 调试面板挡住身后主界面，跳月份不结算中间月份，界面显示与模型一致。
const Model = preload("res://scripts/game_model.gd")
const Config = preload("res://scripts/debug/debug_config.gd")
const Tools = preload("res://scripts/debug/debug_tools.gd")
var checks := 0
var failures := 0
var scene

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func close_to(a: float, b: float) -> bool:
	return absf(a - b) < 0.00001

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if not Tools.enabled():
		## 正式版构建里调试功能按设计关闭，没有需要验证的行为。
		print("Debug tools are disabled in this build; nothing to check.")
		quit(0)
		return
	_rules()
	await _ui()
	print("Debug tools: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _rules() -> void:
	var opened := Model.select_project(Model.fresh(), "调试测试", "act", "fantasy", 1)
	var state: Dictionary = opened.state

	## 1. 作品属性：叠加、直接替换、上下限与非法输入
	var bumped := Tools.change_work(state, "g", "add", 1200.5)
	check(bumped.ok and close_to(float(bumped.state.work.g), 1200.5), "增加可以在当前值上叠加作品属性")
	check(close_to(float(state.work.g), 0.0), "调试不修改传进来的状态")
	var replaced := Tools.change_work(bumped.state, "p", "set", 4000.0)
	check(replaced.ok and close_to(float(replaced.state.work.p), 4000.0), "设为可以直接替换作品属性")
	var floored := Tools.change_work(replaced.state, "b", "add", -50.0)
	check(floored.ok and close_to(float(floored.state.work.b), 0.0), "Bug 不会被改成负数")
	var capped := Tools.change_work(replaced.state, "g", "set", Tools.WORK_MAXIMUM + 500.0)
	check(capped.ok and close_to(float(capped.state.work.g), Tools.WORK_MAXIMUM), "作品属性限制在模型上限")
	check(not Tools.change_work(state, "x", "add", 1.0).ok, "未知的作品属性被拒绝")
	check(not Tools.change_work(state, "g", "multiply", 2.0).ok, "未知的修改方式被拒绝")
	check(not Tools.change_work(state, "g", "add", NAN).ok, "非数字被拒绝")
	check(not Tools.change_work(Model.fresh(), "g", "add", 1.0).ok, "本年未立项时拒绝改作品属性")

	## 2. 时间：只允许在本年内跳到更晚的月份，跨年与回退直接拒绝
	var jumped := Tools.jump_month(state, 12)
	check(jumped.ok and int(jumped.state.month) == 12 and int(jumped.state.year) == 1, "可以跳到本年更晚的月份")
	check(close_to(float(jumped.state.work.g), 0.0) and int(jumped.state.inspiration) == int(state.inspiration), "跳月份不补算中间月份的产出与灵感")
	check(Model.action_steps(jumped.state) == 1, "跳月份后行动步数恢复")
	check(Model.available_tasks(jumped.state).size() == 1, "跳月份后年度任务次数保留")
	check(not Tools.jump_month(state, 1).ok, "跳到当前月份被拒绝")
	check(not Tools.jump_month(jumped.state, 5).ok, "回退到更早的月份被拒绝")
	check(not Tools.jump_month(state, 0).ok and not Tools.jump_month(state, 13).ok, "非法月份被拒绝")
	check(not Tools.jump_month(Model.fresh(), 12).ok, "本年未立项时拒绝跳月份")
	var settled := Model.advance_work(jumped.state, 1, 12)
	check(settled.ok and settled.report.has("annual"), "跳到 12 月后可以正常结算年末评奖")
	check(Model.valid_state(settled.state), "跳月份后的状态仍然通过正式校验")

	## 3. 全员满好感：记录原始值，关闭后恢复
	var mode := Tools.set_full_affinity(state, true, [])
	check(mode.ok and mode.backup.size() == 4, "开启满好感时记录四个人的原始好感")
	check(mode.backup[0] == int(state.members[0].affinity), "记录的是开启前的好感")
	var maxed := true
	for member in mode.state.members:
		maxed = maxed and int(member.affinity) == Tools.AFFINITY_MAXIMUM
	check(maxed, "开启后所有人按好感上限计算")
	check(close_to(Model.ability_bonus(mode.state, 0), Tools.AFFINITY_MAXIMUM * Model.ABILITY_PER_AFFINITY), "满好感按现有规则提供增幅")
	check(not Tools.set_full_affinity(mode.state, true, mode.backup).ok, "重复开启被拒绝")
	var restored := Tools.set_full_affinity(mode.state, false, mode.backup)
	check(restored.ok and restored.backup.is_empty(), "关闭满好感后清空记录")
	check(int(restored.state.members[0].affinity) == mode.backup[0], "关闭后按记录恢复好感")
	check(not Tools.set_full_affinity(state, false, []).ok, "没有记录时关闭被拒绝")

	## 4. 总开关：关掉后所有入口都拒绝
	Config.ENABLED = false
	check(not Tools.enabled(), "关闭总开关后调试功能不可用")
	check(not Tools.change_work(state, "g", "add", 1.0).ok, "关闭总开关后拒绝改作品属性")
	check(not Tools.jump_month(state, 12).ok, "关闭总开关后拒绝跳月份")
	check(not Tools.set_full_affinity(state, true, []).ok, "关闭总开关后拒绝满好感")
	Config.ENABLED = true
	check(Tools.enabled(), "恢复总开关后调试功能可用")

func _ui() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1440, 900)

	## 5. 关闭总开关时不创建任何调试入口：正式版因此不会出现调试按钮
	Config.ENABLED = false
	var disabled_scene = load("res://scenes/interface_shell.tscn").instantiate()
	root.add_child(disabled_scene)
	for frame in 4:
		await process_frame
	check(disabled_scene.debug_button == null and disabled_scene.debug_panel == null, "关闭总开关后不创建调试按钮与面板")
	disabled_scene.queue_free()
	await process_frame
	Config.ENABLED = true

	scene = load("res://scenes/interface_shell.tscn").instantiate()
	root.add_child(scene)
	for frame in 4:
		await process_frame
	check(scene.debug_button != null and scene.debug_panel != null and scene.debug_button.visible, "调试启用时创建调试按钮与面板")
	check(not scene.debug_panel.visible, "调试面板默认不显示")

	## 6. 满好感默认开启，但只在打开调试面板时才套用：普通游玩不受调试影响
	scene.start_game()
	await process_frame
	check(scene.debug_full_affinity, "全员满好感默认开启")
	check(int(scene.state.members[0].affinity) == int(Model.DEFINITIONS[0].affinity), "普通游玩沿用人物表好感")
	scene._select_project("调试测试", "act", "fantasy", 1)
	await process_frame
	check(scene.main_screen.visible, "立项后进入主界面")
	check(scene.time_label.text == "第1年1月", "主界面显示当前年月")
	var affinity_before := int(scene.state.members[0].affinity)

	## 7. 真实鼠标点开调试面板，并套用默认开启的满好感
	await click(scene.debug_button.get_global_rect().get_center())
	check(scene.debug_panel.visible, "点击调试按钮打开调试面板")
	check(int(scene.state.members[0].affinity) == Tools.AFFINITY_MAXIMUM, "打开调试面板时套用全员满好感")
	check(scene.debug_panel.status_label.text.contains("满好感"), "面板提示满好感的套用结果")
	check(scene.debug_panel.affinity_check.button_pressed, "满好感开关默认打开")
	check(scene.debug_panel.work_inputs["g"].text == "0.0", "面板显示当前作品属性")

	## 8. 改作品属性：主界面同步刷新，非法输入不改数值
	scene.debug_panel.work_inputs["g"].text = "1200"
	scene.debug_panel.work_add_buttons["g"].pressed.emit()
	await process_frame
	check(close_to(float(scene.state.work.g), 1200.0), "面板可以增加游戏性")
	check(scene.gameplay_label.text == "游戏性 1200.0", "属性栏显示调试后的游戏性")
	scene.debug_panel.work_inputs["p"].text = "4000"
	scene.debug_panel.work_set_buttons["p"].pressed.emit()
	await process_frame
	check(close_to(float(scene.state.work.p), 4000.0), "面板可以直接设为表现力")
	check(scene.presentation_label.text == "表现力 4000.0", "属性栏显示调试后的表现力")
	scene.debug_panel.work_inputs["g"].text = "abc"
	scene.debug_panel.work_add_buttons["g"].pressed.emit()
	await process_frame
	check(close_to(float(scene.state.work.g), 1200.0), "非法输入不改动数值")
	check(not scene.debug_panel.status_label.text.is_empty(), "非法输入给出提示")

	## 9. 跳月份：非法与回退被拒绝，跳转不推进年份
	scene.debug_panel.month_input.text = "13"
	scene.debug_panel.jump_button.pressed.emit()
	await process_frame
	check(int(scene.state.month) == 1 and not scene.debug_panel.status_label.text.is_empty(), "非法月份被拒绝并给出原因")
	scene.debug_panel.month_input.text = "12"
	scene.debug_panel.jump_button.pressed.emit()
	await process_frame
	check(int(scene.state.month) == 12 and int(scene.state.year) == 1, "跳到 12 月不跨年")
	check(scene.time_label.text == "第1年12月", "跳月份后主界面年月同步")
	check(scene.debug_panel.status_label.text.contains("未结算中间月份"), "跳月份提示没有结算中间月份")
	scene.debug_panel.month_input.text = "3"
	scene.debug_panel.jump_button.pressed.emit()
	await process_frame
	check(int(scene.state.month) == 12, "回退被拒绝且月份不变")
	check(scene.debug_panel.status_label.text.contains("回退与跨年"), "回退给出被禁止的原因")
	check(scene.debug_panel.year_label.text == "第 1 年", "面板只显示当前年份")

	## 10. 满好感开关：关掉后按记录恢复，人物页同步
	scene.debug_panel.affinity_check.button_pressed = false
	await process_frame
	check(not scene.debug_full_affinity, "面板可以关掉全员满好感")
	check(int(scene.state.members[0].affinity) == affinity_before, "关闭后好感按开启前记录的值恢复")
	check(close_to(Model.ability_bonus(scene.state, 0), affinity_before * Model.ABILITY_PER_AFFINITY), "关闭后能力增幅回落")
	scene.debug_panel.affinity_check.button_pressed = true
	await process_frame
	check(scene.debug_full_affinity and int(scene.state.members[0].affinity) == Tools.AFFINITY_MAXIMUM, "面板可以重新打开全员满好感")
	scene.debug_panel.close()
	await process_frame
	check(not scene.debug_panel.visible, "关闭按钮收起调试面板")
	scene.open_character("a")
	await process_frame
	check(scene.member_sheet.affinity_label.text == "好感度    %d / %d" % [Tools.AFFINITY_MAXIMUM, Tools.AFFINITY_MAXIMUM], "人物页显示满好感")
	check(close_to(Model.ability_bonus(scene.state, 0), Tools.AFFINITY_MAXIMUM * Model.ABILITY_PER_AFFINITY), "满好感的能力增幅一致")
	scene.close_character()
	await process_frame
	check(scene.main_screen.visible, "关闭人物页回到主界面")

	## 11. 面板打开时挡住身后主界面，点界面外或 Esc 关闭
	await click(scene.debug_button.get_global_rect().get_center())
	check(scene.debug_panel.visible, "再次打开调试面板")
	await click(scene.schedule_button.get_global_rect().get_center())
	check(not scene.duty_panel.visible, "调试面板打开时排期按钮被挡住")
	check(not scene.debug_panel.visible, "点调试面板外的部分回到主界面")
	await click(scene.debug_button.get_global_rect().get_center())
	check(scene.debug_panel.visible, "调试按钮可以反复打开面板")
	await press_key(KEY_ESCAPE)
	check(not scene.debug_panel.visible, "Esc 关闭调试面板")
	await press_key(KEY_F8)
	check(scene.debug_panel.visible, "F8 打开调试面板")
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://qa/debug_panel.png")
	await press_key(KEY_F8)
	check(not scene.debug_panel.visible, "F8 再按一次关闭调试面板")

	## 12. 未立项时打开面板：两条修改都被拒绝并给出原因
	scene.state = Model.fresh()
	scene.debug_panel.open(scene.state, scene.debug_full_affinity)
	await process_frame
	scene.debug_panel.work_inputs["g"].text = "10"
	scene.debug_panel.work_add_buttons["g"].pressed.emit()
	await process_frame
	check(close_to(float(scene.state.work.g), 0.0), "未立项时拒绝改作品属性")
	check(scene.debug_panel.status_label.text.contains("还没有立项"), "未立项时给出原因")
	scene.debug_panel.month_input.text = "6"
	scene.debug_panel.jump_button.pressed.emit()
	await process_frame
	check(int(scene.state.month) == 1, "未立项时拒绝跳月份")
	scene.debug_panel.close()
	await process_frame

	scene.queue_free()
	await process_frame

func click(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame

func press_key(keycode: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame


