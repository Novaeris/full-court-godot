class_name FcPreferences
extends RefCounted
## The player's own settings, kept apart from saved games (they belong to the person, not to a playthrough):
## whether the first-time tutorial has been seen. Stored as a small text file (user://preferences.cfg).
## Reading never fails: a missing or damaged file just means the defaults.

const DEFAULT_PATH := "user://preferences.cfg"

var path: String
var tutorial_done: bool = false
## The text size: 0 small, 1 normal, 2 large (see FcUiTheme).
var text_size: int = 1
## The shared content folder chosen by the player ("" = the default, Documents/FullCourtContent).
var content_root: String = ""


## Where content releases are looked for when no folder has been chosen.
static func default_content_root() -> String:
	return FcContentPaths.default_root()


## Only an absolute folder (or user://) with no ".." parts is accepted as a content folder.
static func is_valid_content_root(path: String) -> bool:
	return FcContentPaths.is_valid_root(path)


## The folder to use: the chosen one if it is valid, otherwise the default (never fails).
func effective_content_root() -> String:
	return FcContentPaths.effective_root(content_root)


func _init(file_path: String = DEFAULT_PATH) -> void:
	path = file_path
	load_file()


func load_file() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) == OK:
		tutorial_done = bool(cfg.get_value("tutorial", "done", false))
		text_size = clampi(int(cfg.get_value("display", "text_size", 1)), 0, 2)
		content_root = str(cfg.get_value("content", "root", ""))


## Writes the settings. Returns false if the file could not be written (the game goes on regardless).
func save_file() -> bool:
	var cfg := ConfigFile.new()
	cfg.set_value("tutorial", "done", tutorial_done)
	cfg.set_value("display", "text_size", text_size)
	cfg.set_value("content", "root", content_root)
	return cfg.save(path) == OK


func mark_tutorial_done() -> void:
	tutorial_done = true
	save_file()


func reset_tutorial() -> void:
	tutorial_done = false
	save_file()
