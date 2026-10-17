extends Control
## 新界面骨架：开始页 → 十个人物入口 → 人物资料页。
## 主界面背景取自 assets/backgrounds 下的图片，写进场景里的 Background 节点，
## 这样在编辑器里能直接对着背景图调人物矩形；缺图时隐藏该节点、回退场景纯色底。
## 人物入口的立绘按人物表路径写进场景里的 Portrait 子节点；配好立绘的入口除立绘外全透明，缺立绘时保留编号矩形。

const Model = preload("res://scripts/game_model.gd")
const MemberSheet = preload("res://scripts/member_sheet.gd")
const DutyPanel = preload("res://scripts/duty_assignment_panel.gd")
const WorkPanel = preload("res://scripts/monthly_work_panel.gd")
const TaskPanel = preload("res://scripts/task_assignment_panel.gd")
const TaskExecution = preload("res://scripts/task_execution_panel.gd")
const CharacterTable = preload("res://scripts/character_table.gd")
const GameCatalog = preload("res://scripts/game_catalog.gd")
const GameSelection = preload("res://scripts/game_selection_screen.gd")
const StartingRoster = preload("res://scripts/starting_roster.gd")
const RecruitmentPanel = preload("res://scripts/recruitment_panel.gd")
const AnnualAward = preload("res://scripts/annual_award_screen.gd")
const SettlementScreen = preload("res://scripts/settlement_screen.gd")
const DebugTools = preload("res://scripts/debug/debug_tools.gd")
const DebugPanel = preload("res://scripts/debug/debug_panel.gd")
static var CHARACTER_IDS: Array = CharacterTable.initial_ids()

const PAPER := Color("fffdf7")
const INK := Color("203e42")
const TEAL := Color("2a6965")
const GOLD := Color("efc56c")
const NumberDisplay = preload("res://scripts/number_display.gd")
const BACKGROUND_PATH := "res://assets/backgrounds/clubroom.png"
const BACKGROUND_NODE := "Background"
const PORTRAIT_NODE := "Portrait"
## 有立绘的入口默认「除立绘外全透明」，连焦点框也不画；改成 true 会给键盘／手柄焦点加一圈金边。
const PORTRAIT_FOCUS_HINT := false

@onready var start_screen: Control = $StartScreen
@onready var main_screen: Control = $MainScreen
@onready var character_screen: Control = $CharacterScreen
@onready var start_button: Button = $StartScreen/StartButton
@onready var close_button: Button = $CharacterScreen/CloseButton
@onready var time_panel: PanelContainer = $MainScreen/TimePanel
@onready var time_label: Label = $MainScreen/TimePanel/TimeLabel
@onready var inspiration_panel: PanelContainer = $MainScreen/InspirationPanel
@onready var inspiration_label: Label = $MainScreen/InspirationPanel/InspirationLabel
@onready var status_panel: PanelContainer = $MainScreen/StatusPanel
@onready var status_column: VBoxContainer = $MainScreen/StatusPanel/StatusColumn
@onready var project_label: Label = $MainScreen/StatusPanel/StatusColumn/ProjectLabel
@onready var gameplay_label: Label = $MainScreen/StatusPanel/StatusColumn/StatusRow/GameplayLabel
@onready var innovation_label: Label = $MainScreen/StatusPanel/StatusColumn/StatusRow/InnovationLabel
@onready var presentation_label: Label = $MainScreen/StatusPanel/StatusColumn/StatusRow/PresentationLabel
@onready var bug_label: Label = $MainScreen/StatusPanel/StatusColumn/StatusRow/BugLabel
@onready var schedule_button: Button = $MainScreen/ScheduleButton
@onready var character_buttons: Array[Button] = [
	$MainScreen/CharacterA, $MainScreen/CharacterB,
	$MainScreen/CharacterC, $MainScreen/CharacterD,
	$MainScreen/CharacterE, $MainScreen/CharacterF,
	$MainScreen/CharacterG, $MainScreen/CharacterH,
	$MainScreen/CharacterI, $MainScreen/CharacterJ,
]

var starting_roster: Control
var selected_character: String = ""
var state: Dictionary = Model.fresh()
var member_sheet: PanelContainer
var duty_panel: Control
var work_panel: Control
var task_panel: Control
var trait_labels: Dictionary = {}
var task_execution: Control
var invite_pending := false
var game_selection: Control
## 十二月结算得到的年度评奖结果；工作展示确认后交给评奖界面播放。
var pending_annual: Dictionary = {}
var award_screen: Control
var settlement_screen: Control
var recruitment_panel: Control
## 调试：面板只在 DebugTools.enabled() 时创建；满好感默认开启，随时可以在面板里关掉。
var debug_button: Button
var debug_panel: Control
var debug_full_affinity := true
var debug_affinity_backup: Array = []

func _ready() -> void:
	if CHARACTER_IDS.size() != character_buttons.size() or Model.DEFINITIONS.size() != CHARACTER_IDS.size():
		push_error("请修正 data/characters.json 后重新运行。")
		get_tree().quit(1)
		return
	var ui_font := SystemFont.new()
	ui_font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	var ui_theme := Theme.new()
	ui_theme.default_font = ui_font
	ui_theme.default_font_size = 24
	theme = ui_theme
	member_sheet = MemberSheet.new()
	character_screen.add_child(member_sheet)
	member_sheet.learn_requested.connect(_learn_skill)
	member_sheet.anchor_left = 0.12
	member_sheet.anchor_top = 0.12
	member_sheet.anchor_right = 0.88
	member_sheet.anchor_bottom = 0.98
	_attach_background(main_screen)
	duty_panel = DutyPanel.new()
	duty_panel.name = "DutyAssignmentPanel"
	duty_panel.assign_requested.connect(_assign_role)
	duty_panel.closed.connect(_on_duty_closed)
	main_screen.add_child(duty_panel)
	duty_panel.next_turn_requested.connect(_next_turn)
	work_panel = WorkPanel.new()
	work_panel.name = "MonthlyWorkPanel"
	add_child(work_panel)
	work_panel.closed.connect(_on_work_closed)
	task_panel = TaskPanel.new()
	add_child(task_panel)
	task_panel.task_requested.connect(_confirm_task)
	task_panel.closed.connect(func(): member_sheet.task_button.grab_focus())
	member_sheet.task_requested.connect(open_tasks)
	member_sheet.invite_requested.connect(open_invite)
	task_execution = TaskExecution.new()
	add_child(task_execution)
	task_execution.closed.connect(close_character)
	_style_hud_panels()
	_style_button(schedule_button, true)
	schedule_button.pressed.connect(open_schedule)
	refresh_time()
	_style_button(start_button, true)
	_style_button(close_button, true)
	game_selection = GameSelection.new()
	game_selection.name = "GameSelectionScreen"
	add_child(game_selection)
	game_selection.project_requested.connect(_select_project)
	award_screen = AnnualAward.new()
	award_screen.name = "AnnualAwardScreen"
	add_child(award_screen)
	award_screen.closed.connect(_on_award_closed)
	settlement_screen = SettlementScreen.new()
	settlement_screen.name = "SettlementScreen"
	add_child(settlement_screen)
	settlement_screen.return_requested.connect(_return_to_start)
	recruitment_panel = RecruitmentPanel.new()
	recruitment_panel.name = "RecruitmentPanel"
	add_child(recruitment_panel)
	recruitment_panel.confirmed.connect(_confirm_recruit)
	_build_debug_tools()
	starting_roster = StartingRoster.new()
	starting_roster.name = "StartingRoster"
	start_screen.add_child(starting_roster)
	starting_roster.selection_changed.connect(func(): start_button.disabled = not starting_roster.is_complete())
	start_button.disabled = true
	start_button.pressed.connect(start_game)
	close_button.pressed.connect(close_character)
	for index in character_buttons.size():
		var button := character_buttons[index]
		button.text = Model.DEFINITIONS[index].name
		button.tooltip_text = Model.DEFINITIONS[index].name
		button.add_theme_font_size_override("font_size", 18)
		if _attach_portrait(button, index):
			_style_portrait_button(button)
		else:
			_style_button(button, false)
		button.pressed.connect(open_character.bind(CHARACTER_IDS[index]))
	start_screen.show()
	main_screen.hide()
	character_screen.hide()
	starting_roster.slot_buttons[0].grab_focus()

func show_main() -> void:
	if award_screen.visible or work_panel.visible: return
	if Model.is_finished(state):
		open_settlement()
		return
	if not Model.pending_recruits(state).is_empty():
		open_recruitment()
		return
	if Model.needs_project_selection(state):
		open_game_selection()
		return
	start_screen.hide()
	character_screen.hide()
	game_selection.hide()
	main_screen.show()
	refresh_time()
	var active := Model.recruited_ids(state)
	if active.is_empty(): schedule_button.grab_focus()
	else: character_buttons[int(active[0])].grab_focus()

func start_game() -> void:
	if starting_roster.picker.visible or not starting_roster.is_complete(): return
	var result := Model.start_with_members(starting_roster.selected_ids)
	if not result.ok: return
	recruitment_panel.hide()
	starting_roster.close_picker()
	state = result.state
	## 新的一局重新开始记录：调试满好感会在下次打开调试面板时重新套用。
	debug_affinity_backup = []
	open_game_selection()

func open_game_selection() -> void:
	if award_screen.visible or work_panel.visible: return
	if Model.is_finished(state):
		open_settlement()
		return
	if not Model.pending_recruits(state).is_empty():
		open_recruitment()
		return
	start_screen.hide()
	main_screen.hide()
	character_screen.hide()
	game_selection.open(int(state.year), state.members.map(func(member: Dictionary): return int(member.affinity)), state.members.map(func(member: Dictionary): return bool(member.recruited)))

func _select_project(title: String, genre_id: String, topic_id: String, year: int) -> void:
	if not game_selection.visible:
		return
	var result := Model.select_project(state, title, genre_id, topic_id, year)
	if not result.ok:
		return
	state = result.state
	show_main()

func _on_work_closed() -> void:
	if not pending_annual.is_empty():
		## 年末评奖先于次年立项：播放完评奖界面后再进入下一年的选择页。
		var annual := pending_annual
		pending_annual = {}
		refresh_time()
		award_screen.open(annual)
		return
	if Model.needs_project_selection(state):
		open_game_selection()
	else:
		schedule_button.grab_focus()

func _on_award_closed() -> void:
	## 第三年进入两页结算；前两年继续招募与立项。
	refresh_time()
	show_main()

func open_settlement() -> void:
	if not Model.is_finished(state) or award_screen.visible or work_panel.visible: return
	start_screen.hide()
	main_screen.hide()
	character_screen.hide()
	game_selection.hide()
	recruitment_panel.hide()
	duty_panel.hide()
	settlement_screen.open(state)

func _return_to_start() -> void:
	if not settlement_screen.visible: return
	settlement_screen.hide()
	state = Model.fresh()
	pending_annual = {}
	selected_character = ""
	debug_affinity_backup = []
	refresh_time()
	start_screen.show()
	starting_roster.slot_buttons[0].grab_focus()

func open_recruitment() -> void:
	if award_screen.visible or work_panel.visible: return
	if Model.is_finished(state):
		open_settlement()
		return
	var pending := Model.pending_recruits(state)
	if pending.is_empty():
		open_game_selection()
		return
	start_screen.hide()
	main_screen.hide()
	character_screen.hide()
	game_selection.hide()
	var index := CHARACTER_IDS.find(pending[0])
	recruitment_panel.open(Model.DEFINITIONS[index])

func _confirm_recruit(character_id: String) -> void:
	if not recruitment_panel.visible or recruitment_panel.character_id != character_id: return
	var result := Model.confirm_recruit(state, character_id)
	if not result.ok: return
	state = result.state
	recruitment_panel.hide()
	refresh_time()
	show_main()

func open_character(character_id: String) -> void:
	if Model.is_finished(state): return
	if Model.needs_project_selection(state):
		return
	if work_panel.visible or task_execution.visible or task_panel.visible or award_screen.visible or recruitment_panel.visible or invite_pending or _debug_open():
		return
	if duty_panel.visible:
		duty_panel.close()
	var member_id := CHARACTER_IDS.find(character_id)
	if not Model.is_recruited(state, member_id):
		return
	selected_character = character_id
	member_sheet.display_member(state, member_id, character_id)
	main_screen.hide()
	character_screen.show()
	close_button.grab_focus()

func close_character() -> void:
	if Model.is_finished(state): return
	if task_panel.visible or task_execution.visible or award_screen.visible or recruitment_panel.visible or invite_pending or _debug_open():
		return
	if Model.needs_project_selection(state):
		open_game_selection()
		return
	var index := CHARACTER_IDS.find(selected_character)
	selected_character = ""
	character_screen.hide()
	main_screen.show()
	refresh_time()
	character_buttons[maxi(0, index)].grab_focus()

func _learn_skill(member_id: int, slot_index: int) -> void:
	if Model.is_finished(state): return
	if task_panel.visible or task_execution.visible or award_screen.visible or recruitment_panel.visible or invite_pending or _debug_open():
		return
	state = Model.learn(state, member_id, slot_index)
	refresh_time()
	member_sheet.display_member(state, member_id, CHARACTER_IDS[member_id])

func open_schedule() -> void:
	if Model.is_finished(state): return
	## 打开工作分配表；界面只发出调整请求，职责是否真的改变由游戏规则决定。
	if Model.needs_project_selection(state) or work_panel.visible or task_execution.visible or task_panel.visible or award_screen.visible or recruitment_panel.visible or invite_pending or _debug_open():
		return
	duty_panel.open(state)

func open_tasks() -> void:
	if Model.is_finished(state): return
	if not character_screen.visible or task_execution.visible or task_panel.visible or award_screen.visible or recruitment_panel.visible or invite_pending or _debug_open():
		return
	if Model.action_steps(state) <= 0 and not Model.Characters.free_task(state, Model.DEFINITIONS, CHARACTER_IDS.find(selected_character)):
		member_sheet.show_action_notice()
		return
	task_panel.open(state, CHARACTER_IDS.find(selected_character))

func open_invite() -> void:
	if Model.is_finished(state): return
	if not character_screen.visible or task_execution.visible or task_panel.visible or award_screen.visible or recruitment_panel.visible or invite_pending or _debug_open():
		return
	if Model.action_steps(state) <= 0:
		member_sheet.show_action_notice()
		return
	var member_id := CHARACTER_IDS.find(selected_character)
	if not Model.is_recruited(state, member_id):
		return
	var year := int(state.year)
	var month := int(state.month)
	invite_pending = true
	var confirmed: bool = await get_node("/root/TextConfirm").ask("邀约 %s？\n消耗 1 行动步数，好感度 +%d（上限 50）。" % [Model.DEFINITIONS[member_id].name, Model.invite_gain(state, member_id)])
	invite_pending = false
	if not confirmed or not character_screen.visible or CHARACTER_IDS.find(selected_character) != member_id:
		return
	var result := Model.execute_invite(state, member_id, year, month)
	if not result.ok:
		return
	state = result.state
	refresh_time()
	member_sheet.display_member(state, member_id, selected_character)
	task_execution.open(result.report)

func _confirm_task(task_id: String) -> void:
	var member_id := CHARACTER_IDS.find(selected_character)
	var year := int(state.year)
	var month := int(state.month)
	var task_name := task_id
	for task in Model.available_tasks(state, member_id):
		if task.id == task_id: task_name = task.name
	var cost := 0 if Model.Characters.free_task(state, Model.DEFINITIONS, member_id) else 1
	var confirmed: bool = await get_node("/root/TextConfirm").ask("让 %s 执行%s？\n消耗 %d 行动步数。\n此任务每款游戏（每年）全社团只能执行一次。" % [Model.DEFINITIONS[member_id].name, task_name, cost])
	task_panel.pending = false
	if not confirmed:
		return
	if not task_panel.visible or CHARACTER_IDS.find(selected_character) != member_id:
		return
	var result := Model.execute_task(state, member_id, task_id, year, month)
	if not result.ok:
		task_panel.open(state, CHARACTER_IDS.find(selected_character))
		return
	state = result.state
	task_panel.hide()
	refresh_time()
	member_sheet.display_member(state, member_id, selected_character)
	task_execution.open(result.report)

func _next_turn() -> void:
	if Model.is_finished(state): return
	if not duty_panel.visible or work_panel.visible or task_panel.visible or task_execution.visible or award_screen.visible or recruitment_panel.visible or invite_pending or _debug_open():
		return
	var result := Model.advance_work(state, int(state.year), int(state.month))
	if not result.ok:
		return
	state = result.state
	## 十二月结算带回年度评奖结果，等工作展示确认后再播放。
	pending_annual = result.report.get("annual", {})
	duty_panel.close()
	refresh_time()
	if Model.recruited_ids({"members": result.report.members}).is_empty():
		_on_work_closed()
	else:
		work_panel.open(result.report)

func refresh_time() -> void:
	## 主界面 HUD 统一刷新：年月、全局灵感与当前作品的四项属性。
	time_label.text = "第%d年%d月" % [int(state.year), int(state.month)]
	inspiration_label.text = "%s %d" % [Model.INSPIRATION.name, int(state.inspiration)]
	for index in character_buttons.size():
		character_buttons[index].visible = Model.is_recruited(state, index)
	refresh_status()

func refresh_status() -> void:
	## 主界面下方展示当前作品：名字、类型题材与四项属性。
	## 数值只读自模型快照，界面不参与结算。
	var work: Dictionary = state.get("work", {})
	project_label.text = _project_line()
	gameplay_label.text = "游戏性 " + NumberDisplay.text(float(work.get("g", 0.0)))
	innovation_label.text = "创新性 " + NumberDisplay.text(float(work.get("i", 0.0)))
	presentation_label.text = "表现力 " + NumberDisplay.text(_presentation(work))
	bug_label.text = "Bug " + NumberDisplay.text(float(work.get("b", 0.0)))
	for key in trait_labels:
		trait_labels[key].text = str(int(state.get("project_traits", {}).get(key, 0)))

func _project_line() -> String:
	## 作品名字与类型题材都来自当年的作品档案。
	var profile := Model.project_for_year(state)
	if profile.is_empty():
		return "「未命名作品」 · 未选类型 / 未选题材"
	return "「%s」 · %s / %s" % [
		_title_text(str(profile.get("title", ""))),
		GameCatalog.display_name(GameCatalog.GENRES, str(profile.get("genre_id", ""))),
		GameCatalog.display_name(GameCatalog.TOPICS, str(profile.get("topic_id", ""))),
	]

func _title_text(title: String) -> String:
	return title.strip_edges() if not title.strip_edges().is_empty() else "未命名作品"

func _presentation(work: Dictionary) -> float:
	## 表现力是作品属性本身，直接读模型。
	return Model.performance(work)

func _assign_role(member_id: int, role: int) -> void:
	state = Model.assign(state, member_id, role)
	duty_panel.apply_state(state, false)

func _on_duty_closed() -> void:
	schedule_button.grab_focus()

## ---------------- 调试 ----------------

func _build_debug_tools() -> void:
	## 调试入口只在 DebugTools.enabled() 时创建：正式版关闭总开关后，
	## 这里不会新建按钮与面板，F8 也会被 open_debug 的同一道判断挡住。
	if not DebugTools.enabled():
		return
	debug_button = Button.new()
	debug_button.name = "DebugButton"
	debug_button.text = "调试"
	debug_button.tooltip_text = "开发用：改当前作品属性、在本年内跳到更晚的月份、全员满好感（F8）。"
	debug_button.anchor_left = 0.0
	debug_button.anchor_top = 0.0
	debug_button.anchor_right = 0.0
	debug_button.anchor_bottom = 0.0
	debug_button.offset_left = 32.0
	debug_button.offset_top = 32.0
	debug_button.offset_right = 152.0
	debug_button.offset_bottom = 88.0
	_style_button(debug_button, false)
	debug_button.pressed.connect(open_debug)
	main_screen.add_child(debug_button)
	debug_panel = DebugPanel.new()
	debug_panel.name = "DebugPanel"
	main_screen.add_child(debug_panel)
	debug_panel.closed.connect(_on_debug_closed)
	debug_panel.work_requested.connect(_debug_change_work)
	debug_panel.month_requested.connect(_debug_jump_month)
	debug_panel.affinity_requested.connect(_set_debug_affinity)

func open_debug() -> void:
	if Model.is_finished(state): return
	## 只有停在主界面、没有其他弹窗在进行时才能打开；面板打开期间不让玩法被改动。
	if debug_panel == null or not main_screen.visible or _debug_open():
		return
	if duty_panel.visible or work_panel.visible or task_panel.visible or task_execution.visible or award_screen.visible or recruitment_panel.visible or game_selection.visible or invite_pending:
		return
	debug_panel.open(state, debug_full_affinity)
	_apply_debug_affinity_default()

func _debug_open() -> bool:
	return debug_panel != null and debug_panel.visible

func _on_debug_closed() -> void:
	if debug_button != null:
		debug_button.grab_focus()

func _debug_change_work(key: String, mode: String, amount: float) -> void:
	if not _debug_open():
		return
	var result := DebugTools.change_work(state, key, mode, amount)
	if result.ok:
		state = result.state
		refresh_time()
	debug_panel.show_state(state, debug_full_affinity)
	debug_panel.set_status(result.message)

func _debug_jump_month(month: int) -> void:
	if not _debug_open():
		return
	var result := DebugTools.jump_month(state, month)
	if result.ok:
		state = result.state
		refresh_time()
	debug_panel.show_state(state, debug_full_affinity)
	debug_panel.set_status(result.message)

func _set_debug_affinity(on: bool) -> void:
	if not _debug_open():
		return
	var result := DebugTools.set_full_affinity(state, on, debug_affinity_backup)
	if result.ok:
		state = result.state
		debug_affinity_backup = result.backup
		debug_full_affinity = on
		refresh_time()
	debug_panel.show_state(state, debug_full_affinity)
	debug_panel.set_status(result.message)

func _apply_debug_affinity_default() -> void:
	## 满好感默认开启：打开调试面板时把这套覆盖套到当前状态上（已经套过就不再重复），
	## 在面板里关掉后不再自动套用。这条路径只走调试面板，普通游玩不会经过，
	## 所以调试功能不会改变正式玩法里人物表的好感数值。
	if not debug_full_affinity or not debug_affinity_backup.is_empty():
		return
	var result := DebugTools.set_full_affinity(state, true, debug_affinity_backup)
	if not result.ok:
		return
	state = result.state
	debug_affinity_backup = result.backup
	refresh_time()
	debug_panel.show_state(state, debug_full_affinity)
	debug_panel.set_status(result.message)

func _unhandled_key_input(event: InputEvent) -> void:
	## F8 打开或关闭调试面板；调试关闭时 _debug_open() 与 open_debug() 都不放行。
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo or key.physical_keycode != KEY_F8:
		return
	if _debug_open():
		debug_panel.close()
	else:
		open_debug()
	get_viewport().set_input_as_handled()

func _style_hud_panels() -> void:
	var header := HBoxContainer.new()
	var status_column := $MainScreen/StatusPanel/StatusColumn
	status_column.add_child(header)
	status_column.move_child(header, 0)
	project_label.reparent(header)
	project_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var traits_row := HBoxContainer.new()
	traits_row.add_theme_constant_override("separation", 8)
	header.add_child(traits_row)
	for key in ["manuscripts", "creatures"]:
		var badge := HBoxContainer.new()
		badge.tooltip_text = "手稿：每份使全队表现力产出+1%" if key == "manuscripts" else "小生物：供相关角色技能与任务使用"
		traits_row.add_child(badge)
		var icon := TextureRect.new()
		icon.texture = load("res://assets/manuscript.svg" if key == "manuscripts" else "res://assets/creature.svg")
		icon.custom_minimum_size = Vector2(22, 22)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		badge.add_child(icon)
		var caption := Label.new()
		caption.text = "手稿" if key == "manuscripts" else "小生物"
		caption.add_theme_color_override("font_color", INK)
		caption.add_theme_font_size_override("font_size", 14)
		badge.add_child(caption)
		var count := Label.new()
		count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		count.add_theme_color_override("font_color", TEAL)
		count.add_theme_font_size_override("font_size", 18)
		badge.add_child(count)
		trait_labels[key] = count
	var box := _box(PAPER, INK, 2)
	box.set_corner_radius_all(6)
	box.content_margin_left = 20.0
	box.content_margin_right = 20.0
	box.content_margin_top = 6.0
	box.content_margin_bottom = 6.0
	time_panel.add_theme_stylebox_override("panel", box)
	inspiration_panel.add_theme_stylebox_override("panel", box.duplicate())
	status_panel.add_theme_stylebox_override("panel", box.duplicate())
	inspiration_label.add_theme_font_size_override("font_size", 24)
	inspiration_label.add_theme_color_override("font_color", TEAL)
	time_label.add_theme_font_size_override("font_size", 28)
	time_label.add_theme_color_override("font_color", INK)
	project_label.add_theme_font_size_override("font_size", 24)
	project_label.add_theme_color_override("font_color", INK)
	for label in [gameplay_label, innovation_label, presentation_label, bug_label]:
		label.add_theme_font_size_override("font_size", 22)
		label.add_theme_color_override("font_color", INK)

func _style_button(button: Button, filled: bool) -> void:
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var base := TEAL if filled else PAPER
	button.add_theme_stylebox_override("normal", _box(base, INK if not filled else TEAL, 2))
	button.add_theme_stylebox_override("hover", _box(base.darkened(0.06), TEAL, 3))
	button.add_theme_stylebox_override("pressed", _box(base.darkened(0.12), TEAL, 3))
	button.add_theme_stylebox_override("focus", _box(Color.TRANSPARENT, GOLD, 3))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, PAPER if filled else INK)

func _box(fill: Color, border: Color, width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(width)
	return box

func _style_portrait_button(button: Button) -> void:
	## 有立绘的入口默认除立绘外全透明：五个状态都不画底色与边框，只保留手型光标。
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	if PORTRAIT_FOCUS_HINT:
		button.add_theme_stylebox_override("focus", _box(Color.TRANSPARENT, GOLD, 3))

func _attach_background(screen: Control) -> void:
	var background := screen.get_node_or_null(BACKGROUND_NODE) as TextureRect
	if background == null:
		background = _create_background(screen)
	var texture := _load_texture(BACKGROUND_PATH)
	background.texture = texture
	background.visible = texture != null
	if screen.get_child(0) != background:
		screen.move_child(background, 0)

func _create_background(screen: Control) -> TextureRect:
	## 场景里没有 Background 节点时就地创建，铺满画面并垫在人物矩形下面。
	var background := TextureRect.new()
	background.name = BACKGROUND_NODE
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_child(background)
	return background

func _attach_portrait(button: Button, member_id: int) -> bool:
	## 人物表里的立绘写进场景里的 Portrait 子节点，并返回该入口是否配了立绘；
	## 没有立绘时保留矩形与角色名字。
	var portrait := button.get_node_or_null(PORTRAIT_NODE) as TextureRect
	if portrait == null:
		return false
	var definition: Dictionary = Model.DEFINITIONS[member_id]
	var texture := CharacterTable.portrait_texture(definition.portrait)
	portrait.texture = texture
	portrait.visible = texture != null
	if texture == null:
		return false
	button.text = ""
	button.tooltip_text = "%s · %s" % [definition.id, definition.name]
	return true

func _load_texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		push_warning("找不到背景图：%s，回退为纯色底。" % path)
		return null
	var resource := load(path)
	if not resource is Texture2D:
		push_warning("背景资源不是 Texture2D：%s，回退为纯色底。" % path)
		return null
	return resource
