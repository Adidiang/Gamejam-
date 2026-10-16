extends RefCounted
## 每个技能获得独立的阶段快照，不能修改真实状态或其他技能上下文。
const HOOKS := ["PROJECT_BEFORE", "PROJECT_AFTER", "ACTION_BEFORE", "ACTION_AFTER", "DUTY_BEFORE", "DUTY_AFTER", "AWARD_BEFORE", "AWARD_AFTER"]
var state: Dictionary
var plan: Dictionary
var values: Dictionary
var owner_id: String
var hook: String

func _init(snapshot: Dictionary = {}, stage_plan: Dictionary = {}, metadata: Dictionary = {}, owner: String = "", stage: String = "") -> void:
	state = snapshot.duplicate(true)
	plan = stage_plan.duplicate(true)
	values = metadata.duplicate(true)
	owner_id = owner
	hook = stage

func member_index(id: String) -> int:
	for index in state.members.size():
		if state.members[index].id == id:
			return index
	return -1

func targets(target: String) -> Array:
	match target:
		"owner": return [owner_id]
		"actor": return [values.get("actor_id", "")] if not values.get("actor_id", "").is_empty() else []
		"team": return state.members.filter(func(member: Dictionary): return bool(member.get("recruited", false))).map(func(member: Dictionary): return member.id)
	return []

func matches(conditions: Dictionary) -> bool:
	for key in conditions:
		var actual: Variant
		match key:
			"owner_role": actual = state.members[member_index(owner_id)].role
			"actor_is_owner": actual = values.get("actor_id", "") == owner_id
			"owner_slept": actual = owner_id in values.get("sleeping_member_ids", [])
			"year", "month": actual = state[key]
			_: actual = values.get(key)
		if actual != conditions[key]:
			return false
	return true
