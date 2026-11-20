class_name FcStudioSettings
extends RefCounted
## Creator Studio's own small settings file (kept in Studio's own user folder, not the game's):
## which shared content folder to use and who is signing releases.

const DEFAULT_PATH := "user://studio_settings.cfg"

var path: String
var content_root: String = ""
var approver: String = ""


func _init(file_path: String = DEFAULT_PATH) -> void:
	path = file_path
	var cfg := ConfigFile.new()
	if cfg.load(path) == OK:
		content_root = str(cfg.get_value("content", "root", ""))
		approver = str(cfg.get_value("owner", "approver", ""))


## The folder in use: the chosen one if valid, otherwise the same default the game uses.
func effective_root() -> String:
	return FcContentPaths.effective_root(content_root)


func save_file() -> bool:
	var cfg := ConfigFile.new()
	cfg.set_value("content", "root", content_root)
	cfg.set_value("owner", "approver", approver)
	return cfg.save(path) == OK
