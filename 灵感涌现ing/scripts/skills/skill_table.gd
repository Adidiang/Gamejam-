extends RefCounted
const Definition = preload("res://scripts/skills/skill_definition.gd")
const PATH := "res://data/skills.json"
static var skills: Dictionary = load_table(PATH)

static func load_table(path: String) -> Dictionary:
	var parser := JSON.new()
	if not FileAccess.file_exists(path) or parser.parse(FileAccess.get_file_as_string(path)) != OK:
		push_error("技能表读取失败：" + path)
		return {}
	var error := validate(parser.data)
	if not error.is_empty():
		push_error("技能表格式错误：" + error)
		return {}
	var result: Dictionary = {}
	for row in parser.data.skills:
		result[row.id] = Definition.from_row(row)
	return result

static func validate(value: Variant) -> String:
	if not value is Dictionary or not value.has("skills") or not value.skills is Array:
		return "需要 skills 数组。"
	var ids: Array = []
	for row in value.skills:
		var error := Definition.validate(row)
		if not error.is_empty(): return error
		if row.id in ids: return "技能 ID 重复：" + row.id
		ids.append(row.id)
	return ""
