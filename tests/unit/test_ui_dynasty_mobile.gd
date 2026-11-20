extends FcTestCase
## Phase 8: the lineup court, wrapping text, touch-sized controls and the mobile layout of the remaining Dynasty screens.
## (The width limit itself is in test_ui_layout.gd; touch events are in tests/live/test_live_dynasty_mobile.gd.)

const PREFS := "user://test_preferences_dyn_mobile.cfg"
const DYNASTY := "user://test_dynasty_mobile"

var app: FcApp


func after_each() -> void:
	FcMotion.reduced = false
	FcUiTokens.touch_mode = false
	FcUiTheme.build(1)
	if app != null:
		Engine.get_main_loop().root.remove_child(app)
		app.free()
		app = null
	for path in [PREFS, "user://test_ui_state_dyn_mobile.cfg"]:
		DirAccess.remove_absolute(path)
	FcSafeFile.remove_tree(DYNASTY)
	FcSafeFile.remove_tree("user://test_saves_dyn_mobile")
	FcDynastyFixture.wipe()


func _mobile_app() -> void:
	DirAccess.remove_absolute(PREFS)
	FcSafeFile.remove_tree(DYNASTY)
	FcDynastyFixture.wipe()
	app = FcApp.new()
	app.preferences = FcPreferences.new(PREFS)
	app.preferences.tutorial_done = true
	app.preferences.layout_override = "mobile"
	app.saves = FcSaveManager.new("user://test_saves_dyn_mobile")
	Engine.get_main_loop().root.add_child(app)
	app.setup()
	app.dynasty = FcDynastyController.new(app.content, app._defs, FcDynastyStore.new(DYNASTY))
	app.dynasty.catalog = FcDynastyFixture.catalog()
	app.dynasty_ui = FcDynastyUi.new(app, app.dynasty)
	assert_true(app.dynasty_ui.on_create("Mobile Kings", "MBK"))
	app.layout.update(Vector2(412, 915))


func _find(node: Node, type: Variant) -> Array:
	var out: Array = []
	if is_instance_of(node, type):
		out.append(node)
	for c in node.get_children():
		out.append_array(_find(c, type))
	return out


func _stub(w: float, h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	return c


# --- the court ---------------------------------------------------------------------------------------------------------------------

func test_the_five_starters_stand_inside_the_court_without_overlapping() -> void:
	for width: float in [300.0, 360.0, 412.0, 560.0, 900.0, 1400.0]:
		var court := FcLineupCourt.new()
		var widgets: Array = []
		for i in 5:
			widgets.append(_stub(84, 135))
		court.set_slots(widgets)
		court.size = Vector2(width, 900)
		court._layout()
		var cw := minf(width, FcLineupCourt.MAX_WIDTH)
		var ox := (width - cw) / 2.0
		for i in 5:
			var r := Rect2(widgets[i].position, widgets[i].size)
			assert_true(r.position.x >= ox - 0.5 and r.end.x <= ox + cw + 0.5, "width %d: starter %d is inside the court" % [width, i])
			assert_true(r.position.y >= -0.5 and r.end.y <= 900.5, "width %d: starter %d is inside vertically" % [width, i])
			for j in range(i + 1, 5):
				assert_true(not r.intersects(Rect2(widgets[j].position, widgets[j].size)), "width %d: starters %d and %d do not overlap" % [width, i, j])
		court.free()


func test_the_court_is_never_wider_than_its_cap_and_grows_taller_on_a_phone() -> void:
	var court := FcLineupCourt.new()
	court.size = Vector2(1500, 900)
	assert_eq(court._court_width(), FcLineupCourt.MAX_WIDTH, "centred and capped on a big screen")
	court.size = Vector2(380, 900)
	assert_eq(court._court_width(), 380.0, "all the width on a phone")
	court.set_slots([])
	court._layout()
	assert_true(court.custom_minimum_size.y >= 580.0, "tall enough for five cards")
	court.free()


func test_set_slots_replaces_the_previous_widgets() -> void:
	var court := FcLineupCourt.new()
	court.set_slots([_stub(50, 50), _stub(50, 50)])
	assert_eq(court.slot_count(), 2)
	court.set_slots([_stub(50, 50)])
	assert_eq(court.slot_count(), 1)
	court.free()


func test_the_lineup_screen_puts_the_starters_on_the_court_and_the_bench_below() -> void:
	_mobile_app()
	app.dynasty_ui.show_tab("lineup")
	var courts := _find(app._root, FcLineupCourt)
	assert_eq(courts.size(), 1)
	assert_eq(courts[0].slot_count(), 5, "the five starters")
	var on_court := _find(courts[0], FcCardFace)
	assert_eq(on_court.size(), 5)
	for card in on_court:
		assert_eq(card.custom_minimum_size, FcCardFace.SIZE_MINI, "mini cards fit the court")
	var all := _find(app._root, FcCardFace)
	assert_eq(all.size(), 13, "starters, bench and reserve: 13 slots")


func test_a_court_card_opens_the_picker_for_its_slot() -> void:
	_mobile_app()
	app.dynasty_ui.show_tab("lineup")
	var court: FcLineupCourt = _find(app._root, FcLineupCourt)[0]
	var before := app.get_child_count()
	(_find(court, FcCardFace)[0] as FcCardFace).on_click.call()
	assert_true(app.get_child_count() > before or app.host.modals.count() > 0, "tapping a starter opens the player picker")


# --- wrapping and touch ---------------------------------------------------------------------------------------------------------------

func test_dynasty_text_wraps_instead_of_widening_the_screen() -> void:
	var label := FcDynastyUi.wl("A long sentence that must wrap when the window is narrow instead of forcing it wider.", 14)
	assert_eq(label.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART)
	assert_eq(label.size_flags_horizontal, Control.SIZE_EXPAND_FILL)
	assert_true(label.get_combined_minimum_size().x <= 140, "its minimum width is small")
	label.free()


func test_notes_no_longer_force_a_width() -> void:
	_mobile_app()
	var note := app.dynasty_ui.note("Some explanation", 900)
	assert_true(note.get_combined_minimum_size().x < 200, "the old width argument is only a hint now")
	note.free()


func test_every_button_on_the_dynasty_screens_is_touch_sized_in_the_mobile_layout() -> void:
	_mobile_app()
	assert_true(FcUiTokens.touch_mode, "the mobile layout turned touch sizing on")
	for tab in ["hub", "lineup", "packs", "market", "play", "challenges", "season"]:
		app.dynasty_ui.show_tab(tab)
		for b in _find(app._root, Button):
			if (b as Button).toggle_mode or not (b as Button).visible:
				continue
			assert_true((b as Button).get_combined_minimum_size().y >= 40, "%s: '%s' is %d px tall" % [tab, (b as Button).text, (b as Button).get_combined_minimum_size().y])


func test_the_mobile_play_screen_shows_games_as_cards_not_a_wide_table() -> void:
	_mobile_app()
	app.dynasty.auto_fill_lineup()
	assert_true(app.dynasty.play_quick_game("easy").ok)
	app.dynasty_ui.show_tab("play")
	assert_eq(_find(app._root, Tree).size(), 0, "no sideways-scrolling tables on a phone")
	assert_true(_find(app._root, FcPanel).size() >= 1, "the recent games are cards")


func test_the_desktop_play_screen_keeps_its_table() -> void:
	_mobile_app()
	app.preferences.layout_override = "desktop"
	app.layout.override = "desktop"
	app.layout.update(Vector2(1280, 800))
	app.dynasty.auto_fill_lineup()
	app.dynasty.play_quick_game("easy")
	app.dynasty_ui.show_tab("play")
	assert_true(_find(app._root, Tree).size() >= 1, "desktop keeps the dense table")


func test_the_hub_stacks_on_a_phone_and_features_a_card() -> void:
	_mobile_app()
	app.dynasty_ui.show_tab("hub")
	assert_true(_find(app._root, HFlowContainer).size() >= 1, "the two columns flow")
	assert_true(_find(app._root, FcCardFace).size() >= 1, "the featured card is there")
	assert_true(app._root.get_combined_minimum_size().x + 32 <= 412)
