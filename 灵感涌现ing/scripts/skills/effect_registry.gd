extends RefCounted
const Numeric = preload("res://scripts/skills/effects/numeric_modifier.gd")
const Temporary = preload("res://scripts/skills/effects/temporary_modifier.gd")
const Sheep = preload("res://scripts/skills/effects/sheep_skill.gd")
const Context = preload("res://scripts/skills/skill_context.gd")
const EFFECTS := {"numeric_modifier": Numeric, "temporary_modifier": Temporary, "sheep_skill": Sheep}

static func validate(trigger: Dictionary) -> String:
	if trigger.effect_id not in EFFECTS:
		return "未注册的 effect_id：" + str(trigger.effect_id)
	var params: Dictionary = trigger.params
	if trigger.effect_id == "sheep_skill":
		return Sheep.validate(trigger.hook, trigger.target, params)
	if trigger.effect_id == "temporary_modifier":
		if not params.has_all(["apply_hook", "duration"]) or params.apply_hook not in ["ACTION_BEFORE", "DUTY_BEFORE"] or params.duration not in ["month", "year"]:
			return "临时修正需要 ACTION_BEFORE/DUTY_BEFORE 和 month/year 持续范围。"
		if trigger.hook in ["AWARD_BEFORE", "AWARD_AFTER"]:
			return "当前不支持在评奖阶段建立临时修正。"
		return Numeric.validate(params.apply_hook, trigger.target, params)
	return Numeric.validate(trigger.hook, trigger.target, params)

static func evaluate(context, trigger: Dictionary):
	var effect = EFFECTS[trigger.effect_id].new()
	if not effect.can_trigger(context, trigger.conditions):
		return null
	return effect.evaluate(context, trigger.target, trigger.params)
