extends RefCounted
## Keep prototype saves beside the project, so this local build remains self-contained.
const Model = preload("res://scripts/game_model.gd")
const SAVE_DIR := "res://saves"
const SAVE_PATH := SAVE_DIR + "/club.json"

static func save_run(state: Dictionary, path: String = SAVE_PATH) -> Error:
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	if error != OK:
		return error
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(state, "\t"))
	file.flush()
	file.close()
	if FileAccess.file_exists(path):
		error = DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(path + ".bak"))
		if error != OK:
			return error
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(path + ".tmp"), ProjectSettings.globalize_path(path))

static func load_run(save_path: String = SAVE_PATH) -> Dictionary:
	for path in [save_path, save_path + ".bak"]:
		if FileAccess.file_exists(path):
			var parser := JSON.new()
			if parser.parse(FileAccess.get_file_as_string(path)) != OK:
				continue
			var parsed: Variant = parser.data
			if Model.valid_state(parsed):
				return parsed
	return {}
