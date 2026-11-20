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
## Reduced motion: animations are instant (fades at most 80 ms). Read by FcMotion; see docs/UI_POLISH_PLAN.md, section 6.
var reduce_motion: bool = false
## "auto", "desktop" or "mobile": which presentation target to use (Settings; auto follows the device and window).
var layout_override: String = "auto"
## Sound (Phase 11): volumes 0 to 100 for the master and each bus, one mute switch, and the phone vibration toggle.
var audio_master: int = 80
var audio_ui: int = 80
var audio_sfx: int = 80
var audio_music: int = 60
var audio_muted: bool = false
var haptics: bool = true
## First-run hints on screens (Phase 12); the dismissed ones are remembered in the UI state file, not here.
var hints_enabled: bool = true
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
		reduce_motion = bool(cfg.get_value("display", "reduce_motion", false))
		layout_override = str(cfg.get_value("display", "layout", "auto"))
		if not layout_override in ["auto", "desktop", "mobile"]:
			layout_override = "auto"
		audio_master = clampi(int(cfg.get_value("audio", "master", 80)), 0, 100)
		audio_ui = clampi(int(cfg.get_value("audio", "ui", 80)), 0, 100)
		audio_sfx = clampi(int(cfg.get_value("audio", "sfx", 80)), 0, 100)
		audio_music = clampi(int(cfg.get_value("audio", "music", 60)), 0, 100)
		audio_muted = bool(cfg.get_value("audio", "muted", false))
		haptics = bool(cfg.get_value("audio", "haptics", true))
		hints_enabled = bool(cfg.get_value("ui", "hints", true))
		content_root = str(cfg.get_value("content", "root", ""))


## Writes the settings. Returns false if the file could not be written (the game goes on regardless).
func save_file() -> bool:
	var cfg := ConfigFile.new()
	cfg.set_value("tutorial", "done", tutorial_done)
	cfg.set_value("display", "text_size", text_size)
	cfg.set_value("display", "reduce_motion", reduce_motion)
	cfg.set_value("display", "layout", layout_override)
	cfg.set_value("audio", "master", audio_master)
	cfg.set_value("audio", "ui", audio_ui)
	cfg.set_value("audio", "sfx", audio_sfx)
	cfg.set_value("audio", "music", audio_music)
	cfg.set_value("audio", "muted", audio_muted)
	cfg.set_value("audio", "haptics", haptics)
	cfg.set_value("ui", "hints", hints_enabled)
	cfg.set_value("content", "root", content_root)
	return cfg.save(path) == OK


func mark_tutorial_done() -> void:
	tutorial_done = true
	save_file()


func reset_tutorial() -> void:
	tutorial_done = false
	save_file()
