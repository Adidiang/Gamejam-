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
	if state.skill_runtime.events.has(event_id): return {"plan": plan, "records": []}
	var snapshot := state.duplicate(true)
	var records: Array = []
	var modifiers: Array = []
	var pending_temporary: Array = []
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
		if result == null or (result.modifiers.is_empty() and result.temporary.is_empty()): continue
		modifiers.append_array(result.modifiers)
		for temporary in result.temporary:
			temporary.skill_id = job.skill.id
			temporary.name = job.skill.display_name
			temporary.quip = job.skill.quip
			pending_temporary.append(temporary)
		state.skill_runtime.counts[counter_key] = 1
		records.append({"owner_id": job.owner_id, "skill_id": job.skill.id, "name": job.skill.display_name,
			"quip": job.skill.quip, "hook": hook, "temporary": false, "modifiers": result.modifiers.duplicate(true)})
	state.skill_runtime.temporary.append_array(pending_temporary)
	state.skill_runtime.events[event_id] = true
	_apply_modifiers(plan, modifiers)
	return {"plan": plan, "records": records}

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
		for modifier in record.modifiers:
			if not modifier is Dictionary or not modifier.has_all(["path", "operation", "amount"]): return false
			if not modifier.path is Array or modifier.path.size() < 1 or modifier.path.size() > 3 or not modifier.path.all(func(part): return part is String): return false
			if modifier.operation not in ["add", "percent"] or not (modifier.amount is int or modifier.amount is float) or not is_finite(float(modifier.amount)): return false
	return true
