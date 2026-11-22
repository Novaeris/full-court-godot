extends FcLiveTestCase
## The three modes in one running app (Phase 1 integration): menu -> Owner -> menu -> Career -> menu -> Dynasty -> menu -> Continue.
## Each mode keeps its own state (an Owner league, a Career league with its player, a Dynasty profile), going back to the menu never
## loses or mixes them, Continue lists only the saves FcSaveManager owns (Owner and Career; Dynasty profiles live in their own store),
## and a Career save loads back into the Career hub. Everything is written to scratch folders, never to the player's real saves.
## The pure checks (shared definitions, positions, ratings, content references) are in tests/unit/test_ecosystem_integrity.gd.

const PREFS := "user://test_preferences_live_modes.cfg"
const SAVES := "user://test_saves_live_modes"
const DYNASTY := "user://test_dynasty_live_modes"

var app: FcApp


func before_each() -> void:
	super.before_each()
	_wipe()
	app = FcApp.new()
	app.preferences = FcPreferences.new(PREFS)
	app.preferences.tutorial_done = true
	app.saves = FcSaveManager.new(SAVES)
	host.add_child(app)


func after_each() -> void:
	super.after_each()
	_wipe()


func _wipe() -> void:
	DirAccess.remove_absolute(PREFS)
	DirAccess.remove_absolute("user://test_ui_state_live_modes.cfg")
	FcSafeFile.remove_tree(SAVES)
	FcSafeFile.remove_tree(DYNASTY)


func _start() -> void:
	app.setup()
	# the app builds its Dynasty controller on the player's real store; this test uses its own
	app.dynasty = FcDynastyController.new(app.content, app._defs, FcDynastyStore.new(DYNASTY))
	app.dynasty_ui = FcDynastyUi.new(app, app.dynasty)
	await frames(2)


func _screen() -> String:
	return app.navigator.current_id


func test_the_three_modes_keep_their_own_state_across_the_menu() -> void:
	await _start()
	assert_eq(_screen(), "menu", "the app starts on the main menu")
	assert_true(app.controller == null and app.career == null and app.dynasty.profile() == null, "no mode is open yet")

	# --- Owner: a small league, started with a team
	assert_true(app.on_create_league({"teams": 8, "conferences": 2, "divisions": 1, "free_agents": 10, "seed": "7", "name": "Modes Owner"}), "an Owner league is created")
	app.on_start_game(app._pending_state.world.teams.ids()[0])
	await frames(2)
	assert_true(app.controller != null, "the Owner controller exists")
	var owner_state: FcGameState = app.controller.state
	assert_eq(owner_state.mode, FcGameState.MODE_OWNER)
	app.show_main_menu()
	await frames(2)
	assert_eq(_screen(), "menu", "back at the menu")
	assert_true(app.controller != null and app.controller.state == owner_state, "leaving the Owner game to the menu did not replace its state")

	# --- Career: one created player in a 12-team league
	var spec := FcPlayerBuild.default_spec("custom", FcPosition.Id.SG, app._defs)
	spec["first_name"] = "Modes"
	spec["last_name"] = "Tester"
	assert_true(app.on_create_career(spec, 11), "a Career player is created")
	await frames(2)
	assert_eq(_screen(), "career_hub", "the Career hub is showing")
	assert_true(app.career != null, "the Career controller exists")
	var career_state: FcGameState = app.career.state
	assert_eq(career_state.mode, FcGameState.MODE_CAREER)
	assert_true(career_state != owner_state, "Career has its own league, not the Owner one")
	assert_true(app.controller.state == owner_state, "creating a Career did not touch the Owner state")
	var career_player: FcPlayer = career_state.world.players.get_by_id(app.career.profile().player_id)
	assert_true(career_player != null and career_player.identity.last_name == "Tester", "the Career player is an FcPlayer in the Career world")
	app.show_main_menu()
	await frames(2)

	# --- Dynasty: a profile in its own store
	app.show_dynasty_home()
	await frames(2)
	assert_eq(_screen(), "dynasty_entry", "the Dynasty entry screen is showing")
	assert_true(app.dynasty_ui.on_create("Mode Kings", "MDK"), "a Dynasty profile is created")
	await frames(2)
	assert_true(app.dynasty.profile() != null, "the Dynasty profile is open")
	var dynasty_profile: FcDynastyProfile = app.dynasty.profile()
	app.show_main_menu()
	await frames(2)
	assert_eq(_screen(), "menu")
	assert_true(app.controller.state == owner_state and app.career.state == career_state, "the Owner and Career states survived a Dynasty visit")
	assert_true(app.dynasty.profile() == null or app.dynasty.profile() == dynasty_profile, "the Dynasty profile is not replaced by another mode")

	# --- saves: Owner and Career share FcSaveManager; a Dynasty profile never appears there
	assert_true(app.career.save(app.saves).is_ok(), "the Career saves")
	assert_true(app.saves.save("owner_1", app.controller.state, "Modes Owner").is_ok(), "the Owner saves")
	var modes := {}
	for m in app.saves.list_slots():
		modes[m.slot_id] = str(m.mode)
		assert_true(["owner", "career"].has(str(m.mode)), "slot %s is an Owner or Career save (mode %s)" % [m.slot_id, m.mode])
	assert_eq(modes.get("career_1"), "career")
	assert_eq(modes.get("owner_1"), "owner")
	assert_true(not app.dynasty.profiles().is_empty(), "the Dynasty profile is in the Dynasty store, not in the Owner/Career saves")

	# --- loading each save opens the right mode with the same data
	app._load_slot("career_1")
	await frames(2)
	assert_eq(_screen(), "career_hub", "a Career save opens the Career hub")
	assert_true(app.career.state != career_state, "a loaded Career is a fresh object, read from disk")
	assert_eq(app.career.profile().player_id, career_player.id, "the same player came back")
	app.show_main_menu()
	await frames(2)
	app._load_slot("owner_1")
	await frames(2)
	assert_eq(app.controller.state.mode, FcGameState.MODE_OWNER, "an Owner save opens as Owner")
	assert_eq(app.controller.state.user_team_id, owner_state.user_team_id, "with the same team")
	app.show_main_menu()
	await frames(2)
	app.on_continue()
	await frames(2)
	assert_true(_screen() != "menu", "Continue opens the newest save")
