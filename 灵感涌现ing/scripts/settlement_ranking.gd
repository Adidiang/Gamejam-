extends RefCounted
## 制作组成绩是可编辑的本地数据；玩家成绩只取模型计算的三年总分。
const DATA_PATH := "res://data/leaderboard.json"
const STAFF_COUNT := 9

static func load_entries() -> Array:
	var rows: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	var error := validation_error(rows)
	if not error.is_empty():
		push_warning("排行榜配置：" + error)
		return []
	return rows.duplicate(true)

static func validation_error(rows: Variant) -> String:
	if not rows is Array or rows.size() != STAFF_COUNT:
		return "请录入 9 名制作组人员的名字和分数。"
	var names: Array = []
	for row in rows:
		if not row is Dictionary or not row.has_all(["name", "score"]): return "每条记录都需要 name 和 score。"
		if not row.name is String or row.name.strip_edges().is_empty() or row.name != row.name.strip_edges() or "\n" in row.name or "\r" in row.name:
			return "名字不能为空、换行或带首尾空格。"
		if row.name == "你" or row.name in names: return "制作组名字不能重复，也不能使用玩家名“你”。"
		if not (row.score is int or row.score is float) or not is_finite(float(row.score)): return "分数必须是有限数字。"
		names.append(row.name)
	return ""

## 同分并列（1、1、3）；同分行按录入顺序，玩家排在同分制作组记录之后。
static func build(total: float, staff: Array) -> Array:
	var result: Array = []
	if validation_error(staff).is_empty():
		for index in staff.size():
			result.append({"name": staff[index].name, "score": float(staff[index].score), "is_player": false, "order": index})
	result.append({"name": "你", "score": total, "is_player": true, "order": STAFF_COUNT})
	result.sort_custom(func(a: Dictionary, b: Dictionary):
		return a.order < b.order if a.score == b.score else a.score > b.score)
	var rank := 1
	for index in result.size():
		if index > 0 and result[index].score != result[index - 1].score: rank = index + 1
		result[index].rank = rank
	return result
