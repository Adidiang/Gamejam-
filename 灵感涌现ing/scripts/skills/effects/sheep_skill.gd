extends RefCounted
## 绵羊技能只返回结果，执行器负责取消产出、提交局内成长和作品标记。
const Result = preload("res://scripts/skills/skill_result.gd")

static func validate(hook: String, target: String, params: Dictionary) -> String:
	if not params.get("mode") is String:
		return "绵羊技能需要 mode。"
	match params.mode:
		"sleep":
			if target != "owner" or hook not in ["ACTION_BEFORE", "DUTY_BEFORE"]:
				return "睡着只能在行动或职责结算前作用于自己。"
			var chance: Variant = params.get("probability")
			if not (chance is int or chance is float) or not is_finite(float(chance)) or float(chance) < 0 or float(chance) > 1:
				return "睡着概率必须为0到1之间的有限数值。"
		"growth":
			if target != "team" or hook not in ["ACTION_AFTER", "DUTY_AFTER"]:
				return "梦境成长只能在行动或职责结算后作用于社团。"
			for key in ["owner_gain", "others_gain"]:
				var amount: Variant = params.get(key)
				if not (amount is int or amount is float) or not is_finite(float(amount)) or float(amount) < 0 or float(amount) > 100000:
					return "脑洞成长必须为有限非负数。"
		"dreamer":
			if target != "work" or hook not in ["ACTION_AFTER", "DUTY_AFTER"]:
				return "梦想家只能在行动或职责结算后建立作品标记。"
		_:
			return "未知的绵羊技能模式。"
	return ""

func can_trigger(context, conditions: Dictionary) -> bool:
	return context.matches(conditions)

func evaluate(context, _target: String, params: Dictionary):
	var result := Result.new()
	match params.mode:
		"sleep":
			# 邀约和其他人的任务都不触发；月末只取消技能所属人的贡献。
			if context.hook == "ACTION_BEFORE" and (context.values.get("action_kind", "") != "task" or context.values.get("actor_id", "") != context.owner_id):
				return result
			var chance := float(params.probability)
			var rng := RandomNumberGenerator.new()
			rng.seed = ("%s:%d:%d:%s:%s" % [context.state.run_id, int(context.state.year), int(context.state.month), context.hook, context.owner_id]).hash()
			if chance >= 1.0 or (chance > 0.0 and rng.randf() < chance):
				result.outcomes.append({"kind": "sleep", "owner_id": context.owner_id})
		"growth":
			if context.owner_id not in context.values.get("sleeping_member_ids", []):
				return result
			for member in context.state.members:
				result.outcomes.append({"kind": "ability_add", "member_id": member.id, "stat": 1,
					"amount": float(params.owner_gain if member.id == context.owner_id else params.others_gain)})
		"dreamer":
			if context.owner_id not in context.values.get("sleeping_member_ids", []) or not context.state.skill_runtime.get("next_task_double", {}).is_empty():
				return result
			result.outcomes.append({"kind": "arm_task_double", "owner_id": context.owner_id})
	return result
