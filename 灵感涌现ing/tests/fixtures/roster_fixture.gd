extends RefCounted
## 已入社阵容样本供原有岗位、技能和界面回归使用；正式新局的空社团由招募测试覆盖。
const Model = preload("res://scripts/game_model.gd")

static func recruit_all(state: Dictionary) -> void:
	for member in state.members: member.recruited = true

static func fresh() -> Dictionary:
	var state := Model.fresh()
	recruit_all(state)
	return state

static func select_starting_pair(scene: Control) -> void:
	for index in 2:
		scene.starting_roster.open_slot(index)
		scene.starting_roster.choose(str(Model.DEFINITIONS[index].id))
