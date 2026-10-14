extends RefCounted
## 调试工具：把「改当前作品属性 / 在本年内跳到更晚的月份 / 全员满好感」集中成可测试的纯数据操作。
## 界面只发出请求，判断与修改都在这里；每条入口都先过 enabled()，
## 所以即使有人绕过界面直接调用，正式版也不会真的改到状态。
## 调试只替换当前状态快照，不改游戏规则：结算公式、好感上限与技能费用仍然只有一处定义。

const Config = preload("res://scripts/debug/debug_config.gd")
const Model = preload("res://scripts/game_model.gd")
const CharacterTable = preload("res://scripts/character_table.gd")

## 当前作品的四项属性，键与 ClubGame.work 一致。
const WORK_KEYS := ["g", "i", "p", "b"]
const WORK_NAMES := {"g": "游戏性", "i": "创新性", "p": "表现力", "b": "Bug"}
## 与 ClubGame 的写入上限、valid_state 的取值范围保持一致。
const WORK_MAXIMUM := 100000.0
## 作品属性的两种修改方式：叠加与直接替换。
const MODES := ["add", "set"]
const MONTHS_IN_YEAR := 12
const AFFINITY_MAXIMUM := CharacterTable.AFFINITY_MAX
const DISABLED_MESSAGE := "调试功能已关闭（scripts/debug/debug_config.gd）。"

static func enabled() -> bool:
	## 正式版不生效：总开关关掉、或导出成 Release 模板都算不可用。
	if not Config.ENABLED:
		return false
	return Config.ALLOW_IN_RELEASE or OS.is_debug_build()

## 面板显示用的当前作品四项属性。
static func work_values(state: Dictionary) -> Dictionary:
	var work: Dictionary = state.get("work", {})
	var values: Dictionary = {}
	for key in WORK_KEYS:
		values[key] = float(work.get(key, 0.0))
	return values

## mode 为 add 时在当前值上叠加，为 set 时直接替换；结果限制在 0～WORK_MAXIMUM。
static func change_work(state: Dictionary, key: String, mode: String, amount: float) -> Dictionary:
	if not enabled():
		return _reject(DISABLED_MESSAGE)
	if key not in WORK_KEYS:
		return _reject("未知的作品属性。")
	if mode not in MODES:
		return _reject("未知的修改方式。")
	if not is_finite(amount):
		return _reject("请输入一个有效的数字。")
	if Model.needs_project_selection(state):
		return _reject("本年还没有立项，作品属性只在立项后生效。")
	var current := float(state.work.get(key, 0.0))
	var target := clampf(current + amount if mode == "add" else amount, 0.0, WORK_MAXIMUM)
	if is_equal_approx(target, current):
		return {"ok": true, "state": state, "message": "%s 保持 %s。" % [WORK_NAMES[key], _number_text(current)]}
	var next := state.duplicate(true)
	next.work[key] = target
	return {"ok": true, "state": next,
		"message": "%s：%s → %s。" % [WORK_NAMES[key], _number_text(current), _number_text(target)]}

## 时间只允许在本年内向更晚的月份跳转：跨年与回退都被直接拒绝。
## 跳转是搭建测试条件，不是模拟游玩：只改月份与行动步数，
## 不补算跳过的月份产出、灵感或奖励，年度任务的已用次数也保留。
static func jump_month(state: Dictionary, target_month: int) -> Dictionary:
	if not enabled():
		return _reject(DISABLED_MESSAGE)
	if Model.needs_project_selection(state):
		return _reject("本年还没有立项，无法跳转月份。")
	if target_month < 1 or target_month > MONTHS_IN_YEAR:
		return _reject("月份只能是 1 到 %d 的整数。" % MONTHS_IN_YEAR)
	var current := int(state.month)
	if target_month <= current:
		return _reject("只能跳到本年更晚的月份（回退与跨年已被禁止），当前是第 %d 月。" % current)
	var next := state.duplicate(true)
	next.month = target_month
	next.action_steps = 1
	return {"ok": true, "state": next,
		"message": "时间跳到第 %d 年 %d 月（未结算中间月份）。" % [int(next.year), target_month]}

## 全员满好感：临时把所有人的好感写成上限，并记录开启前的值；关闭时按记录原样恢复。
## 好感上限与技能解锁门槛都由现有规则决定，这里不改习得费用、也不免费习得技能。
## backup 由调用方保存（通常是主界面），重复开启与没有记录时关闭都会被拒绝。
static func set_full_affinity(state: Dictionary, on: bool, backup: Array) -> Dictionary:
	if not enabled():
		return {"ok": false, "state": state, "backup": backup, "message": DISABLED_MESSAGE}
	if on and not backup.is_empty():
		return {"ok": false, "state": state, "backup": backup, "message": "已经处于全员满好感模式。"}
	if not on and backup.is_empty():
		return {"ok": false, "state": state, "backup": [], "message": "当前没有开启全员满好感，无需恢复。"}
	var next := state.duplicate(true)
	var restored: Array = []
	for index in next.members.size():
		if on:
			restored.append(int(next.members[index].affinity))
			next.members[index].affinity = AFFINITY_MAXIMUM
		else:
			var original: int = int(backup[index]) if index < backup.size() else int(next.members[index].affinity)
			next.members[index].affinity = clampi(original, 0, AFFINITY_MAXIMUM)
	var message := "已开启全员满好感（上限 %d）。" % AFFINITY_MAXIMUM
	if not on:
		message = "已关闭全员满好感，好感按开启前记录的值恢复。"
	return {"ok": true, "state": next, "backup": restored, "message": message}

static func _reject(message: String) -> Dictionary:
	return {"ok": false, "message": message}

static func _number_text(value: float) -> String:
	return String.num(value, 1)
