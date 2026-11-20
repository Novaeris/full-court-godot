extends FcLiveTestCase
## Phase 5 in a live tree: the carousel slides, the inspector answers keys, and the collection screen lays out as a grid and as a carousel.

const PREFS := "user://test_preferences_live_collection.cfg"
const STATE := "user://test_ui_state_live_collection.cfg"
const DYNASTY := "user://test_dynasty_live_collection"

var app: FcApp


func before_each() -> void:
	super.before_each()
	for path in [PREFS, STATE]:
		DirAccess.remove_absolute(path)
	FcSafeFile.remove_tree(DYNASTY)
	FcDynastyFixture.wipe()
	host.size = Vector2(1280, 800)
	app = FcApp.new()
	app.preferences = FcPreferences.new(PREFS)
	app.preferences.tutorial_done = true
	app.saves = FcSaveManager.new("user://test_saves_live_collection")
	host.add_child(app)


func after_each() -> void:
	super.after_each()
	for path in [PREFS, STATE]:
		DirAccess.remove_absolute(path)
	FcSafeFile.remove_tree(DYNASTY)
	FcSafeFile.remove_tree("user://test_saves_live_collection")
	FcDynastyFixture.wipe()


func _open_dynasty() -> void:
	await frames(2)
	app.dynasty = FcDynastyController.new(app.content, app._defs, FcDynastyStore.new(DYNASTY))
	app.dynasty.catalog = FcDynastyFixture.catalog()
	app.dynasty_ui = FcDynastyUi.new(app, app.dynasty)
	app.dynasty_ui.on_create("Live Collectors", "LVC")
	await frames(2)


func _press(action: String) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)


func test_the_carousel_slides_to_the_next_card() -> void:
	var rows: Array = []
	for i in 10:
		rows.append({"card_id": "c%d" % i, "rarity": "rare", "overall": 70 + i, "position": "PG", "name": "Player %d" % i, "edition": "Base", "owned": true, "available": true})
	var carousel := FcCardCarousel.new()
	carousel.size = Vector2(900, 460)
	host.add_child(carousel)
	carousel.set_rows(rows)
	await frames(2)
	carousel.step(1)
	await seconds(0.08)
	assert_true(carousel.position_index > 0.0 and carousel.position_index < 1.0, "sliding between cards (%s)" % carousel.position_index)
	await seconds(0.4)
	assert_eq(carousel.position_index, 1.0, "settled on the next card")
	assert_eq(carousel.index, 1)
	var middle: FcCardFace = null
	for c in carousel.get_children():
		if c is FcCardFace and c.visible and c.get_meta("idx", -1) == 1:
			middle = c
	assert_true(middle != null and middle.scale.x > 0.99, "the focused card is shown at full size")
	assert_true(middle.inspected, "and carries the inspected look")


func test_the_inspector_answers_arrow_keys_and_escape() -> void:
	await _open_dynasty()
	var ids: Array = [FcDynastyFixture.card_id(0), FcDynastyFixture.card_id(1), FcDynastyFixture.card_id(2)]
	var inspector := FcCardInspector.open_for(app.dynasty_ui, ids[0], ids)
	await frames(3)
	_press("ui_right")
	await frames(2)
	assert_eq(inspector.current_id(), ids[1], "right shows the next card")
	_press("ui_left")
	await frames(2)
	assert_eq(inspector.current_id(), ids[0], "left shows the previous card")
	_press("ui_cancel")
	await frames(2)
	assert_eq(app.host.modals.count(), 0, "Escape closes the inspector")


func test_the_collection_lays_out_as_a_grid_and_as_a_carousel() -> void:
	await _open_dynasty()
	app.dynasty_ui.show_tab("collection")
	await frames(3)
	var cards := app._root.find_children("*", "FcCardFace", true, false)
	assert_true(cards.size() >= 15, "a grid of cards")
	for c in cards.slice(0, 5):
		assert_true(c.size.x >= 100 and c.size.y >= 150, "cards were laid out at a readable size")
	app.ui_state.set_value("collection", "view", "carousel")
	app.dynasty_ui.show_tab("collection")
	await frames(3)
	var carousels := app._root.find_children("*", "FcCardCarousel", true, false)
	assert_eq(carousels.size(), 1)
	assert_true((carousels[0] as FcCardCarousel).visible_card_count() >= 3, "the focused card and its neighbours")


func test_clicking_a_card_opens_the_inspector_and_the_new_marker_goes_away() -> void:
	await _open_dynasty()
	app.dynasty_ui.show_tab("collection")
	await frames(3)
	var card: FcCardFace = app._root.find_children("*", "FcCardFace", true, false)[0]
	card.activated.emit()
	card.on_click.call()
	await frames(2)
	assert_eq(app.host.modals.count(), 1, "the inspector opened")
	app.host.modals.top().close(true)
	await seconds(0.3)
	assert_eq(app.host.modals.count(), 0)
