extends FcTestCase
## The card system (Phase 4): the rarity registry, the card face and its states, flip, input, and the FcCardView compatibility API.
## Real animation (hover lift, flip, the light sweep) runs in tests/live/test_live_cards.gd.


func after_each() -> void:
	FcMotion.reduced = false


func _row(rarity: String = "epic", extra: Dictionary = {}) -> Dictionary:
	var row := {"card_id": "c1", "rarity": rarity, "overall": 83, "position": "SG", "secondary": "SF", "name": "Lena Voss", "edition": "Base Edition",
		"team": "Harbor", "badges": ["a"], "quantity": 1, "owned": true, "available": true, "mastery": 0, "art_path": ""}
	row.merge(extra, true)
	return row


# --- the rarity registry ------------------------------------------------------------------------------------------------

func test_every_rarity_has_its_own_treatment_not_just_a_colour() -> void:
	var frames := {}
	var patterns := {}
	var colours := {}
	for rarity in FcDynastyContentRules.RARITY_ORDER:
		assert_true(FcRarityStyle.known(rarity), "%s is styled" % rarity)
		var style := FcRarityStyle.of(rarity)
		frames[style["frame"]] = true
		patterns[style["pattern"]] = true
		colours[style["color"].to_html()] = true
	assert_eq(frames.size(), 5, "five different frames")
	assert_eq(patterns.size(), 5, "five different backgrounds")
	assert_eq(colours.size(), 5, "five different colours")


func test_reveal_intensity_climbs_with_rarity() -> void:
	var last := -1
	for rarity in FcDynastyContentRules.RARITY_ORDER:
		var level := FcRarityStyle.intensity(rarity)
		assert_true(level > last, "%s is more intense than the one before" % rarity)
		last = level
	assert_eq(FcRarityStyle.intensity("legendary"), 4)


func test_only_rare_and_better_get_the_light_sweep() -> void:
	assert_true(not FcRarityStyle.of("common")["sweep"] and not FcRarityStyle.of("uncommon")["sweep"])
	for rarity in ["rare", "epic", "legendary"]:
		assert_true(FcRarityStyle.of(rarity)["sweep"], rarity)


func test_a_future_rarity_never_breaks_the_look() -> void:
	assert_true(not FcRarityStyle.known("mythic"))
	assert_eq(FcRarityStyle.of("mythic"), FcRarityStyle.of("common"), "unknown rarities get the common look")
	assert_eq(FcRarityStyle.label("mythic_future"), "Mythic Future", "but keep their own name")
	assert_eq(FcRarityStyle.intensity("mythic"), 0, "and reveal quietly")
	var card := FcCardView.build(_row("mythic"))
	assert_true(card != null and "Mythic" in card.accessible_text(), "a card of an unknown rarity builds")
	card.free()


func test_text_on_every_rarity_colour_is_readable_on_the_card() -> void:
	for rarity in FcDynastyContentRules.RARITY_ORDER:
		var body: Color = FcRarityStyle.dark(rarity).lerp(FcUiTokens.SURFACE_RAISED, 0.35)
		assert_true(FcUiContrast.ratio(FcRarityStyle.color(rarity), body) >= 4.5, "%s rating colour on its card body" % rarity)
		assert_true(FcUiContrast.ratio(FcUiTokens.TEXT, body) >= 7.0, "name text on a %s card" % rarity)


func test_mastery_colours_climb_and_none_is_transparent() -> void:
	assert_eq(FcRarityStyle.mastery_color(0).a, 0.0)
	var seen := {}
	for level in range(1, 6):
		seen[FcRarityStyle.mastery_color(level).to_html()] = true
	assert_eq(seen.size(), 5, "bronze to diamond are all different")
	assert_eq(FcRarityStyle.mastery_color(99), FcRarityStyle.mastery_color(5), "levels clamp")


func test_the_old_style_helpers_follow_the_registry() -> void:
	for rarity in FcDynastyContentRules.RARITY_ORDER:
		assert_eq(FcDynastyStyle.rarity_color(rarity), FcRarityStyle.color(rarity))
		assert_eq(FcDynastyStyle.rarity_label(rarity), FcRarityStyle.label(rarity))


# --- the card face ----------------------------------------------------------------------------------------------------

func test_every_rarity_builds_with_and_without_readable_art() -> void:
	for rarity in FcDynastyContentRules.RARITY_ORDER:
		for art in ["", "res://does/not/exist.png", "user://missing_art.png"]:
			var card := FcCardView.build(_row(rarity, {"art_path": art}))
			assert_true(card is FcCardFace, "%s with art '%s'" % [rarity, art])
			assert_eq(card.custom_minimum_size, FcCardFace.SIZE_STANDARD)
			card.free()


func test_card_sizes_cover_mini_to_hero() -> void:
	var last := 0.0
	for kind in ["mini", "small", "standard", "detail", "hero"]:
		var size := FcCardFace.size_for(kind)
		assert_true(size.x > last, kind)
		assert_between(size.y / size.x, 1.38, 1.44, "%s keeps the card proportions" % kind)
		last = size.x
	assert_eq(FcCardFace.size_for("nonsense"), FcCardFace.SIZE_STANDARD)
	var hero := FcCardView.build(_row(), {"size": FcCardFace.size_for("hero")})
	assert_eq(hero.custom_minimum_size, FcCardFace.SIZE_HERO)
	hero.free()


func test_a_card_describes_itself_in_words() -> void:
	var card := FcCardView.build(_row("legendary"))
	assert_eq(card.accessible_text(), "Lena Voss (Base Edition), Legendary, 83 overall, SG")
	assert_eq(card.tooltip_text, card.accessible_text(), "the same words are the tooltip")
	var new_card := FcCardView.build(_row("rare", {"owned": false}), {"tag": "NEW"})
	assert_true("not owned" in new_card.accessible_text() and "new" in new_card.accessible_text())
	var back := FcCardView.build({}, {"face_down": true})
	assert_eq(back.accessible_text(), "A card, face down")
	assert_eq(back.tooltip_text, "", "a face-down card gives nothing away")
	for c in [card, new_card, back]:
		c.free()


func test_cards_that_are_not_owned_or_available_are_dimmed() -> void:
	assert_eq(FcCardView.build(_row()).modulate.a, 1.0)
	assert_between(FcCardView.build(_row("epic", {"owned": false})).modulate.a, 0.549, 0.551, "not owned")
	assert_between(FcCardView.build(_row("epic", {"available": false})).modulate.a, 0.549, 0.551, "unavailable")
	assert_eq(FcCardView.build({}, {"face_down": true}).modulate.a, 1.0, "the back of a card is never dimmed")


func test_selected_and_inspected_are_separate_states() -> void:
	var card := FcCardView.build(_row())
	assert_true(not card.selected and not card.inspected)
	card.selected = true
	assert_true(card.selected and not card.inspected, "selecting does not inspect")
	card.inspected = true
	card.selected = false
	assert_true(card.inspected and not card.selected, "inspecting does not select")
	var both := FcCardView.build(_row(), {"selected": true, "inspected": true})
	assert_true(both.selected and both.inspected)
	card.free()
	both.free()


func test_a_card_is_keyboard_and_controller_reachable() -> void:
	var card := FcCardView.build(_row())
	assert_eq(card.focus_mode, Control.FOCUS_ALL)
	assert_eq(card.mouse_default_cursor_shape, Control.CURSOR_POINTING_HAND)
	card.free()


func test_clicking_or_pressing_accept_activates_the_card() -> void:
	var got: Array = []
	var card := FcCardView.build(_row(), {"on_click": func() -> void: got.append("click")})
	card.activated.connect(func() -> void: got.append("signal"))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	card._gui_input(click)
	assert_eq(got, ["signal", "click"])
	var accept := InputEventAction.new()
	accept.action = "ui_accept"
	accept.pressed = true
	card._gui_input(accept)
	assert_eq(got.size(), 4, "Enter or the controller's accept button does the same")
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	card._gui_input(right)
	assert_eq(got.size(), 4, "other buttons do nothing")
	card.free()


func test_flipping_without_a_tree_just_turns_the_card() -> void:
	var card := FcCardView.build(_row(), {"face_down": true})
	assert_true(card.flip_to(false) == null)
	assert_true(not card.face_down and card.scale == Vector2.ONE)
	assert_true(card.flip_to(false) == null, "already face up: nothing to do")
	card.flip_to(true)
	assert_true(card.face_down)
	card.free()


func test_only_rare_and_better_cards_carry_the_sweep_overlay() -> void:
	for rarity in FcDynastyContentRules.RARITY_ORDER:
		var card := FcCardView.build(_row(rarity))
		var has_sweep := card.get_children().any(func(c: Node) -> bool: return c is ColorRect and c.material is ShaderMaterial)
		assert_eq(has_sweep, bool(FcRarityStyle.of(rarity)["sweep"]), "%s sweep overlay" % rarity)
		card.free()
	var back := FcCardView.build(_row("legendary"), {"face_down": true})
	assert_eq(back.get_child_count(), 0, "a face-down card has no sweep")
	back.free()


func test_the_sweep_shader_file_ships() -> void:
	assert_true(ResourceLoader.exists(FcCardFace.SWEEP_SHADER))
	assert_true("render_mode blend_add" in FileAccess.get_file_as_string(FcCardFace.SWEEP_SHADER), "it only adds light")


func test_card_rows_are_never_modified_by_drawing_or_states() -> void:
	var row := _row("legendary")
	var before := row.duplicate(true)
	var card := FcCardView.build(row, {"tag": "NEW", "caption": "500 credits"})
	card.selected = true
	card.inspected = true
	card.flip_to(true)
	card.lift = 1.0
	assert_eq(row, before, "presentation never changes a card's data")
	card.free()


func test_the_card_view_api_is_unchanged_for_the_dynasty_screens() -> void:
	assert_eq(FcCardView.SIZE, FcCardFace.SIZE_STANDARD)
	assert_eq(FcCardView.SMALL, FcCardFace.SIZE_SMALL)
	var card := FcCardView.build(_row(), {"size": FcCardView.SMALL, "caption": "500 credits", "tag": "DUPLICATE"})
	assert_eq(card.caption, "500 credits")
	assert_eq(card.tag, "DUPLICATE")
	card.free()
