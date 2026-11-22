extends FcLiveTestCase
## The release screen matrix (docs/RELEASE_READINESS.md): every screen of the game is laid out inside a REAL viewport of each window shape and
## each text size, and FcUiViewportAudit looks for what a player would hit: controls outside the window, sideways overflow, taps that are too
## small, dialogs that do not fit. This is stronger than "the screen builds" (test_release_readiness.gd) and than the minimum-size probe
## (test_ui_layout.gd), and it is still not "a person used it": look, feel and comfort stay manual checks.
##
## What is required where (D-030, D6):
##   - Dynasty screens (desktop AND mobile layouts) must fit and be usable at EVERY window shape and text size.
##   - Owner, Career and the shared menus are desktop screens: they must fit from 800 x 600 up at every text size. On a phone-shaped window
##     they are NOT required to fit (the numbers are printed for information only).
## Known failures that are not fixed yet live in tests/support/screen_matrix_baseline.json. That list only shrinks: a new failure fails the
## test, and so does a listed combination that now passes (remove it from the list, the ratchet tightens).

const BASELINE_PATH := "res://tests/support/screen_matrix_baseline.json"
const PREFS := "user://test_preferences_matrix.cfg"
const DYNASTY := "user://test_dynasty_matrix"
const SAVES := "user://test_saves_matrix"
const UI_STATE := "user://test_ui_state_matrix.cfg"
const SIZES := [Vector2i(360, 800), Vector2i(412, 915), Vector2i(800, 600), Vector2i(1024, 768), Vector2i(1280, 800), Vector2i(1920, 1080), Vector2i(2560, 1080)]
const TEXT_SIZES := [0, 1, 2]
const TEXT_NAMES := ["small", "normal", "large"]
## Desktop-designed screens are required to fit from this window upward.
const DESKTOP_MINIMUM := Vector2i(800, 600)

var app: FcApp
var _screen: SubViewport
## "kind|screen|WxH|text" -> number of problems, collected over the whole run of one test.
var _found := {}
var _first_problem := {}


func after_each() -> void:
	_teardown()
	super.after_each()


func _teardown() -> void:
	if app != null and is_instance_valid(app):
		_screen.remove_child(app)
		app.free()
	app = null
	if _screen != null and is_instance_valid(_screen):
		host.remove_child(_screen)
		_screen.free()
	_screen = null
	for path in [PREFS, UI_STATE]:
		DirAccess.remove_absolute(path)
	for dir in [DYNASTY, SAVES]:
		FcSafeFile.remove_tree(dir)
	FcDynastyFixture.wipe()
	_reset_statics()


## A fresh app inside a viewport of exactly `size`. `touch` is whether the device has a touch screen (a phone does).
func _open(size: Vector2i, text_size: int, touch: bool, dynasty: bool) -> void:
	_teardown()
	_screen = SubViewport.new()
	_screen.size = size
	host.add_child(_screen)
	app = FcApp.new()
	app.preferences = FcPreferences.new(PREFS)
	app.preferences.tutorial_done = true
	app.preferences.hints_enabled = false
	app.preferences.text_size = text_size
	app.saves = FcSaveManager.new(SAVES)
	app.ui_state = FcUiState.new(UI_STATE)
	_screen.add_child(app)
	app.setup()
	app.layout.touch_available = touch
	app.layout.update(Vector2(size))
	if dynasty:
		app.dynasty = FcDynastyController.new(app.content, app._defs, FcDynastyStore.new(DYNASTY))
		app.dynasty.catalog = FcDynastyFixture.catalog()
		app.dynasty_ui = FcDynastyUi.new(app, app.dynasty)
		# A FIXED seed: the default is time-based, so every run played a different first game and some results (an overtime line score) were
		# wider than a phone, which made this test fail one run in about twenty (S1-UI-2). The overtime case has its own regression test
		# (test_live_post_game_line_score.gd); this test must be repeatable.
		app.dynasty.create_profile("Matrix Kings", "MTX", "f58c29", 7)
		app.dynasty_ui.show_tab("hub")
		app.dynasty.auto_fill_lineup()
		app.dynasty.play_quick_game("easy")
	await frames(2)


func _record(kind: String, screen: String, size: Vector2i, text_size: int, touch: bool) -> void:
	await frames(3)
	var problems := FcUiViewportAudit.audit(app, Vector2(size), touch and app.layout.is_mobile())
	var key := "%s|%s|%dx%d|%s" % [kind, screen, size.x, size.y, TEXT_NAMES[text_size]]
	if not problems.is_empty():
		_found[key] = problems.size()
		_first_problem[key] = " | ".join(PackedStringArray(problems.slice(0, 4).map(func(p): return str(p))))


func _is_phone(size: Vector2i) -> bool:
	return size.x < DESKTOP_MINIMUM.x


func _required(kind: String, size: Vector2i) -> bool:
	return kind == "dynasty" or not _is_phone(size)


func _baseline() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(BASELINE_PATH))
	return (parsed as Dictionary).get("known", {}) if parsed is Dictionary else {}


## Fails for every required combination that has problems and is not on the known list, or has more than listed; and for every listed
## combination that no longer has any (so the list can only shrink).
func _judge(label: String, ran: Array) -> void:
	var known := _baseline()
	var informational := 0
	for key in _found:
		var kind: String = str(key).get_slice("|", 0)
		var dims: String = str(key).get_slice("|", 2)
		var size := Vector2i(int(dims.get_slice("x", 0)), int(dims.get_slice("x", 1)))
		if not _required(kind, size):
			informational += 1
			continue
		var allowed := int(known.get(key, 0))
		assert_true(int(_found[key]) <= allowed, "%s: %d problem(s), %d allowed. First: %s" % [key, _found[key], allowed, _first_problem[key]])
	for key in known:
		if ran.has(str(key).get_slice("|", 0)) and not _found.has(key):
			assert_true(false, "%s is on the known-failures list but now passes: remove it from screen_matrix_baseline.json" % key)
	print("MATRIX %s: %d combinations with problems (%d informational on phone-shaped windows, desktop-only screens)" % [label, _found.size(), informational])
	for key in _found:
		print("  %s -> %d: %s" % [key, _found[key], _first_problem[key]])


# --- Dynasty: every screen, both layouts, every window shape and text size --------------------------------------------------------------

func test_every_dynasty_screen_fits_every_window_shape_and_text_size() -> void:
	for text_size in TEXT_SIZES:
		for size in SIZES:
			var touch := _is_phone(size)
			await _open(size, text_size, touch, true)
			for entry in FcDynastyUi.TABS:
				app.dynasty_ui.show_tab(str(entry[0]))
				await _record("dynasty", str(entry[0]), size, text_size, touch)
	_judge("dynasty", ["dynasty"])


func test_dynasty_entry_screen_fits_every_window_shape_and_text_size() -> void:
	for text_size in TEXT_SIZES:
		for size in SIZES:
			var touch := _is_phone(size)
			await _open(size, text_size, touch, false)
			app.dynasty = FcDynastyController.new(app.content, app._defs, FcDynastyStore.new(DYNASTY))
			app.dynasty.catalog = FcDynastyFixture.catalog()
			app.dynasty_ui = FcDynastyUi.new(app, app.dynasty)
			app.dynasty_ui.show_entry()
			await _record("dynasty", "entry", size, text_size, touch)
	_judge("dynasty_entry", ["dynasty"])


# --- Owner Mode: all 13 tabs ----------------------------------------------------------------------------------------------------

func test_every_owner_tab_fits_from_800_by_600_at_every_text_size() -> void:
	for text_size in TEXT_SIZES:
		for size in SIZES:
			await _open(size, text_size, false, false)
			app.on_create_league({"teams": 8, "conferences": 2, "divisions": 1, "free_agents": 10, "seed": "5", "name": "Matrix League"})
			app.on_start_game(app._pending_state.world.teams.ids()[2])
			await frames(2)
			for i in FcApp.TAB_NAMES.size():
				app._tabs.current_tab = i
				await _record("owner", FcApp.TAB_NAMES[i], size, text_size, false)
	_judge("owner", ["owner"])


# --- Career and the shared screens ---------------------------------------------------------------------------------------------

func test_career_and_the_shared_screens_fit_from_800_by_600_at_every_text_size() -> void:
	for text_size in TEXT_SIZES:
		for size in SIZES:
			await _open(size, text_size, false, false)
			var shown := {
				"main_menu": app.show_main_menu, "settings": app.show_settings, "new_league": app.show_new_league,
				"about": app.show_about, "career_home": app.show_career_home}
			for name in shown:
				(shown[name] as Callable).call()
				await _record("shared", name, size, text_size, false)
			app.show_career_creator()
			await frames(2)
			var creator: FcCareerCreator = app._form["career_creator"]
			for step in creator.step_ids():
				creator.show_step(step)
				await _record("shared", "career_creator_%s" % step, size, text_size, false)
	_judge("shared", ["shared"])


# --- dialogs and the focus style --------------------------------------------------------------------------------------------------

func test_a_confirmation_dialog_stays_inside_every_window_shape() -> void:
	var problems: Array[String] = []
	for text_size in TEXT_SIZES:
		for size in SIZES:
			await _open(size, text_size, _is_phone(size), false)
			var modal := app.host.modals.confirm("Return to the main menu?", "Anything you have not saved will be lost. This text is long enough to wrap onto several lines in a narrow window.", func() -> void: pass, true, "Leave")
			await frames(3)
			var rect := modal.panel.get_global_rect()
			var bounds := Rect2(Vector2.ZERO, Vector2(size))
			if not bounds.grow(2.0).encloses(rect):
				problems.append("%dx%d %s: the dialog panel is %s in %s" % [size.x, size.y, TEXT_NAMES[text_size], str(rect), str(bounds)])
			for p in FcUiViewportAudit.audit(modal, Vector2(size), _is_phone(size)):
				problems.append("%dx%d %s: %s" % [size.x, size.y, TEXT_NAMES[text_size], p])
	assert_true(problems.is_empty(), "dialog problems: %s" % str(problems.slice(0, 5)))


func test_the_theme_gives_every_interactive_control_a_visible_focus_style() -> void:
	for text_size in TEXT_SIZES:
		var missing := FcUiViewportAudit.focus_styles_missing(FcUiTheme.build(text_size))
		assert_true(missing.is_empty(), "text size %d: %s" % [text_size, str(missing)])

# --- ultrawide (21:9): the content stays in a centred column ---------------------------------------------------------------------

func test_on_wide_windows_every_control_stays_in_the_centred_content_column() -> void:
	var problems: Array[String] = []
	for size in [Vector2i(1920, 1080), Vector2i(2560, 1080), Vector2i(3440, 1440)]:
		var pad := FcScreenHost.side_padding(float(size.x))
		var column := Rect2(Vector2(pad, -100000), Vector2(size.x - 2 * pad, 200000)).grow_individual(2.0, 0.0, 2.0, 0.0)   # only the sideways position matters here (long screens scroll down)
		assert_true(size.x - 2 * pad <= FcScreenHost.MAX_CONTENT_WIDTH + 1, "%dx%d: the column is at most %d wide" % [size.x, size.y, FcScreenHost.MAX_CONTENT_WIDTH])
		await _open(size, 1, false, true)
		for entry in FcDynastyUi.TABS:
			app.dynasty_ui.show_tab(str(entry[0]))
			await frames(3)
			_collect_outside(app, column, "%dx%d dynasty %s" % [size.x, size.y, entry[0]], problems)
			# cards keep a sensible size: none is wider than a card detail needs
			_collect_wide_cards(app, "%dx%d dynasty %s" % [size.x, size.y, entry[0]], problems)
		var modal := app.host.modals.confirm("Leave?", "A dialog on a very wide window stays centred and compact.", func() -> void: pass)
		await frames(3)
		if modal.panel.size.x > 800.0:
			problems.append("%dx%d: the dialog panel is %d px wide (it should stay compact)" % [size.x, size.y, roundi(modal.panel.size.x)])
		var centre := modal.panel.get_global_rect().get_center().x
		if absf(centre - size.x / 2.0) > 2.0:
			problems.append("%dx%d: the dialog is not centred (centre x %d)" % [size.x, size.y, roundi(centre)])
	assert_true(problems.is_empty(), "ultrawide problems (%d): %s" % [problems.size(), str(problems.slice(0, 6))])


func _collect_outside(node: Node, column: Rect2, label: String, problems: Array[String]) -> void:
	if node is CanvasItem and not (node as CanvasItem).visible:
		return
	if node is FcModal or node is FcToastStack:
		return
	if node is Control and (node is BaseButton or node is LineEdit) and (node as Control).is_visible_in_tree():
		var rect := (node as Control).get_global_rect()
		if rect.size.x > 1.0 and not column.encloses(rect):
			problems.append("%s: %s is outside the content column (%s, column %s)" % [label, node.name, str(rect), str(column)])
	for child in node.get_children():
		_collect_outside(child, column, label, problems)


func _collect_wide_cards(node: Node, label: String, problems: Array[String]) -> void:
	if node is FcCardFace and (node as Control).is_visible_in_tree() and (node as Control).size.x > 420.0:
		problems.append("%s: a card is %d px wide" % [label, roundi((node as Control).size.x)])
	for child in node.get_children():
		_collect_wide_cards(child, label, problems)
