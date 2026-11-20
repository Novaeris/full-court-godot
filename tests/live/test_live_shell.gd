extends FcLiveTestCase
## The shell in a real scene tree: the Escape key, screen transitions, toasts from messages, the loading overlay, and the layout
## switching between desktop and mobile while a screen is open.

const SAVE_DIR := "user://test_saves_live_shell"
const DYNASTY_DIR := "user://test_dynasty_live_shell"
const PREFS := "user://test_prefs_live_shell.cfg"

var app: FcApp


func before_each() -> void:
	super.before_each()
	DirAccess.remove_absolute(PREFS)
	app = FcApp.new()
	app.preferences = FcPreferences.new(PREFS)
	app.preferences.tutorial_done = true
	app.saves = FcSaveManager.new(SAVE_DIR)
	host.size = Vector2(1280, 800)   # the host stands in for the window; the app fills it
	host.add_child(app)


func after_each() -> void:
	super.after_each()
	FcSafeFile.remove_tree(SAVE_DIR)
	FcSafeFile.remove_tree(DYNASTY_DIR)
	FcDynastyFixture.wipe()
	DirAccess.remove_absolute(PREFS)


func _press_escape() -> void:
	var esc := InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	Input.parse_input_event(esc)


func test_escape_goes_back_one_screen() -> void:
	await frames(2)
	app.show_career_creator()
	await frames(2)
	_press_escape()
	await frames(2)
	assert_eq(app.navigator.current_id, "career_home", "Escape on the creator returns to the Career home")
	_press_escape()
	await frames(2)
	assert_eq(app.navigator.current_id, "menu", "and again to the main menu")
	_press_escape()
	await frames(2)
	assert_eq(app.navigator.current_id, "menu", "the main menu stays (the game does not quit on Escape)")


func test_escape_closes_a_dialog_first() -> void:
	await frames(2)
	app.show_career_home()
	await frames(2)
	app.host.modals.notice("Hello", "A dialog")
	await frames(2)
	_press_escape()
	await frames(2)
	assert_eq(app.host.modals.count(), 0, "the dialog closed")
	assert_eq(app.navigator.current_id, "career_home", "without leaving the screen")


func test_a_new_screen_fades_in_but_a_rebuild_of_the_same_screen_does_not() -> void:
	await frames(2)
	app.show_career_home()
	assert_true(app._root.modulate.a < 1.0, "a different screen starts to fade in")
	await seconds(0.4)
	assert_eq(app._root.modulate.a, 1.0, "and is fully visible after the fade")
	app.show_career_home()
	assert_eq(app._root.modulate.a, 1.0, "the same screen rebuilt after an action does not flash")


func test_reduced_motion_shows_screens_without_a_slow_fade() -> void:
	await frames(2)
	app.preferences.reduce_motion = true
	FcMotion.reduced = true
	app.show_career_home()
	await seconds(0.2)
	assert_eq(app._root.modulate.a, 1.0, "within the 80 ms cap")


func test_a_message_appears_as_a_toast() -> void:
	await frames(2)
	app._say("Saved.")
	assert_eq(app.host.toasts.visible_count(), 1, "one toast")
	app._say("Cannot create this league")
	assert_eq(app.host.toasts.visible_count(), 2)
	app._say("Saved.")
	assert_eq(app.host.toasts.visible_count(), 2, "the same message does not stack")


func test_a_slow_action_runs_behind_the_loading_overlay() -> void:
	await frames(2)
	var done: Array = []
	app.run_with_loading("Simulating...", func() -> void: done.append(1))
	await frames(1)
	var overlays := app.host.overlay.get_children().filter(func(c: Node) -> bool: return c is FcLoadingOverlay)
	assert_eq(overlays.size(), 1, "the overlay is shown while the work is pending")
	await frames(3)
	assert_eq(done, [1], "the work ran exactly once")
	await seconds(0.4)
	overlays = app.host.overlay.get_children().filter(func(c: Node) -> bool: return c is FcLoadingOverlay and not c.is_queued_for_deletion())
	assert_eq(overlays.size(), 0, "and the overlay went away")


func test_the_window_changing_to_a_phone_rebuilds_the_open_screen_as_mobile() -> void:
	await frames(2)
	app.dynasty = FcDynastyController.new(app.content, app._defs, FcDynastyStore.new(DYNASTY_DIR))
	app.dynasty.catalog = FcDynastyFixture.catalog()
	app.dynasty_ui = FcDynastyUi.new(app, app.dynasty)
	app.dynasty_ui.on_create("Live Kings", "LVE")
	await frames(2)
	assert_eq(app.host.bottom_slot.get_child_count(), 0, "a desktop window: tabs on top")
	app.layout.touch_available = true
	host.size = Vector2(412, 915)   # the window shrinks: the app's resized signal tells the layout profile
	await frames(3)
	assert_true(app.layout.is_mobile(), "now mobile")
	assert_true(app.host.bottom_slot.get_child_count() > 0, "the open Dynasty screen was rebuilt with the bottom bar")
	assert_true(FcUiTokens.touch_mode)
	host.size = Vector2(1280, 800)
	await frames(3)
	assert_eq(app.host.bottom_slot.get_child_count(), 0, "and back to desktop when the window grows")


func test_a_wide_screen_scrolls_sideways_in_a_small_window() -> void:
	await frames(2)
	host.size = Vector2(400, 600)
	app.show_career_creator()   # needs about 740 px
	await frames(3)
	var scroll := app.host.content.get_parent() as ScrollContainer
	assert_true(scroll.get_h_scroll_bar().max_value > scroll.size.x, "the screen scrolls sideways instead of being cut off")
	assert_true(scroll.get_h_scroll_bar().visible, "and shows a scroll bar")


func test_the_more_menu_opens_from_the_bottom_bar() -> void:
	var nav := FcNavBar.new()
	host.add_child(nav)
	nav.setup([["a", "A", "house"], ["b", "B", "layers"], ["c", "C", "star"]], "a", true, ["a"])
	nav.size = Vector2(412, 68)
	await frames(2)
	nav.more_button().pressed.emit()
	await frames(2)
	assert_true(nav._menu.visible, "the menu pops up")
	var picked: Array = []
	nav.selected.connect(func(id: String) -> void: picked.append(id))
	nav._menu.index_pressed.emit(0)
	assert_eq(picked, ["b"])
	nav._menu.hide()
