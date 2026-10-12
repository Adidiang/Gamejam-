extends RefCounted
## 稳定 ID 用于存档与规则；显示名和排列顺序可以独立调整。
const GENRES := [
	{"id": "act", "name": "ACT"}, {"id": "shooter", "name": "射击"},
	{"id": "rpg", "name": "RPG"}, {"id": "strategy", "name": "策略"},
	{"id": "management", "name": "模拟经营"}, {"id": "narrative", "name": "剧情向"},
]
const TOPICS := [
	{"id": "fantasy", "name": "奇幻"}, {"id": "sci_fi", "name": "科幻"},
	{"id": "modern", "name": "现代"}, {"id": "historical", "name": "历史"},
	{"id": "horror", "name": "惊悚"},
]

static func display_name(options: Array, id: String) -> String:
	for option in options:
		if option.id == id:
			return option.name
	return ""

static func valid_profile(value: Variant, year: int, run_id: String) -> bool:
	if not value is Dictionary or not value.has_all(["id", "year", "title", "genre_id", "topic_id"]):
		return false
	if value.id != "%s:project:%d" % [run_id, year] or value.year != year:
		return false
	if not value.title is String or value.title.strip_edges().is_empty() or value.title != value.title.strip_edges():
		return false
	if "\n" in value.title or "\r" in value.title:
		return false
	return value.genre_id is String and value.topic_id is String and not display_name(GENRES, value.genre_id).is_empty() and not display_name(TOPICS, value.topic_id).is_empty()
