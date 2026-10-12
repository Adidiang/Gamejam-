extends Resource
const Context = preload("res://scripts/skills/skill_context.gd")
const Registry = preload("res://scripts/skills/effect_registry.gd")
const GameCatalog = preload("res://scripts/game_catalog.gd")
@export var id: String
@export var display_name: String
@export var description: String
@export var quip: String
@export var acquisition: String
@export var inspiration_cost: int
@export var triggers: Array

static func validate(row: Variant) -> String:
	if not row is Dictionary or not row.has_all(["id", "name", "description", "quip", "acquisition", "inspiration_cost", "triggers"]):
		return "技能定义缺少必填字段。"
	for key in ["id", "name", "description", "quip", "acquisition"]:
		if not row[key] is String:
			return "技能 %s 必须为文本。" % key
	if row.id.is_empty() or row.acquisition not in ["auto", "inspiration"]:
		return "技能需要唯一 ID，acquisition 必须是 auto 或 inspiration。"
	if not (row.inspiration_cost is int or row.inspiration_cost is float) or not is_finite(float(row.inspiration_cost)) or row.inspiration_cost != int(row.inspiration_cost):
		return "灵感费用必须为整数。"
	if (row.acquisition == "auto" and row.inspiration_cost != 0) or (row.acquisition == "inspiration" and row.inspiration_cost <= 0):
		return "自动技能费用为 0，付费技能费用必须大于 0。"
	if not row.triggers is Array:
		return "triggers 必须为数组。"
	if row.name.is_empty() and not row.triggers.is_empty():
		return "有效果的技能必须填写名称。"
	for trigger in row.triggers:
		if not trigger is Dictionary or not trigger.has_all(["hook", "conditions", "target", "frequency", "effect_id", "params", "priority"]):
			return "触发器缺少必填字段。"
		if trigger.hook not in Context.HOOKS or trigger.target not in ["owner", "actor", "team", "work", "shared", "score"] or trigger.frequency not in ["event", "month", "year", "run"]:
			return "触发点、目标或频次不合法。"
		if not trigger.conditions is Dictionary or not trigger.params is Dictionary:
			return "conditions 和 params 必须是对象。"
		if not (trigger.priority is int or trigger.priority is float) or not is_finite(float(trigger.priority)) or trigger.priority != int(trigger.priority):
			return "priority 必须为整数。"
		for key in trigger.conditions:
			match key:
				"owner_role", "action_id", "month", "year":
					var value: Variant = trigger.conditions[key]
					if not (value is int or value is float) or not is_finite(float(value)) or value != int(value):
						return "条件 %s 必须为整数。" % key
					var limits: Array = {"owner_role": [0, 3], "action_id": [0, 5], "month": [1, 12], "year": [1, 3]}[key]
					if value < limits[0] or value > limits[1]: return "条件 %s 超出允许范围。" % key
				"actor_is_owner", "award_best":
					if not trigger.conditions[key] is bool: return "%s 必须为布尔值。" % key
				"genre", "topic":
					if not trigger.conditions[key] is String: return "类型与题材条件必须为文本。"
				"genre_id", "topic_id":
					var options: Array = GameCatalog.GENRES if key == "genre_id" else GameCatalog.TOPICS
					if not trigger.conditions[key] is String or GameCatalog.display_name(options, trigger.conditions[key]).is_empty():
						return "类型与题材条件必须使用有效的稳定 ID。"
				"action_kind":
					if trigger.conditions[key] not in ["task", "invite"]: return "action_kind 必须是 task 或 invite。"
				_: return "未支持的条件：" + str(key)
		var error := Registry.validate(trigger)
		if not error.is_empty(): return error
	return ""

static func from_row(row: Dictionary):
	var definition = load("res://scripts/skills/skill_definition.gd").new()
	definition.id = row.id
	definition.display_name = row.name
	definition.description = row.description
	definition.quip = row.quip
	definition.acquisition = row.acquisition
	definition.inspiration_cost = int(row.inspiration_cost)
	definition.triggers = row.triggers.duplicate(true)
	return definition
