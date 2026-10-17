extends RefCounted
## 人物表是人物资料的唯一来源；界面与初始状态共用。

const TABLE_PATH := "res://data/characters.json"
const ATTRIBUTE_KEYS := ["programming", "imagination", "art", "music"]
const AFFINITY_MAX := 50
const SKILL_SLOT_COUNT := 3
const SKILL_THRESHOLDS := [0, 20, 50]
const SkillTable = preload("res://scripts/skills/skill_table.gd")
static var table: Dictionary = load_table(TABLE_PATH)

static func load_table(path: String) -> Dictionary:
	var parser := JSON.new()
	if not FileAccess.file_exists(path) or parser.parse(FileAccess.get_file_as_string(path)) != OK:
		push_error("人物表读取失败：%s；%s" % [path, parser.get_error_message()])
		return {}
	var error := validate(parser.data)
	if not error.is_empty():
		push_error("人物表格式错误：" + error)
		return {}
	return parser.data

static func validate(value: Variant) -> String:
	if not value is Dictionary or not value.has_all(["initial_members", "characters"]):
		return "需要 initial_members 和 characters。"
	if not value.initial_members is Array or value.initial_members.is_empty() or not value.characters is Array:
		return "initial_members 必须指定至少一名可用人物，characters 必须为数组。"
	var ids: Array = []
	for row in value.characters:
		if not row is Dictionary or not row.has_all(["id", "name", "attributes", "affinity", "preferred_genre", "preferred_topic", "skills", "other_modifiers", "portrait", "join_text"]):
			return "人物记录缺少必填字段。"
		for key in ["id", "name", "preferred_genre", "preferred_topic", "other_modifiers", "portrait", "join_text"]:
			if not row[key] is String:
				return "字段 %s 必须为文本。" % key
		if row.id.is_empty() or row.id in ids:
			return "人物 id 不可为空或重复。"
		ids.append(row.id)
		if not row.attributes is Dictionary or not row.attributes.has_all(ATTRIBUTE_KEYS):
			return "%s 需要四项能力。" % row.id
		for key in ATTRIBUTE_KEYS:
			if not _number(row.attributes[key]) or row.attributes[key] < 0:
				return "%s 的 %s 必须是非负数。" % [row.id, key]
		if not _number(row.affinity) or row.affinity < 0 or row.affinity > AFFINITY_MAX or row.affinity != int(row.affinity):
			return "%s 的好感度必须为 0 到 %d 的整数。" % [row.id, AFFINITY_MAX]
		if not row.skills is Array or row.skills.size() != SKILL_SLOT_COUNT:
			return "%s 必须有三个技能位。" % row.id
		var skill_ids: Array = []
		for index in SKILL_SLOT_COUNT:
			var skill: Variant = row.skills[index]
			if not skill is Dictionary or not skill.has_all(["skill_id", "unlock_affinity"]):
				return "%s 的技能位缺少字段。" % row.id
			var threshold: int = 0 if row.id == "j" and index == 2 else SKILL_THRESHOLDS[index]
			if not skill.skill_id is String or skill.skill_id not in SkillTable.skills or skill.skill_id in skill_ids or skill.unlock_affinity != threshold:
				return "%s 的三个技能需要有效且不重复的 ID，以及 0/20/50 解锁门槛。" % row.id
			skill_ids.append(skill.skill_id)
		if not row.portrait.is_empty() and not row.portrait.begins_with("res://"):
			return "%s 的立绘路径必须位于 res:// 工程内。" % row.id
	var active: Array = []
	for id in value.initial_members:
		if not id is String or id not in ids or id in active:
			return "initial_members 中的 id 不存在或重复。"
		active.append(id)
	return ""

static func initial_ids() -> Array:
	return table.get("initial_members", []).duplicate()

static func definitions() -> Array:
	var result: Array = []
	for id in initial_ids():
		for row in table.characters:
			if row.id != id:
				continue
			var stats: Array = []
			for key in ATTRIBUTE_KEYS:
				stats.append(float(row.attributes[key]))
			result.append({"id": id, "name": row.name if not row.name.is_empty() else "人物" + id,
				"stats": stats, "affinity": int(row.affinity), "genre": row.preferred_genre,
				"topic": row.preferred_topic, "skills": row.skills.duplicate(true),
				"other_modifiers": row.other_modifiers, "portrait": row.portrait, "join_text": row.join_text})
	return result

static func portrait_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if not ResourceLoader.exists(path):
		push_warning("找不到立绘：" + path)
		return null
	var resource := load(path)
	if not resource is Texture2D:
		push_warning("立绘资源不是 Texture2D：" + path)
		return null
	return resource

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
