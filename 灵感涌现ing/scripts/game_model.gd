class_name ClubGame
extends RefCounted
## Deterministic rules. UI previews use a copied state and the same resolver as commit.

const VERSION := 4
## 全局资源：归整个社团共有，可由回合、奖励和技能获得，供技能等系统消费。
## 与作品属性、人物属性分开保存；继续沿用已有余额字段及数值。
const INSPIRATION := {"name": "灵感", "initial": 2, "maximum": 10000, "monthly_gain": 1}
const CharacterTable = preload("res://scripts/character_table.gd")
const GameCatalog = preload("res://scripts/game_catalog.gd")
const SkillTable = preload("res://scripts/skills/skill_table.gd")
const SkillRunner = preload("res://scripts/skills/skill_runner.gd")
const ROLES := ["玩法开发", "美术开发", "音效开发", "Bug 修复"]
const AFFINITY_MAX := CharacterTable.AFFINITY_MAX
const SKILL_SLOTS := CharacterTable.SKILL_SLOT_COUNT
## 每点好感带来的能力百分比增幅；好感上限 50 时最高 +50%。
const ABILITY_PER_AFFINITY := 0.01
const ACTIONS := ["邀约交流", "玩法打磨", "原型实验", "风格设计", "配乐制作", "集中测试"]
const GENRES := ["动作", "解谜", "剧情"]
const TOPICS := ["科幻", "奇幻", "校园"]
static var DEFINITIONS: Array = CharacterTable.definitions()

static func fresh() -> Dictionary:
	var members: Array = []
	for id in DEFINITIONS.size():
		members.append({"id": DEFINITIONS[id].id, "affinity": DEFINITIONS[id].affinity, "role": [0, 0, 1, 2][id], "learned_skills": []})
	return {"version": VERSION, "phase": "setup", "year": 1, "month": 1, "inspiration": INSPIRATION.initial, "action_steps": 1,
		"run_id": "%.6f:%d" % [Time.get_unix_time_from_system(), Time.get_ticks_usec()],
		"skill_runtime": {"events": {}, "counts": {}, "temporary": []}, "skill_log": [],
		"title": "未命名的灵感", "genre": 0, "topic": 0,
		"members": members,
		"work": {"g": 0.0, "i": 0.0, "v": 0.0, "m": 0.0, "b": 0.0},
		"last_invite": -1, "history": [], "log": [], "report": {}, "claimed": []}

static func begin(state: Dictionary, title: String, genre: int, topic: int) -> Dictionary:
	if state.has("annual_projects"):
		return state
	if state.phase != "setup" or genre < 0 or genre >= GENRES.size() or topic < 0 or topic >= TOPICS.size():
		return state
	var next := state.duplicate(true)
	next.title = title.strip_edges().left(18) if not title.strip_edges().is_empty() else "未命名的灵感"
	next.genre = genre
	next.topic = topic
	var plan := _plan(next)
	for id in range(4): plan.affinity[DEFINITIONS[id].id] = match_bonus(id, genre, topic)
	var metadata := _metadata(next)
	var before := SkillRunner.run(next, DEFINITIONS, "PROJECT_BEFORE", metadata, plan)
	_apply_plan(next, before.plan)
	var after := SkillRunner.run(next, DEFINITIONS, "PROJECT_AFTER", metadata, _plan(next))
	_apply_plan(next, after.plan)
	next.skill_log = before.records + after.records
	next.phase = "ready"
	next.log = ["新项目立项。十二个月，一起把它做出来。"]
	return next

static func match_bonus(id: int, genre: int, topic: int) -> int:
	return (6 if DEFINITIONS[id].genre == GENRES[genre] else 0) + (6 if DEFINITIONS[id].topic == TOPICS[topic] else 0)

## 新界面的作品档案独立于旧原型的 title/genre/topic；旧字段仅供旧原型兼容。
## 每年一款，按年份保存，当前作品由日历查询，不再保存一份容易失步的 current_project。
static func fresh_annual() -> Dictionary:
	var state := fresh()
	state.annual_project_schema = 1
	state.annual_projects = {}
	return state

static func project_for_year(state: Dictionary, year: int = -1) -> Dictionary:
	var target_year := int(state.year) if year < 0 else year
	return state.get("annual_projects", {}).get(str(target_year), {}).duplicate(true)

static func needs_project_selection(state: Dictionary) -> bool:
	return state.has("annual_projects") and project_for_year(state).is_empty()

static func select_project(state: Dictionary, title: String, genre_id: String, topic_id: String, expected_year: int) -> Dictionary:
	if not needs_project_selection(state) or int(state.year) != expected_year or int(state.month) != 1 or state.phase not in ["setup", "ready"]:
		return {"ok": false}
	var profile := {"id": "%s:project:%d" % [state.run_id, expected_year], "year": expected_year,
		"title": title.strip_edges(), "genre_id": genre_id, "topic_id": topic_id}
	if not GameCatalog.valid_profile(profile, expected_year, state.run_id):
		return {"ok": false}
	var next := state.duplicate(true)
	next.annual_projects[str(expected_year)] = profile
	# 接入已有立项技能触发点；偏好奖励数值不在此处新增。
	var metadata := _metadata(next)
	var before := SkillRunner.run(next, DEFINITIONS, "PROJECT_BEFORE", metadata, _plan(next))
	_apply_plan(next, before.plan)
	var after := SkillRunner.run(next, DEFINITIONS, "PROJECT_AFTER", metadata, _plan(next))
	_apply_plan(next, after.plan)
	next.skill_log = before.records + after.records
	next.phase = "ready"
	return {"ok": true, "state": next, "project": profile.duplicate(true)}

## 白值：人物表基础属性，加上直接增加的数值。
## 后续技能或“其他修正”里的直接加值都汇总在这里，不再参与百分比计算。
static func base_ability(id: int) -> Array:
	var result: Array = []
	for value in DEFINITIONS[id].stats:
		result.append(float(value))
	return result

## 百分比增幅合计：目前只有好感增幅。
## 后续技能的百分比增幅在这里相加，最终只对白值乘一次。
static func ability_bonus(state: Dictionary, id: int) -> float:
	return ABILITY_PER_AFFINITY * float(state.members[id].affinity)

## 最终能力 = 白值 × (1 + 百分比增幅合计)。
static func ability(state: Dictionary, id: int) -> Array:
	var factor: float = 1.0 + ability_bonus(state, id)
	var result: Array = []
	for value in base_ability(id):
		result.append(value * factor)
	return result

static func performance(work: Dictionary) -> float:
	return float(work.get("p", 0.0)) + 0.5 * (float(work.v) + float(work.m)) + minf(float(work.v), float(work.m))

static func efficiency(_bugs: float) -> float:
	## 保留旧调用入口；Bug 仅是数值，不影响产出。
	return 1.0

static func gain_inspiration(state: Dictionary, amount: int) -> Dictionary:
	if amount <= 0:
		return state
	var next := state.duplicate(true)
	_change_inspiration(next, amount)
	return next

static func spend_inspiration(state: Dictionary, amount: int) -> Dictionary:
	if amount <= 0 or amount > int(state.inspiration):
		return state
	var next := state.duplicate(true)
	_change_inspiration(next, -amount)
	return next

static func _change_inspiration(state: Dictionary, delta: int) -> void:
	state.inspiration = clampi(int(state.inspiration) + delta, 0, INSPIRATION.maximum)

static func score(work: Dictionary) -> Dictionary:
	var g := minf(100.0, float(work.g) / 2.1)
	var i := minf(100.0, float(work.i) / 2.1)
	var p := minf(100.0, performance(work) / 2.1)
	var penalty := 0.0 # 兼容既有报告字段，不再产生扣分。
	var total := maxf(0.0, 0.4 * g + 0.3 * i + 0.3 * p)
	var best := total >= 80.0 and minf(g, minf(i, p)) >= 50.0
	var award := "最佳游戏奖" if best else ("优秀作品" if total >= 65.0 else ("入围作品" if total >= 45.0 else "完成参展"))
	return {"g": g, "i": i, "p": p, "penalty": penalty, "total": total, "best": best, "award": award}

static func invite_gain(state: Dictionary, id: int) -> int:
	return mini(AFFINITY_MAX - int(state.members[id].affinity), 10)

static func learn(state: Dictionary, id: int, slot_index: int = 0) -> Dictionary:
	if state.phase not in ["setup", "ready"] or id < 0 or id >= 4 or slot_index < 0 or slot_index >= SKILL_SLOTS:
		return state
	var slot: Dictionary = DEFINITIONS[id].skills[slot_index]
	var skill = SkillTable.skills.get(slot.skill_id)
	if skill == null or skill.display_name.is_empty() or skill.acquisition != "inspiration":
		return state
	if slot.skill_id in state.members[id].learned_skills or int(state.members[id].affinity) < int(slot.unlock_affinity) or int(state.inspiration) < skill.inspiration_cost:
		return state
	var next := spend_inspiration(state, skill.inspiration_cost)
	next.members[id].learned_skills.append(skill.id)
	next.log.push_front("%s 消耗 %d 灵感习得「%s」。" % [DEFINITIONS[id].name, skill.inspiration_cost, skill.display_name])
	return next

static func assign(state: Dictionary, id: int, role: int) -> Dictionary:
	## 调整职责不消耗回合：立项准备和每月准备阶段都可自由调整，报告与结局阶段禁止。
	if state.phase not in ["setup", "ready"] or id < 0 or id >= 4 or role < 0 or role >= 4:
		return state
	var next := state.duplicate(true)
	next.members[id].role = role
	return next

static func resolve(state: Dictionary, id: int, action: int, expected_month: int) -> Dictionary:
	# 旧原型整月行动入口不能绕过新界面的年度作品流程。
	if state.has("annual_projects"):
		return {"ok": false}
	if state.phase != "ready" or int(state.month) != expected_month or id < 0 or id >= 4 or action < 0 or action >= ACTIONS.size():
		return {"ok": false}
	var next := state.duplicate(true)
	var old: Dictionary = state.work.duplicate(true)
	var old_inspiration := int(state.inspiration)
	var old_affinity := int(state.members[id].affinity)
	var metadata := _metadata(next, id, action)
	var records: Array = []
	var action_plan := _plan(next)
	var a := ability(next, id)
	if action == 0:
		action_plan.affinity[DEFINITIONS[id].id] = invite_gain(next, id)
		next.last_invite = id
	else:
		next.last_invite = -1
		match action:
			1: action_plan.work.g = 1.5 * a[0]; action_plan.work.b = 2.0
			2: action_plan.work.i = 1.5 * a[1]; action_plan.work.b = 3.0
			3: action_plan.work.v = 1.5 * a[2]; action_plan.work.b = 1.0
			4: action_plan.work.m = 1.5 * a[3]; action_plan.work.b = 1.0
			5: action_plan.work.b = -1.5 * a[0]
	var stage := SkillRunner.run(next, DEFINITIONS, "ACTION_BEFORE", metadata, action_plan)
	_apply_plan(next, stage.plan)
	records.append_array(stage.records)
	metadata.action_result = stage.plan.duplicate(true)
	stage = SkillRunner.run(next, DEFINITIONS, "ACTION_AFTER", metadata, _plan(next))
	_apply_plan(next, stage.plan)
	records.append_array(stage.records)
	var duties := _resolve_duties(next, metadata)
	var rate: float = duties.efficiency
	var contributions: Array = duties.contributions
	records.append_array(duties.records)
	_change_inspiration(next, INSPIRATION.monthly_gain)
	var month := int(next.month)
	var reward := 0
	var targets: Array = []
	if month == 4 or month == 8:
		var limits := [35.0, 30.0, 45.0] if month == 4 else [80.0, 65.0, 100.0]
		var values := [float(next.work.g), float(next.work.i), performance(next.work)]
		for index in range(3):
			var reached: bool = values[index] >= limits[index]
			targets.append({"name": ["游戏性", "创新性", "表现力"][index], "value": values[index], "target": limits[index], "reached": reached})
			reward += 1 if reached else 0
		next.claimed.append(month)
	var final_score := score(next.work)
	if month == 12:
		var award_plan := _plan(next)
		award_plan.score = {"g": final_score.g, "i": final_score.i, "p": final_score.p, "bonus": 0.0}
		stage = SkillRunner.run(next, DEFINITIONS, "AWARD_BEFORE", metadata, award_plan)
		final_score = _award_score(next.work, stage.plan.score)
		records.append_array(stage.records)
		metadata.award_best = final_score.best
		metadata.award_result = final_score.duplicate(true)
		var reward_plan := _plan(next)
		reward_plan.inspiration = 6 + floori(float(final_score.total) / 20.0)
		stage = SkillRunner.run(next, DEFINITIONS, "AWARD_AFTER", metadata, reward_plan)
		reward = roundi(float(stage.plan.inspiration))
		_apply_plan(next, stage.plan)
		records.append_array(stage.records)
	else:
		_change_inspiration(next, reward)
	var work: Dictionary = next.work
	var delta := {"g": float(work.g) - float(old.g), "i": float(work.i) - float(old.i), "p": performance(work) - performance(old), "b": float(work.b) - float(old.b)}
	var report := {"month": month, "member": id, "action": action, "affinity": int(next.members[id].affinity) - old_affinity,
		"delta": delta, "efficiency": rate, "bonus_inspiration": reward, "inspiration_delta": int(next.inspiration) - old_inspiration,
		"targets": targets, "contributions": contributions, "score": final_score, "skill_events": records}
	next.report = report
	next.skill_log = records
	next.phase = "report"
	next.history.append({"month": month, "score": final_score.total, "work": work.duplicate(true)})
	next.log.push_front("%02d 月 · %s%s，游戏性 +%.1f / 创新性 +%.1f / 表现力 +%.1f" % [month, DEFINITIONS[id].name, "参与邀约" if action == 0 else "完成" + ACTIONS[action], delta.g, delta.i, delta.p])
	if next.log.size() > 20: next.log.resize(20)
	return {"ok": true, "state": next, "report": report}


## 新界面仅执行岗位工作，不隐式选择邀约、任务、类型或题材。
## 报告保留结算月份；日历先走到下月，UI 播放期间禁止再次提交。
static func advance_work(state: Dictionary, expected_year: int, expected_month: int) -> Dictionary:
	if needs_project_selection(state):
		return {"ok": false}
	if state.phase not in ["setup", "ready"] or int(state.year) != expected_year or int(state.month) != expected_month:
		return {"ok": false}
	var next := state.duplicate(true)
	var old_inspiration := int(state.inspiration)
	var duties := _resolve_duties(next, _metadata(next))
	_change_inspiration(next, INSPIRATION.monthly_gain)
	var report := {"year": expected_year, "month": expected_month,
		"inspiration_delta": int(next.inspiration) - old_inspiration, "inspiration": next.inspiration,
		"contributions": duties.contributions, "efficiency": duties.efficiency,
		"members": next.members.duplicate(true), "work": next.work.duplicate(true),
		"project": project_for_year(state)}
	next.skill_log = duties.records
	next.month = 1 if expected_month == 12 else expected_month + 1
	next.year = expected_year + 1 if expected_month == 12 else expected_year
	next.action_steps = 1
	return {"ok": true, "state": next, "report": report}

## 任务次数归当前作品（年份）共有，不因更换执行成员而重置。
const TASKS := [{"id": "art_concept", "name": "美术概念设计", "cost": 1}]

## 隐藏的全社团回合行动余额；旧状态缺字段时按初始一步处理。
static func action_steps(state: Dictionary) -> int:
	return int(state.get("action_steps", 1))

static func available_tasks(state: Dictionary) -> Array:
	if needs_project_selection(state):
		return []
	if state.phase not in ["setup", "ready"] or action_steps(state) < 1:
		return []
	var completed: Array = state.get("completed_tasks", {}).get(str(int(state.year)), [])
	return TASKS.filter(func(task: Dictionary): return task.id not in completed)

static func execute_task(state: Dictionary, member_id: int, task_id: String, expected_year: int, expected_month: int) -> Dictionary:
	if member_id < 0 or member_id >= DEFINITIONS.size() or int(state.year) != expected_year or int(state.month) != expected_month:
		return {"ok": false}
	var available := available_tasks(state)
	if not available.any(func(task: Dictionary): return task.id == task_id):
		return {"ok": false}
	var stats := ability(state, member_id)
	var plan := _plan(state)
	plan.work.p = float(stats[1]) + float(stats[2])
	# 仅美术概念设计：分母最低取 1，比值限制为 0.1～2，不改变人物属性。
	var concept_ratio := clampf(float(stats[1]) / maxf(1.0, float(stats[2])), 0.1, 2.0)
	plan.work.i = plan.work.p * concept_ratio
	var metadata := _metadata(state, member_id, 3)
	metadata.task_id = task_id
	return _execute_member_action(state, member_id, metadata, plan, TASKS[0].name)

## 邀约与任务共用行动余额，只执行行动技能，不推进月份或结算职责。
static func execute_invite(state: Dictionary, member_id: int, expected_year: int, expected_month: int) -> Dictionary:
	if needs_project_selection(state):
		return {"ok": false}
	if state.phase not in ["setup", "ready"] or action_steps(state) < 1 or member_id < 0 or member_id >= DEFINITIONS.size():
		return {"ok": false}
	if int(state.year) != expected_year or int(state.month) != expected_month:
		return {"ok": false}
	var plan := _plan(state)
	plan.affinity[DEFINITIONS[member_id].id] = invite_gain(state, member_id)
	return _execute_member_action(state, member_id, _metadata(state, member_id, 0), plan, "邀约")

static func _execute_member_action(state: Dictionary, member_id: int, metadata: Dictionary, plan: Dictionary, action_name: String) -> Dictionary:
	var next := state.duplicate(true)
	next.action_steps = action_steps(state) - 1
	var old_work: Dictionary = next.work.duplicate(true)
	var old_inspiration := int(next.inspiration)
	next.last_invite = member_id if metadata.action_kind == "invite" else -1
	var before := SkillRunner.run(next, DEFINITIONS, "ACTION_BEFORE", metadata, plan)
	_apply_plan(next, before.plan)
	metadata.action_result = before.plan.duplicate(true)
	var after := SkillRunner.run(next, DEFINITIONS, "ACTION_AFTER", metadata, _plan(next))
	_apply_plan(next, after.plan)
	if metadata.action_kind == "task":
		if not next.has("completed_tasks"):
			next.completed_tasks = {}
		var year_key := str(int(state.year))
		if not next.completed_tasks.has(year_key):
			next.completed_tasks[year_key] = []
		next.completed_tasks[year_key].append(metadata.task_id)
	var records: Array = before.records + after.records
	next.skill_log = records
	var delta := {"p": performance(next.work) - performance(old_work)}
	for key in ["g", "i", "v", "m", "b"]:
		delta[key] = float(next.work[key]) - float(old_work[key])
	return {"ok": true, "state": next, "report": {"member": member_id, "task_id": metadata.get("task_id", ""), "kind": metadata.action_kind,
		"name": action_name, "year": int(state.year), "month": int(state.month), "project": project_for_year(state),
		"task_delta": delta, "delta": delta,
		"inspiration_delta": int(next.inspiration) - old_inspiration, "inspiration": next.inspiration,
		"members_before": state.members.duplicate(true), "members": next.members.duplicate(true), "skill_events": records}}

static func _resolve_duties(state: Dictionary, metadata: Dictionary) -> Dictionary:
	var records: Array = []
	var rate := 1.0
	var duty_plan := _plan(state)
	for member_id in range(4):
		var stats := ability(state, member_id)
		var member: Dictionary = state.members[member_id]
		var contribution := {"g": 0.0, "i": 0.0, "v": 0.0, "m": 0.0, "b": 0.0, "repair": 0.0}
		match int(member.role):
			0:
				contribution.g = 0.6 * stats[0] + 0.4 * stats[1]
				contribution.i = 0.8 * stats[1]
				contribution.b = 0.2 * stats[0]
			1: contribution.v = 0.9 * stats[2]
			2: contribution.m = 0.9 * stats[3]
			3: contribution.repair = 1.5 * stats[0]
		duty_plan.contributions[DEFINITIONS[member_id].id] = contribution
	var stage := SkillRunner.run(state, DEFINITIONS, "DUTY_BEFORE", metadata, duty_plan)
	var contributions: Array = []
	for member in state.members:
		contributions.append(stage.plan.contributions[member.id].duplicate(true))
	_apply_plan(state, stage.plan)
	records.append_array(stage.records)
	metadata.duty_result = stage.plan.duplicate(true)
	stage = SkillRunner.run(state, DEFINITIONS, "DUTY_AFTER", metadata, _plan(state))
	_apply_plan(state, stage.plan)
	records.append_array(stage.records)
	return {"efficiency": rate, "contributions": contributions, "records": records}

static func _plan(state: Dictionary) -> Dictionary:
	var affinity: Dictionary = {}
	for member in state.members: affinity[member.id] = 0.0
	return {"work": {"g": 0.0, "i": 0.0, "v": 0.0, "m": 0.0, "b": 0.0},
		"affinity": affinity, "inspiration": 0.0, "contributions": {}, "score": {"g": 0.0, "i": 0.0, "p": 0.0, "bonus": 0.0}}

static func _metadata(state: Dictionary, actor: int = -1, action: int = -1) -> Dictionary:
	var profile := project_for_year(state)
	var metadata := {"actor_id": DEFINITIONS[actor].id if actor >= 0 else "", "action_id": action,
		"action_kind": "invite" if action == 0 else ("task" if action > 0 else ""),
		"genre": GENRES[int(state.genre)], "topic": TOPICS[int(state.topic)]}
	if state.has("annual_projects"):
		metadata.project = profile
		metadata.project_id = profile.get("id", "")
		metadata.title = profile.get("title", "")
		metadata.genre_id = profile.get("genre_id", "")
		metadata.topic_id = profile.get("topic_id", "")
		metadata.genre = GameCatalog.display_name(GameCatalog.GENRES, metadata.genre_id)
		metadata.topic = GameCatalog.display_name(GameCatalog.TOPICS, metadata.topic_id)
	return metadata

static func _apply_plan(state: Dictionary, plan: Dictionary) -> void:
	var delta: Dictionary = plan.work.duplicate(true)
	for contribution in plan.contributions.values():
		for key in ["g", "i", "v", "m", "b"]: delta[key] += float(contribution[key])
		delta.b -= float(contribution.repair)
	for key in delta: state.work[key] = clampf(float(state.work.get(key, 0.0)) + float(delta[key]), 0.0, 100000.0)
	for member in state.members:
		member.affinity = clampi(int(member.affinity) + roundi(float(plan.affinity[member.id])), 0, AFFINITY_MAX)
	_change_inspiration(state, roundi(float(plan.inspiration)))

static func _award_score(_work: Dictionary, points: Dictionary) -> Dictionary:
	var g := clampf(float(points.g), 0, 100)
	var i := clampf(float(points.i), 0, 100)
	var p := clampf(float(points.p), 0, 100)
	var penalty := 0.0
	var total := clampf(0.4 * g + 0.3 * i + 0.3 * p + float(points.bonus), 0, 100)
	var best := total >= 80 and minf(g, minf(i, p)) >= 50
	return {"g": g, "i": i, "p": p, "penalty": penalty, "total": total, "best": best,
		"award": "最佳游戏奖" if best else ("优秀作品" if total >= 65 else ("入围作品" if total >= 45 else "完成参展"))}
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
	if DEFINITIONS.size() != 4: return false
	if not value is Dictionary:
		return false
	for key in fresh():
		if key == "action_steps": continue
		if not value.has(key):
			return false
	if value.version != VERSION or not value.phase in ["setup", "ready", "report", "ending"]:
		return false
	if value.has("action_steps"):
		if not _finite_range(value.action_steps, 0, 1) or float(value.action_steps) != int(value.action_steps): return false
	if not value.run_id is String or value.run_id.is_empty() or not _finite_range(value.year, 1, 100000 if value.has("annual_projects") else 3) or value.year != int(value.year): return false
	if value.has("annual_projects"):
		if value.get("annual_project_schema", 0) != 1 or not value.annual_projects is Dictionary: return false
		for year_key in value.annual_projects:
			if not year_key is String or not year_key.is_valid_int(): return false
			var project_year := int(year_key)
			if project_year < 1 or project_year > int(value.year) or str(project_year) != year_key: return false
			if not GameCatalog.valid_profile(value.annual_projects[year_key], project_year, value.run_id): return false
		# 历年必须完整；本年未确认只允许发生在一月。
		var confirmed_years := int(value.year) - (1 if needs_project_selection(value) else 0)
		if value.annual_projects.size() != confirmed_years: return false
		if needs_project_selection(value) and int(value.month) != 1: return false
	elif value.has("annual_project_schema"):
		return false
	if not value.month is float and not value.month is int:
		return false
	if float(value.month) != float(int(value.month)) or int(value.month) < 1 or int(value.month) > 12:
		return false
	if not value.members is Array or value.members.size() != 4 or not value.work is Dictionary:
		return false
	if value.work.has("p") and not _finite_range(value.work.p, 0, 100000): return false
	if value.has("completed_tasks"):
		if not value.completed_tasks is Dictionary: return false
		for year_key in value.completed_tasks:
			if not year_key is String or not year_key.is_valid_int() or str(int(year_key)) != year_key or int(year_key) < 1 or int(year_key) > int(value.year) or not value.completed_tasks[year_key] is Array: return false
			var tasks: Array = value.completed_tasks[year_key]
			if tasks.size() > 1 or (tasks.size() == 1 and tasks[0] != "art_concept"): return false
	for member_id in 4:
		var member: Variant = value.members[member_id]
		if not member is Dictionary or not member.has_all(["affinity", "role", "learned_skills"]):
			return false
		if member.get("id", "") != DEFINITIONS[member_id].id:
			return false
		if not _finite_range(member.affinity, 0, AFFINITY_MAX) or not _finite_range(member.role, 0, 3) or not member.learned_skills is Array:
			return false
		var known: Array = DEFINITIONS[member_id].skills.map(func(slot: Dictionary): return slot.skill_id)
		var learned_ids: Array = []
		for skill_id in member.learned_skills:
			if not skill_id is String or skill_id not in known or skill_id in learned_ids: return false
			if not SkillTable.skills.has(skill_id) or SkillTable.skills[skill_id].acquisition != "inspiration": return false
			learned_ids.append(skill_id)
		if float(member.role) != int(member.role) or float(member.affinity) != int(member.affinity):
			return false
	var runtime_max_year := maxi(3, int(value.year)) if value.has("annual_projects") else 3
	if not SkillRunner.valid_runtime(value.skill_runtime, value.members, runtime_max_year) or not SkillRunner.valid_records(value.skill_log, value.members): return false
	for key in ["g", "i", "v", "m", "b"]:
		if not value.work.has(key) or not _finite_range(value.work[key], 0, 100000):
			return false
	if not _finite_range(value.inspiration, 0, INSPIRATION.maximum) or not _finite_range(value.genre, 0, 2) or not _finite_range(value.topic, 0, 2) or not _finite_range(value.last_invite, -1, 3):
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
		if not value.report.has_all(["month", "member", "action", "affinity", "delta", "efficiency", "bonus_inspiration", "targets", "contributions", "score", "skill_events"]):
			return false
		if not value.report.delta is Dictionary or not value.report.delta.has_all(["g", "i", "p", "b"]):
			return false
		for key in ["g", "i", "p", "b"]:
			if not _finite_range(value.report.delta[key], -100000, 100000):
				return false
		for key in ["month", "member", "action", "efficiency"]:
			if not _finite_range(value.report[key], 0, 100000):
				return false
		if not _finite_range(value.report.affinity, -100, 100) or not _finite_range(value.report.bonus_inspiration, -10000, 10000) or not SkillRunner.valid_records(value.report.skill_events, value.members): return false
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
