extends Control
## 工作分配表：四个职责方框，方框上方是职责名称，框内可以自由放置角色圆形。
## 界面只判断“圆形中心落在哪个方框”，职责是否真的改变由 ClubGame.assign 决定：
## 主界面收到 assign_requested 后同步回传 apply_state，界面据此确认调整是否生效。
## 拖动与“点击拿起再点击放下”共用同一套拿起状态和落点判断；拾起和落点全部在视口坐标里比较。

signal assign_requested(member_id: int, role: int)
signal closed
signal next_turn_requested

const Model = preload("res://scripts/game_model.gd")
const Token = preload("res://scripts/member_token.gd")

const PAPER := Color("fffdf7")
const INK := Color("203e42")
const TEAL := Color("2a6965")
const GOLD := Color("efc56c")
const MUTED := Color("72817a")

const DIALOG_SIZE := Vector2(1240, 620)
const BOARD_HEIGHT := 400.0
const DRAG_THRESHOLD := 6.0
const ASSIGNABLE_PHASES := ["setup", "ready"]
const TITLE := "工作分配表"
const HINT := "拖动角色，或点击拿起后再点击放下。圆心落在方框内即调整职责；落在框外会回到拿起前的位置。"

enum Phase { IDLE, PRESSED, DRAGGING, ARMED }

var dialog: PanelContainer
var dimmer: ColorRect
var status_label: Label
var next_turn_button: Button
var slot_titles: Array[Label] = []
var slot_boxes: Array[Panel] = []
var tokens: Array = []
var role_of_token: Array[int] = []

var _board: Control
var _token_layer: Control
var _box_styles: Array[StyleBoxFlat] = []
var _phase: int = Phase.IDLE
var _held: Control = null
var _press_point := Vector2.ZERO
var _grab_offset := Vector2.ZERO

func _ready() -> void:
	# 根节点不拦截输入；遮罩和对话框负责挡住身后的主界面。
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process_input(true)
	dimmer = ColorRect.new()
	dimmer.name = "Dimmer"
	dimmer.color = Color(0, 0, 0, 0.45)
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dimmer)
	dialog = PanelContainer.new()
	dialog.name = "Dialog"
	dialog.anchor_left = 0.5
	dialog.anchor_top = 0.5
	dialog.anchor_right = 0.5
	dialog.anchor_bottom = 0.5
	dialog.offset_left = -DIALOG_SIZE.x * 0.5
	dialog.offset_top = -DIALOG_SIZE.y * 0.5
	dialog.offset_right = DIALOG_SIZE.x * 0.5
	dialog.offset_bottom = DIALOG_SIZE.y * 0.5
	dialog.grow_horizontal = Control.GROW_DIRECTION_BOTH
	dialog.grow_vertical = Control.GROW_DIRECTION_BOTH
	dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	dialog.add_theme_stylebox_override("panel", _style(PAPER, Color("dcded1")))
	add_child(dialog)
	_build_body()
	visible = false

func open(state: Dictionary) -> void:
	_build_tokens()
	apply_state(state, true)
	next_turn_button.disabled = state.phase not in ASSIGNABLE_PHASES
	status_label.text = "" if state.phase in ASSIGNABLE_PHASES else "当前阶段不能调整职责，报告与结局阶段不会改动工作分配。"
	visible = true

func close() -> void:
	if not visible:
		return
	_cancel_hold()
	visible = false
	closed.emit()

func apply_state(state: Dictionary, relayout: bool) -> void:
	## 用真实游戏状态刷新界面职责；调整过程中不要重排，避免角色离开落点。
	if state.members.size() != tokens.size():
		push_warning("工作分配表收到的人物数量与界面不一致，已保持原有分工。")
		return
	for index in tokens.size():
		tokens[index].visible = Model.is_recruited(state, index)
		role_of_token[index] = clampi(int(state.members[index].role), 0, Model.ROLES.size() - 1)
	if relayout:
		_layout_tokens()

func is_holding() -> bool:
	return _phase != Phase.IDLE

func _build_body() -> void:
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	dialog.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(header)
	header.add_child(_label(TITLE, 30, INK))
	var hint := _label(HINT, 18, MUTED)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(hint)
	_board = Control.new()
	_board.name = "Board"
	_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_board.custom_minimum_size.y = BOARD_HEIGHT
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.resized.connect(_layout_tokens)
	column.add_child(_board)
	var row := HBoxContainer.new()
	row.name = "DutyRow"
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 24)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.add_child(row)
	for index in Model.ROLES.size():
		var slot := VBoxContainer.new()
		slot.name = "DutySlot" + str(index)
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot.add_theme_constant_override("separation", 10)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(slot)
		var title := _label(Model.ROLES[index], 24, TEAL)
		title.name = "DutyTitle" + str(index)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot.add_child(title)
		slot_titles.append(title)
		var box := Panel.new()
		box.name = "DutyBox" + str(index)
		box.size_flags_vertical = Control.SIZE_EXPAND_FILL
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := _style(Color("fffdf7", 0.35), INK, 3)
		box.add_theme_stylebox_override("panel", style)
		_box_styles.append(style)
		slot.add_child(box)
		slot_boxes.append(box)
	_token_layer = Control.new()
	_token_layer.name = "TokenLayer"
	_token_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_token_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.add_child(_token_layer)
	status_label = _label("", 18, MUTED)
	status_label.name = "StatusLabel"
	column.add_child(status_label)
	next_turn_button = Button.new()
	next_turn_button.name = "NextTurnButton"
	next_turn_button.text = "下一回合"
	next_turn_button.custom_minimum_size = Vector2(200, 52)
	next_turn_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	next_turn_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	next_turn_button.add_theme_stylebox_override("normal", _style(TEAL, TEAL))
	next_turn_button.add_theme_stylebox_override("hover", _style(TEAL.lightened(0.12), GOLD, 2))
	next_turn_button.add_theme_color_override("font_color", PAPER)
	next_turn_button.pressed.connect(func():
		if is_holding():
			_cancel_hold()
		next_turn_requested.emit()
	)
	column.add_child(next_turn_button)

func _build_tokens() -> void:
	if not tokens.is_empty():
		return
	for index in Model.DEFINITIONS.size():
		var definition: Dictionary = Model.DEFINITIONS[index]
		var token := Token.new()
		_token_layer.add_child(token)
		token.setup(index, definition.id, "%s · %s" % [definition.id, definition.name])
		tokens.append(token)
		role_of_token.append(0)

func _layout_tokens() -> void:
	## 按当前职责把圆形排进对应方框；同一职责多人时用网格错开。
	if tokens.is_empty() or slot_boxes.is_empty():
		return
	var groups: Array = [[], [], [], []]
	for token in tokens:
		if not token.visible: continue
		groups[role_of_token[token.member_id]].append(token)
	for role in slot_boxes.size():
		var rect := slot_boxes[role].get_global_rect()
		var group: Array = groups[role]
		if group.is_empty() or rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		var origin := _token_layer.get_global_transform().affine_inverse() * rect.position
		var columns := ceili(sqrt(float(group.size())))
		var rows := ceili(float(group.size()) / float(columns))
		var step := Vector2(rect.size.x / float(columns + 1), rect.size.y / float(rows + 1))
		for index in group.size():
			var token := group[index] as Token
			var column := index % columns
			var line := floori(float(index) / float(columns))
			var point := origin + Vector2(step.x * float(column + 1), step.y * float(line + 1)) - token.size * 0.5
			token.home_position = point
			token.position = point
	_highlight(-1)

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.is_action("ui_cancel"):
			if _phase == Phase.IDLE:
				close()
			else:
				_cancel_hold()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		if _phase != Phase.IDLE:
			_move_held((event as InputEventMouseMotion).position)
		return
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed and _phase != Phase.IDLE:
			_cancel_hold()
			get_viewport().set_input_as_handled()
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed:
		if _phase == Phase.IDLE:
			var token := _token_at(event.position)
			if token != null:
				_begin_hold(token, event.position)
				get_viewport().set_input_as_handled()
			elif not _inside_dialog(event.position):
				# 点击非本界面的部分：回到主界面。
				close()
				get_viewport().set_input_as_handled()
		elif _phase == Phase.ARMED:
			# 拿起后的第二次点击：框内放下，框外先取消再回到主界面。
			if _inside_dialog(event.position):
				_place()
			else:
				_cancel_hold()
				close()
			get_viewport().set_input_as_handled()
		return
	match _phase:
		Phase.PRESSED:
			# 只有按下没有拖动：视为点击拿起，等下一次点击才放下。
			_phase = Phase.ARMED
			status_label.text = "已拿起 %s，移到方框上再次点击放下。" % (_held as Token).member_text
			get_viewport().set_input_as_handled()
		Phase.DRAGGING:
			_place()
			get_viewport().set_input_as_handled()
		_:
			pass

func _begin_hold(token: Token, viewport_point: Vector2) -> void:
	_held = token
	_phase = Phase.PRESSED
	_press_point = viewport_point
	_grab_offset = _token_layer.get_global_transform().affine_inverse() * viewport_point - token.position
	token.set_highlight(true)
	status_label.text = "已拿起 %s。" % token.member_text

func _move_held(viewport_point: Vector2) -> void:
	var held := _held as Token
	if held == null:
		return
	if _phase == Phase.PRESSED:
		if viewport_point.distance_to(_press_point) < DRAG_THRESHOLD:
			return
		_phase = Phase.DRAGGING
	var local := _token_layer.get_global_transform().affine_inverse() * viewport_point
	held.position = local - _grab_offset
	var role := _role_at(held.get_global_rect().get_center())
	_highlight(role)
	if role >= 0:
		status_label.text = "圆心落在「%s」框内，放下即调整职责。" % Model.ROLES[role]
	else:
		status_label.text = "圆心不在方框内，放下后 %s 回到拿起前的位置。" % held.member_text

func _place() -> void:
	var held := _held as Token
	if held == null:
		return
	var role := _role_at(held.get_global_rect().get_center())
	var current: int = role_of_token[held.member_id]
	if role >= 0 and role != current:
		assign_requested.emit(held.member_id, role)
	# 主界面在信号里同步回传真实职责，这里按结果决定保留落点还是回到拿起前的位置。
	if role >= 0 and role_of_token[held.member_id] == role:
		held.home_position = held.position
		status_label.text = "%s 的职责：%s" % [held.member_text, Model.ROLES[role]]
	else:
		held.position = held.home_position
		if role < 0:
			status_label.text = "圆心不在任何方框内，%s 回到拿起前的位置。" % held.member_text
		else:
			status_label.text = "%s 的职责没有改变，回到拿起前的位置。" % held.member_text
	_release_hold()

func _release_hold() -> void:
	if _held != null:
		(_held as Token).set_highlight(false)
	_held = null
	_phase = Phase.IDLE
	_highlight(-1)

func _cancel_hold() -> void:
	if _held != null:
		var held := _held as Token
		held.position = held.home_position
		held.set_highlight(false)
	_held = null
	_phase = Phase.IDLE
	_highlight(-1)

func _highlight(role: int) -> void:
	for index in _box_styles.size():
		_box_styles[index].border_color = GOLD if index == role else INK

func _token_at(viewport_point: Vector2) -> Token:
	## 后加入的圆形画在上层，命中判断从上层往下找，只认圆形内部。
	for index in range(tokens.size() - 1, -1, -1):
		var token := tokens[index] as Token
		if token.visible and token.covers(viewport_point):
			return token
	return null

func _role_at(viewport_point: Vector2) -> int:
	for index in slot_boxes.size():
		if _contains(slot_boxes[index].get_global_rect(), viewport_point):
			return index
	return -1

func _inside_dialog(viewport_point: Vector2) -> bool:
	return _contains(dialog.get_global_rect(), viewport_point)

func _contains(rect: Rect2, viewport_point: Vector2) -> bool:
	## 方框四边都算有效落点，所以不直接用 Rect2.has_point 的右开下开判断。
	return viewport_point.x >= rect.position.x and viewport_point.x <= rect.position.x + rect.size.x \
		and viewport_point.y >= rect.position.y and viewport_point.y <= rect.position.y + rect.size.y

func _label(text: String, font_size: int, color: Color = INK) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _style(fill: Color, border: Color, width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	return style
