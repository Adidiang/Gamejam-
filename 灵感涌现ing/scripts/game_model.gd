class_name ClubGame
extends RefCounted
## Deterministic rules. UI previews use a copied state and the same resolver as commit.

const VERSION := 1
const ROLES := ["玩法开发", "美术开发", "音效开发", "Bug 修复"]
const ACTIONS := ["邀约交流", "玩法打磨", "原型实验", "风格设计", "配乐制作", "集中测试"]
const GENRES := ["动作", "解谜", "剧情"]
const TOPICS := ["科幻", "奇幻", "校园"]
const DEFINITIONS := [
	{"name": "阿序", "tag": "把想法跑起来", "stats": [8, 4, 1, 1], "genre": "动作", "topic": "科幻", "specialty": 3, "color": "83b9c7", "skill": "有序调试", "quote": "能跑了。等等，我再看一眼报错。"},
	{"name": "小满", "tag": "脑洞永不关机", "stats": [3, 8, 2, 2], "genre": "解谜", "topic": "奇幻", "specialty": 0, "color": "ecc36d", "skill": "灵光一现", "quote": "如果把这个规则反过来呢？"},
	{"name": "青禾", "tag": "给世界一点颜色", "stats": [2, 3, 8, 4], "genre": "剧情", "topic": "奇幻", "specialty": 1, "color": "a8ba91", "skill": "色彩直觉", "quote": "这一帧，终于有我们想要的感觉了。"},
	{"name": "声声", "tag": "听见故事的形状", "stats": [3, 2, 4, 8], "genre": "剧情", "topic": "校园", "specialty": 2, "color": "d4a3b3", "skill": "恰好合拍", "quote": "戴上耳机试试，这段是给结尾写的。"}
]

static func fresh() -> Dictionary:
	return {"version": VERSION, "phase": "setup", "month": 1, "inspiration": 2,
		"title": "未命名的灵感", "genre": 0, "topic": 0,
		"members": [{"affinity": 0, "role": 0, "learned": false}, {"affinity": 0, "role": 0, "learned": false}, {"affinity": 0, "role": 1, "learned": false}, {"affinity": 0, "role": 2, "learned": false}],
		"work": {"g": 0.0, "i": 0.0, "v": 0.0, "m": 0.0, "b": 0.0},
		"last_invite": -1, "history": [], "log": [], "report": {}, "claimed": []}

static func begin(state: Dictionary, title: String, genre: int, topic: int) -> Dictionary:
	if state.phase != "setup" or genre < 0 or genre >= GENRES.size() or topic < 0 or topic >= TOPICS.size():
		return state
	var next := state.duplicate(true)
	next.title = title.strip_edges().left(18) if not title.strip_edges().is_empty() else "未命名的灵感"
	next.genre = genre
	next.topic = topic
	for id in range(4):
		next.members[id].affinity = match_bonus(id, genre, topic)
	next.phase = "ready"
	next.log = ["新项目立项。十二个月，一起把它做出来。"]
	return next

static func match_bonus(id: int, genre: int, topic: int) -> int:
	return (6 if DEFINITIONS[id].genre == GENRES[genre] else 0) + (6 if DEFINITIONS[id].topic == TOPICS[topic] else 0)

static func ability(state: Dictionary, id: int) -> Array:
	var factor: float = 1.0 + 0.004 * float(state.members[id].affinity)
	var result: Array = []
	for value in DEFINITIONS[id].stats:
		result.append(float(value) * factor)
	return result

static func performance(work: Dictionary) -> float:
	return 0.5 * (float(work.v) + float(work.m)) + minf(float(work.v), float(work.m))

static func efficiency(bugs: float) -> float:
	return 0.7 if bugs >= 24.0 else (0.85 if bugs >= 12.0 else 1.0)

static func score(work: Dictionary) -> Dictionary:
	var g := minf(100.0, float(work.g) / 2.1)
	var i := minf(100.0, float(work.i) / 2.1)
	var p := minf(100.0, performance(work) / 2.1)
	var penalty := minf(40.0, float(work.b) * 2.0)
	var total := maxf(0.0, 0.4 * g + 0.3 * i + 0.3 * p - penalty)
	var best := total >= 80.0 and minf(g, minf(i, p)) >= 50.0 and float(work.b) <= 5.0
	var award := "最佳游戏奖" if best else ("优秀作品" if total >= 65.0 else ("入围作品" if total >= 45.0 else "完成参展"))
	return {"g": g, "i": i, "p": p, "penalty": penalty, "total": total, "best": best, "award": award}

static func invite_gain(state: Dictionary, id: int) -> int:
	return mini(100 - int(state.members[id].affinity), 6 if int(state.last_invite) == id else 12)

static func learn(state: Dictionary, id: int) -> Dictionary:
	if state.phase != "ready" or id < 0 or id >= 4:
		return state
	if state.members[id].learned or int(state.members[id].affinity) < 20 or int(state.inspiration) < 6:
		return state
	var next := state.duplicate(true)
	next.inspiration -= 6
	next.members[id].learned = true
	next.log.push_front("%s 学会了「%s」。" % [DEFINITIONS[id].name, DEFINITIONS[id].skill])
	return next

static func assign(state: Dictionary, id: int, role: int) -> Dictionary:
	if state.phase != "ready" or id < 0 or id >= 4 or role < 0 or role >= 4:
		return state
	var next := state.duplicate(true)
	next.members[id].role = role
	return next

static func resolve(state: Dictionary, id: int, action: int, expected_month: int) -> Dictionary:
	if state.phase != "ready" or int(state.month) != expected_month or id < 0 or id >= 4 or action < 0 or action >= ACTIONS.size():
		return {"ok": false}
	var next := state.duplicate(true)
	var old: Dictionary = state.work.duplicate(true)
	var work: Dictionary = next.work
	var a := ability(next, id)
	var gain := 0
	if action == 0:
		gain = invite_gain(next, id)
		next.members[id].affinity += gain
		next.last_invite = id
	else:
		next.last_invite = -1
		match action:
			1:
				work.g += 1.5 * a[0]
				work.b += 2.0
			2:
				work.i += 1.5 * a[1]
				work.b += 3.0
			3:
				work.v += 1.5 * a[2]
				work.b += 1.0
			4:
				work.m += 1.5 * a[3]
				work.b += 1.0
			5:
				work.b = maxf(0.0, float(work.b) - 1.5 * a[0])
	var rate := efficiency(float(work.b))
	var added_bugs := 0.0
	var repair := 0.0
	var contributions: Array = []
	for member_id in range(4):
		var stats := ability(next, member_id)
		var member: Dictionary = next.members[member_id]
		var bonus := 1.2 if member.learned and int(member.role) == int(DEFINITIONS[member_id].specialty) else 1.0
		var contribution := {"g": 0.0, "i": 0.0, "v": 0.0, "m": 0.0, "repair": 0.0}
		match int(member.role):
			0:
				contribution.g = (0.6 * stats[0] + 0.4 * stats[1]) * bonus * rate
				contribution.i = 0.8 * stats[1] * bonus * rate
				added_bugs += 0.2 * stats[0]
			1:
				contribution.v = 0.9 * stats[2] * bonus * rate
			2:
				contribution.m = 0.9 * stats[3] * bonus * rate
			3:
				contribution.repair = 1.5 * stats[0] * bonus
		for key in ["g", "i", "v", "m"]:
			work[key] += contribution[key]
		repair += contribution.repair
		contributions.append(contribution)
	work.b = maxf(0.0, float(work.b) + added_bugs - repair)
	next.inspiration += 1
	var month := int(state.month)
	var reward := 0
	var targets: Array = []
	if month == 4 or month == 8:
		var limits := [35.0, 30.0, 45.0] if month == 4 else [80.0, 65.0, 100.0]
		var values := [float(work.g), float(work.i), performance(work)]
		for index in range(3):
			var reached: bool = values[index] >= limits[index]
			targets.append({"name": ["游戏性", "创新性", "表现力"][index], "value": values[index], "target": limits[index], "reached": reached})
			reward += 1 if reached else 0
		targets.append({"name": "稳定性", "value": work.b, "target": 10.0, "reached": float(work.b) <= 10.0})
		reward += 1 if float(work.b) <= 10.0 else 0
		next.claimed.append(month)
	if month == 12:
		reward = 6 + floori(float(score(work).total) / 20.0)
	next.inspiration += reward
	var delta := {"g": float(work.g) - float(old.g), "i": float(work.i) - float(old.i), "p": performance(work) - performance(old), "b": float(work.b) - float(old.b)}
	var report := {"month": month, "member": id, "action": action, "affinity": gain, "delta": delta, "efficiency": rate, "bonus_inspiration": reward, "targets": targets, "contributions": contributions, "score": score(work)}
	next.report = report
	next.phase = "report"
	next.history.append({"month": month, "score": score(work).total, "work": work.duplicate(true)})
	next.log.push_front("%02d 月 · %s%s，游戏性 +%.1f / 创新性 +%.1f / 表现力 +%.1f" % [month, DEFINITIONS[id].name, "参与邀约" if action == 0 else "完成" + ACTIONS[action], delta.g, delta.i, delta.p])
	if next.log.size() > 20:
		next.log.resize(20)
	return {"ok": true, "state": next, "report": report}

static func acknowledge(state: Dictionary) -> Dictionary:
	if state.phase != "report":
		return state
	var next := state.duplicate(true)
	if int(next.month) == 12:
		next.phase = "ending"
	else:
		next.month += 1
		next.phase = "ready"
	return next

static func valid_state(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for key in fresh():
		if not value.has(key):
			return false
	if value.version != VERSION or not value.phase in ["setup", "ready", "report", "ending"]:
		return false
	if not value.month is float and not value.month is int:
		return false
	if float(value.month) != float(int(value.month)) or int(value.month) < 1 or int(value.month) > 12:
		return false
	if not value.members is Array or value.members.size() != 4 or not value.work is Dictionary:
		return false
	for member in value.members:
		if not member is Dictionary or not member.has_all(["affinity", "role", "learned"]):
			return false
		if not _finite_range(member.affinity, 0, 100) or not _finite_range(member.role, 0, 3) or not member.learned is bool:
			return false
		if float(member.role) != int(member.role) or float(member.affinity) != int(member.affinity):
			return false
	for key in ["g", "i", "v", "m", "b"]:
		if not value.work.has(key) or not _finite_range(value.work[key], 0, 100000):
			return false
	if not _finite_range(value.inspiration, 0, 10000) or not _finite_range(value.genre, 0, 2) or not _finite_range(value.topic, 0, 2) or not _finite_range(value.last_invite, -1, 3):
		return false
	for key in ["inspiration", "genre", "topic", "last_invite"]:
		if float(value[key]) != int(value[key]):
			return false
	if not value.title is String or not value.history is Array or not value.log is Array or not value.claimed is Array or not value.report is Dictionary:
		return false
	for item in value.log:
		if not item is String:
			return false
	if value.history.size() > 12 or value.log.size() > 20 or value.title.length() > 18:
		return false
	for item in value.history:
		if not item is Dictionary or not item.has_all(["month", "score", "work"]) or not _finite_range(item.month, 1, 12) or not _finite_range(item.score, 0, 100):
			return false
		if not item.work is Dictionary:
			return false
		for key in ["g", "i", "v", "m", "b"]:
			if not item.work.has(key) or not _finite_range(item.work[key], 0, 100000):
				return false
	if value.phase == "ending" and int(value.month) != 12:
		return false
	if value.phase == "report":
		if not value.report.has_all(["month", "member", "action", "affinity", "delta", "efficiency", "bonus_inspiration", "targets", "contributions", "score"]):
			return false
		if not value.report.delta is Dictionary or not value.report.delta.has_all(["g", "i", "p", "b"]):
			return false
		for key in ["g", "i", "p", "b"]:
			if not _finite_range(value.report.delta[key], -100000, 100000):
				return false
		for key in ["month", "member", "action", "affinity", "efficiency", "bonus_inspiration"]:
			if not _finite_range(value.report[key], 0, 100000):
				return false
		if value.report.month != value.month or int(value.report.member) >= 4 or int(value.report.action) >= 6:
			return false
		if not value.report.targets is Array or value.report.targets.size() > 4:
			return false
		for target in value.report.targets:
			if not target is Dictionary or not target.has_all(["name", "value", "target", "reached"]):
				return false
			if not target.name is String or not target.reached is bool or not _finite_range(target.value, 0, 100000) or not _finite_range(target.target, 0, 100000):
				return false
	return true

static func _finite_range(value: Variant, low: float, high: float) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value) >= low and float(value) <= high
