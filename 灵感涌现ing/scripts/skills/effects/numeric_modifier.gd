extends RefCounted
const Result = preload("res://scripts/skills/skill_result.gd")

static func validate(hook: String, target: String, params: Dictionary) -> String:
	if not params.has_all(["field", "operation", "amount"]):
		return "数值效果需要 field、operation、amount。"
	if not params.field is String or params.operation not in ["add", "percent"]:
		return "数值运算只支持 add 或 percent。"
	if not (params.amount is int or params.amount is float) or not is_finite(float(params.amount)):
		return "amount 必须是有限数值。"
	if params.operation == "percent" and float(params.amount) < -1:
		return "百分比修正不能低于 -100%。"
	if hook == "AWARD_BEFORE":
		return "" if target == "score" and params.field in ["g", "i", "p", "bonus"] else "评奖前仅能修正评分分项或 bonus。"
	if hook == "AWARD_AFTER":
		return "" if (target == "shared" and params.field == "inspiration") or (target in ["owner", "actor", "team"] and params.field == "affinity") else "评奖后只能修正奖励或好感。"
	if target == "shared" and params.field == "inspiration":
		return ""
	if target == "work" and params.field in ["g", "i", "v", "m", "b"]:
		return ""
	if target in ["owner", "actor", "team"]:
		if params.field == "affinity":
			return ""
		if hook == "DUTY_BEFORE" and params.field in ["g", "i", "v", "m", "b", "repair"]:
			return ""
	return "该阶段、目标与字段组合不可用。"

func can_trigger(context, conditions: Dictionary) -> bool:
	return context.matches(conditions)

func evaluate(context, target: String, params: Dictionary):
	var result := Result.new()
	var field: String = params.field
	var operation: String = params.operation
	var amount := float(params.amount)
	match target:
		"shared": result.add([field], operation, amount)
		"work", "score": result.add([target, field], operation, amount)
		_:
			for id in context.targets(target):
				if field == "affinity":
					result.add(["affinity", id], operation, amount)
				elif context.plan.contributions.has(id):
					result.add(["contributions", id, field], operation, amount)
	return result
