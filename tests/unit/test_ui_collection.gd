extends FcTestCase
## Phase 5: the UI-only state store, collection completion, the carousel, the inspector and compare views, the collection screen
## (filters, grid and carousel, NEW markers), the featured card, and a performance check for big collections.

const PREFS := "user://test_preferences_collection.cfg"
const STATE := "user://test_ui_state_collection.cfg"
const SAVES := "user://test_saves_collection"
const DYNASTY := "user://test_dynasty_collection"

var app: FcApp


func after_each() -> void:
	FcMotion.reduced = false
	FcUiTokens.touch_mode = false
	FcUiTheme.build(1)
	if app != null:
		Engine.get_main_loop().root.remove_child(app)
		app.free()
		app = null
	for path in [PREFS, STATE]:
		DirAccess.remove_absolute(path)
	FcSafeFile.remove_tree(SAVES)
	FcSafeFile.remove_tree(DYNASTY)
	FcDynastyFixture.wipe()


func _dynasty_app() -> void:
	FcSafeFile.remove_tree(DYNASTY)
	FcDynastyFixture.wipe()
	for path in [PREFS, STATE]:
		DirAccess.remove_absolute(path)
	app = FcApp.new()
	app.preferences = FcPreferences.new(PREFS)
	app.preferences.tutorial_done = true
	app.saves = FcSaveManager.new(SAVES)
	Engine.get_main_loop().root.add_child(app)
	app.setup()
	app.dynasty = FcDynastyController.new(app.content, app._defs, FcDynastyStore.new(DYNASTY))
	app.dynasty.catalog = FcDynastyFixture.catalog()
	app.dynasty_ui = FcDynastyUi.new(app, app.dynasty)
	assert_true(app.dynasty_ui.on_create("Collect Kings", "CLK"))


func _find(node: Node, type: Variant) -> Array:
	var out: Array = []
	if is_instance_of(node, type):
		out.append(node)
	for c in node.get_children():
		out.append_array(_find(c, type))
	return out


func _rows(n: int, owned_every: int = 1) -> Array:
	var out: Array = []
	var rarities := FcDynastyContentRules.RARITY_ORDER
	for i in n:
		out.append({"card_id": "r%d" % i, "rarity": rarities[i % rarities.size()], "overall": 60 + i % 40, "position": "SG", "secondary": "", "name": "Player %d" % i,
			"edition": "Base Edition", "team": "Team %d" % (i % 4), "badges": [], "quantity": 1, "owned": i % owned_every == 0, "available": true, "mastery": 0, "art_path": ""})
	return out


# --- UI-only state ----------------------------------------------------------------------------------------------------

func test_the_first_look_at_a_profile_marks_everything_owned_as_seen() -> void:
	var state := FcUiState.new(STATE)
	assert_eq(state.new_cards("p1", ["a", "b", "c"]), [], "nothing is NEW the first time (no flood)")
	assert_true(state.is_baselined("p1"))
	assert_eq(state.new_cards("p1", ["a", "b", "c", "d"]), ["d"], "a card acquired later is NEW")
	state.mark_seen("p1", ["d"])
	assert_eq(state.new_cards("p1", ["a", "b", "c", "d"]), [], "looking at it clears the marker")


func test_profiles_do_not_share_what_they_have_seen() -> void:
	var state := FcUiState.new(STATE)
	state.new_cards("p1", ["a"])
	state.new_cards("p2", ["a"])
	assert_eq(state.new_cards("p1", ["a", "x"]), ["x"])
	assert_eq(state.new_cards("p2", ["a"]), [], "p2 has not got x")
	state.forget("p1")
	assert_true(not state.is_baselined("p1"), "a deleted profile is forgotten")


func test_ui_state_is_remembered_between_runs_and_survives_a_damaged_file() -> void:
	var a := FcUiState.new(STATE)
	a.set_value("collection", "view", "carousel")
	a.mark_seen("p1", ["a", "b"])
	var b := FcUiState.new(STATE)
	assert_eq(b.get_value("collection", "view", "grid"), "carousel")
	assert_eq(b.seen_cards("p1"), ["a", "b"])
	var f := FileAccess.open(STATE, FileAccess.WRITE)
	f.store_string("this is [not a valid config file")
	f.close()
	var c := FcUiState.new(STATE)
	assert_eq(c.get_value("collection", "view", "grid"), "grid", "a damaged file just means defaults")
	assert_eq(c.new_cards("p1", ["a"]), [], "and a fresh baseline")


func test_the_seen_list_is_capped() -> void:
	var state := FcUiState.new(STATE)
	var ids: Array = []
	for i in FcUiState.SEEN_LIMIT + 50:
		ids.append("c%d" % i)
	state.mark_seen("p1", ids)
	assert_eq(state.seen_cards("p1").size(), FcUiState.SEEN_LIMIT)
	assert_eq(state.seen_cards("p1").back(), "c%d" % (FcUiState.SEEN_LIMIT + 49), "the newest are kept")


func test_the_app_keeps_its_ui_state_beside_its_preferences_and_never_in_a_save() -> void:
	_dynasty_app()
	assert_eq(app.ui_state.path, STATE, "named after the preferences file")
	var dyn := app.dynasty.profile().to_dict()
	assert_true(not str(dyn).contains("seen"), "the Dynasty profile (the save) carries no UI-only data")


# --- completion ---------------------------------------------------------------------------------------------------------

func test_completion_counts_overall_rarity_and_team() -> void:
	var data := FcCompletion.compute(_rows(10, 2))
	assert_eq(data["overall"], {"key": "all", "owned": 5, "total": 10, "percent": 50, "complete": false})
	var keys: Array = data["by_rarity"].map(func(g: Dictionary) -> String: return g["key"])
	assert_eq(keys, ["common", "uncommon", "rare", "epic", "legendary"], "rarity order")
	assert_eq(data["by_team"].size(), 4)
	var total := 0
	for g in data["by_rarity"]:
		total += g["total"]
	assert_eq(total, 10, "every card is counted in exactly one rarity")


func test_a_finished_set_is_marked_complete() -> void:
	var rows := _rows(5)
	var data := FcCompletion.compute(rows)
	assert_true(data["overall"]["complete"] and data["by_rarity"][0]["complete"])
	rows[2]["owned"] = false
	assert_true(not FcCompletion.compute(rows)["overall"]["complete"])


func test_completion_copes_with_future_rarities_and_no_cards() -> void:
	var rows := _rows(3)
	rows[1]["rarity"] = "mythic"
	var keys: Array = FcCompletion.compute(rows)["by_rarity"].map(func(g: Dictionary) -> String: return g["key"])
	assert_eq(keys.back(), "mythic", "unknown rarities come last")
	var empty := FcCompletion.compute([])
	assert_eq(empty["overall"]["percent"], 0)
	assert_true(not empty["overall"]["complete"], "an empty collection is not complete")


func test_the_completion_panel_draws_the_numbers() -> void:
	var panel := FcCompletionPanel.build(FcCompletion.compute(_rows(10, 2)))
	var texts := ""
	for l in _find(panel, Label):
		texts += (l as Label).text + "\n"
	assert_true("5 of 10 cards (50%)" in texts, "the overall count")
	assert_true("Team 0" in texts, "the team sets")
	panel.free()


# --- compare ------------------------------------------------------------------------------------------------------------

func test_compare_rows_put_the_biggest_gaps_first() -> void:
	var rows := FcCardCompare.compare_rows([{"key": "a", "a": 50, "b": 52}, {"key": "b", "a": 90, "b": 40}, {"key": "c", "a": 70, "b": 70}, {"key": "d", "a": 60, "b": 52}])
	assert_eq(rows.map(func(r: Dictionary) -> String: return r["key"]), ["b", "d", "a", "c"])


func test_badges_are_split_into_only_and_shared() -> void:
	var split := FcCardCompare.badge_split(["x", "y"], ["y", "z"])
	assert_eq(split, {"only_a": ["x"], "only_b": ["z"], "both": ["y"]})


# --- carousel -----------------------------------------------------------------------------------------------------------

func test_the_carousel_keeps_a_small_pool_whatever_the_collection_size() -> void:
	var c := FcCardCarousel.new()
	c.size = Vector2(900, 460)
	c.set_rows(_rows(1000))
	assert_eq(c.get_children().filter(func(n: Node) -> bool: return n is FcCardFace).size(), FcCardCarousel.POOL, "nine card nodes, however many cards")
	assert_true(c.visible_card_count() <= 4, "the focused card and its neighbours to the right (none to the left yet)")
	c.go_to(500, false)
	assert_eq(c.visible_card_count(), 7, "the middle card and three each side")
	c.free()


func test_the_carousel_moves_clamps_and_announces_focus() -> void:
	var c := FcCardCarousel.new()
	c.size = Vector2(900, 460)
	var seen: Array = []
	c.focused.connect(func(i: int) -> void: seen.append(i))
	c.set_rows(_rows(5))
	c.go_to(3, false)
	assert_eq(c.index, 3)
	assert_eq(c.focused_row()["card_id"], "r3")
	c.go_to(99, false)
	assert_eq(c.index, 4, "clamped to the last card")
	c.go_to(-5, false)
	assert_eq(c.index, 0, "and to the first")
	assert_eq(seen, [3, 4, 0], "each real change is announced once")
	c.go_to(0, false)
	assert_eq(seen.size(), 3, "no change, no announcement")
	c.free()


func test_the_carousel_answers_keys_the_wheel_and_swipes() -> void:
	var c := FcCardCarousel.new()
	c.size = Vector2(900, 460)
	c.set_rows(_rows(8), 3)
	FcMotion.reduced = true
	var right := InputEventAction.new()
	right.action = "ui_right"
	right.pressed = true
	c._gui_input(right)
	assert_eq(c.index, 4, "right")
	var left := InputEventAction.new()
	left.action = "ui_left"
	left.pressed = true
	c._gui_input(left)
	c._gui_input(left)
	assert_eq(c.index, 2, "left twice")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	c._gui_input(wheel)
	assert_eq(c.index, 3, "the wheel moves too")
	var drag := InputEventMouseMotion.new()
	drag.button_mask = MOUSE_BUTTON_MASK_LEFT
	drag.relative = Vector2(FcCardCarousel.SWIPE_DISTANCE + 5, 0)
	c._gui_input(drag)
	assert_eq(c.index, 2, "dragging right shows the previous card")
	var picked: Array = []
	c.activated.connect(func(i: int) -> void: picked.append(i))
	var accept := InputEventAction.new()
	accept.action = "ui_accept"
	accept.pressed = true
	c._gui_input(accept)
	assert_eq(picked, [2], "accept opens the middle card")
	c.free()


func test_an_empty_carousel_is_safe() -> void:
	var c := FcCardCarousel.new()
	c.size = Vector2(900, 460)
	c.set_rows([])
	c.step(1)
	assert_eq(c.visible_card_count(), 0)
	assert_eq(c.focused_row(), {})
	c.free()


# --- the collection screen ---------------------------------------------------------------------------------------------

func test_the_collection_screen_shows_completion_filters_and_cards() -> void:
	_dynasty_app()
	app.dynasty_ui.show_tab("collection")
	assert_true(_find(app._root, FcPanel).size() > 0, "the completion panel")
	assert_eq(_find(app._root, FcFilterBar).size(), 1, "one filter bar")
	assert_true(_find(app._root, FcCardFace).size() >= 15, "the cards are listed")
	assert_eq(_find(app._root, FcChoiceGroup).size(), 1, "grid or carousel")


func test_filters_narrow_the_grid_without_rebuilding_the_screen() -> void:
	_dynasty_app()
	app.dynasty_ui.show_tab("collection")
	var bar: FcFilterBar = _find(app._root, FcFilterBar)[0]
	var all := _find(app._root, FcCardFace).size()
	var rarity_button: Button = null
	for b in _find(bar, Button):
		if (b as Button).text == "Legendary":
			rarity_button = b
	assert_true(rarity_button != null)
	rarity_button.button_pressed = true
	var filtered := _find(app._root, FcCardFace)
	assert_true(filtered.size() < all and filtered.size() > 0, "only legendary cards remain")
	for card in filtered:
		assert_eq(card.row["rarity"], "legendary")
	assert_eq(app.dynasty_ui.collection_filters.get("rarity", ""), "legendary", "the screen remembers the filter")
	assert_true(_find(app._root, FcFilterBar)[0] == bar, "the filter bar itself was not rebuilt")


func test_a_filter_with_no_matches_explains_and_offers_a_way_out() -> void:
	_dynasty_app()
	app.dynasty_ui.collection_filters = {"search": "zzzz-no-such-card"}
	app.dynasty_ui.show_tab("collection")
	var empty: FcEmptyState = _find(app._root, FcEmptyState)[0]
	assert_eq(empty.title_label.text, "No cards match")
	assert_true(empty.action_button != null, "with a Clear filters button")


func test_the_browse_mode_is_remembered() -> void:
	_dynasty_app()
	app.dynasty_ui.show_tab("collection")
	var view: FcChoiceGroup = _find(app._root, FcChoiceGroup)[0]
	view.selected.emit("carousel")
	assert_eq(app.ui_state.get_value("collection", "view", "grid"), "carousel")
	assert_eq(_find(app._root, FcCardCarousel).size(), 1, "the carousel replaced the grid")
	app.dynasty_ui.show_tab("hub")
	app.dynasty_ui.show_tab("collection")
	assert_eq(_find(app._root, FcCardCarousel).size(), 1, "and it is still the carousel on return")


func test_new_cards_wear_a_marker_until_they_are_inspected() -> void:
	_dynasty_app()
	app.dynasty_ui.show_tab("collection")   # the first look: the starter collection counts as seen
	for card in _find(app._root, FcCardFace):
		assert_true(card.tag != "NEW", "no flood of NEW markers on a first look")
	var ctl := app.dynasty
	var before := ctl.profile().unique_owned()
	var bought := ctl.buy_pack("bronze_pack")
	assert_true(bought.ok)
	var gained: Array = []
	for e in bought.data["opening"]["cards"]:
		if bool(e["new"]) and not gained.has(e["card_id"]):
			gained.append(e["card_id"])
	if gained.is_empty():
		return   # this seed produced only duplicates: nothing to mark
	app.dynasty_ui.show_tab("collection")
	var marked := _find(app._root, FcCardFace).filter(func(c: FcCardFace) -> bool: return c.tag == "NEW")
	assert_eq(marked.size(), gained.size(), "exactly the cards the pack added are NEW")
	FcCardInspector.open_for(app.dynasty_ui, gained[0], gained)
	assert_true(app.ui_state.seen_cards(ctl.profile().profile_id).has(gained[0]), "opening a card marks it seen")
	assert_true(before < ctl.profile().unique_owned())


# --- the inspector -----------------------------------------------------------------------------------------------------

func test_the_inspector_walks_through_the_cards_it_was_given() -> void:
	_dynasty_app()
	var ids: Array = [FcDynastyFixture.card_id(0), FcDynastyFixture.card_id(1), FcDynastyFixture.card_id(2)]
	var inspector := FcCardInspector.open_for(app.dynasty_ui, ids[1], ids)
	assert_eq(inspector.current_id(), ids[1])
	inspector.step(1)
	assert_eq(inspector.current_id(), ids[2])
	inspector.step(1)
	assert_eq(inspector.current_id(), ids[2], "stops at the last card")
	inspector.step(-5)
	assert_eq(inspector.current_id(), ids[0], "and at the first")
	assert_eq(app.host.modals.count(), 1, "it is an overlay in the dialog layer")


func test_the_inspector_zoom_is_clamped_and_resizes_the_card() -> void:
	_dynasty_app()
	var inspector := FcCardInspector.open_for(app.dynasty_ui, FcDynastyFixture.card_id(0), [])
	assert_eq(inspector.zoom_level(), 1)
	inspector.zoom(5)
	assert_eq(inspector.zoom_level(), FcCardInspector.ZOOM_SIZES.size() - 1)
	inspector.zoom(-9)
	assert_eq(inspector.zoom_level(), 0)
	var hero: FcCardFace = _find(inspector, FcCardFace)[0]
	assert_eq(hero.custom_minimum_size, FcCardFace.SIZE_STANDARD)
	assert_true(hero.inspected, "the card being examined shows the inspected state")


func test_the_inspector_shows_attributes_badges_and_ratings_from_the_card() -> void:
	_dynasty_app()
	var inspector := FcCardInspector.open_for(app.dynasty_ui, FcDynastyFixture.card_id(0), [])
	var text := ""
	for l in _find(inspector, Label):
		text += (l as Label).text + "\n"
	assert_true("Catch and Shoot" in text, "badges with their names")
	assert_true("Three-Point Shooting" in text, "attributes")
	assert_eq(_find(inspector, FcRatingBadge).size(), 1, "the overall rating badge")
	assert_true(_find(inspector, ProgressBar).size() >= 28, "a bar for every attribute")


func test_inspecting_and_comparing_never_change_the_profile() -> void:
	_dynasty_app()
	var snapshot := app.dynasty.profile().to_dict()
	var ids: Array = [FcDynastyFixture.card_id(0), FcDynastyFixture.card_id(1)]
	var inspector := FcCardInspector.open_for(app.dynasty_ui, ids[0], ids)
	inspector.step(1)
	inspector.zoom(1)
	FcCardCompare.open_for(app.dynasty_ui, ids[0], ids[1])
	assert_eq(app.host.modals.count(), 2, "compare opens over the inspector")
	assert_true(app.dynasty.profile().to_dict() == snapshot, "looking never changes the collection")


func test_compare_shows_both_cards_and_follows_its_picker() -> void:
	_dynasty_app()
	var compare := FcCardCompare.open_for(app.dynasty_ui, FcDynastyFixture.card_id(0), FcDynastyFixture.card_id(1))
	assert_eq(_find(compare, FcCardFace).size(), 2, "two cards side by side")
	assert_true(_find(compare, FcStatBar).size() > 20, "a bar for overall and each attribute")
	compare._picker.select_value(FcDynastyFixture.card_id(2) if compare._picker.value() != FcDynastyFixture.card_id(2) else FcDynastyFixture.card_id(1))
	compare._picker.chosen.emit(compare._picker.value())
	assert_eq(_find(compare, FcCardFace).size(), 2, "still two after choosing another")


# --- the hub -------------------------------------------------------------------------------------------------------------

func test_the_hub_features_the_strongest_owned_card() -> void:
	_dynasty_app()
	var featured := app.dynasty_ui.featured_card()
	assert_true(not featured.is_empty())
	var best := 0
	for row in app.dynasty.collection_rows({"ownership": "owned"}):
		best = maxi(best, int(row["overall"]))
	assert_eq(int(featured["overall"]), best, "the highest-rated owned card")
	app.dynasty_ui.show_tab("hub")
	var faces := _find(app._root, FcCardFace).filter(func(c: FcCardFace) -> bool: return c.row.get("card_id", "") == featured["card_id"])
	assert_eq(faces.size(), 1, "it is on the hub")


# --- performance -----------------------------------------------------------------------------------------------------------

func test_big_collections_cost_one_node_per_card_and_build_quickly() -> void:
	for count in [500, 2000]:
		var start := Time.get_ticks_msec()
		var grid := HFlowContainer.new()
		for row in _rows(count, 2):
			grid.add_child(FcCardView.build(row))
		var elapsed := Time.get_ticks_msec() - start
		assert_eq(grid.get_child_count(), count)
		var nodes := 0
		for c in grid.get_children():
			nodes += 1 + c.get_child_count()
		assert_true(nodes <= count * 2, "%d cards use %d nodes (one per card, plus a sweep overlay on rare and better)" % [count, nodes])
		assert_true(elapsed < 4000, "%d cards built in %d ms (budget 4000)" % [count, elapsed])
		print("PERF collection grid: %d cards, %d nodes, %d ms" % [count, nodes, elapsed])
		grid.free()
