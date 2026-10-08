extends Control
const Model = preload("res://scripts/game_model.gd")
const Store = preload("res://scripts/save_store.gd")
const RoomArt = preload("res://scripts/room_view.gd")
const Sounds = preload("res://scripts/audio.gd")

const BG := Color("f0ede5")
const PAPER := Color("fffdf7")
const INK := Color("203e42")
const MUTED := Color("72817a")
const TEAL := Color("2a6965")
const GOLD := Color("efc56c")
const LINE := Color("dcded1")
const RED := Color("ad6250")
const CREAM := Color("e6e9dd")

var state: Dictionary = Model.fresh()
var selected := 0
var action := 0
var genre := 1
var topic := 1
var project_title := "纸飞机与未完成的梦"
var saved: Dictionary = {}
var page: Control
var font: SystemFont
var bold_font: SystemFont
var sound: Node
var commit_button: Button
var title_input: LineEdit
var notice := ""
var qa_mode := false
var locked := false
var return_to_game := false

func _ready() -> void:
	qa_mode = "--ui-smoke" in OS.get_cmdline_user_args()
	get_window().min_size = Vector2i(960, 600)
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	bold_font = SystemFont.new()
	bold_font.font_names = font.font_names
	bold_font.font_weight = 700
	var theme_base := Theme.new()
	theme_base.default_font = font
	theme_base.default_font_size = 18
	theme = theme_base
	sound = Sounds.new()
	add_child(sound)
	saved = {} if qa_mode else Store.load_run()
	if qa_mode:
		sound.enabled = false
	show_setup()
	if qa_mode:
		_run_ui_smoke.call_deferred()

func clear_page() -> void:
	if is_instance_valid(page):
		remove_child(page)
		page.queue_free()
	page = Control.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(page)
	var background := ColorRect.new()
	background.color = BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(background)
	commit_button = null

func style(color: Color, radius: int = 14, border: Color = Color.TRANSPARENT, width: int = 0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.corner_radius_top_left = radius
	box.corner_radius_top_right = radius
	box.corner_radius_bottom_left = radius
	box.corner_radius_bottom_right = radius
	box.border_color = border
	box.set_border_width_all(width)
	box.content_margin_left = 14
	box.content_margin_right = 14
	return box

func panel(rect: Rect2, color: Color = PAPER, radius: int = 16, parent: Control = null, border: Color = Color.TRANSPARENT) -> Panel:
	var node := Panel.new()
	node.position = rect.position
	node.size = rect.size
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_theme_stylebox_override("panel", style(color, radius, border, 1 if border.a > 0 else 0))
	(page if parent == null else parent).add_child(node)
	return node

func label_at(text: String, rect: Rect2, size_px: int = 18, color: Color = INK, heavy: bool = false, parent: Control = null) -> Label:
	var node := Label.new()
	node.text = text
	node.position = rect.position
	node.size = rect.size
	node.add_theme_font_override("font", bold_font if heavy else font)
	node.add_theme_font_size_override("font_size", size_px)
	node.add_theme_color_override("font_color", color)
	node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(page if parent == null else parent).add_child(node)
	return node

func paragraph(text: String, rect: Rect2, size_px: int = 17, color: Color = MUTED, parent: Control = null) -> Label:
	var node := label_at(text, rect, size_px, color, false, parent)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	return node

func button_at(text: String, rect: Rect2, callback: Callable, filled: bool = false, parent: Control = null, size_px: int = 17) -> Button:
	var button := Button.new()
	button.text = text
	button.position = rect.position
	button.size = rect.size
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", size_px)
	button.add_theme_color_override("font_color", PAPER if filled else INK)
	button.add_theme_color_override("font_hover_color", PAPER if filled else TEAL)
	button.add_theme_color_override("font_pressed_color", PAPER if filled else INK)
	button.add_theme_color_override("font_disabled_color", Color("94a198"))
	button.add_theme_stylebox_override("normal", style(TEAL if filled else CREAM, 9))
	button.add_theme_stylebox_override("hover", style(TEAL.lightened(0.13) if filled else Color("d6e0d4"), 9, TEAL, 1))
	button.add_theme_stylebox_override("pressed", style(TEAL.darkened(0.12) if filled else Color("c9d5c6"), 9))
	button.add_theme_stylebox_override("disabled", style(Color("e9e9e0"), 9))
	button.add_theme_stylebox_override("focus", style(Color.TRANSPARENT, 9, GOLD, 3))
	button.pressed.connect(func():
		sound.play("tap")
		callback.call()
	)
	(page if parent == null else parent).add_child(button)
	return button

func portrait_at(id: int, rect: Rect2, parent: Control = null) -> Control:
	var art := RoomArt.new()
	art.portrait = true
	art.member_id = id
	art.animate = false
	art.position = rect.position
	art.size = rect.size
	(page if parent == null else parent).add_child(art)
	return art

func meter(rect: Rect2, fraction: float, color: Color = TEAL, parent: Control = null) -> void:
	panel(rect, LINE, int(rect.size.y / 2), parent)
	if fraction > 0:
		panel(Rect2(rect.position, Vector2(maxf(rect.size.y, rect.size.x * clampf(fraction, 0, 1)), rect.size.y)), color, int(rect.size.y / 2), parent)

func show_setup() -> void:
	clear_page()
	panel(Rect2(0, 0, 880, 900), INK, 0)
	label_at("INSPIRATION CLUB  /  01", Rect2(56, 37, 620, 32), 16, Color("a7c3b8"), true)
	label_at("灵感涌现", Rect2(54, 94, 500, 88), 64, PAPER, true)
	label_at("ing", Rect2(388, 109, 180, 71), 65, GOLD, true)
	label_at("从一个脑洞，到一款自己的游戏。", Rect2(60, 191, 730, 44), 25, Color("d2dbcf"))
	var art := RoomArt.new()
	art.position = Vector2(56, 280)
	art.size = Vector2(770, 290)
	art.selected = 1
	page.add_child(art)
	label_at("四位社员。十二个月。一个共同的作品。", Rect2(60, 607, 740, 38), 24, PAPER, true)
	paragraph("安排分工，培养伙伴，处理开发中的小麻烦。\n年底，把大家的灵感一起带上游戏展。", Rect2(60, 665, 730, 76), 20, Color("c1d0c5"))
	label_at("一年可玩版  ·  所有选择都有机会成本", Rect2(60, 824, 760, 30), 16, Color("a7c3b8"))
	label_at("新项目立项", Rect2(934, 67, 425, 50), 32, INK, true)
	label_at("01 — 给我们的第一款游戏起个名字", Rect2(936, 138, 430, 32), 17, MUTED)
	title_input = LineEdit.new()
	title_input.position = Vector2(936, 185)
	title_input.size = Vector2(438, 52)
	title_input.max_length = 18
	title_input.text = project_title
	title_input.placeholder_text = "作品名，最多 18 字"
	title_input.add_theme_stylebox_override("normal", style(PAPER, 9, LINE, 1))
	title_input.add_theme_stylebox_override("focus", style(PAPER, 9, TEAL, 2))
	title_input.add_theme_color_override("font_color", INK)
	title_input.text_changed.connect(func(text: String): project_title = text)
	page.add_child(title_input)
	label_at("02 — 游戏类型", Rect2(936, 271, 420, 30), 17, MUTED)
	for index in range(3):
		var chosen := index
		button_at(Model.GENRES[index], Rect2(936 + index * 151, 314, 136, 46), func(): genre = chosen; show_setup(), genre == index)
	label_at("03 — 故事题材", Rect2(936, 388, 420, 30), 17, MUTED)
	for index in range(3):
		var chosen := index
		button_at(Model.TOPICS[index], Rect2(936 + index * 151, 431, 136, 46), func(): topic = chosen; show_setup(), topic == index)
	panel(Rect2(936, 515, 438, 129), PAPER)
	label_at("这个选题让大家更有干劲", Rect2(954, 528, 390, 30), 17, INK, true)
	var matches: Array[String] = []
	for id in range(4):
		var bonus: int = Model.match_bonus(id, genre, topic)
		if bonus > 0:
			matches.append("%s +%d" % [Model.DEFINITIONS[id].name, bonus])
	paragraph("初始好感  ·  " + "    ".join(matches) + "\n类型与题材影响好感，不改变评分权重。", Rect2(954, 571, 399, 65), 16, MUTED)
	button_at("开始我们的第一年  →", Rect2(936, 681, 438, 58), func():
		state = Model.begin(Model.fresh(), project_title, genre, topic)
		selected = 1
		action = 0
		persist()
		show_game()
	, true, null, 21)
	if not saved.is_empty() and saved.phase != "setup":
		button_at("继续「%s」 · 第 %d 月" % [saved.title, int(saved.month)], Rect2(936, 758, 438, 48), continue_saved)
	else:
		paragraph("点击社员选择行动；每次执行推进一个月。\n进度自动保存，下次可从这里继续。", Rect2(939, 762, 430, 62), 16)
	if return_to_game:
		button_at("返回当前游戏", Rect2(1191, 835, 183, 36), show_game, false, null, 15)

func continue_saved() -> void:
	state = saved.duplicate(true)
	selected = 0
	action = 0
	if state.phase == "ending":
		show_ending()
	else:
		show_game()
		if state.phase == "report":
			show_report()

func persist() -> void:
	if qa_mode:
		return
	var error: Error = Store.save_run(state)
	if error == OK:
		saved = state.duplicate(true)
		notice = "已自动保存"
	else:
		notice = "保存失败 · 当前游戏仍可继续"
		push_warning("Save failed: " + error_string(error))

func show_game() -> void:
	clear_page()
	label_at("灵感涌现ing", Rect2(32, 22, 340, 51), 32, INK, true)
	label_at("游戏开发社团", Rect2(292, 32, 200, 32), 17, MUTED)
	panel(Rect2(639, 29, 370, 38), CREAM, 19)
	var stage := "发布准备" if int(state.month) >= 10 else ("打磨阶段" if int(state.month) >= 5 else "从零起步")
	var head := label_at("第一年   /   %02d 月   /   %s" % [int(state.month), stage], Rect2(649, 29, 349, 38), 17, TEAL, true)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button_at("玩法说明", Rect2(1108, 28, 130, 40), show_help, false, null, 16)
	button_at("声音 开" if sound.enabled else "声音 关", Rect2(1250, 28, 96, 40), func(): sound.enabled = not sound.enabled; show_game(), false, null, 15)
	button_at("主页", Rect2(1356, 28, 52, 40), func(): return_to_game = true; show_setup(), false, null, 15)
	var work: Dictionary = state.work
	var stats := [
		["游戏性", float(work.g), "让人忍不住再玩一次", TEAL],
		["创新性", float(work.i), "属于我们的奇妙点子", Color("ae8542")],
		["表现力", Model.performance(work), "视觉 %.1f  /  听觉 %.1f" % [work.v, work.m], Color("8876a0")],
		["Bug", float(work.b), "开发效率 %d%%" % int(Model.efficiency(float(work.b)) * 100), RED]
	]
	for index in range(4):
		var x := 32.0 + index * 275.0
		panel(Rect2(x, 94, 259, 98))
		label_at(stats[index][0], Rect2(x + 18, 104, 100, 29), 16, MUTED)
		label_at("%.1f" % stats[index][1], Rect2(x + 145, 99, 103, 42), 31, stats[index][3], true)
		label_at(stats[index][2], Rect2(x + 18, 145, 232, 24), 14, MUTED)
		meter(Rect2(x + 18, 178, 223, 4), float(stats[index][1]) / (24.0 if index == 3 else 210.0), stats[index][3])
	panel(Rect2(1132, 94, 276, 98), INK)
	label_at("可用灵感", Rect2(1152, 104, 143, 30), 16, Color("c4d5c8"))
	label_at(str(int(state.inspiration)), Rect2(1300, 100, 89, 42), 33, GOLD, true)
	label_at("学习技能，让热爱变成实力", Rect2(1152, 148, 236, 29), 15, Color("c4d5c8"))
	# Club room and live workstations.
	panel(Rect2(32, 210, 890, 293), PAPER)
	label_at("社团活动室", Rect2(50, 215, 230, 32), 17, INK, true)
	label_at("「%s」  ·  %s / %s" % [state.title, Model.GENRES[int(state.genre)], Model.TOPICS[int(state.topic)]], Rect2(277, 215, 626, 32), 15, MUTED)
	var room := RoomArt.new()
	room.position = Vector2(32, 254)
	room.size = Vector2(890, 249)
	room.selected = selected
	room.month = int(state.month)
	room.roles = []
	for member in state.members:
		room.roles.append(int(member.role))
	room.member_clicked.connect(select_member)
	page.add_child(room)
	for id in range(4):
		member_card(id)
	show_bottom()
	show_action_panel()
	label_at("一年可玩版  v0.1", Rect2(33, 875, 290, 20), 12, MUTED)
	var save_label := label_at(notice, Rect2(1040, 875, 367, 20), 12, MUTED)
	save_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

func select_member(id: int) -> void:
	if locked or state.phase != "ready":
		return
	selected = id
	show_game()

func member_card(id: int) -> void:
	var x := 32.0 + id * 227.0
	var chosen := id == selected
	var card := button_at("", Rect2(x, 519, 209, 193), func(): select_member(id), chosen)
	card.add_theme_stylebox_override("normal", style(INK if chosen else PAPER, 14, GOLD if chosen else LINE, 2 if chosen else 1))
	card.add_theme_stylebox_override("hover", style(INK.lightened(0.05) if chosen else Color("f7f8ef"), 14, TEAL, 2))
	portrait_at(id, Rect2(x + 15, 533, 61, 61))
	var def: Dictionary = Model.DEFINITIONS[id]
	var member: Dictionary = state.members[id]
	label_at(def.name, Rect2(x + 89, 531, 112, 30), 23, PAPER if chosen else INK, true)
	label_at("已学技能" if member.learned else ("技能可解锁" if int(member.affinity) >= 20 else "一起成长中"), Rect2(x + 89, 565, 110, 24), 13, GOLD if chosen else MUTED)
	label_at(Model.ROLES[int(member.role)], Rect2(x + 15, 608, 180, 30), 18, Color("d9e9d6") if chosen else TEAL, true)
	label_at("好感 %d / 100" % int(member.affinity), Rect2(x + 15, 650, 180, 26), 14, Color("c5d6cb") if chosen else MUTED)
	meter(Rect2(x + 15, 688, 178, 5), float(member.affinity) / 100.0, GOLD if chosen else TEAL)

func show_bottom() -> void:
	panel(Rect2(32, 730, 421, 138), Color("e2e6d9"))
	var month := int(state.month)
	var next_node := 4 if month <= 4 else (8 if month <= 8 else 12)
	label_at("下个节点  /  %02d 月%s" % [next_node, "年度游戏展" if next_node == 12 else "社内试玩"], Rect2(49, 741, 389, 30), 17, INK, true)
	var target_text := "目标：游戏性 35 · 创新 30 · 表现 45"
	if next_node == 8:
		target_text = "目标：游戏性 80 · 创新 65 · 表现 100"
	elif next_node == 12:
		target_text = "最佳游戏：80 分 · 三项均 ≥ 50 · Bug ≤ 5"
	label_at(target_text, Rect2(49, 783, 392, 24), 14, MUTED)
	label_at("Bug ≤ 10 额外得灵感；每项达标 +1" if next_node < 12 else "原始三项属性各 210 点，对应评分 100", Rect2(49, 821, 394, 24), 14, MUTED)
	panel(Rect2(469, 730, 453, 138), PAPER)
	label_at("开发手记", Rect2(487, 741, 420, 30), 17, INK, true)
	var recent: String = state.log[0] if state.log.size() > 0 else "今天的灵感，还等着大家一起实现。"
	paragraph(recent, Rect2(487, 784, 414, 67), 15, MUTED)

func show_action_panel() -> void:
	panel(Rect2(942, 210, 466, 658), PAPER)
	var def: Dictionary = Model.DEFINITIONS[selected]
	var member: Dictionary = state.members[selected]
	portrait_at(selected, Rect2(962, 230, 66, 66))
	label_at(def.name, Rect2(1043, 228, 241, 35), 26, INK, true)
	label_at(def.tag, Rect2(1043, 264, 339, 28), 16, MUTED)
	var a: Array = Model.ability(state, selected)
	label_at("编程 %.1f    脑洞 %.1f    美术 %.1f    音乐 %.1f" % a, Rect2(962, 308, 426, 28), 15, MUTED)
	label_at("当前分工", Rect2(962, 345, 211, 27), 15, INK, true)
	label_at("调整不消耗回合", Rect2(1207, 345, 182, 27), 13, MUTED)
	for role in range(4):
		var target_role := role
		var item := button_at(["玩法", "美术", "音效", "修复"][role], Rect2(962 + role * 108, 380, 101, 34), func():
			state = Model.assign(state, selected, target_role)
			persist()
			show_game()
		, int(member.role) == role, null, 15)
		item.tooltip_text = Model.ROLES[role] + " · 免费调整，回合结束时自动产出"
	label_at("这个月，一起做什么？", Rect2(962, 429, 405, 27), 17, INK, true)
	for index in range(6):
		var chosen_action := index
		var text: String = Model.ACTIONS[index]
		if index == 0:
			text += " +%d" % Model.invite_gain(state, selected)
		var item := button_at(text, Rect2(962 + (index % 2) * 217, 464 + int(index / 2) * 47, 209, 39), func(): action = chosen_action; show_game(), action == index, null, 16)
		item.tooltip_text = action_description(selected, index)
	var preview: Dictionary = Model.resolve(state, selected, action, int(state.month))
	panel(Rect2(962, 614, 426, 112), Color("edf0e6"), 10)
	label_at("本回合预计变化  ·  已含全员开发", Rect2(976, 622, 401, 24), 14, MUTED)
	if preview.get("ok", false):
		var delta: Dictionary = preview.report.delta
		label_at("游戏性 +%.1f   创新 +%.1f   表现 +%.1f" % [delta.g, delta.i, delta.p], Rect2(976, 653, 399, 25), 15, TEAL, true)
		var bug_text := "Bug %+.1f → %.1f" % [delta.b, preview.state.work.b]
		label_at(bug_text + "    效率 %d%%" % int(preview.report.efficiency * 100), Rect2(976, 688, 400, 23), 14, RED if preview.state.work.b >= 12 else MUTED)
	var skill_text: String
	var disabled := false
	if member.learned:
		skill_text = "%s · %s产出 +20%%" % [def.skill, ["玩法", "美术", "音效", "修复"][int(def.specialty)]]
		disabled = true
	elif int(member.affinity) < 20:
		skill_text = "%s · 好感 %d/20 解锁" % [def.skill, int(member.affinity)]
		disabled = true
	elif int(state.inspiration) < 6:
		skill_text = "%s · 灵感不足 %d/6" % [def.skill, int(state.inspiration)]
		disabled = true
	else:
		skill_text = "学习 %s  ·  6 灵感 / 不耗回合" % def.skill
	var skill_button := button_at(skill_text, Rect2(962, 741, 426, 38), func():
		state = Model.learn(state, selected)
		persist()
		sound.play("learn")
		show_game()
	, false, null, 15)
	skill_button.disabled = disabled
	skill_button.tooltip_text = "好感 20 解锁，消耗 6 灵感习得。\n分配到%s时，自动产出或修复量 +20%%。" % Model.ROLES[int(def.specialty)]
	var expected_month := int(state.month)
	commit_button = button_at("执行行动，结束 %02d 月  →" % expected_month, Rect2(962, 796, 426, 50), func(): commit_turn(expected_month), true, null, 20)
	commit_button.disabled = locked or state.phase != "ready"
	commit_button.tooltip_text = action_description(selected, action) + "\n所有社员随后自动工作；确认后无法撤销本回合。"

func action_description(id: int, which: int) -> String:
	var stats: Array = Model.ability(state, id)
	match which:
		0:
			return "好感 +%d；能力随好感提升。连续邀约同一人只 +6。" % Model.invite_gain(state, id)
		1:
			return "任务即时：游戏性 +%.1f，Bug +2。" % (1.5 * stats[0])
		2:
			return "任务即时：创新性 +%.1f，Bug +3。" % (1.5 * stats[1])
		3:
			return "任务即时：视觉 +%.1f，Bug +1；表现力结合视觉与听觉。" % (1.5 * stats[2])
		4:
			return "任务即时：听觉 +%.1f，Bug +1；表现力结合视觉与听觉。" % (1.5 * stats[3])
		5:
			return "任务即时：修复最多 %.1f Bug，然后计算本回合开发效率。" % (1.5 * stats[0])
	return ""

func commit_turn(expected_month: int) -> void:
	if locked:
		return
	locked = true
	if is_instance_valid(commit_button):
		commit_button.disabled = true
	var result: Dictionary = Model.resolve(state, selected, action, expected_month)
	if not result.get("ok", false):
		locked = false
		return
	state = result.state
	persist()
	sound.play("turn")
	show_game()
	show_report()
	locked = false

func overlay(rect: Rect2) -> Control:
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	page.add_child(layer)
	# A modal owns keyboard navigation as well as mouse input.
	for focusable in page.find_children("*", "BaseButton", true, false):
		focusable.set_meta("previous_focus_mode", focusable.focus_mode)
		focusable.focus_mode = Control.FOCUS_NONE
	layer.tree_exiting.connect(func():
		if is_instance_valid(page):
			for focusable in page.find_children("*", "BaseButton", true, false):
				if focusable.has_meta("previous_focus_mode"):
					focusable.focus_mode = focusable.get_meta("previous_focus_mode")
	)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.04, 0.1, 0.11, 0.72)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(shade)
	panel(rect, PAPER, 22, layer)
	return layer

func show_report() -> void:
	var report: Dictionary = state.report
	var month := int(state.month)
	var stage := month == 4 or month == 8
	var layer := overlay(Rect2(360, 113, 720, 674))
	label_at("MONTH %02d   /   %s" % [month, "PLAYTEST" if stage else "DEVELOPMENT"], Rect2(394, 137, 655, 28), 15, TEAL, true, layer)
	label_at("年度游戏展，准备登场" if month == 12 else ("第一次社内试玩" if month == 4 else ("第二次社内试玩" if month == 8 else "这个月，也向前了一点")), Rect2(394, 179, 650, 55), 31, INK, true, layer)
	var id := int(report.member)
	portrait_at(id, Rect2(395, 253, 68, 68), layer)
	label_at("%s · %s" % [Model.DEFINITIONS[id].name, Model.ACTIONS[int(report.action)]], Rect2(483, 250, 553, 31), 20, INK, true, layer)
	label_at(Model.DEFINITIONS[id].quote, Rect2(483, 288, 554, 34), 17, MUTED, false, layer)
	var delta: Dictionary = report.delta
	var names := ["游戏性", "创新性", "表现力", "Bug"]
	var values := [delta.g, delta.i, delta.p, delta.b]
	for i in range(4):
		var x := 394.0 + i * 166
		panel(Rect2(x, 352, 151, 95), CREAM, 12, layer)
		label_at(names[i], Rect2(x + 14, 362, 120, 27), 16, MUTED, false, layer)
		label_at("%+.1f" % values[i], Rect2(x + 14, 393, 124, 40), 29, RED if i == 3 and values[i] > 0 else TEAL, true, layer)
	if stage:
		label_at("试玩反馈  ·  达标一项，额外获得 1 灵感", Rect2(394, 469, 650, 30), 17, INK, true, layer)
		for i in range(report.targets.size()):
			var target: Dictionary = report.targets[i]
			var x := 394.0 + (i % 2) * 330
			var y := 510.0 + int(i / 2) * 43
			label_at(("达标  " if target.reached else "待提升  ") + target.name + "  %.1f / %s%.0f" % [target.value, "≤" if i == 3 else "", target.target], Rect2(x, y, 323, 35), 16, TEAL if target.reached else RED, false, layer)
	else:
		paragraph("好感 +%d    灵感 +1    本回合开发效率 %d%%\n%s" % [int(report.affinity), int(report.efficiency * 100), "发布前最后一次检查完成。看看我们的作品吧。" if month == 12 else advice()], Rect2(394, 483, 648, 100), 18, MUTED, layer)
	label_at("本次获得灵感  +%d" % (1 + int(report.bonus_inspiration)), Rect2(394, 619, 650, 35), 20, TEAL, true, layer)
	button_at("前往年度游戏展  →" if month == 12 else "收起手记，进入 %02d 月  →" % (month + 1), Rect2(394, 698, 652, 55), advance_report, true, layer, 20)

func advice() -> String:
	if float(state.work.b) >= 12:
		return "Bug 开始拖慢大家的工作。试试集中测试，或安排阿序修复。"
	if absf(float(state.work.v) - float(state.work.m)) > 15:
		return "视觉和听觉有些失衡，补齐较弱的一项能更快提高表现力。"
	if int(state.inspiration) >= 6:
		for member in state.members:
			if int(member.affinity) >= 20 and not member.learned:
				return "有人已经可以学习技能了。花费灵感，能让专长岗位持续增产。"
	return "开发顺畅。培养伙伴还是打磨作品，下个月由你决定。"

func advance_report() -> void:
	if state.phase != "report":
		return
	state = Model.acknowledge(state)
	persist()
	if state.phase == "ending":
		sound.play("finish")
		show_ending()
	else:
		show_game()

func show_help() -> void:
	var layer := overlay(Rect2(330, 103, 780, 696))
	label_at("把灵感，变成一款游戏", Rect2(368, 129, 700, 58), 31, INK, true, layer)
	var help := [
		["01  每个月选择一次行动", "先点击社员，再选邀约或任务。执行后全员自动开发，月份 +1。"],
		["02  分工可以随时调整", "玩法产出游戏性和创新，美术与音乐共同决定表现力；修复降低 Bug。"],
		["03  好感与技能是长期投资", "好感 20 解锁专长技能，花 6 灵感习得。学技能、换岗位不消耗月份。"],
		["04  别让 Bug 一直堆着", "行动后 Bug 达到 12 / 24，自动开发效率降到 85% / 70%。"],
		["05  年底带作品去参展", "第 4、8 月试玩，第 12 月评奖。最佳游戏需总分 ≥80、三项评分 ≥50、Bug ≤5。"]
	]
	for i in range(help.size()):
		label_at(help[i][0], Rect2(368, 213 + i * 90, 700, 32), 20, TEAL, true, layer)
		paragraph(help[i][1], Rect2(368, 250 + i * 90, 700, 53), 16, MUTED, layer)
	button_at("明白了，回到社团", Rect2(369, 718, 702, 48), func(): layer.queue_free(), true, layer, 19)

func show_ending() -> void:
	clear_page()
	var result: Dictionary = Model.score(state.work)
	panel(Rect2(0, 0, 510, 900), INK, 0)
	label_at("YEAR ONE  /  SHOWCASE", Rect2(47, 43, 420, 35), 16, Color("b5ccbe"), true)
	label_at("我们的第一款游戏", Rect2(47, 126, 424, 50), 28, PAPER, true)
	paragraph("「%s」" % state.title, Rect2(47, 213, 416, 115), 34, GOLD)
	label_at(result.award, Rect2(47, 359, 420, 70), 41, PAPER, true)
	label_at("%.1f" % (floorf(float(result.total) * 10) / 10), Rect2(42, 439, 386, 145), 98, GOLD, true)
	label_at("年度综合评分 / 100", Rect2(50, 579, 390, 31), 18, Color("b5ccbe"))
	paragraph("无论分数如何，这款游戏里，\n已经有了四个人的名字。", Rect2(50, 702, 399, 90), 23, Color("dce5d6"))
	label_at("灵感涌现ing · 一年可玩版", Rect2(50, 836, 400, 30), 16, Color("b5ccbe"))
	label_at("十二个月，我们做到了这些", Rect2(560, 53, 820, 52), 31, INK, true)
	var labels := ["游戏性", "创新性", "表现力"]
	var values := [float(result.g), float(result.i), float(result.p)]
	for i in range(3):
		var y := 141.0 + i * 73
		label_at(labels[i], Rect2(562, y, 140, 31), 20, INK, true)
		meter(Rect2(718, y + 10, 478, 14), values[i] / 100.0, [TEAL, Color("ae8542"), Color("8876a0")][i])
		label_at("%.1f 分" % values[i], Rect2(1220, y - 3, 160, 39), 23, TEAL, true)
	panel(Rect2(560, 374, 817, 88), PAPER)
	label_at("Bug %.1f   →   扣除 %.1f 分" % [state.work.b, result.penalty], Rect2(580, 388, 767, 30), 19, RED, true)
	label_at("总分 = 游戏性 ×40% + 创新性 ×30% + 表现力 ×30% − Bug 扣分", Rect2(580, 426, 767, 22), 15, MUTED)
	label_at("最佳游戏奖的三个条件", Rect2(563, 489, 780, 34), 20, INK, true)
	var checks := [float(result.total) >= 80, minf(result.g, minf(result.i, result.p)) >= 50, float(state.work.b) <= 5]
	var check_names := ["总分 ≥ 80", "三项评分均 ≥ 50", "Bug ≤ 5"]
	for i in range(3):
		panel(Rect2(560 + i * 279, 539, 260, 51), CREAM)
		label_at(("已达成  " if checks[i] else "还差一点  ") + check_names[i], Rect2(574 + i * 279, 547, 235, 35), 16, TEAL if checks[i] else RED, true)
	label_at("一年后的伙伴们", Rect2(562, 624, 780, 32), 20, INK, true)
	for id in range(4):
		var x := 560.0 + id * 206
		portrait_at(id, Rect2(x, 678, 57, 57))
		label_at(Model.DEFINITIONS[id].name, Rect2(x + 69, 675, 127, 27), 18, INK, true)
		label_at("好感 %d%s" % [int(state.members[id].affinity), " · 技能✓" if state.members[id].learned else ""], Rect2(x + 69, 710, 134, 26), 14, MUTED)
	button_at("换一种策略，再来一年  →", Rect2(560, 797, 523, 59), func(): return_to_game = false; show_setup(), true, null, 21)
	button_at("查看制作手记", Rect2(1102, 797, 275, 59), show_history, false, null, 19)

func show_history() -> void:
	var layer := overlay(Rect2(305, 66, 830, 769))
	label_at("这一年的制作手记", Rect2(342, 90, 752, 45), 29, INK, true, layer)
	for index in range(state.history.size()):
		var item: Dictionary = state.history[index]
		var y := 157.0 + index * 44
		label_at("%02d 月" % int(item.month), Rect2(344, y, 100, 32), 17, TEAL, true, layer)
		label_at("游戏性 %.1f    创新 %.1f    表现 %.1f    Bug %.1f" % [item.work.g, item.work.i, Model.performance(item.work), item.work.b], Rect2(450, y, 627, 32), 17, MUTED, false, layer)
	button_at("回到作品展台", Rect2(343, 748, 753, 49), func(): layer.queue_free(), true, layer, 20)

func _run_ui_smoke() -> void:
	var output := "res://qa"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	await capture(output + "/01-setup.png")
	await ui_click(Vector2(1130, 710))
	if state.phase != "ready":
		push_error("Mouse could not start the game")
		get_tree().quit(1)
		return
	await capture(output + "/02-game.png")
	await ui_click(Vector2(130, 550))
	if selected != 0:
		push_error("Member card not clickable")
		get_tree().quit(1)
		return
	await ui_click(Vector2(1335, 397))
	if int(state.members[0].role) != 3:
		push_error("Role assignment click failed")
		get_tree().quit(1)
		return
	await ui_click(Vector2(1000, 397))
	await ui_click(Vector2(1170, 48))
	await capture(output + "/03-help.png")
	await ui_click(Vector2(1170, 818))
	if state.phase != "ready" or int(state.month) != 1:
		push_error("Modal allowed click-through")
		get_tree().quit(1)
		return
	await ui_click(Vector2(712, 740))
	for month in range(1, 13):
		selected = 0 if float(state.work.b) >= 10 else 1
		action = 5 if float(state.work.b) >= 10 else (0 if month <= 5 else 2)
		if int(state.members[1].affinity) >= 20 and not state.members[1].learned:
			state = Model.learn(state, 1)
		show_game()
		# Exercise the real UI signal, controller, report, and transition path.
		commit_button.pressed.emit()
		if state.phase != "report":
			push_error("UI smoke failed to commit month " + str(month))
			get_tree().quit(1)
			return
		if month == 4:
			await capture(output + "/04-playtest.png")
		advance_report()
		await get_tree().process_frame
	await capture(output + "/05-ending.png")
	show_history()
	await capture(output + "/06-history.png")
	# Validate the same UI layout and controls at the default smaller window size.
	get_window().size = Vector2i(1280, 800)
	await get_tree().process_frame
	show_setup()
	await ui_click(Vector2(1130, 710))
	await capture(output + "/07-game-1280.png")
	var small_window_works: bool = state.phase == "ready"
	# Restore the completed state to verify save restoration without modifying player saves.
	var completed := Model.begin(Model.fresh(), "存档恢复检查", 1, 1)
	for month in range(1, 13):
		completed = Model.acknowledge(Model.resolve(completed, 0, 5, month).state)
	state = completed
	if state.phase != "ending" or state.history.size() != 12:
		push_error("UI smoke did not reach ending")
		get_tree().quit(1)
	elif not small_window_works:
		push_error("1280x800 mouse input failed")
		get_tree().quit(1)
	else:
		print("UI_SMOKE_PASS: real mouse setup/member/role, modal blocking, 12 turns, playtest, ending, history, 1280x800")
		get_tree().quit(0)

func ui_click(point: Vector2) -> void:
	await get_tree().process_frame
	var position_in_viewport := get_global_transform_with_canvas() * point
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position_in_viewport
		event.global_position = position_in_viewport
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		get_viewport().push_input(event, true)
		await get_tree().process_frame

func capture(path: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(path)
	if error != OK:
		push_error("Screenshot failed: " + error_string(error))
