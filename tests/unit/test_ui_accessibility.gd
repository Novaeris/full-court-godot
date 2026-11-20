extends FcTestCase
## Phase 12: first-run hints, empty and error states, keyboard and controller reach, and a wider contrast audit. (Hints and contrast are
## pure and fast; the screen sweeps build every Dynasty tab on a fresh profile in both layouts.)

const PREFS := "user://test_preferences_access.cfg"
const DYNASTY := "user://test_dynasty_access"
const STATE := "user://test_ui_state_access.cfg"

var app: FcApp


func after_each() -> void:
	FcMotion.reduced = false
	FcUiTokens.touch_mode = false
	FcUiTheme.build(1)
	if app != null:
		Engine.get_main_loop().root.remove_child(app)
		app.free()
		app = null
	for path in [PREFS, STATE, "user://test_ui_state_access2.cfg"]:
		DirAccess.remove_absolute(path)
	FcSafeFile.remove_tree(DYNASTY)
	FcSafeFile.remove_tree("user://test_saves_access")
	FcDynastyFixture.wipe()


func _app(layout_name: String = "desktop") -> void:
	DirAccess.remove_absolute(PREFS)
	DirAccess.remove_absolute(STATE)
	FcSafeFile.remove_tree(DYNASTY)
	FcDynastyFixture.wipe()
	app = FcApp.new()
	app.preferences = FcPreferences.new(PREFS)
	app.preferences.tutorial_done = true
	app.preferences.layout_override = layout_name
	app.saves = FcSaveManager.new("user://test_saves_access")
	app.ui_state = FcUiState.new(STATE)
	Engine.get_main_loop().root.add_child(app)
	app.setup()
	app.dynasty = FcDynastyController.new(app.content, app._defs, FcDynastyStore.new(DYNASTY))
	app.dynasty.catalog = FcDynastyFixture.catalog()
	app.dynasty_ui = FcDynastyUi.new(app, app.dynasty)
	assert_true(app.dynasty_ui.on_create("Access Kings", "ACC"))
	app.layout.update(Vector2(412, 915) if layout_name == "mobile" else Vector2(1280, 800))


func _walk(node: Node, out: Array = []) -> Array:
	out.append(node)
	for c in node.get_children():
		_walk(c, out)
	return out


func _texts(node: Node) -> String:
	var text := ""
	for n in _walk(node):
		if n is Label:
			text += (n as Label).text + "\n"
		elif n is BaseButton and "text" in n:
			text += str(n.text) + "\n"
	return text


# --- hints -------------------------------------------------------------------------------------------------------------------------------------

func test_every_hint_is_complete() -> void:
	var hints := FcHints.new(FcUiState.new(STATE), FcPreferences.new(PREFS))
	assert_true(hints.ids().size() >= 7, "Dynasty and Career have hints")
	for id in hints.ids():
		var h := hints.get_hint(id)
		assert_true(str(h["title"]) != "" and str(h["text"]).length() > 40 and str(h["mode"]) in ["dynasty", "career"], id)
	for id in ["dynasty_hub", "dynasty_collection", "dynasty_packs", "dynasty_lineup", "dynasty_play", "career_creator", "career_hub"]:
		assert_true(hints.ids().has(id), "%s has a hint" % id)


func test_a_dismissed_hint_stays_dismissed_and_can_be_brought_back() -> void:
	var prefs := FcPreferences.new(PREFS)
	var hints := FcHints.new(FcUiState.new(STATE), prefs)
	var total := hints.pending_count()
	assert_true(hints.is_pending("dynasty_hub"))
	hints.dismiss("dynasty_hub")
	assert_true(not hints.is_pending("dynasty_hub"))
	assert_eq(hints.pending_count(), total - 1)
	var again := FcHints.new(FcUiState.new(STATE), prefs)
	assert_true(not again.is_pending("dynasty_hub"), "remembered in the UI state file")
	again.reset()
	assert_true(again.is_pending("dynasty_hub"), "and back after Show the hints again")


func test_turning_hints_off_hides_them_all() -> void:
	var prefs := FcPreferences.new(PREFS)
	var hints := FcHints.new(FcUiState.new(STATE), prefs)
	prefs.hints_enabled = false
	assert_eq(hints.pending_count(), 0)
	assert_true(hints.card("dynasty_hub") == null)
	assert_true(prefs.save_file())
	assert_true(not FcPreferences.new(PREFS).hints_enabled, "the choice is saved")


func test_an_unknown_hint_is_never_shown() -> void:
	var hints := FcHints.new(FcUiState.new(STATE), FcPreferences.new(PREFS))
	assert_true(not hints.is_pending("nope") and hints.card("nope") == null)
	hints.dismiss("nope")   # harmless


func test_the_dynasty_hub_shows_its_hint_once() -> void:
	_app()
	app.dynasty_ui.show_tab("hub")
	assert_eq(_walk(app._root).filter(func(n: Node) -> bool: return n.name == "Hint").size(), 1, "the hint is on the hub")
	app.hints.dismiss("dynasty_hub")
	app.dynasty_ui.show_tab("hub")
	assert_eq(_walk(app._root).filter(func(n: Node) -> bool: return n.name == "Hint").size(), 0, "and gone once dismissed")
	app.dynasty_ui.show_tab("market")
	assert_eq(_walk(app._root).filter(func(n: Node) -> bool: return n.name == "Hint").size(), 0, "a screen with no hint shows none")


func test_the_hint_card_dismisses_itself_with_got_it() -> void:
	_app()
	app.dynasty_ui.show_tab("packs")
	var card: Control = _walk(app._root).filter(func(n: Node) -> bool: return n.name == "Hint")[0]
	var got_it: Button = _walk(card).filter(func(n: Node) -> bool: return n is Button and (n as Button).text == "Got it")[0]
	got_it.pressed.emit()
	assert_true(not app.hints.is_pending("dynasty_packs"), "dismissed")
	assert_true(card.get_parent() == null, "and removed")


func test_career_screens_have_their_hints_and_settings_can_bring_them_back() -> void:
	_app()
	app.show_career_creator()
	assert_eq(_walk(app._root).filter(func(n: Node) -> bool: return n.name == "Hint").size(), 1, "the creator hint")
	app.hints.dismiss("career_creator")
	app.show_settings()
	var text := _texts(app._root)
	assert_true("Show first-time hints" in text and "Show the hints again" in text, "Settings controls the hints")


# --- empty and error states -------------------------------------------------------------------------------------------------------------------

func test_every_dynasty_tab_on_a_new_profile_says_something() -> void:
	for layout_name in ["desktop", "mobile"]:
		_app(layout_name)
		for entry in FcDynastyUi.TABS:
			app.dynasty_ui.show_tab(str(entry[0]))
			var text := _texts(app._root)
			assert_true(text.length() > 80, "%s (%s) is not blank" % [entry[0], layout_name])
			assert_true(not text.contains("null") and not text.contains("<Object"), "%s shows no raw engine text" % entry[0])


func test_a_new_profile_play_screen_explains_there_are_no_games() -> void:
	_app()
	app.dynasty_ui.show_tab("play")
	assert_true("No games yet" in _texts(app._root))


func test_the_empty_state_kit_covers_empty_error_and_success() -> void:
	for kind in [FcEmptyState.Kind.EMPTY, FcEmptyState.Kind.ERROR, FcEmptyState.Kind.SUCCESS]:
		var state := FcEmptyState.new("Title", "Say what to do next.", kind)
		assert_true(state.title_label.text == "Title" and state.body_label.text != "")
		state.free()


# --- keyboard and controller ------------------------------------------------------------------------------------------------------------------

func test_every_button_and_card_on_the_dynasty_screens_can_take_focus() -> void:
	for layout_name in ["desktop", "mobile"]:
		_app(layout_name)
		for entry in FcDynastyUi.TABS:
			app.dynasty_ui.show_tab(str(entry[0]))
			for n in _walk(app.host):
				if n is BaseButton and n.is_visible_in_tree() == false:
					continue
				if n is Button and not (n as Button).disabled:
					assert_true((n as Button).focus_mode == Control.FOCUS_ALL, "%s: button '%s' can take focus" % [entry[0], (n as Button).text])
				if n is FcCardFace:
					assert_true((n as FcCardFace).focus_mode == Control.FOCUS_ALL, "%s: a card can take focus" % entry[0])


func test_a_dialog_takes_focus_and_the_cancel_key_is_wired() -> void:
	_app()
	var modal := FcModal.new("Title", "Text", FcModal.Kind.CONFIRM, "Yes", "No")
	app.host.modals.open(modal)
	assert_eq(app.host.modals.count(), 1)
	assert_true(app.go_back(), "the back key closes the dialog first")


# --- contrast --------------------------------------------------------------------------------------------------------------------------------------

func test_every_rarity_colour_reads_on_its_own_card_background() -> void:
	for id in FcRarityStyle.STYLES:
		var color := FcRarityStyle.color(id)
		var dark := FcRarityStyle.dark(id)
		assert_true(FcUiContrast.ratio(color, dark) >= 4.5, "%s label on its card (%.1f:1)" % [id, FcUiContrast.ratio(color, dark)])
		assert_true(FcUiContrast.ratio(FcUiTokens.TEXT, dark) >= 7.0, "%s: body text on its card" % id)


func test_mastery_frames_are_visible_against_a_card() -> void:
	for level in range(1, 6):
		var frame := FcRarityStyle.mastery_color(level)
		assert_true(FcUiContrast.ratio(frame, FcUiTokens.SURFACE) >= 3.0, "mastery %d frame is visible (graphics need 3:1)" % level)


func test_the_post_game_and_hint_accents_read_on_their_panels() -> void:
	for color in [FcUiTokens.SUCCESS, FcUiTokens.DANGER, FcUiTokens.INFO]:
		assert_true(FcUiContrast.ratio(color, FcUiTokens.SURFACE_RAISED) >= 4.5, "%s on a raised panel" % str(color))
		assert_true(FcUiContrast.ratio(color, FcUiTokens.BG) >= 4.5, "%s on the background" % str(color))
