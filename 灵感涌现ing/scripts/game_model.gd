class_name ClubGame
extends RefCounted
## Deterministic rules. UI previews use a copied state and the same resolver as commit.

const VERSION := 6
const MAX_YEARS := 3
## 全局资源：归整个社团共有，可由回合、奖励和技能获得，供技能等系统消费。
## 与作品属性、人物属性分开保存；月末逐人按增幅后脑洞判定工作灵感。
const INSPIRATION := {"name": "灵感", "initial": 10, "maximum": 10000}
const CharacterTable = preload("res://scripts/character_table.gd")
const GameCatalog = preload("res://scripts/game_catalog.gd")
const SkillTable = preload("res://scripts/skills/skill_table.gd")
const SkillRunner = preload("res://scripts/skills/skill_runner.gd")
const ROLES := ["玩法开发", "美术开发", "音效开发", "Bug 修复"]
const AFFINITY_MAX := CharacterTable.AFFINITY_MAX
const SKILL_SLOTS := CharacterTable.SKILL_SLOT_COUNT
## 每点好感带来的能力百分比增幅；好感上限 50 时最高 +50%。
const ABILITY_PER_AFFINITY := 0.01
## 数值转换单元：由属性算出的作品产出，在进入其他 buff 之前走一次这里；工作灵感单独概率判定。
## 系数取 3 个 [0.5, 1.5] 均匀随机数的平均（Irwin–Hall 近似）；
## 种子由本局 ID、年月与产出对象决定，所以预览、重复结算和读档结果一致。
## 同一份产出只转换一次：转换之后叠加的 buff（例如梦想家翻倍）不再重复换算。
const OUTPUT_SAMPLES := 3
const OUTPUT_LOW := 0.5
const OUTPUT_HIGH := 1.5
## 转换结果量化到 4 位小数：数值保持可读，存档 JSON（约 16 位有效数字）往返后完全一致。
const OUTPUT_DECIMALS := 4
## 立项时命中成员喜欢的类型／题材：每命中一项提升的好感。
const PREFERENCE_AFFINITY := 10
## 年度评奖：作品只有游戏性、创新性、表现力与 Bug 四项属性，分项按 1:1 直接取用。
## 最佳美术看表现力（美术与音乐岗位产出的就是表现力），不再引入其他换算。
const AWARD_NOMINATION_TOTAL := 3000.0
const AWARD_ART_PRESENTATION := 4000.0
const AWARD_BEST_PAIR := 10000.0
const AWARD_BEST_PRESENTATION := 2000.0
## 三个奖项按列表顺序依次展示；条件用 BUG灾难 修正后的分数判断。
const ANNUAL_AWARDS := [
	{"id": "best_game_nomination", "name": "最佳游戏提名", "condition": "游戏性 + 创新性 + 表现力 达到 3000", "reward": 20},
	{"id": "best_art", "name": "最佳美术", "condition": "表现力达到 4000", "reward": 30},
	{"id": "best_game", "name": "最佳游戏", "condition": "游戏性与创新性之和达到 10000，且表现力达到 2000", "reward": 50},
]
## BUG灾难：结算后 Bug 0～20 不判定，21～100 每多 1 只概率 +1%，100 以上恒为 80%。
const BUG_DISASTER := {"id": "bug_disaster", "name": "BUG灾难", "factor": 0.5, "free_bugs": 20, "full_bugs": 100, "maximum": 0.8,
	"message": "收到玩家反映，大量BUG造成了灾难性的体验......",
	"detail": "获得特质「BUG灾难」：计算该游戏分数时 ×0.5。"}
static var DEFINITIONS: Array = CharacterTable.definitions()

## 新游戏状态：只有游戏性、创新性、表现力与 Bug 四个作品属性，每年一部作品。
static func fresh() -> Dictionary:
	var members: Array = []
	for id in DEFINITIONS.size():
		members.append({"id": DEFINITIONS[id].id, "affinity": DEFINITIONS[id].affinity, "recruited": false, "role": ([0, 0, 1, 2][id] if id < 4 else 2), "learned_skills": [], "ability_growth": [0.0, 0.0, 0.0, 0.0]})
	return {"version": VERSION, "phase": "setup", "year": 1, "month": 1, "inspiration": INSPIRATION.initial, "action_steps": 1,
		"run_id": "%.6f:%d" % [Time.get_unix_time_from_system(), Time.get_ticks_usec()],
		"skill_runtime": {"events": {}, "counts": {}, "temporary": []}, "skill_log": [],
		"members": members, "recruitment": {},
		"work": {"g": 0.0, "i": 0.0, "p": 0.0, "b": 0.0},
		"annual_project_schema": 1, "annual_projects": {}, "annual_results": {}}

## 开始界面的初始阵容：必须是两名不同的有效角色，直接入社，无年初加入事件。
static func start_with_members(character_ids: Array) -> Dictionary:
	if character_ids.size() != 2: return {"ok": false}
	var available := CharacterTable.initial_ids()
	if not character_ids[0] is String or not character_ids[1] is String or character_ids[0] == character_ids[1] or character_ids[0] not in available or character_ids[1] not in available:
		return {"ok": false}
	var state := fresh()
	for id in character_ids: state.members[available.find(id)].recruited = true
	return {"ok": true, "state": state}

## 所有角色保留固定编号；只有已加入者参与玩法。
static func is_recruited(state: Dictionary, member_id: int) -> bool:
	return member_id >= 0 and member_id < state.members.size() and bool(state.members[member_id].get("recruited", false))

static func recruited_ids(state: Dictionary) -> Array:
	var result: Array = []
	for member_id in state.members.size():
		if is_recruited(state, member_id): result.append(member_id)
	return result

## 十二月结算后只根据刚结束的作品抽选，加入仍由年初事件逐人确认。
static func _prepare_recruitment(state: Dictionary) -> void:
	var key := str(int(state.year))
	if int(state.year) <= 1 or state.recruitment.has(key): return
	var previous := project_for_year(state, int(state.year) - 1)
	var candidates: Array = []
	if not previous.is_empty():
		for member_id in DEFINITIONS.size():
			if not is_recruited(state, member_id) and preference_bonus(member_id, previous.genre_id, previous.topic_id) > 0:
				candidates.append(DEFINITIONS[member_id].id)
	var selected: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%s:recruitment:%d" % [state.run_id, int(state.year)]).hash()
	while not candidates.is_empty() and selected.size() < 2:
		var index := rng.randi_range(0, candidates.size() - 1)
		selected.append(candidates[index])
		candidates.remove_at(index)
	state.recruitment[key] = {"selected": selected, "confirmed": 0}

static func pending_recruits(state: Dictionary) -> Array:
	var record: Dictionary = state.get("recruitment", {}).get(str(int(state.year)), {})
	return record.get("selected", []).slice(int(record.get("confirmed", 0)))

static func confirm_recruit(state: Dictionary, character_id: String) -> Dictionary:
	var pending := pending_recruits(state)
	if int(state.month) != 1 or not needs_project_selection(state) or pending.is_empty() or pending[0] != character_id:
		return {"ok": false}
	var member_id := CharacterTable.initial_ids().find(character_id)
	if member_id < 0 or is_recruited(state, member_id): return {"ok": false}
	var next := state.duplicate(true)
	next.members[member_id].recruited = true
	next.recruitment[str(int(next.year))].confirmed += 1
	return {"ok": true, "state": next}

static func _valid_recruitment(state: Dictionary) -> bool:
	if not state.recruitment is Dictionary: return false
	var known: Array = state.members.map(func(member: Dictionary): return member.id)
	var seen: Array = []
	for year_key in state.recruitment:
		if not year_key is String or not year_key.is_valid_int() or str(int(year_key)) != year_key: return false
		var year := int(year_key)
		if year < 2 or year > int(state.year): return false
		var record: Variant = state.recruitment[year_key]
		if not record is Dictionary or not record.has_all(["selected", "confirmed"]): return false
		if not record.selected is Array or record.selected.size() > 2 or not _finite_range(record.confirmed, 0, record.selected.size()) or float(record.confirmed) != int(record.confirmed): return false
		if int(record.confirmed) < record.selected.size() and (year != int(state.year) or int(state.month) != 1 or not needs_project_selection(state)): return false
		for index in record.selected.size():
			var id: Variant = record.selected[index]
			if not id is String or id not in known or id in seen: return false
			seen.append(id)
			if is_recruited(state, known.find(id)) != (index < int(record.confirmed)): return false
	return true

## 喜欢的类型／题材：按显示名匹配，支持“奇幻、科幻”这样的多项偏好。
static func preference_bonus(id: int, genre_id: String, topic_id: String) -> int:
	return (PREFERENCE_AFFINITY if _likes(str(DEFINITIONS[id].genre), GameCatalog.display_name(GameCatalog.GENRES, genre_id)) else 0) \
		+ (PREFERENCE_AFFINITY if _likes(str(DEFINITIONS[id].topic), GameCatalog.display_name(GameCatalog.TOPICS, topic_id)) else 0)

static func _likes(preference: String, value: String) -> bool:
	if preference.strip_edges().is_empty() or value.is_empty():
		return false
	for item in preference.replace(",", "、").replace("，", "、").split("、", false):
		if item.strip_edges() == value:
			return true
	return false

static func project_for_year(state: Dictionary, year: int = -1) -> Dictionary:
	var target_year := int(state.year) if year < 0 else year
	return state.get("annual_projects", {}).get(str(target_year), {}).duplicate(true)

static func needs_project_selection(state: Dictionary) -> bool:
	return not is_finished(state) and state.has("annual_projects") and project_for_year(state).is_empty()

static func is_finished(state: Dictionary) -> bool:
	return state.get("phase", "") == "finished"

## 总结算独立于评奖：读取归档原始属性，不叠加评奖技能或 BUG灾难 系数。
static func settlement_score(work: Dictionary) -> float:
	return float(work.get("g", 0.0)) + float(work.get("i", 0.0)) + float(work.get("p", 0.0)) - 10.0 * float(work.get("b", 0.0))

static func settlement_summary(state: Dictionary) -> Dictionary:
	if not is_finished(state): return {}
	var projects: Array = []
	var total := 0.0
	for year in range(1, MAX_YEARS + 1):
		var annual := annual_result_for_year(state, year)
		if annual.is_empty(): return {}
		var score := settlement_score(annual.work)
		projects.append({"year": year, "project": annual.project, "work": annual.work, "score": score})
		total += score
	return {"projects": projects, "total": total}

static func select_project(state: Dictionary, title: String, genre_id: String, topic_id: String, expected_year: int) -> Dictionary:
	if expected_year < 1 or expected_year > MAX_YEARS: return {"ok": false}
	if not pending_recruits(state).is_empty() or not needs_project_selection(state) or int(state.year) != expected_year or int(state.month) != 1 or state.phase not in ["setup", "ready"]:
		return {"ok": false}
	var profile := {"id": "%s:project:%d" % [state.run_id, expected_year], "year": expected_year,
		"title": title.strip_edges(), "genre_id": genre_id, "topic_id": topic_id}
	if not GameCatalog.valid_profile(profile, expected_year, state.run_id):
		return {"ok": false}
	var next := state.duplicate(true)
	next.annual_projects[str(expected_year)] = profile
	## 立项时先结算偏好好感，再派发立项技能；技能仍可在其之上继续修正。
	var plan := _plan(next)
	for id in recruited_ids(state): plan.affinity[DEFINITIONS[id].id] = preference_bonus(id, genre_id, topic_id)
	var metadata := _metadata(next)
	var before := SkillRunner.run(next, DEFINITIONS, "PROJECT_BEFORE", metadata, plan)
	_apply_plan(next, before.plan)
	var after := SkillRunner.run(next, DEFINITIONS, "PROJECT_AFTER", metadata, _plan(next))
	_apply_plan(next, after.plan)
	next.skill_log = before.records + after.records
	next.phase = "ready"
	return {"ok": true, "state": next, "project": profile.duplicate(true)}

## 白值：人物表基础属性，加上直接增加的数值。
## 直接成长先并入白值，再由 ability() 统一应用一次百分比增幅。
static func base_ability(id: int, state: Dictionary = {}) -> Array:
	var result: Array = []
	var growth: Array = state.members[id].get("ability_growth", [0.0, 0.0, 0.0, 0.0]) if state.has("members") else [0.0, 0.0, 0.0, 0.0]
	for index in DEFINITIONS[id].stats.size():
		result.append(float(DEFINITIONS[id].stats[index]) + float(growth[index]))
	return result

## 百分比增幅合计：目前只有好感增幅。
## 后续技能的百分比增幅在这里相加，最终只对白值乘一次。
static func ability_bonus(state: Dictionary, id: int) -> float:
	return ABILITY_PER_AFFINITY * float(state.members[id].affinity)

## 最终能力 = 白值 × (1 + 百分比增幅合计)。
static func ability(state: Dictionary, id: int) -> Array:
	var factor: float = 1.0 + ability_bonus(state, id)
	var result: Array = []
	for value in base_ability(id, state):
		result.append(value * factor)
	return result

## 表现力是作品属性本身（美术与音乐岗位、美术概念设计都直接产出它）。
static func performance(work: Dictionary) -> float:
	return float(work.get("p", 0.0))

## ---------------- 数值转换单元 ----------------

## 3 个 [0.5, 1.5] 均匀随机数的平均值；同一个种子永远得到同一个系数。
static func output_factor(seed_key: String) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_key.hash()
	var total := 0.0
	for sample in OUTPUT_SAMPLES:
		total += rng.randf_range(OUTPUT_LOW, OUTPUT_HIGH)
	return total / float(OUTPUT_SAMPLES)

## 岗位产出的系数：每人每月独立，跨月或换人都会变。
static func duty_output_factor(state: Dictionary, member_id: int) -> float:
	return output_factor("%s:duty:%d:%d:%d" % [state.run_id, int(state.year), int(state.month), member_id])

## 任务产出的系数：每部作品、每个人、每种任务独立。
static func task_output_factor(state: Dictionary, member_id: int, task_id: String) -> float:
	return output_factor("%s:task:%d:%d:%d:%s" % [state.run_id, int(state.year), int(state.month), member_id, task_id])

## 整份产出乘同一个系数：一次事件只走一遍，之后的其他 buff 直接改结果。
static func transform_output(values: Dictionary, factor: float) -> Dictionary:
	var scale := pow(10.0, float(OUTPUT_DECIMALS))
	var result: Dictionary = {}
	for key in values:
		result[key] = roundf(float(values[key]) * factor * scale) / scale
	return result

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

static func invite_gain(state: Dictionary, id: int) -> int:
	return mini(AFFINITY_MAX - int(state.members[id].affinity), 10)

static func learn(state: Dictionary, id: int, slot_index: int = 0) -> Dictionary:
	if state.phase not in ["setup", "ready"] or id < 0 or id >= DEFINITIONS.size() or not is_recruited(state, id) or slot_index < 0 or slot_index >= SKILL_SLOTS:
		return state
	var slot: Dictionary = DEFINITIONS[id].skills[slot_index]
	var skill = SkillTable.skills.get(slot.skill_id)
	if skill == null or skill.display_name.is_empty() or skill.acquisition != "inspiration":
		return state
	if slot.skill_id in state.members[id].learned_skills or int(state.members[id].affinity) < int(slot.unlock_affinity) or int(state.inspiration) < skill.inspiration_cost:
		return state
	var next := spend_inspiration(state, skill.inspiration_cost)
	next.members[id].learned_skills.append(skill.id)
	return next

static func assign(state: Dictionary, id: int, role: int) -> Dictionary:
	## 调整职责不消耗回合：立项准备和每月准备阶段都可自由调整，报告与结局阶段禁止。
	if state.phase not in ["setup", "ready"] or id < 0 or id >= DEFINITIONS.size() or not is_recruited(state, id) or role < 0 or role >= 4:
		return state
	var next := state.duplicate(true)
	next.members[id].role = role
	return next

## 岗位结算入口：只有每月的全员工作会推进日历。
static func advance_work(state: Dictionary, expected_year: int, expected_month: int) -> Dictionary:
	if expected_year < 1 or expected_year > MAX_YEARS: return {"ok": false}
	if needs_project_selection(state):
		return {"ok": false}
	if state.phase not in ["setup", "ready"] or int(state.year) != expected_year or int(state.month) != expected_month:
		return {"ok": false}
	var next := state.duplicate(true)
	var old_inspiration := int(state.inspiration)
	var duties := _resolve_duties(next, _metadata(next))
	var records: Array = duties.records
	var finished_work: Dictionary = next.work.duplicate(true)
	var annual: Dictionary = {}
	if expected_month == 12:
		## 年末先判定 BUG灾难、再结算评奖与灵感，最后归档并让新作品从零开始。
		annual = _resolve_annual_award(next, records)
		finished_work = annual.work.duplicate(true)
		if expected_year < MAX_YEARS:
			next.work = {"g": 0.0, "i": 0.0, "p": 0.0, "b": 0.0}
	var report := {"year": expected_year, "month": expected_month,
		"inspiration_delta": int(next.inspiration) - old_inspiration, "inspiration": next.inspiration,
		"contributions": duties.contributions,
		"members_before": state.members.duplicate(true), "members": next.members.duplicate(true), "work": finished_work,
		"sleeping_member_ids": duties.sleeping, "skill_events": records,
		"project": project_for_year(state)}
	if expected_month == 12:
		report.annual = annual
	next.skill_log = records
	var finished := expected_year == MAX_YEARS and expected_month == 12
	next.month = 12 if finished else (1 if expected_month == 12 else expected_month + 1)
	next.year = expected_year + 1 if expected_month == 12 and not finished else expected_year
	if finished: next.phase = "finished"
	SkillRunner.clear_expired_project_effect(next)
	next.action_steps = 0 if finished else 1
	if expected_month == 12 and not finished:
		_prepare_recruitment(next)
	return {"ok": true, "state": next, "report": report}

## 任务次数归当前作品（年份）共有，不因更换执行成员而重置。
const TASKS := [{"id": "art_concept", "name": "美术概念设计", "cost": 1}]

## 隐藏的全社团回合行动余额。
static func action_steps(state: Dictionary) -> int:
	return int(state.get("action_steps", 1))

static func available_tasks(state: Dictionary) -> Array:
	if needs_project_selection(state):
		return []
	if state.phase not in ["setup", "ready"] or action_steps(state) < 1 or recruited_ids(state).is_empty():
		return []
	var completed: Array = state.get("completed_tasks", {}).get(str(int(state.year)), [])
	return TASKS.filter(func(task: Dictionary): return task.id not in completed)

static func execute_task(state: Dictionary, member_id: int, task_id: String, expected_year: int, expected_month: int) -> Dictionary:
	if not is_recruited(state, member_id) or int(state.year) != expected_year or int(state.month) != expected_month:
		return {"ok": false}
	var available := available_tasks(state)
	if not available.any(func(task: Dictionary): return task.id == task_id):
		return {"ok": false}
	var stats := ability(state, member_id)
	var plan := _plan(state)
	## 计算规则 → 转换单元：产出先算出来并只转换一次，再交给 ACTION_BEFORE 的 buff（如梦想家翻倍）。
	var raw := {"p": float(stats[1]) + float(stats[2]), "i": 0.0}
	# 仅美术概念设计：分母最低取 1，比值限制为 0.1～2，不改变人物属性。
	raw.i = raw.p * clampf(float(stats[1]) / maxf(1.0, float(stats[2])), 0.1, 2.0)
	var output: Dictionary = transform_output(raw, task_output_factor(state, member_id, task_id))
	plan.work.p = float(output.p)
	plan.work.i = float(output.i)
	var metadata := _metadata(state, member_id, 3)
	metadata.task_id = task_id
	return _execute_member_action(state, member_id, metadata, plan, TASKS[0].name)

## 邀约与任务共用行动余额，只执行行动技能，不推进月份或结算职责。
static func execute_invite(state: Dictionary, member_id: int, expected_year: int, expected_month: int) -> Dictionary:
	if needs_project_selection(state):
		return {"ok": false}
	if state.phase not in ["setup", "ready"] or action_steps(state) < 1 or not is_recruited(state, member_id):
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
	var before := SkillRunner.run(next, DEFINITIONS, "ACTION_BEFORE", metadata, plan)
	_apply_plan(next, before.plan)
	metadata.action_result = before.plan.duplicate(true)
	metadata.sleeping_member_ids = before.sleeping
	metadata.task_multiplier = before.task_multiplier
	var after := SkillRunner.run(next, DEFINITIONS, "ACTION_AFTER", metadata, _plan(next))
	_apply_plan(next, after.plan)
	if metadata.action_kind == "task" and DEFINITIONS[member_id].id not in before.sleeping:
		if not next.has("completed_tasks"):
			next.completed_tasks = {}
		var year_key := str(int(state.year))
		if not next.completed_tasks.has(year_key):
			next.completed_tasks[year_key] = []
		next.completed_tasks[year_key].append(metadata.task_id)
	var records: Array = before.records + after.records
	next.skill_log = records
	var delta := {"p": performance(next.work) - performance(old_work)}
	for key in ["g", "i", "b"]:
		delta[key] = float(next.work[key]) - float(old_work[key])
	return {"ok": true, "state": next, "report": {"member": member_id, "task_id": metadata.get("task_id", ""), "kind": metadata.action_kind,
		"name": action_name, "year": int(state.year), "month": int(state.month), "project": project_for_year(state),
		"task_delta": delta, "delta": delta,
		"inspiration_delta": int(next.inspiration) - old_inspiration, "inspiration": next.inspiration,
		"members_before": state.members.duplicate(true), "members": next.members.duplicate(true), "skill_events": records,
		"sleeping_member_ids": before.sleeping, "task_multiplier": before.task_multiplier}}

## 工作灵感独立于作品数值转换：脑洞 40 对应 40%，每人每月最多 1 点。
static func duty_inspiration(state: Dictionary, member_id: int) -> int:
	if not is_recruited(state, member_id): return 0
	var chance := clampf(float(ability(state, member_id)[1]) / 100.0, 0.0, 1.0)
	if chance <= 0.0: return 0
	if chance >= 1.0: return 1
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%s:duty_inspiration:%d:%d:%s" % [state.run_id, int(state.year), int(state.month), DEFINITIONS[member_id].id]).hash()
	return 1 if rng.randf() < chance else 0

static func _resolve_duties(state: Dictionary, metadata: Dictionary) -> Dictionary:
	var records: Array = []
	var duty_plan := _plan(state)
	for member_id in recruited_ids(state):
		var stats := ability(state, member_id)
		var member: Dictionary = state.members[member_id]
		var raw := {"g": 0.0, "i": 0.0, "p": 0.0, "b": 0.0, "repair": 0.0}
		match int(member.role):
			0:
				## 玩法开发：Bug 增量向下取整后最低为 0，不承担修复。
				raw.g = 0.7 * stats[0] + 0.5 * stats[1]
				raw.i = 1.2 * stats[1]
				raw.b = maxf(0.0, floorf((stats[1] - stats[0]) * 0.1))
			1:
				## 美术开发：表现力 +（0.8 美术 + 0.2 脑洞），创新性 +（0.3 美术 + 0.2 脑洞）。
				raw.p = 0.8 * stats[2] + 0.2 * stats[1]
				raw.i = 0.3 * stats[2] + 0.2 * stats[1]
			2:
				## 音乐开发：表现力 +（0.8 音乐 + 0.2 脑洞），游戏性 +（0.3 音乐 + 0.2 脑洞）。
				raw.p = 0.8 * stats[3] + 0.2 * stats[1]
				raw.g = 0.3 * stats[3] + 0.2 * stats[1]
			3:
				## Bug 修复：Bug −（1 × 编程）。
				raw.repair = 1.0 * stats[0]
		## 计算规则 → 转换单元；转换之后才交给 DUTY_BEFORE 的其他 buff。
		var contribution: Dictionary = transform_output(raw, duty_output_factor(state, member_id))
		contribution.inspiration = duty_inspiration(state, member_id)
		duty_plan.contributions[DEFINITIONS[member_id].id] = contribution
	var stage := SkillRunner.run(state, DEFINITIONS, "DUTY_BEFORE", metadata, duty_plan)
	var sleeping: Array = stage.sleeping
	var contributions: Array = []
	for member in state.members:
		contributions.append(stage.plan.contributions.get(member.id, {"g": 0.0, "i": 0.0, "p": 0.0, "b": 0.0, "repair": 0.0}).duplicate(true))
	_apply_plan(state, stage.plan)
	records.append_array(stage.records)
	metadata.duty_result = stage.plan.duplicate(true)
	metadata.sleeping_member_ids = sleeping
	stage = SkillRunner.run(state, DEFINITIONS, "DUTY_AFTER", metadata, _plan(state))
	_apply_plan(state, stage.plan)
	records.append_array(stage.records)
	return {"contributions": contributions, "records": records, "sleeping": sleeping}

static func _plan(state: Dictionary) -> Dictionary:
	var affinity: Dictionary = {}
	for member in state.members: affinity[member.id] = 0.0
	return {"work": {"g": 0.0, "i": 0.0, "p": 0.0, "b": 0.0},
		"affinity": affinity, "inspiration": 0.0, "contributions": {}, "score": {"g": 0.0, "i": 0.0, "p": 0.0, "bonus": 0.0}}

static func _metadata(state: Dictionary, actor: int = -1, action: int = -1) -> Dictionary:
	var profile := project_for_year(state)
	var metadata := {"actor_id": DEFINITIONS[actor].id if actor >= 0 else "", "action_id": action,
		"action_kind": "invite" if action == 0 else ("task" if action > 0 else ""),
		"project": profile, "project_id": profile.get("id", ""),
		"title": profile.get("title", ""),
		"genre_id": profile.get("genre_id", ""), "topic_id": profile.get("topic_id", ""),
		"genre": GameCatalog.display_name(GameCatalog.GENRES, str(profile.get("genre_id", ""))),
		"topic": GameCatalog.display_name(GameCatalog.TOPICS, str(profile.get("topic_id", "")))}
	return metadata

static func _apply_plan(state: Dictionary, plan: Dictionary) -> void:
	var delta: Dictionary = plan.work.duplicate(true)
	var inspiration := float(plan.inspiration)
	for contribution in plan.contributions.values():
		inspiration += float(contribution.get("inspiration", 0.0))
		for key in ["g", "i", "p", "b"]:
			delta[key] = float(delta.get(key, 0.0)) + float(contribution[key])
		delta.b -= float(contribution.repair)
	for key in delta: state.work[key] = clampf(float(state.work.get(key, 0.0)) + float(delta[key]), 0.0, 100000.0)
	for member in state.members:
		if not member.recruited: continue
		member.affinity = clampi(int(member.affinity) + roundi(float(plan.affinity[member.id])), 0, AFFINITY_MAX)
	_change_inspiration(state, roundi(inspiration))

## ---------------- 年度评奖 ----------------

## 评奖技能修正前的分项起点：直接取作品的游戏性、创新性、表现力。
static func annual_score(work: Dictionary) -> Dictionary:
	return {"g": maxf(0.0, float(work.get("g", 0.0))),
		"i": maxf(0.0, float(work.get("i", 0.0))),
		"p": maxf(0.0, performance(work)),
		"bonus": 0.0}

## 结算评分：先让评奖技能修正分项与 bonus，再由 BUG灾难 特质把各分项与各项之和统一乘一次系数。
static func finalize_annual_score(points: Dictionary, bug_disaster: bool) -> Dictionary:
	var factor: float = float(BUG_DISASTER.factor) if bug_disaster else 1.0
	var g := maxf(0.0, float(points.get("g", 0.0))) * factor
	var i := maxf(0.0, float(points.get("i", 0.0))) * factor
	var p := maxf(0.0, float(points.get("p", 0.0))) * factor
	var bonus := float(points.get("bonus", 0.0)) * factor
	return {"g": g, "i": i, "p": p,
		"bonus": bonus, "pair": g + i, "total": g + i + p + bonus, "factor": factor,
		"trait": BUG_DISASTER.name if bug_disaster else ""}

## 按固定顺序判定奖项；传入的分数已经包含 BUG灾难 特质修正。
static func annual_awards(score: Dictionary) -> Array:
	var awards: Array = []
	if float(score.get("total", 0.0)) >= AWARD_NOMINATION_TOTAL:
		awards.append(_award_row(ANNUAL_AWARDS[0], float(score.get("total", 0.0))))
	if float(score.get("p", 0.0)) >= AWARD_ART_PRESENTATION:
		awards.append(_award_row(ANNUAL_AWARDS[1], float(score.get("p", 0.0))))
	if float(score.get("pair", 0.0)) >= AWARD_BEST_PAIR and float(score.get("p", 0.0)) >= AWARD_BEST_PRESENTATION:
		awards.append(_award_row(ANNUAL_AWARDS[2], float(score.get("pair", 0.0))))
	return awards

static func _award_row(definition: Dictionary, value: float) -> Dictionary:
	return {"id": definition.id, "name": definition.name, "condition": definition.condition,
		"reward": int(definition.reward), "score": value}

static func award_reward(awards: Array) -> int:
	var total := 0
	for award in awards:
		total += int(award.reward)
	return total

## 每个作品只判定一次：概率只由结算后的作品 Bug 决定，小数向下取整，不改动 Bug 本身。
static func bug_disaster_probability(bugs: float) -> float:
	var effective := int(floorf(maxf(0.0, bugs)))
	if effective <= int(BUG_DISASTER.free_bugs):
		return 0.0
	return clampf(float(effective - int(BUG_DISASTER.free_bugs)) / 100.0, 0.0, float(BUG_DISASTER.maximum))

## 判定与预览使用同一个确定性种子；结果随状态保存，不在每次打开界面时重抽。
static func bug_disaster_roll(state: Dictionary) -> bool:
	var chance := bug_disaster_probability(float(state.work.get("b", 0.0)))
	if chance <= 0.0:
		return false
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%s:bug_disaster:%d" % [state.run_id, int(state.year)]).hash()
	return rng.randf() < chance

static func annual_result_for_year(state: Dictionary, year: int = -1) -> Dictionary:
	var target_year := int(state.year) if year < 0 else year
	return state.get("annual_results", {}).get(str(target_year), {}).duplicate(true)

## 年末评奖：BUG灾难 判定 → 评奖技能修正 → 奖项与灵感奖励 → 写入年度档案。
static func _resolve_annual_award(state: Dictionary, records: Array) -> Dictionary:
	var bug_disaster := bug_disaster_roll(state)
	var metadata := _metadata(state)
	metadata.bug_disaster = bug_disaster
	var award_plan := _plan(state)
	award_plan.score = annual_score(state.work)
	var stage := SkillRunner.run(state, DEFINITIONS, "AWARD_BEFORE", metadata, award_plan)
	records.append_array(stage.records)
	var score := finalize_annual_score(stage.plan.score, bug_disaster)
	var awards := annual_awards(score)
	metadata.award_best = awards.any(func(award: Dictionary): return award.id == ANNUAL_AWARDS[2].id)
	metadata.award_result = score.duplicate(true)
	metadata.awards = awards.duplicate(true)
	var reward_plan := _plan(state)
	reward_plan.inspiration = float(award_reward(awards))
	stage = SkillRunner.run(state, DEFINITIONS, "AWARD_AFTER", metadata, reward_plan)
	records.append_array(stage.records)
	_apply_plan(state, stage.plan)
	var annual := {"year": int(state.year), "project": project_for_year(state), "work": state.work.duplicate(true),
		"score": score, "awards": awards, "reward": roundi(float(stage.plan.inspiration)),
		"trait": score.trait, "bug_disaster": bug_disaster,
		"bug_probability": bug_disaster_probability(float(state.work.get("b", 0.0)))}
	if state.has("annual_results"):
		state.annual_results[str(int(state.year))] = annual.duplicate(true)
	return annual

## 校验新游戏状态：只有一份年度作品档案与评奖档案，没有旧原型字段。
static func valid_state(value: Variant) -> bool:
	if DEFINITIONS.is_empty(): return false
	if not value is Dictionary:
		return false
	for key in fresh():
		if not value.has(key):
			return false
	if value.version != VERSION or not value.phase in ["setup", "ready", "finished"]:
		return false
	if not _finite_range(value.action_steps, 0, 1) or float(value.action_steps) != int(value.action_steps): return false
	if not value.run_id is String or value.run_id.is_empty(): return false
	if not _finite_range(value.year, 1, MAX_YEARS) or value.year != int(value.year): return false
	if not value.month is float and not value.month is int:
		return false
	if float(value.month) != float(int(value.month)) or int(value.month) < 1 or int(value.month) > 12:
		return false
	if is_finished(value) and (int(value.year) != MAX_YEARS or int(value.month) != 12 or int(value.action_steps) != 0): return false
	## 作品档案：每年一款；本年未确认只允许发生在一月。
	if value.get("annual_project_schema", 0) != 1 or not value.annual_projects is Dictionary: return false
	for year_key in value.annual_projects:
		if not year_key is String or not year_key.is_valid_int() or str(int(year_key)) != year_key: return false
		var project_year := int(year_key)
		if project_year < 1 or project_year > int(value.year): return false
		if not GameCatalog.valid_profile(value.annual_projects[year_key], project_year, value.run_id): return false
	var confirmed_years := int(value.year) - (1 if needs_project_selection(value) else 0)
	if value.annual_projects.size() != confirmed_years: return false
	if needs_project_selection(value) and int(value.month) != 1: return false
	## 评奖档案：终局包含第三年，其余状态的本年不能提前出现。
	if not value.annual_results is Dictionary: return false
	var finished_years := MAX_YEARS if is_finished(value) else int(value.year) - 1
	for year_key in value.annual_results:
		if not year_key is String or not year_key.is_valid_int() or str(int(year_key)) != year_key: return false
		var result_year := int(year_key)
		if result_year < 1 or result_year > finished_years: return false
		if not _valid_annual_result(value.annual_results[year_key], result_year, value.run_id): return false
		if value.annual_results[year_key].project != value.annual_projects.get(year_key, {}): return false
	for finished_year in range(1, finished_years + 1):
		if not value.annual_results.has(str(finished_year)): return false
	if not value.members is Array or value.members.size() != DEFINITIONS.size() or not value.work is Dictionary:
		return false
	if value.work.has("p") and not _finite_range(value.work.p, 0, 100000): return false
	if value.has("completed_tasks"):
		if not value.completed_tasks is Dictionary: return false
		for year_key in value.completed_tasks:
			if not year_key is String or not year_key.is_valid_int() or str(int(year_key)) != year_key or int(year_key) < 1 or int(year_key) > int(value.year) or not value.completed_tasks[year_key] is Array: return false
			var tasks: Array = value.completed_tasks[year_key]
			if tasks.size() > 1 or (tasks.size() == 1 and tasks[0] != "art_concept"): return false
	for member_id in DEFINITIONS.size():
		var member: Variant = value.members[member_id]
		if not member is Dictionary or not member.has_all(["affinity", "role", "learned_skills", "recruited"]) or not member.recruited is bool:
			return false
		if member.get("id", "") != DEFINITIONS[member_id].id:
			return false
		if member.has("ability_growth"):
			if not member.ability_growth is Array or member.ability_growth.size() != 4: return false
			for amount in member.ability_growth:
				if not _finite_range(amount, 0, 100000): return false
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
	if not _valid_recruitment(value): return false
	var runtime_max_year := maxi(3, int(value.year))
	if not SkillRunner.valid_runtime(value.skill_runtime, value.members, runtime_max_year) or not SkillRunner.valid_records(value.skill_log, value.members): return false
	for key in ["g", "i", "p", "b"]:
		if not value.work.has(key) or not _finite_range(value.work[key], 0, 100000):
			return false
	if not _finite_range(value.inspiration, 0, INSPIRATION.maximum) or float(value.inspiration) != int(value.inspiration):
		return false
	return true

static func _finite_range(value: Variant, low: float, high: float) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value) >= low and float(value) <= high

## 年度评奖档案：作品快照、分数、奖项、特质与灵感奖励都要能被存档校验读懂。
static func _valid_annual_result(result: Variant, year: int, run_id: String) -> bool:
	if not result is Dictionary or not result.has_all(["year", "project", "work", "score", "awards", "reward", "trait", "bug_disaster", "bug_probability"]):
		return false
	if not _finite_range(result.year, 1, 100000) or int(result.year) != year:
		return false
	if not GameCatalog.valid_profile(result.project, year, run_id):
		return false
	if not result.work is Dictionary:
		return false
	for key in ["g", "i", "p", "b"]:
		if not result.work.has(key) or not _finite_range(result.work[key], 0, 100000):
			return false
	var score: Variant = result.score
	if not score is Dictionary or not score.has_all(["g", "i", "p", "bonus", "pair", "total", "factor", "trait"]):
		return false
	for key in ["g", "i", "p", "pair", "total"]:
		if not _finite_range(score[key], 0, 1000000):
			return false
	if not _finite_range(score.bonus, -1000000, 1000000) or not _finite_range(score.factor, 0, 1) or not score.trait is String or not result.trait is String:
		return false
	if not result.awards is Array or result.awards.size() > ANNUAL_AWARDS.size():
		return false
	var seen: Array = []
	for award in result.awards:
		if not award is Dictionary or not award.has_all(["id", "name", "condition", "reward", "score"]) or not award.id is String or award.id in seen:
			return false
		if not ANNUAL_AWARDS.any(func(definition: Dictionary): return definition.id == award.id):
			return false
		if not _finite_range(award.reward, 0, 1000) or not _finite_range(award.score, 0, 1000000):
			return false
		seen.append(award.id)
	if not _finite_range(result.reward, 0, INSPIRATION.maximum) or not result.bug_disaster is bool:
		return false
	return _finite_range(result.bug_probability, 0, 1)
