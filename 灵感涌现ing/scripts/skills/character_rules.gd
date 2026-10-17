extends RefCounted
## 十人设计中的生命周期规则：习得、月初缓存、专属任务与产出后成长。
## 所有写入只作用于 Model 提供的副本；随机数由事件种子确定，预览不会重抽。
const Runner = preload("res://scripts/skills/skill_runner.gd")
const Table = preload("res://scripts/skills/skill_table.gd")
const TASKS := [
	{"id": "memory_share", "name": "记忆分享", "owner": "b", "slot": 1, "cost": 1, "description": "将一名好感度最低的其他成员提升至与自己相同的好感度。"},
	{"id": "restructure", "name": "系统重构", "owner": "d", "slot": 2, "cost": 1, "description": "进行整体重构，大幅减少BUG（4×编程）。"},
	{"id": "stylize", "name": "风格化", "owner": "f", "slot": 1, "cost": 1, "description": "获得等同于当前表现力的创新性。"},
	{"id": "dream_real", "name": "绘梦成真", "owner": "g", "slot": 2, "cost": 1, "description": "当前作品的「手稿」与「小生物」数量翻倍。"},
	{"id": "sound_conduction", "name": "声音传导构建", "owner": "h", "slot": 1, "cost": 1, "description": "游戏性与表现力各增加：小生物×（程序＋音乐）×0.5。"},
	{"id": "shared_world", "name": "大一统世界观", "owner": "i", "slot": 2, "cost": 1, "description": "获得上一部作品的创新性、表现力和手稿；首年增加0。"},
]

static func has_skill(state: Dictionary, defs: Array, id: int, slot: int) -> bool:
	if id < 0 or id >= state.members.size(): return false
	var skill = Table.skills.get(defs[id].skills[slot].skill_id)
	return skill != null and skill.implementation == "character_rules" and Runner.active(state, id, defs[id].skills[slot])

static func index_of(defs: Array, id: String) -> int:
	for index in defs.size():
		if defs[index].id == id: return index
	return -1

static func grow(state: Dictionary, defs: Array, id: int, stat: int, amount: float) -> void:
	var growth: Array = state.members[id].ability_growth
	growth[stat] = clampf(float(growth[stat]) + amount, -float(defs[id].stats[stat]), 100000.0)

static func white(state: Dictionary, defs: Array, id: int, stat: int) -> float:
	return maxf(0.0, float(defs[id].stats[stat]) + float(state.members[id].ability_growth[stat]))

static func traits(state: Dictionary) -> Dictionary:
	if not state.has("project_traits"): state.project_traits = {"manuscripts": 0, "creatures": 0}
	return state.project_traits

static func add_trait(state: Dictionary, key: String, amount: int) -> void:
	var counts := traits(state)
	counts[key] = clampi(int(counts[key]) + amount, 0, 100000)

static func sync(state: Dictionary, defs: Array, monthly: bool = false) -> void:
	# 协奏只在已招募成员之间同步；对方日后加入时再补发，忽略其好感门槛。
	var pumpkin := index_of(defs, "c")
	var bat := index_of(defs, "h")
	if has_skill(state, defs, pumpkin, 0) and has_skill(state, defs, bat, 0):
		for slot in [1, 2]:
			if has_skill(state, defs, pumpkin, slot) or has_skill(state, defs, bat, slot):
				for id in [pumpkin, bat]:
					var skill_id: String = defs[id].skills[slot].skill_id
					if skill_id not in state.members[id].learned_skills: state.members[id].learned_skills.append(skill_id)
	for id in defs.size():
		var member: Dictionary = state.members[id]
		if not member.recruited: continue
		if not member.has("character_runtime"): member.character_runtime = {}
		var runtime: Dictionary = member.character_runtime
		for slot in 3:
			var key := "activated_%d" % slot
			if not has_skill(state, defs, id, slot) or runtime.has(key): continue
			runtime[key] = true
			match "%s:%d" % [member.id, slot]:
				"b:2": state.extra_recruitment = true
				"f:0": runtime.free_task = 1
				"f:2": runtime.art_bonus = 0.2 + 0.02 * white(state, defs, id, 1)
				"h:2": add_trait(state, "creatures", 5)
				"i:1": grow(state, defs, id, 1, white(state, defs, id, 2) + white(state, defs, id, 3))
	# 月初仅一次。年初等待新作品立项，避免往上一作品或尚不存在的作品写入。
	var stamp := "%d:%d" % [int(state.year), int(state.month)]
	if not monthly or state.get("character_month", "") == stamp: return
	state.character_month = stamp
	for id in defs.size():
		if not state.members[id].recruited: continue
		if defs[id].id == "g" and has_skill(state, defs, id, 0):
			grow(state, defs, id, 2, 2)
			add_trait(state, "creatures", 1)
		if defs[id].id == "i" and has_skill(state, defs, id, 1): add_trait(state, "creatures", 1)
	for id in defs.size():
		if not state.members[id].recruited: continue
		var runtime: Dictionary = state.members[id].character_runtime
		match defs[id].id:
			"d": runtime.bug_bonus = minf(100.0, float(state.work.b) * 0.01)
			"f":
				if has_skill(state, defs, id, 2): runtime.art_bonus = 0.2 + 0.02 * white(state, defs, id, 1)
				if int(state.month) == 1 and has_skill(state, defs, id, 0): runtime.free_task = 1
			"h": runtime.creature_stats = int(traits(state).creatures) if has_skill(state, defs, id, 2) else 0

static func free_task(state: Dictionary, defs: Array, id: int) -> bool:
	return id >= 0 and defs[id].id == "f" and has_skill(state, defs, id, 0) and int(state.members[id].get("character_runtime", {}).get("free_task", 0)) > 0

static func rng_for(state: Dictionary, event: String, id: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	var serial := 0 if event in ["drunk", "angel_gift", "tech_duty"] else int(state.get("action_serial", 0))
	rng.seed = ("%s:%d:%d:%s:%d:%d" % [state.run_id, int(state.year), int(state.month), event, id, serial]).hash()
	return rng

static func drunk(state: Dictionary, id: int) -> bool:
	return rng_for(state, "drunk", id).randf() < 0.5

static func modify_output(state: Dictionary, defs: Array, id: int, output: Dictionary, duty: bool) -> void:
	# 转换单元之后应用产出增幅；额外5 BUG最后追加。
	var manuscript_bonus := float(state.get("project_traits", {}).get("manuscripts", 0)) * 0.01
	for key in output:
		var bonus := manuscript_bonus if key == "p" else 0.0
		if defs[id].id == "e" and has_skill(state, defs, id, 2) and key in ["g", "i", "p", "repair"]: bonus += 0.66
		if defs[id].id == "c" and key == "p" and has_skill(state, defs, id, 2): bonus += float(state.get("project_traits", {}).get("creatures", 0)) * 0.1
		if defs[id].id == "j":
			if duty and has_skill(state, defs, id, 0):
				if key == "i": bonus += 0.5 if drunk(state, id) else 1.0
				if key == "b" and drunk(state, id): bonus += 1.0
			if key == "b" and has_skill(state, defs, id, 2): bonus += 1.0
		output[key] = float(output[key]) * (1.0 + bonus)
	if duty and defs[id].id == "j" and has_skill(state, defs, id, 0) and drunk(state, id): output.b += 5.0

static func after_output(state: Dictionary, defs: Array, id: int, output: Dictionary, duty: bool, repaired: float, messages: Array) -> void:
	if defs[id].id == "i" and has_skill(state, defs, id, 0):
		var runtime: Dictionary = state.members[id].character_runtime
		var total := float(runtime.get("manuscript_progress", 0.0)) + maxf(0.0, float(output.get("i", 0.0)))
		add_trait(state, "manuscripts", int(floorf(total / 100.0)))
		runtime.manuscript_progress = fmod(total, 100.0)
	if defs[id].id == "c" and not duty and has_skill(state, defs, id, 1):
		grow(state, defs, id, 3, 5)
		add_trait(state, "creatures", 2)
	if defs[id].id == "e" and repaired > 0 and has_skill(state, defs, id, 1):
		var candidates: Array = []
		for other in defs.size():
			if state.members[other].recruited: candidates.append(other)
		var target: int = candidates[rng_for(state, "tech_duty" if duty else "tech_task", id).randi_range(0, candidates.size() - 1)]
		grow(state, defs, target, 0, 5)
		messages.append("%s 程序+5" % defs[target].name)
	if defs[id].id == "j" and duty and has_skill(state, defs, id, 0):
		messages.append("喝醉了..." if drunk(state, id) else "微醺！")
		if drunk(state, id) and has_skill(state, defs, id, 1):
			var candidates: Array = []
			for other in defs.size():
				if other != id and state.members[other].recruited: candidates.append(other)
			if not candidates.is_empty():
				var target: int = candidates[rng_for(state, "angel_gift", id).randi_range(0, candidates.size() - 1)]
				grow(state, defs, target, 0, -5)
				grow(state, defs, target, 1, 10)
				messages.append("%s 程序-5，脑洞+10" % defs[target].name)

static func task_effect(state: Dictionary, defs: Array, id: int, task_id: String) -> void:
	match task_id:
		"memory_share":
			var lowest := int(state.members[id].affinity)
			var candidates: Array = []
			for other in defs.size():
				if other == id or not state.members[other].recruited: continue
				var affinity := int(state.members[other].affinity)
				if affinity < lowest:
					lowest = affinity
					candidates.clear()
				if affinity == lowest: candidates.append(other)
			if not candidates.is_empty():
				var target: int = candidates[rng_for(state, "memory", id).randi_range(0, candidates.size() - 1)]
				state.members[target].affinity = state.members[id].affinity
		"dream_real":
			for key in ["manuscripts", "creatures"]: add_trait(state, key, int(traits(state)[key]))
		"shared_world":
			var previous: Dictionary = state.annual_results.get(str(int(state.year) - 1), {})
			add_trait(state, "manuscripts", int(previous.get("project_traits", {}).get("manuscripts", 0)))

static func valid(state: Dictionary, defs: Array) -> bool:
	var counts: Variant = state.get("project_traits", {"manuscripts": 0, "creatures": 0})
	if not counts is Dictionary: return false
	for key in ["manuscripts", "creatures"]:
		if not integer_in(counts.get(key), 0, 100000): return false
	if not state.get("extra_recruitment", false) is bool: return false
	if not state.get("character_month", "") is String: return false
	if not integer_in(state.get("action_serial", 0), 0, 10000000): return false
	for id in defs.size():
		var runtime: Variant = state.members[id].get("character_runtime", {})
		if not runtime is Dictionary: return false
		for key in runtime:
			match key:
				"activated_0", "activated_1", "activated_2":
					if not runtime[key] is bool: return false
				"free_task":
					if not integer_in(runtime[key], 0, 1): return false
				"creature_stats":
					if not integer_in(runtime[key], 0, 100000): return false
				"art_bonus", "bug_bonus", "manuscript_progress":
					if not (runtime[key] is float or runtime[key] is int) or not is_finite(float(runtime[key])) or float(runtime[key]) < 0 or float(runtime[key]) > 100000: return false
				_: return false
	return true

static func integer_in(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == int(value) and value >= low and value <= high
