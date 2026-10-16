extends SceneTree
const Roster = preload("res://tests/fixtures/roster_fixture.gd")
## 新游戏规则回归：立项、岗位结算、任务与邀约、技能、灵感、跨年与存档。
## 规则测试使用独立的空白人物样本，允许策划自由修改正式人物表。
const Model = preload("res://scripts/game_model.gd")
const Store = preload("res://scripts/save_store.gd")
const SkillTable = preload("res://scripts/skills/skill_table.gd")
const SkillDefinition = preload("res://scripts/skills/skill_definition.gd")
var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func close_to(a: float, b: float) -> bool:
	return absf(a - b) < 0.00001

func _init() -> void:
	var original_definitions: Array = Model.DEFINITIONS
	var original_skills := SkillTable.skills
	SkillTable.skills = original_skills.duplicate()
	for skill_id in SkillTable.skills:
		SkillTable.skills[skill_id] = original_skills[skill_id].duplicate(true)
		SkillTable.skills[skill_id].display_name = ""
		SkillTable.skills[skill_id].triggers = []
	Model.DEFINITIONS = original_definitions.duplicate(true)
	for definition in Model.DEFINITIONS:
		definition.stats = [0.0, 0.0, 0.0, 0.0]
		definition.affinity = 0
		definition.genre = ""
		definition.topic = ""

	## 1. 初始状态与立项
	var initial := Roster.fresh()
	check(Model.valid_state(initial) and Model.needs_project_selection(initial), "新游戏等待立项且可存档")
	check(initial.work == {"g": 0.0, "i": 0.0, "p": 0.0, "b": 0.0}, "作品只有游戏性、创新性、表现力与 Bug")
	check(initial.phase == "setup" and initial.action_steps == 1, "初始阶段与行动步数")
	check(not initial.has("title") and not initial.has("history") and not initial.has("report"), "状态里没有旧原型字段")
	check(not Model.advance_work(initial, 1, 1).ok and Model.available_tasks(initial).is_empty(), "未立项时拒绝工作与任务")
	check(not Model.execute_invite(initial, 0, 1, 1).ok, "未立项时拒绝邀约")
	var selection := Model.select_project(initial, "测试游戏", "act", "fantasy", 1)
	check(selection.ok and Model.needs_project_selection(initial) and initial.annual_projects.is_empty(), "立项不修改输入状态")
	var state: Dictionary = selection.state
	check(state.phase == "ready" and state.annual_projects.size() == 1, "立项写入当年档案并进入准备阶段")
	check(Model.project_for_year(state).title == "测试游戏" and Model.project_for_year(state, 1).genre_id == "act", "作品档案保留名字与稳定 ID")
	check(not Model.select_project(state, "重复", "act", "fantasy", 1).ok, "同年不可重复立项")
	check(not Model.select_project(initial, "过期", "act", "fantasy", 2).ok, "过期年份立项被拒绝")
	check(not Model.select_project(initial, "非法", "missing", "fantasy", 1).ok, "非法类型被拒绝")
	check(not Model.select_project(initial, "非法", "act", "missing", 1).ok, "非法题材被拒绝")
	check(not Model.select_project(initial, " ", "act", "fantasy", 1).ok, "空名字被拒绝")

	## 2. 偏好好感：命中喜欢的类型／题材时立项加好感
	check(Model.preference_bonus(0, "act", "fantasy") == 0, "空偏好不加好感")
	Model.DEFINITIONS[0].topic = "奇幻、科幻"
	check(Model.preference_bonus(0, "act", "fantasy") == Model.PREFERENCE_AFFINITY, "多项偏好中命中一项即加好感")
	check(Model.preference_bonus(0, "act", "sci_fi") == Model.PREFERENCE_AFFINITY, "偏好中的第二项同样命中")
	check(Model.preference_bonus(0, "act", "modern") == 0, "未命中的题材不加好感")
	Model.DEFINITIONS[0].genre = "ACT"
	check(Model.preference_bonus(0, "act", "fantasy") == Model.PREFERENCE_AFFINITY * 2, "类型与题材同时命中各加一次")
	var matched := Model.select_project(Roster.fresh(), "偏好", "act", "fantasy", 1)
	check(matched.state.members[0].affinity == Model.PREFERENCE_AFFINITY * 2, "立项把偏好好感写进状态")
	check(matched.state.members[1].affinity == 0, "没有偏好的人不加好感")
	Model.DEFINITIONS[0].genre = ""
	Model.DEFINITIONS[0].topic = ""

	## 3. 能力两层：白值 + 好感增幅
	for definition in Model.DEFINITIONS:
		definition.stats = [10.0, 10.0, 10.0, 10.0]
	var growth: Dictionary = Model.select_project(Roster.fresh(), "成长", "act", "modern", 1).state
	growth.members[0].affinity = 50
	check(close_to(Model.base_ability(0, growth)[0], 10.0), "白值保持人物表属性")
	check(close_to(Model.ability_bonus(growth, 0), 0.5), "每点好感提供百分之一增幅")
	check(close_to(Model.ability(growth, 0)[0], 15.0), "最终能力只乘一次增幅")
	growth.members[0].affinity = 0
	check(close_to(Model.ability(growth, 0)[0], 10.0), "零好感保持白值")
	check(Model.invite_gain(growth, 0) == 10, "邀约固定加十点好感")
	growth.members[0].affinity = 45
	check(Model.invite_gain(growth, 0) == 5, "邀约受好感上限约束")
	for definition in Model.DEFINITIONS:
		definition.stats = [0.0, 0.0, 0.0, 0.0]

	## 4. 岗位结算：零属性不产出数值，输入状态不被修改
	var blank: Dictionary = Model.select_project(Roster.fresh(), "空属性", "act", "modern", 1).state
	var snapshot: String = JSON.stringify(blank)
	var settled := Model.advance_work(blank, 1, 1)
	check(settled.ok, "准备阶段允许下一回合")
	check(JSON.stringify(blank) == snapshot, "结算不修改输入状态或嵌套数据")
	check(settled.state.month == 2 and settled.state.year == 1 and settled.state.action_steps == 1, "结算推进一个月并恢复行动步数")
	check(settled.state.work == {"g": 0.0, "i": 0.0, "p": 0.0, "b": 0.0}, "零属性不产出作品数值")
	check(settled.state.inspiration == Model.INSPIRATION.initial + Model.INSPIRATION.monthly_gain, "每月获得一份灵感")
	check(not Model.advance_work(settled.state, 1, 1).ok, "旧月份请求被拒绝")
	check(settled.report.contributions.size() == Model.DEFINITIONS.size(), "报告保留全员贡献")
	check(settled.report.project.title == "空属性", "报告带当年作品档案")

	## 5. 任务与邀约共用行动步数，都不推进月份
	var task := Model.execute_task(blank, 0, "art_concept", 1, 1)
	check(task.ok and task.state.month == 1 and task.state.action_steps == 0, "任务消耗一步且不推进月份")
	check(task.state.completed_tasks["1"] == ["art_concept"], "任务登记年度次数")
	check(Model.available_tasks(task.state).is_empty() and not Model.execute_task(task.state, 1, "art_concept", 1, 1).ok, "每部作品只能做一次任务")
	check(not Model.execute_task(blank, 0, "art_concept", 1, 2).ok, "陈旧年月不能提交任务")
	check(not Model.execute_task(blank, 0, "missing", 1, 1).ok, "未知任务被拒绝")
	check(not Model.execute_task(blank, -1, "art_concept", 1, 1).ok, "无效成员被拒绝")
	var invite := Model.execute_invite(blank, 0, 1, 1)
	check(invite.ok and invite.state.members[0].affinity == 10 and invite.state.work == blank.work, "邀约加好感且不产出作品数值")
	check(invite.report.kind == "invite" and not invite.state.has("completed_tasks"), "邀约不登记任务次数")
	check(not Model.execute_task(invite.state, 0, "art_concept", 1, 1).ok, "行动后不能再分配任务")
	check(not Model.execute_invite(task.state, 1, 1, 1).ok, "任务后不能再邀约")
	var next_month := Model.advance_work(task.state, 1, 1)
	check(next_month.ok and next_month.state.action_steps == 1, "下个月恢复行动步数")
	check(Model.available_tasks(next_month.state).is_empty(), "当年任务次数不因跨月恢复")

	## 6. 职责调整
	var setup_state := Roster.fresh()
	check(int(Model.assign(setup_state, 0, 3).members[0].role) == 3, "准备阶段可以调整职责")
	check(int(setup_state.members[0].role) == 0, "调整职责不修改输入状态")
	var finished: Dictionary = Model.select_project(Roster.fresh(), "职责", "act", "modern", 1).state
	check(int(Model.assign(finished, 0, 1).members[0].role) == 1, "立项后仍可调整职责")
	check(Model.assign(finished, 0, 4) == finished and Model.assign(finished, -1, 0) == finished, "非法职责被拒绝")

	## 7. 灵感是全局资源
	var resource_state := Roster.fresh()
	var earned := Model.gain_inspiration(resource_state, 7)
	check(earned.inspiration == 9 and resource_state.inspiration == Model.INSPIRATION.initial, "灵感获得不修改输入状态")
	var spent := Model.spend_inspiration(earned, 4)
	check(spent.inspiration == 5 and earned.inspiration == 9, "灵感消费不修改输入状态")
	check(Model.spend_inspiration(spent, 6) == spent and Model.spend_inspiration(spent, -1) == spent, "超额与负数消费被拒绝")
	check(Model.gain_inspiration(spent, -1) == spent, "负数获得被拒绝")
	check(Model.gain_inspiration(earned, 10000).inspiration == Model.INSPIRATION.maximum, "灵感有上限")

	## 8. 技能学习：门槛、费用与重复购买
	var slot_id: String = Model.DEFINITIONS[0].skills[0].skill_id
	SkillTable.skills[slot_id] = SkillDefinition.from_row({"id": slot_id, "name": "付费测试", "description": "测试技能", "quip": "",
		"acquisition": "inspiration", "inspiration_cost": 3, "triggers": []})
	var poor := Roster.fresh()
	check(Model.learn(poor, 0, 0) == poor, "灵感不足时不能习得")
	poor.inspiration = 5
	var learned := Model.learn(poor, 0, 0)
	check(learned.inspiration == 2 and learned.members[0].learned_skills == [slot_id], "习得按配置扣费并记录")
	check(poor.inspiration == 5 and poor.members[0].learned_skills.is_empty(), "习得不修改输入状态")
	check(Model.learn(learned, 0, 0) == learned, "重复习得不扣费")
	var locked := Roster.fresh()
	locked.inspiration = 5
	locked.members[0].affinity = int(Model.DEFINITIONS[0].skills[1].unlock_affinity) - 1
	check(Model.learn(locked, 0, 1) == locked, "未达好感门槛不能习得")

	## 9. 立项技能：在偏好好感之后追加效果
	SkillTable.skills[slot_id] = SkillDefinition.from_row({"id": slot_id, "name": "立项测试", "description": "测试", "quip": "",
		"acquisition": "auto", "inspiration_cost": 0, "triggers": [
			{"hook": "PROJECT_AFTER", "conditions": {}, "target": "work", "frequency": "year",
			"effect_id": "numeric_modifier", "params": {"field": "g", "operation": "add", "amount": 2}, "priority": 0}]})
	var skilled := Model.select_project(Roster.fresh(), "技能立项", "act", "modern", 1)
	check(skilled.state.work.g == 2.0 and skilled.state.skill_log.size() == 1, "立项技能写入作品并留下来源记录")
	check(not skilled.state.skill_runtime.events.is_empty(), "立项事件被记录")

	## 10. 完整一年：十二月评奖、跨年清空与年度档案
	var run: Dictionary = Model.select_project(Roster.fresh(), "完整流程", "act", "modern", 1).state
	for month in range(1, 13):
		var turn := Model.advance_work(run, 1, month)
		check(turn.ok, "第 " + str(month) + " 月可以结算")
		check(Model.valid_state(turn.state), "第 " + str(month) + " 月状态有效")
		run = turn.state
	check(run.year == 2 and run.month == 1 and Model.needs_project_selection(run), "十二月后进入下一年并等待立项")
	check(run.work == {"g": 0.0, "i": 0.0, "p": 0.0, "b": 0.0}, "跨年后新作品属性清零")
	check(run.annual_results.has("1") and run.annual_results["1"].project.title == "完整流程", "年度档案归档上一年作品")
	check(Model.annual_result_for_year(run, 1).awards.is_empty() and int(Model.annual_result_for_year(run, 1).reward) == 0, "未达标作品没有奖项与奖励")
	check(Model.valid_state(run), "跨年等待立项的状态有效")
	var second := Model.select_project(run, "第二年", "rpg", "sci_fi", 2)
	check(second.ok and Model.project_for_year(second.state, 1).title == "完整流程" and Model.project_for_year(second.state).title == "第二年", "两年作品档案独立保留")
	check(Model.valid_state(JSON.parse_string(JSON.stringify(second.state))), "JSON 往返后状态有效")

	## 11. 存档往返与损坏拒绝
	var save_path := "res://qa/test_save.json"
	check(Store.save_run(second.state, save_path) == OK, "状态可以保存")
	var loaded := Store.load_run(save_path)
	check(not loaded.is_empty() and loaded.run_id == second.state.run_id and loaded.work == second.state.work, "读档恢复同一局状态")
	check(Store.save_run(second.state, save_path) == OK, "重复保存会生成备份")
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	file.store_string("broken data")
	file.close()
	check(Store.load_run(save_path).run_id == second.state.run_id, "损坏主存档回退到备份")
	var damaged: Dictionary = second.state.duplicate(true)
	damaged.version = 4
	check(not Model.valid_state(damaged), "旧版本存档被拒绝")
	damaged = second.state.duplicate(true)
	damaged.members[0].id = "unknown"
	check(not Model.valid_state(damaged), "人物身份不匹配被拒绝")
	damaged = second.state.duplicate(true)
	damaged.members[0].role = 0.5
	check(not Model.valid_state(damaged), "小数职责被拒绝")
	damaged = second.state.duplicate(true)
	damaged.members[0].affinity = Model.AFFINITY_MAX + 1
	check(not Model.valid_state(damaged), "超出上限的好感被拒绝")
	damaged = second.state.duplicate(true)
	damaged.work.erase("p")
	check(not Model.valid_state(damaged), "缺少表现力的作品被拒绝")
	damaged = second.state.duplicate(true)
	damaged.erase("annual_results")
	check(not Model.valid_state(damaged), "缺少评奖档案被拒绝")
	damaged = second.state.duplicate(true)
	damaged.members[0].learned_skills = ["unknown"]
	check(not Model.valid_state(damaged), "未知已学技能被拒绝")

	print("MODEL_TESTS: %d checks, %d failures" % [checks, failures])
	Model.DEFINITIONS = original_definitions
	SkillTable.skills = original_skills
	quit(1 if failures > 0 else 0)
