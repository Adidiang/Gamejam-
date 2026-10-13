extends RefCounted
## 公式与基础界面测试使用无效果样本，避免正式概率技能造成随机失败。
## 正式绵羊技能由 test_sheep_skills.gd 单独验证，不改写生产资料。
const Table = preload("res://scripts/skills/skill_table.gd")

static func without_effects() -> Dictionary:
	var original: Dictionary = Table.skills
	Table.skills = original.duplicate()
	for skill_id in original:
		Table.skills[skill_id] = original[skill_id].duplicate(true)
		Table.skills[skill_id].triggers = []
	return original

static func restore(original: Dictionary) -> void:
	Table.skills = original
