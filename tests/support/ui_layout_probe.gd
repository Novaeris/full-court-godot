class_name FcUiLayoutProbe
extends RefCounted
## Measures how big a window each screen needs (its combined minimum size) so layout regressions are caught without pixels.
## A screen whose minimum width exceeds the window cannot fit it; the redesign must lower these numbers toward the mobile target
## for Dynasty and keep Owner and Career usable at 800x600 (decision D6). Used by test_ui_layout.gd.
## The numbers include the app margin and the title and message rows.

const SAVE_DIR := "user://test_layout_probe_saves"
const DYNASTY_DIR := "user://test_layout_probe_dynasty"

const SCREENS := ["main_menu", "new_league", "career_home", "career_creator", "dynasty_entry", "dynasty_hub", "dynasty_collection",
	"dynasty_packs", "dynasty_lineup", "owner_overview", "owner_roster"]


## {"screen": {"w": int, "h": int}} for every screen in SCREENS.
static func measure() -> Dictionary:
	var out := {}
	for name in SCREENS:
		out[name] = measure_screen(name)
	return out


static func measure_screen(screen: String) -> Dictionary:
	FcSafeFile.remove_tree(DYNASTY_DIR)
	FcDynastyFixture.wipe()
	var app := FcApp.new()
	app.preferences = FcPreferences.new("user://test_preferences.cfg")
	app.preferences.tutorial_done = true
	app.saves = FcSaveManager.new(SAVE_DIR)
	Engine.get_main_loop().root.add_child(app)
	app.setup()
	app.dynasty = FcDynastyController.new(app.content, app._defs, FcDynastyStore.new(DYNASTY_DIR))
	app.dynasty_ui = FcDynastyUi.new(app, app.dynasty)
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
		"owner_overview", "owner_roster":
			app.on_create_league({"teams": 8, "conferences": 2, "divisions": 1, "free_agents": 10, "seed": "5", "name": "Probe League"})
			app.on_start_game(app._pending_state.world.teams.ids()[2])
			app._tabs.current_tab = FcApp.TAB_NAMES.find("Overview" if screen == "owner_overview" else "Roster")
	# the app is a plain Control (it adds up nothing), so measure the container that holds the screen, plus the 16 px margins
	var size := app._root.get_combined_minimum_size() + Vector2(32, 32)
	Engine.get_main_loop().root.remove_child(app)
	app.free()
	FcSafeFile.remove_tree(SAVE_DIR)
	FcSafeFile.remove_tree(DYNASTY_DIR)
	FcDynastyFixture.wipe()
	return {"w": ceili(size.x), "h": ceili(size.y)}
