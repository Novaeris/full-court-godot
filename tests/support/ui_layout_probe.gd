class_name FcUiLayoutProbe
extends RefCounted
## Measures how big a window each screen needs (its combined minimum size) so layout regressions are caught without pixels.
## A screen whose minimum width exceeds the window cannot fit it; the redesign must lower these numbers toward the mobile target
## for Dynasty and keep Owner and Career usable at 800x600 (decision D6). Used by test_ui_layout.gd.
## The numbers include the app margin and the title and message rows.

## The probe keeps its own preferences file: it sets the phone layout, which must not leak into other tests.
const PREFS_PATH := "user://test_preferences_layout_probe.cfg"
const SAVE_DIR := "user://test_layout_probe_saves"
const DYNASTY_DIR := "user://test_layout_probe_dynasty"

const SCREENS := ["main_menu", "new_league", "career_home", "career_creator", "dynasty_entry", "dynasty_hub", "dynasty_collection",
	"dynasty_packs", "dynasty_lineup", "owner_overview", "owner_standings", "owner_schedule", "owner_roster", "owner_finances", "owner_staff",
	"owner_draft", "owner_market", "owner_trades", "owner_meeting", "owner_history", "owner_news", "owner_league",
	"m_entry", "m_hub", "m_collection", "m_lineup", "m_packs", "m_market", "m_play", "m_challenges", "m_tournament", "m_season", "m_postgame"]
## The Dynasty screens in the MOBILE layout (names start with m_): they must fit a 412 px phone (the margins are included in the numbers).
const MOBILE_LIMIT := 412


## {"screen": {"w": int, "h": int}} for every screen in SCREENS.
static func measure() -> Dictionary:
	var out := {}
	for name in SCREENS:
		out[name] = measure_screen(name)
	return out


static func measure_screen(screen: String, text_size: int = 1) -> Dictionary:
	FcSafeFile.remove_tree(DYNASTY_DIR)
	FcDynastyFixture.wipe()
	var app := FcApp.new()
	app.preferences = FcPreferences.new(PREFS_PATH)
	app.preferences.tutorial_done = true
	app.preferences.text_size = text_size
	app.preferences.hints_enabled = false   # a first-run hint is temporary: the ratchet measures the screen itself
	app.preferences.layout_override = "mobile" if screen.begins_with("m_") else "auto"
	app.saves = FcSaveManager.new(SAVE_DIR)
	Engine.get_main_loop().root.add_child(app)
	app.setup()
	app.dynasty = FcDynastyController.new(app.content, app._defs, FcDynastyStore.new(DYNASTY_DIR))
	app.dynasty_ui = FcDynastyUi.new(app, app.dynasty)
	if screen.begins_with("m_"):
		app.dynasty.catalog = FcDynastyFixture.catalog()
		if screen == "m_entry":
			app.dynasty_ui.show_entry()
		else:
			app.dynasty_ui.on_create("Probe Kings", "PRB")
			if screen == "m_tournament":
				app.dynasty.enter_tournament("test_cup")
			if screen == "m_postgame":
				app.dynasty.auto_fill_lineup()   # a finished game on the Play screen shows the post-game view
				app.dynasty.play_quick_game("easy")
			app.dynasty_ui.show_tab("play" if screen == "m_postgame" else screen.trim_prefix("m_"))
		var phone := app._root.get_combined_minimum_size() + Vector2(32, 32)
		Engine.get_main_loop().root.remove_child(app)
		app.free()
		FcSafeFile.remove_tree(SAVE_DIR)
		FcSafeFile.remove_tree(DYNASTY_DIR)
		FcDynastyFixture.wipe()
		DirAccess.remove_absolute(PREFS_PATH)
		FcUiTokens.touch_mode = false
		FcUiTheme.build(1)
		return {"w": ceili(phone.x), "h": ceili(phone.y)}
	match screen:
		"main_menu":
			app.show_main_menu()
		"new_league":
			app.show_new_league()
		"career_home":
			app.show_career_home()
		"career_creator":
			app.show_career_creator()
		"dynasty_entry", "dynasty_hub", "dynasty_collection", "dynasty_packs", "dynasty_lineup":
			app.dynasty.catalog = FcDynastyFixture.catalog()
			if screen == "dynasty_entry":
				app.dynasty_ui.show_entry()
			else:
				app.dynasty_ui.on_create("Probe Kings", "PRB")
				app.dynasty_ui.show_tab(screen.trim_prefix("dynasty_"))
		_:
			if screen.begins_with("owner_"):
				app.on_create_league({"teams": 8, "conferences": 2, "divisions": 1, "free_agents": 10, "seed": "5", "name": "Probe League"})
				app.on_start_game(app._pending_state.world.teams.ids()[2])
				app._tabs.current_tab = FcApp.TAB_NAMES.find(screen.trim_prefix("owner_").capitalize())
	# the app is a plain Control (it adds up nothing), so measure the container that holds the screen, plus the 16 px margins
	var size := app._root.get_combined_minimum_size() + Vector2(32, 32)
	Engine.get_main_loop().root.remove_child(app)
	app.free()
	FcSafeFile.remove_tree(SAVE_DIR)
	FcSafeFile.remove_tree(DYNASTY_DIR)
	FcDynastyFixture.wipe()
	return {"w": ceili(size.x), "h": ceili(size.y)}
