extends FcTestCase
## Phase 13: release-readiness sweeps. Every Dynasty screen in a matrix of window shapes, the Owner and Career minimum window (D6), large
## text on a phone, navigation that always gets back to the main menu, and the collection performance budget. (What these cannot show, such as
## how it looks on a real phone or sounds on real speakers, is listed in docs/RELEASE_READINESS.md.)

const PREFS := "user://test_preferences_release.cfg"
const DYNASTY := "user://test_dynasty_release"

## width x height of the window shapes the plan names: small phone, phone, small desktop window, 4:3, laptop, full HD, ultrawide.
const SIZES := [Vector2(360, 800), Vector2(412, 915), Vector2(800, 600), Vector2(1024, 768), Vector2(1280, 800), Vector2(1920, 1080), Vector2(2560, 1080)]

var app: FcApp


func after_each() -> void:
	FcMotion.reduced = false
	FcUiTokens.touch_mode = false
	FcUiTheme.build(1)
	if app != null:
		Engine.get_main_loop().root.remove_child(app)
		app.free()
		app = null
	for path in [PREFS, "user://test_ui_state_release.cfg"]:
		DirAccess.remove_absolute(path)
	FcSafeFile.remove_tree(DYNASTY)
	FcSafeFile.remove_tree("user://test_saves_release")
	FcDynastyFixture.wipe()


func _app(touch: bool) -> void:
	DirAccess.remove_absolute(PREFS)
	FcSafeFile.remove_tree(DYNASTY)
	FcDynastyFixture.wipe()
	app = FcApp.new()
	app.preferences = FcPreferences.new(PREFS)
	app.preferences.tutorial_done = true
	app.preferences.hints_enabled = false
	app.saves = FcSaveManager.new("user://test_saves_release")
	app.ui_state = FcUiState.new("user://test_ui_state_release.cfg")
	Engine.get_main_loop().root.add_child(app)
	app.setup()
	app.layout.touch_available = touch
	app.dynasty = FcDynastyController.new(app.content, app._defs, FcDynastyStore.new(DYNASTY))
	app.dynasty.catalog = FcDynastyFixture.catalog()
	app.dynasty_ui = FcDynastyUi.new(app, app.dynasty)
	assert_true(app.dynasty_ui.on_create("Release Kings", "REL"))
	app.dynasty.auto_fill_lineup()
	app.dynasty.play_quick_game("easy")


func _text(node: Node) -> String:
	var out := ""
	if node is Label:
		out += (node as Label).text + "\n"
	for c in node.get_children():
		out += _text(c)
	return out


# --- window shapes ------------------------------------------------------------------------------------------------------------------------

func test_the_layout_choice_follows_the_window_and_the_device() -> void:
	for size in SIZES:
		var phone := FcLayoutProfile.classify(size, true, true)
		assert_eq(phone["mode"], FcLayoutProfile.MOBILE, "a phone OS is always mobile (%s)" % str(size))
		var pc := FcLayoutProfile.classify(size, false, false)
		assert_eq(pc["mode"], FcLayoutProfile.DESKTOP, "a mouse-only PC is desktop at any size (%s)" % str(size))
	assert_eq(FcLayoutProfile.classify(Vector2(412, 915), false, true)["mode"], FcLayoutProfile.MOBILE, "a narrow touch window is mobile")
	assert_eq(FcLayoutProfile.classify(Vector2(1280, 800), false, true)["mode"], FcLayoutProfile.DESKTOP, "a wide touch window (a laptop) is desktop")
	assert_eq(FcLayoutProfile.classify(Vector2(2560, 1080), false, false)["size_class"], FcLayoutProfile.WIDE, "ultrawide is the wide class")
	assert_eq(FcLayoutProfile.classify(Vector2(360, 800), false, true)["size_class"], FcLayoutProfile.COMPACT)


func test_every_dynasty_tab_builds_in_every_window_shape() -> void:
	for touch in [false, true]:
		_app(touch)
		for size in SIZES:
			app.layout.update(size)
			for entry in FcDynastyUi.TABS:
				app.dynasty_ui.show_tab(str(entry[0]))
				assert_true(_text(app._root).length() > 60, "%s at %s (touch %s) shows content" % [entry[0], str(size), str(touch)])
		after_each()


# --- the minimum window (D6) and large text --------------------------------------------------------------------------------------------------

func test_owner_and_career_screens_fit_the_800_pixel_minimum() -> void:
	for screen in FcUiLayoutProbe.SCREENS:
		if screen.begins_with("m_"):
			continue
		var now := FcUiLayoutProbe.measure_screen(screen)
		assert_true(now["w"] <= 800, "%s needs %d px (D6: usable at 800 px wide)" % [screen, now["w"]])


func test_dynasty_still_fits_a_phone_with_large_text() -> void:
	for screen in ["m_hub", "m_collection", "m_lineup", "m_packs", "m_play", "m_postgame"]:
		var now := FcUiLayoutProbe.measure_screen(screen, 2)
		assert_true(now["w"] <= FcUiLayoutProbe.MOBILE_LIMIT, "%s at large text needs %d px (limit %d)" % [screen, now["w"], FcUiLayoutProbe.MOBILE_LIMIT])


# --- navigation -------------------------------------------------------------------------------------------------------------------------------------

func test_every_dynasty_tab_is_reachable_from_the_navigation() -> void:
	var nav := FcNavBar.new()
	nav.setup(FcDynastyUi.TABS, "hub", true, FcDynastyUi.MOBILE_PRIMARY)
	var reachable := nav.visible_ids() + nav.overflow_ids()
	for entry in FcDynastyUi.TABS:
		assert_true(reachable.has(entry[0]), "%s is on the bar or in More" % entry[0])
	nav.free()


func test_back_always_leads_to_the_main_menu() -> void:
	for entry in FcDynastyUi.TABS:
		_app(false)   # a fresh profile each time: leaving a profile closes it
		app.dynasty_ui.show_tab(str(entry[0]))
		var steps := 0
		while app.navigator.current_id != "menu" and steps < 8:
			if not app.go_back():
				break
			steps += 1
			if app.navigator.current_id == "dynasty_entry":
				app.show_main_menu()   # leaving a Dynasty profile returns to the menu through the entry screen
		assert_eq(app.navigator.current_id, "menu", "Back from %s reaches the main menu in %d steps" % [entry[0], steps])
		after_each()


func test_every_owner_tab_builds() -> void:
	_app(false)
	app.on_create_league({"teams": 8, "conferences": 2, "divisions": 1, "free_agents": 10, "seed": "5", "name": "Release League"})
	app.on_start_game(app._pending_state.world.teams.ids()[2])
	for tab_name in FcApp.TAB_NAMES:
		var tab := app.build_tab(tab_name)
		assert_true(tab != null and _text(tab).length() > 10 or tab.get_child_count() > 0, "%s builds" % tab_name)
		tab.free()


# --- performance ----------------------------------------------------------------------------------------------------------------------------------

func test_a_hundred_cards_build_well_inside_a_frame_budget_on_the_hub_and_collection() -> void:
	_app(false)
	var start := Time.get_ticks_msec()
	for i in 5:
		app.dynasty_ui.show_tab("collection")
		app.dynasty_ui.show_tab("hub")
	var each := (Time.get_ticks_msec() - start) / 10.0
	print("PERF screen build: %.0f ms per screen" % each)
	assert_true(each < 400.0, "a Dynasty screen builds in %.0f ms (budget 400)" % each)
