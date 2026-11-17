extends FcTestCase
## The first-time tutorial: its content, when it opens, how it moves and that it is remembered.

const PREFS := "user://test_preferences_tutorial.cfg"
const SAVE_DIR := "user://test_saves_tutorial"

var app: FcApp


func before_each() -> void:
	DirAccess.remove_absolute(PREFS)
	app = FcApp.new()
	app.saves = FcSaveManager.new(SAVE_DIR)
	app.preferences = FcPreferences.new(PREFS)
	Engine.get_main_loop().root.add_child(app)
	app.setup()


func after_each() -> void:
	DirAccess.remove_absolute(PREFS)
	if app != null:
		Engine.get_main_loop().root.remove_child(app)
		app.free()


func _labels_text(node: Node) -> String:
	var text := ""
	if node is Label:
		text += (node as Label).text + "\n"
	for c in node.get_children():
		text += _labels_text(c)
	return text


func _buttons(node: Node, out: Array = []) -> Array:
	if node is Button:
		out.append(node)
	for c in node.get_children():
		_buttons(c, out)
	return out


func _has_button(text: String) -> bool:
	for b in _buttons(app):
		if (b as Button).text == text:
			return true
	return false


func _start(mode_owner: bool = true) -> void:
	assert_true(app.on_create_league({"teams": 8, "conferences": 2, "divisions": 1, "free_agents": 10, "seed": "5", "name": "Tutorial League"}))
	app.on_start_game(app._pending_state.world.teams.ids()[2])


func test_every_step_has_a_title_text_and_a_real_tab() -> void:
	var steps := app.tutorial_steps()
	assert_true(steps.size() >= 8)
	for step in steps:
		assert_true(str(step["title"]) != "" and str(step["text"]).length() > 40, "step %s has real text" % step["title"])
		assert_true(FcApp.TAB_NAMES.has(str(step["tab"])), "tab %s exists" % step["tab"])


func test_a_new_owner_game_opens_the_tutorial_and_it_follows_the_steps() -> void:
	_start()
	assert_true(app.tutorial_open())
	assert_true("Tutorial 1 of" in _labels_text(app) and "Welcome, owner" in _labels_text(app))
	assert_true(_has_button("Next") and _has_button("Skip the tutorial") and not _has_button("Back"))
	app.tutorial_move(1)
	assert_true("Tutorial 2 of" in _labels_text(app) and _has_button("Back"))
	app.tutorial_move(1)
	app.tutorial_move(1)
	assert_eq(app._last_tab, FcApp.TAB_NAMES.find("Finances"), "the Finances step asks for the Finances tab")
	app.tutorial_move(-1)
	assert_true("Tutorial 3 of" in _labels_text(app))


func test_finishing_or_skipping_is_remembered() -> void:
	_start()
	app.close_tutorial()
	assert_true(not app.tutorial_open())
	assert_true(FcPreferences.new(PREFS).tutorial_done, "remembered in the settings file")
	assert_true(not "Tutorial 1 of" in _labels_text(app))
	# the next new game does not open it by itself
	app.show_main_menu()
	_start()
	assert_true(not app.tutorial_open())
	# but the Help button opens it again
	assert_true(_has_button("Help"))
	app.start_tutorial()
	assert_true(app.tutorial_open() and "Tutorial 1 of" in _labels_text(app))


func test_stepping_past_the_last_step_closes_it() -> void:
	_start()
	var count := app.tutorial_steps().size()
	for i in count:
		assert_true(app.tutorial_open(), "still open at step %d" % (i + 1))
		app.tutorial_move(1)
	assert_true(not app.tutorial_open())
	assert_true(app.preferences.tutorial_done)


func test_preferences_survive_and_a_missing_file_is_harmless() -> void:
	var p := FcPreferences.new("user://does_not_exist_prefs.cfg")
	assert_true(not p.tutorial_done)
	var q := FcPreferences.new(PREFS)
	q.mark_tutorial_done()
	assert_true(FcPreferences.new(PREFS).tutorial_done)
	q.reset_tutorial()
	assert_true(not FcPreferences.new(PREFS).tutorial_done)


func test_text_size_is_a_setting_that_changes_the_theme_and_is_remembered() -> void:
	assert_eq(app.preferences.text_size, 1)
	app.apply_text_size(2)
	assert_eq(app.theme.default_font_size, FcUiTheme.SIZES[2])
	assert_eq(FcPreferences.new(PREFS).text_size, 2, "remembered")
	app.apply_text_size(0)
	assert_eq(app.theme.default_font_size, FcUiTheme.SIZES[0])
	app.apply_text_size(99)
	assert_eq(app.preferences.text_size, FcUiTheme.SIZES.size() - 1, "out-of-range choices are clamped")
	assert_true(app.theme.has_stylebox("normal", "Button") and app.theme.has_stylebox("tab_selected", "TabContainer"), "the look is defined by the theme")
