extends Control
## 新界面骨架：开始页 → 四个人物入口 → 人物资料页。
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
static var CHARACTER_IDS: Array = CharacterTable.initial_ids()

const PAPER := Color("fffdf7")
const INK := Color("203e42")
const TEAL := Color("2a6965")
const GOLD := Color("efc56c")
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
]

var selected_character: String = ""
var state: Dictionary = Model.fresh()
var member_sheet: PanelContainer
var duty_panel: Control
var work_panel: Control
var task_panel: Control
var task_execution: Control
var invite_pending := false
var game_selection: Control

func _ready() -> void:
	if CHARACTER_IDS.size() != 4 or Model.DEFINITIONS.size() != 4:
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
	start_button.pressed.connect(start_game)
	close_button.pressed.connect(close_character)
	for index in character_buttons.size():
		var button := character_buttons[index]
		button.text = CHARACTER_IDS[index]
		if _attach_portrait(button, index):
			_style_portrait_button(button)
		else:
			_style_button(button, false)
		button.pressed.connect(open_character.bind(CHARACTER_IDS[index]))
	start_screen.show()
	main_screen.hide()
	character_screen.hide()
	start_button.grab_focus()

func show_main() -> void:
	if Model.needs_project_selection(state):
		open_game_selection()
		return
	start_screen.hide()
	character_screen.hide()
	game_selection.hide()
	main_screen.show()
	refresh_time()
	character_buttons[0].grab_focus()

func start_game() -> void:
	state = Model.fresh_annual()
	open_game_selection()

func open_game_selection() -> void:
	start_screen.hide()
	main_screen.hide()
	character_screen.hide()
	game_selection.open(int(state.year))

func _select_project(title: String, genre_id: String, topic_id: String, year: int) -> void:
	if not game_selection.visible:
		return
	var result := Model.select_project(state, title, genre_id, topic_id, year)
	if not result.ok:
		return
	state = result.state
	show_main()

func _on_work_closed() -> void:
	if Model.needs_project_selection(state):
		open_game_selection()
	else:
		schedule_button.grab_focus()

func open_character(character_id: String) -> void:
	if Model.needs_project_selection(state):
		return
	if work_panel.visible or task_execution.visible or task_panel.visible or invite_pending:
		return
	if duty_panel.visible:
		duty_panel.close()
	var member_id := CHARACTER_IDS.find(character_id)
	if member_id < 0:
		return
	selected_character = character_id
	member_sheet.display_member(state, member_id, character_id)
	main_screen.hide()
	character_screen.show()
	close_button.grab_focus()

func close_character() -> void:
	if task_panel.visible or task_execution.visible or invite_pending:
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
	if task_panel.visible or task_execution.visible or invite_pending:
		return
	state = Model.learn(state, member_id, slot_index)
	refresh_time()
	member_sheet.display_member(state, member_id, CHARACTER_IDS[member_id])

func open_schedule() -> void:
	## 打开工作分配表；界面只发出调整请求，职责是否真的改变由游戏规则决定。
	if Model.needs_project_selection(state) or work_panel.visible or task_execution.visible or task_panel.visible or invite_pending:
		return
	duty_panel.open(state)

func open_tasks() -> void:
	if not character_screen.visible or task_execution.visible or task_panel.visible or invite_pending:
		return
	if Model.action_steps(state) <= 0:
		member_sheet.show_action_notice()
		return
	task_panel.open(state)

func open_invite() -> void:
	if not character_screen.visible or task_execution.visible or task_panel.visible or invite_pending:
		return
	if Model.action_steps(state) <= 0:
		member_sheet.show_action_notice()
		return
	var member_id := CHARACTER_IDS.find(selected_character)
	if member_id < 0:
		return
	var year := int(state.year)
	var month := int(state.month)
	invite_pending = true
	var confirmed: bool = await get_node("/root/TextConfirm").ask("邀约 %s？\n消耗 1 行动步数，好感度 +10（上限 50）。" % selected_character)
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
	var confirmed: bool = await get_node("/root/TextConfirm").ask("让 %s 执行美术概念设计？\n消耗 1 行动步数。\n每款游戏（每年）全社团只能执行一次。" % selected_character)
	task_panel.pending = false
	if not confirmed:
		return
	if not task_panel.visible or CHARACTER_IDS.find(selected_character) != member_id:
		return
	var result := Model.execute_task(state, member_id, task_id, year, month)
	if not result.ok:
		task_panel.open(state)
		return
	state = result.state
	task_panel.hide()
	refresh_time()
	member_sheet.display_member(state, member_id, selected_character)
	task_execution.open(result.report)

func _next_turn() -> void:
	if not duty_panel.visible or work_panel.visible or task_panel.visible or task_execution.visible or invite_pending:
		return
	var result := Model.advance_work(state, int(state.year), int(state.month))
	if not result.ok:
		return
	state = result.state
	duty_panel.close()
	refresh_time()
	work_panel.open(result.report)

func refresh_time() -> void:
	## 主界面 HUD 统一刷新：年月、全局灵感与当前作品的四项属性。
	time_label.text = "第%d年%d月" % [int(state.year), int(state.month)]
	inspiration_label.text = "%s %d" % [Model.INSPIRATION.name, int(state.inspiration)]
	refresh_status()

func refresh_status() -> void:
	## 主界面下方展示当前作品：名字、类型题材与四项属性。
	## 数值只读自模型快照，界面不参与结算。
	var work: Dictionary = state.get("work", {})
	project_label.text = _project_line()
	gameplay_label.text = "游戏性 %.1f" % float(work.get("g", 0.0))
	innovation_label.text = "创新性 %.1f" % float(work.get("i", 0.0))
	presentation_label.text = "表现力 %.1f" % _presentation(work)
	bug_label.text = "Bug %.1f" % float(work.get("b", 0.0))

func _project_line() -> String:
	## 优先读当年作品档案（名字与类型题材由游戏选择页写入）；
	## 旧原型状态没有年度档案，回退到 title／genre／topic 字段。
	var profile := Model.project_for_year(state)
	if profile.is_empty():
		var genre: int = clampi(int(state.get("genre", 0)), 0, Model.GENRES.size() - 1)
		var topic: int = clampi(int(state.get("topic", 0)), 0, Model.TOPICS.size() - 1)
		return "「%s」 · %s / %s" % [_title_text(str(state.get("title", ""))), Model.GENRES[genre], Model.TOPICS[topic]]
	return "「%s」 · %s / %s" % [
		_title_text(str(profile.get("title", ""))),
		GameCatalog.display_name(GameCatalog.GENRES, str(profile.get("genre_id", ""))),
		GameCatalog.display_name(GameCatalog.TOPICS, str(profile.get("topic_id", ""))),
	]

func _title_text(title: String) -> String:
	return title.strip_edges() if not title.strip_edges().is_empty() else "未命名作品"

func _presentation(work: Dictionary) -> float:
	## 表现力沿用模型推导（含任务直接产出）；旧状态缺字段时只显示直接产出。
	if not work.has("v") or not work.has("m"):
		return float(work.get("p", 0.0))
	return Model.performance(work)

func _assign_role(member_id: int, role: int) -> void:
	state = Model.assign(state, member_id, role)
	duty_panel.apply_state(state, false)

func _on_duty_closed() -> void:
	schedule_button.grab_focus()

func _style_hud_panels() -> void:
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
	## 没有立绘时保留矩形与编号文字。
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
