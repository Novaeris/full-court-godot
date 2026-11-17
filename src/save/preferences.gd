class_name FcPreferences
extends RefCounted
## The player's own settings, kept apart from saved games (they belong to the person, not to a playthrough):
## whether the first-time tutorial has been seen. Stored as a small text file (user://preferences.cfg).
## Reading never fails: a missing or damaged file just means the defaults.

const DEFAULT_PATH := "user://preferences.cfg"

var path: String
var tutorial_done: bool = false


func _init(file_path: String = DEFAULT_PATH) -> void:
	path = file_path
	load_file()


func load_file() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) == OK:
		tutorial_done = bool(cfg.get_value("tutorial", "done", false))


## Writes the settings. Returns false if the file could not be written (the game goes on regardless).
func save_file() -> bool:
	var cfg := ConfigFile.new()
	cfg.set_value("tutorial", "done", tutorial_done)
	return cfg.save(path) == OK


func mark_tutorial_done() -> void:
	tutorial_done = true
	save_file()


func reset_tutorial() -> void:
	tutorial_done = false
	save_file()
