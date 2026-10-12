extends "res://scripts/skills/effects/numeric_modifier.gd"
const Context = preload("res://scripts/skills/skill_context.gd")

func evaluate(context, target: String, params: Dictionary):
	var result := Result.new()
	result.temporary.append({"owner_id": context.owner_id, "target": target,
		"apply_hook": params.apply_hook, "params": {"field": params.field, "operation": params.operation, "amount": params.amount},
		"year": context.state.year, "month": context.state.month, "duration": params.duration})
	return result
