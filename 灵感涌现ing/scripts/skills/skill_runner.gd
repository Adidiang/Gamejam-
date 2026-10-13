extends RefCounted
const Context = preload("res://scripts/skills/skill_context.gd")
const Table = preload("res://scripts/skills/skill_table.gd")
const Registry = preload("res://scripts/skills/effect_registry.gd")
const Numeric = preload("res://scripts/skills/effects/numeric_modifier.gd")

static func active(state: Dictionary, member_id: int, slot: Dictionary) -> bool:
	var skill = Table.skills.get(slot.skill_id)
	if skill == null or skill.display_name.is_empty() or int(state.members[member_id].affinity) < int(slot.unlock_affinity):
		return false
	return skill.acquisition == "auto" or slot.skill_id in state.members[member_id].learned_skills

static func status(state: Dictionary, member_id: int, slot: Dictionary) -> Dictionary:
	var skill = Table.skills.get(slot.skill_id)
	if skill == null: return {"text": "技能配置缺失", "can_learn": false, "active": false}
	var prefix := "%d 好感度解锁" % int(slot.unlock_affinity)
	if skill.display_name.is_empty(): return {"text": prefix + " · 内容待填写", "can_learn": false, "active": false}
	if int(state.members[member_id].affinity) < int(slot.unlock_affinity):
		return {"text": prefix + " · 未解锁", "can_learn": false, "active": false}
	if active(state, member_id, slot):
		return {"text": prefix + (" · 自动生效" if skill.acquisition == "auto" else " · 已习得"), "can_learn": false, "active": true}
	var can_learn: bool = state.phase in ["setup", "ready"] and int(state.inspiration) >= skill.inspiration_cost
	var reason := "已解锁，待习得" if can_learn else ("已解锁，灵感不足" if int(state.inspiration) < skill.inspiration_cost else "已解锁，当前不可习得")
	return {"text": prefix + " · " + reason, "can_learn": can_learn, "active": false}

static func run(state: Dictionary, definitions: Array, hook: String, metadata: Dictionary, base_plan: Dictionary) -> Dictionary:
	var plan := base_plan.duplicate(true)
	var event_id := "%s:%d:%d:%s" % [state.run_id, int(state.year), 0 if hook.begins_with("PROJECT_") else int(state.month), hook]
	if state.skill_runtime.events.has(event_id): return {"plan": plan, "records": [], "sleeping": [], "task_multiplier": 1.0}
	clear_expired_project_effect(state)
	var snapshot := state.duplicate(true)
	var records: Array = []
	var modifiers: Array = []
	var pending_temporary: Array = []
	var outcomes: Array = []
	var retained: Array = []
	for temporary in state.skill_runtime.temporary:
		if int(temporary.year) != int(state.year) or (temporary.duration == "month" and int(temporary.month) != int(state.month)):
			continue
		retained.append(temporary)
		if temporary.apply_hook != hook: continue
		var context := Context.new(snapshot, base_plan, metadata, temporary.owner_id, hook)
		var effect := Numeric.new()
		var result = effect.evaluate(context, temporary.target, temporary.params)
		modifiers.append_array(result.modifiers)
		records.append({"owner_id": temporary.owner_id, "skill_id": temporary.skill_id, "name": temporary.name,
			"quip": temporary.quip, "hook": hook, "temporary": true, "modifiers": result.modifiers})
	state.skill_runtime.temporary = retained
	var jobs: Array = []
	for member_id in definitions.size():
		for slot in definitions[member_id].skills:
			if not active(snapshot, member_id, slot): continue
			var skill = Table.skills[slot.skill_id]
			for trigger_id in skill.triggers.size():
				var trigger: Dictionary = skill.triggers[trigger_id]
				if trigger.hook == hook:
					jobs.append({"owner_id": definitions[member_id].id, "skill": skill, "trigger": trigger, "index": trigger_id,
					"order": "%s:%s:%04d" % [definitions[member_id].id, skill.id, trigger_id]})
	jobs.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.trigger.priority) < int(b.trigger.priority) if int(a.trigger.priority) != int(b.trigger.priority) else a.order < b.order)
	for job in jobs:
		var trigger: Dictionary = job.trigger
		var bucket := _bucket(state, trigger.frequency, event_id)
		var counter_key := JSON.stringify([job.owner_id, job.skill.id, job.index, bucket])
		if int(state.skill_runtime.counts.get(counter_key, 0)) >= 1: continue
		var context := Context.new(snapshot, base_plan, metadata, job.owner_id, hook)
		var result = Registry.evaluate(context, trigger)
		if result == null or (result.modifiers.is_empty() and result.temporary.is_empty() and result.outcomes.is_empty()): continue
		modifiers.append_array(result.modifiers)
		for outcome in result.outcomes:
			var command: Dictionary = outcome.duplicate(true)
			command.skill_id = job.skill.id
			command.name = job.skill.display_name
			command.quip = job.skill.quip
			outcomes.append(command)
		for temporary in result.temporary:
			temporary.skill_id = job.skill.id
			temporary.name = job.skill.display_name
			temporary.quip = job.skill.quip
			pending_temporary.append(temporary)
		state.skill_runtime.counts[counter_key] = 1
		records.append({"owner_id": job.owner_id, "skill_id": job.skill.id, "name": job.skill.display_name,
			"quip": job.skill.quip, "hook": hook, "temporary": false, "modifiers": result.modifiers.duplicate(true), "outcomes": result.outcomes.duplicate(true)})
	state.skill_runtime.temporary.append_array(pending_temporary)
	state.skill_runtime.events[event_id] = true
	_apply_modifiers(plan, modifiers)
	var sleeping := _apply_outcomes(state, plan, outcomes)
	var task_multiplier := 1.0
	if hook == "ACTION_BEFORE" and metadata.get("action_kind", "") == "task" and sleeping.is_empty():
		var pending: Dictionary = state.skill_runtime.get("next_task_double", {})
		if not pending.is_empty():
			task_multiplier = 2.0
			_multiply_output(plan, task_multiplier)
			records.append({"owner_id": pending.owner_id, "skill_id": pending.skill_id, "name": pending.name,
				"quip": pending.quip, "hook": hook, "temporary": false, "modifiers": [],
				"outcomes": [{"kind": "task_double", "owner_id": pending.owner_id}]})
			state.skill_runtime.erase("next_task_double")
	elif hook == "ACTION_AFTER" and metadata.get("action_kind", "") == "task":
		if metadata.get("actor_id", "") in metadata.get("sleeping_member_ids", []):
			_clear_output(plan)
		else:
			_multiply_output(plan, float(metadata.get("task_multiplier", 1.0)))
	return {"plan": plan, "records": records, "sleeping": sleeping, "task_multiplier": task_multiplier}

static func _apply_outcomes(state: Dictionary, plan: Dictionary, outcomes: Array) -> Array:
	var sleeping: Array = []
	for outcome in outcomes:
		match outcome.kind:
			"sleep":
				if outcome.owner_id not in sleeping: sleeping.append(outcome.owner_id)
				if plan.contributions.has(outcome.owner_id):
					for key in plan.contributions[outcome.owner_id]: plan.contributions[outcome.owner_id][key] = 0.0
				else:
					_clear_output(plan)
			"ability_add":
				for member in state.members:
					if member.id != outcome.member_id: continue
					var growth: Array = member.get("ability_growth", [0.0, 0.0, 0.0, 0.0]).duplicate()
					growth[int(outcome.stat)] = clampf(float(growth[int(outcome.stat)]) + float(outcome.amount), 0.0, 100000.0)
					member.ability_growth = growth
			"arm_task_double":
				if state.skill_runtime.get("next_task_double", {}).is_empty():
					state.skill_runtime.next_task_double = {"owner_id": outcome.owner_id, "skill_id": outcome.skill_id,
						"name": outcome.name, "quip": outcome.quip, "year": int(state.year), "project_id": _project_id(state)}
	return sleeping

static func _clear_output(plan: Dictionary) -> void:
	for key in plan.work: plan.work[key] = 0.0
	plan.inspiration = 0.0

static func _multiply_output(plan: Dictionary, multiplier: float) -> void:
	for key in ["g", "i", "v", "m", "b", "p"]:
		if plan.work.has(key): plan.work[key] *= multiplier
	plan.inspiration *= multiplier

static func _project_id(state: Dictionary) -> String:
	return str(state.get("annual_projects", {}).get(str(int(state.year)), {}).get("id", "%s:project:%d" % [state.run_id, int(state.year)]))

static func clear_expired_project_effect(state: Dictionary) -> void:
	var pending: Dictionary = state.skill_runtime.get("next_task_double", {})
	if not pending.is_empty() and (int(pending.year) != int(state.year) or pending.project_id != _project_id(state)):
		state.skill_runtime.erase("next_task_double")

static func _bucket(state: Dictionary, frequency: String, event_id: String) -> String:
	match frequency:
		"event": return event_id
		"month": return "month:%d:%d" % [int(state.year), int(state.month)]
		"year": return "year:%d" % int(state.year)
	return "run"

static func _apply_modifiers(plan: Dictionary, modifiers: Array) -> void:
	var groups: Dictionary = {}
	for modifier in modifiers:
		var path: Array = modifier.path
		var key := "/".join(path)
		if not groups.has(key): groups[key] = {"path": path, "add": 0.0, "percent": 0.0}
		groups[key][modifier.operation] += float(modifier.amount)
	for group in groups.values():
		var parent: Dictionary = plan
		for index in range(group.path.size() - 1): parent = parent[group.path[index]]
		var field: String = group.path[-1]
		parent[field] = (float(parent[field]) + float(group.add)) * maxf(0.0, 1.0 + float(group.percent))

static func valid_runtime(value: Variant, members: Array, max_year: int = 3) -> bool:
	if not value is Dictionary or not value.has_all(["events", "counts", "temporary"]): return false
	if not value.events is Dictionary or not value.counts is Dictionary or not value.temporary is Array: return false
	if value.events.size() > 1024 or value.counts.size() > 4096 or value.temporary.size() > 512: return false
	for key in value.events:
		if not key is String or value.events[key] != true: return false
	for key in value.counts:
		if not key is String or value.counts[key] != 1: return false
	var ids: Array = members.map(func(member: Dictionary): return member.id)
	if value.has("next_task_double"):
		var pending: Variant = value.next_task_double
		if not pending is Dictionary or not pending.has_all(["owner_id", "skill_id", "name", "quip", "year", "project_id"]): return false
		if pending.owner_id not in ids or pending.skill_id not in Table.skills or not pending.name is String or not pending.quip is String or not pending.project_id is String or pending.project_id.is_empty(): return false
		if not (pending.year is int or pending.year is float) or not is_finite(float(pending.year)) or pending.year != int(pending.year) or pending.year < 1 or pending.year > max_year: return false
	for entry in value.temporary:
		if not entry is Dictionary or not entry.has_all(["owner_id", "skill_id", "name", "quip", "target", "apply_hook", "params", "year", "month", "duration"]): return false
		if entry.owner_id not in ids or entry.skill_id not in Table.skills: return false
		if not entry.name is String or not entry.quip is String or entry.duration not in ["month", "year"] or entry.apply_hook not in ["ACTION_BEFORE", "DUTY_BEFORE"]: return false
		if not entry.params is Dictionary or not entry.target is String: return false
		if not Numeric.validate(entry.apply_hook, entry.target, entry.params).is_empty(): return false
		for key in ["year", "month"]:
			if not (entry[key] is float or entry[key] is int) or not is_finite(float(entry[key])) or entry[key] != int(entry[key]): return false
		if entry.year < 1 or entry.year > max_year or entry.month < 1 or entry.month > 12: return false
	return true

static func valid_records(value: Variant, members: Array) -> bool:
	if not value is Array or value.size() > 512: return false
	var ids: Array = members.map(func(member: Dictionary): return member.id)
	for record in value:
		if not record is Dictionary or not record.has_all(["owner_id", "skill_id", "name", "quip", "hook", "temporary", "modifiers"]): return false
		if record.owner_id not in ids or record.skill_id not in Table.skills or record.hook not in Context.HOOKS: return false
		if not record.name is String or not record.quip is String or not record.temporary is bool or not record.modifiers is Array: return false
		if not _valid_outcomes(record.get("outcomes", []), ids): return false
		for modifier in record.modifiers:
			if not modifier is Dictionary or not modifier.has_all(["path", "operation", "amount"]): return false
			if not modifier.path is Array or modifier.path.size() < 1 or modifier.path.size() > 3 or not modifier.path.all(func(part): return part is String): return false
			if modifier.operation not in ["add", "percent"] or not (modifier.amount is int or modifier.amount is float) or not is_finite(float(modifier.amount)): return false
	return true

static func _valid_outcomes(value: Variant, ids: Array) -> bool:
	if not value is Array or value.size() > 64: return false
	for outcome in value:
		if not outcome is Dictionary or not outcome.get("kind") is String: return false
		match outcome.kind:
			"sleep", "arm_task_double", "task_double":
				if outcome.get("owner_id") not in ids: return false
			"ability_add":
				if outcome.get("member_id") not in ids or not outcome.has_all(["stat", "amount"]): return false
				if not (outcome.stat is int or outcome.stat is float) or not is_finite(float(outcome.stat)) or outcome.stat != int(outcome.stat) or outcome.stat < 0 or outcome.stat > 3: return false
				if not (outcome.amount is int or outcome.amount is float) or not is_finite(float(outcome.amount)) or outcome.amount < 0 or outcome.amount > 100000: return false
			_: return false
	return true
