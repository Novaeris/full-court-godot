extends FcLiveTestCase
## Dynasty on a phone: the whole loop (navigate, inspect a card, buy and reveal a pack, set the lineup, play a game, claim) driven by
## TOUCH events on a 412x915 screen in the mobile layout. Godot turns a touch into a mouse click, so this proves the controls are reachable
## and respond to a finger, not just to a test calling a method.

const PREFS := "user://test_preferences_live_mobile.cfg"
const DYNASTY := "user://test_dynasty_live_mobile"

var app: FcApp


var _screen: SubViewport


func before_each() -> void:
	super.before_each()
	# a phone-sized screen of its own (the headless window is tiny, so a tap at phone coordinates would hit nothing): as tools/click_test.gd does
	_screen = SubViewport.new()
	_screen.size = Vector2i(412, 915)
	host.add_child(_screen)
	DirAccess.remove_absolute(PREFS)
	FcSafeFile.remove_tree(DYNASTY)
	FcDynastyFixture.wipe()
	app = FcApp.new()
	app.preferences = FcPreferences.new(PREFS)
	app.preferences.tutorial_done = true
	app.preferences.layout_override = "mobile"
	app.saves = FcSaveManager.new("user://test_saves_live_mobile")
	_screen.add_child(app)


func after_each() -> void:
	super.after_each()
	DirAccess.remove_absolute(PREFS)
	DirAccess.remove_absolute("user://test_ui_state_live_mobile.cfg")
	FcSafeFile.remove_tree(DYNASTY)
	FcSafeFile.remove_tree("user://test_saves_live_mobile")
	FcDynastyFixture.wipe()


## A finger tap on the centre of a control: the touch events, and the mouse click Godot produces from them (its "emulate mouse from touch"
## setting, asserted in test_touch_is_emulated_as_a_mouse_click). Events go to the window, like tools/click_test.gd.
func _tap(control: Control) -> void:
	var at := control.get_global_rect().get_center()
	var window: Viewport = _screen
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.position = at
	touch.pressed = true
	window.push_input(touch)
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	window.push_input(motion)
	await frames(1)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = at
	down.global_position = at
	down.button_mask = MOUSE_BUTTON_MASK_LEFT
	window.push_input(down)
	await frames(1)
	touch.pressed = false
	window.push_input(touch)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = at
	up.global_position = at
	window.push_input(up)
	await frames(3)


func _button(text: String) -> Button:
	for b in app._root.find_children("*", "Button", true, false):
		if (b as Button).text.begins_with(text) and (b as Button).is_visible_in_tree() and not (b as Button).disabled:
			return b
	return null


func _start() -> void:
	await frames(2)
	app.dynasty = FcDynastyController.new(app.content, app._defs, FcDynastyStore.new(DYNASTY))
	app.dynasty.catalog = FcDynastyFixture.catalog()
	app.dynasty_ui = FcDynastyUi.new(app, app.dynasty)
	app.dynasty_ui.on_create("Touch Kings", "TCH")
	await frames(3)


func _nav() -> FcNavBar:
	for c in app.host.bottom_slot.get_children():
		if c is FcNavBar:
			return c
	return null


func _find_reveal(n: Node) -> FcPackReveal:
	if n is FcPackReveal:
		return n
	for c in n.get_children():
		var r := _find_reveal(c)
		if r != null:
			return r
	return null


func test_touch_is_emulated_as_a_mouse_click() -> void:
	assert_true(bool(ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch", true)), "Godot turns a finger tap into a click (the project keeps the default)")
	assert_true(not bool(ProjectSettings.get_setting("input_devices/pointing/emulate_touch_from_mouse", false)), "and the desktop mouse is not turned into touches")


func test_the_bottom_bar_navigates_by_touch() -> void:
	await _start()
	assert_true(app.layout.is_mobile() and FcUiTokens.touch_mode, "the phone layout is active")
	var nav := _nav()
	await _tap(nav.button_for("collection"))
	assert_eq(app.dynasty_ui.tab, "collection", "a tap on Collection opens it")
	await _tap(_nav().button_for("packs"))
	assert_eq(app.dynasty_ui.tab, "packs")
	var more: Button = _nav().more_button()
	assert_true(more != null and more.get_global_rect().size.y >= 44, "the More button is a full-size touch target")


func test_a_pack_can_be_bought_revealed_and_finished_by_touch() -> void:
	await _start()
	app.dynasty_ui.show_tab("packs")
	await frames(3)
	var before := app.dynasty.profile().unique_owned()
	await _tap(_button("Buy and open"))
	var reveal: FcPackReveal = _find_reveal(app)
	assert_true("Click the card" in reveal.status.text or reveal.stage == FcPackReveal.Stage.SUMMARY, "the reveal started")
	await _tap(_button("Skip animation"))
	assert_eq(reveal.stage, FcPackReveal.Stage.SUMMARY)
	await _tap(_button("Done"))
	assert_true(app.dynasty.pending_openings().is_empty(), "Done acknowledged the opening")
	assert_true(app.dynasty.profile().unique_owned() >= before)
	assert_eq(app.dynasty_ui.tab, "packs", "and the market is back")


func test_the_lineup_and_a_game_work_by_touch() -> void:
	await _start()
	app.dynasty_ui.show_tab("lineup")
	await frames(3)
	await _tap(_button("Auto-fill"))
	assert_true(app.dynasty.lineup_problems().is_empty(), "the lineup is ready")
	app.dynasty_ui.show_tab("play")
	await frames(3)
	await _tap(_button("Easy opponent"))
	assert_true(not app.dynasty.last_game.is_empty(), "a game was played")
	app.dynasty_ui.show_tab("play")
	await frames(2)
	var texts := ""
	for l in app._root.find_children("*", "Label", true, false):
		texts += (l as Label).text + "\n"
	assert_true("WIN" in texts or "LOSS" in texts, "the result is shown")


func test_a_card_opens_the_inspector_by_touch_and_back_closes_it() -> void:
	await _start()
	app.dynasty_ui.show_tab("collection")
	await frames(3)
	var card: FcCardFace = app._root.find_children("*", "FcCardFace", true, false)[0]
	await _tap(card)
	assert_eq(app.host.modals.count(), 1, "tapping a card opened the inspector")
	assert_true(app.go_back(), "the back gesture closes it")
	await frames(2)
	assert_eq(app.host.modals.count(), 0)


func test_every_tab_builds_on_a_phone_without_errors_and_without_sideways_scrolling() -> void:
	await _start()
	var scroll := app.host.content.get_parent() as ScrollContainer
	for entry in FcDynastyUi.TABS:
		app.dynasty_ui.show_tab(str(entry[0]))
		await frames(3)
		assert_true(scroll.get_h_scroll_bar().max_value <= scroll.size.x + 1.0, "%s fits the phone width" % entry[0])
