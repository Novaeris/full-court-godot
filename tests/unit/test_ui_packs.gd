extends FcTestCase
## Phase 6: pack art, the reveal state machine and its INTEGRITY guarantees (the reveal only presents what was already rolled and saved; it
## cannot change, reorder or lose the result; skipping equals watching), effects by rarity, duplicates and the summary.

const PREFS := "user://test_preferences_packs.cfg"
const DYNASTY := "user://test_dynasty_packs_ui"

var app: FcApp


func after_each() -> void:
	FcMotion.reduced = false
	FcUiTokens.touch_mode = false
	FcUiTheme.build(1)
	if app != null:
		Engine.get_main_loop().root.remove_child(app)
		app.free()
		app = null
	for path in [PREFS, "user://test_ui_state_packs.cfg"]:
		DirAccess.remove_absolute(path)
	FcSafeFile.remove_tree(DYNASTY)
	FcSafeFile.remove_tree("user://test_saves_packs")
	FcDynastyFixture.wipe()


func _dynasty_app() -> void:
	FcSafeFile.remove_tree(DYNASTY)
	FcDynastyFixture.wipe()
	app = FcApp.new()
	app.preferences = FcPreferences.new(PREFS)
	app.preferences.tutorial_done = true
	app.saves = FcSaveManager.new("user://test_saves_packs")
	Engine.get_main_loop().root.add_child(app)
	app.setup()
	app.dynasty = FcDynastyController.new(app.content, app._defs, FcDynastyStore.new(DYNASTY))
	app.dynasty.catalog = FcDynastyFixture.catalog()
	app.dynasty_ui = FcDynastyUi.new(app, app.dynasty)
	assert_true(app.dynasty_ui.on_create("Pack Kings", "PKK"))


func _find(node: Node, type: Variant) -> Array:
	var out: Array = []
	if is_instance_of(node, type):
		out.append(node)
	for c in node.get_children():
		out.append_array(_find(c, type))
	return out


func _find_button(node: Node, text: String) -> Button:
	for b in _find(node, Button):
		if (b as Button).text.begins_with(text):
			return b
	return null


## A reveal over hand-made cards (so rarities and new/duplicate flags are exactly what a test needs). `calls` counts what the control asks for.
func _reveal(rarities: Array, new_flags: Array = [], calls: Dictionary = {}) -> FcPackReveal:
	var cards: Array = []
	var rows := {}
	for i in rarities.size():
		var id := "card_%d" % i
		cards.append({"card_id": id, "new": new_flags[i] if i < new_flags.size() else true, "quantity": 1})
		rows[id] = {"card_id": id, "rarity": rarities[i], "overall": 60 + i, "position": "PG", "name": "Player %d" % i, "edition": "Base", "owned": true, "available": true, "mastery": 0}
	var reveal := FcPackReveal.new()
	reveal.setup({"opening_id": "op_000001", "pack_id": "p", "cards": cards}, "Test Pack", {"name": "Test Pack", "cards_per_pack": cards.size(), "odds": {}},
		func(id: String) -> Dictionary:
			calls["rows"] = int(calls.get("rows", 0)) + 1
			return rows[id].duplicate(),
		func(rarity: String) -> int:
			calls["shards"] = int(calls.get("shards", 0)) + 1
			return {"common": 5, "rare": 20}.get(rarity, 10),
		func() -> Dictionary:
			calls["progress"] = int(calls.get("progress", 0)) + 1
			return {"owned": 12, "total": 32},
		func() -> void: calls["done"] = int(calls.get("done", 0)) + 1)
	return reveal


# --- pack art ---------------------------------------------------------------------------------------------------------------

func test_a_pack_tier_is_its_best_possible_rarity() -> void:
	assert_eq(FcPackArt.tier_of({"fixed": true, "odds": {"legendary": 500}}), "fixed", "a fixed pack has no tier")
	assert_eq(FcPackArt.tier_of({"odds": {"common": 6000, "uncommon": 2500, "rare": 1000, "epic": 400, "legendary": 100}}), "legendary")
	assert_eq(FcPackArt.tier_of({"odds": {"common": 9000, "uncommon": 1000}}), "uncommon")
	assert_eq(FcPackArt.tier_of({"odds": {"common": 10000, "legendary": 0}}), "common", "a zero weight does not count")
	assert_eq(FcPackArt.tier_of({"odds": {}}), "common")
	assert_eq(FcPackArt.tier_of({"odds": {"mythic": 100}}), "common", "an unknown rarity never breaks a pack")
	assert_eq(FcPackArt.tier_color("fixed"), FcUiTokens.STEEL)
	assert_eq(FcPackArt.tier_color("epic"), FcRarityStyle.color("epic"))


func test_every_published_pack_gets_artwork() -> void:
	_dynasty_app()
	var listings := app.dynasty.pack_listing()
	assert_true(listings.size() >= 3)
	for pk in listings:
		var art := FcPackArt.new().setup(pk)
		assert_eq(art.custom_minimum_size, FcPackArt.SIZE)
		assert_eq(art.tier, FcPackArt.tier_of(pk))
		art.free()
	app.dynasty_ui.show_tab("packs")
	assert_eq(_find(app._root, FcPackArt).size(), listings.size(), "one pack artwork per pack on the market screen")
	assert_true(_find_button(app._root, "Buy and open") != null)


func test_the_tear_animation_ends_fully_torn_and_is_instant_when_reduced() -> void:
	var art := FcPackArt.new().setup({"name": "X", "cards_per_pack": 3, "odds": {}})
	assert_eq(art.tear_progress, 0.0)
	art.tear()
	assert_eq(art.tear_progress, 1.0, "outside a tree the end state is immediate")
	art.free()


# --- reveal: order, skipping, integrity ---------------------------------------------------------------------------------------

func test_cards_are_revealed_in_the_order_they_were_rolled() -> void:
	var reveal := _reveal(["common", "rare", "common", "epic"])
	assert_eq(reveal.stage, FcPackReveal.Stage.REVEALING)
	assert_true("Card 1 of 4. Click the card to reveal it." in reveal.status.text)
	for i in 4:
		reveal.reveal_next()
	assert_eq(reveal.effects_log.map(func(e: Dictionary) -> String: return e["card_id"]), ["card_0", "card_1", "card_2", "card_3"], "the rolled order, never reordered")
	assert_eq(reveal.stage, FcPackReveal.Stage.SUMMARY, "the summary follows the last card")
	reveal.reveal_next()
	assert_eq(reveal.effects_log.size(), 4, "extra clicks do nothing")
	reveal.free()


func test_skipping_gives_exactly_the_same_result_as_watching() -> void:
	var watched := _reveal(["common", "rare", "legendary", "uncommon", "common"], [true, false, true, true, false])
	for i in 5:
		watched.reveal_next()
	var skipped := _reveal(["common", "rare", "legendary", "uncommon", "common"], [true, false, true, true, false])
	skipped.reveal_all()
	assert_eq(skipped.effects_log.map(func(e: Dictionary) -> String: return e["card_id"]), watched.effects_log.map(func(e: Dictionary) -> String: return e["card_id"]), "the same cards in the same order")
	assert_eq(skipped.status.text, watched.status.text, "the same summary")
	assert_eq(skipped.stage, FcPackReveal.Stage.SUMMARY)
	var skipped_faces := _find(skipped, FcCardFace).map(func(c: FcCardFace) -> String: return c.row["card_id"])
	var watched_faces := _find(watched, FcCardFace).map(func(c: FcCardFace) -> String: return c.row["card_id"])
	assert_eq(skipped_faces, watched_faces)
	watched.free()
	skipped.free()


func test_skipping_part_way_finishes_the_rest() -> void:
	var reveal := _reveal(["common", "common", "rare"])
	reveal.reveal_next()
	reveal.reveal_all()
	assert_eq(reveal.effects_log.size(), 3)
	assert_eq(reveal.stage, FcPackReveal.Stage.SUMMARY)
	reveal.free()


func test_the_reveal_only_reads_and_the_only_action_is_done() -> void:
	var calls := {}
	var reveal := _reveal(["common", "rare", "epic"], [], calls)
	assert_eq(calls.get("rows"), 3, "each card is looked up once")
	reveal.reveal_all()
	assert_true(not calls.has("done"), "nothing is acknowledged by watching or skipping")
	_find_button(reveal, "Done").pressed.emit()
	_find_button(reveal, "Done").pressed.emit()
	assert_eq(calls.get("done"), 1, "Done acknowledges exactly once, even if pressed twice")
	reveal.free()


func test_the_opening_record_is_never_modified_by_presenting_it() -> void:
	var reveal := _reveal(["common", "rare", "legendary"])
	var before := reveal.opening.duplicate(true)
	reveal.reveal_next()
	reveal.reveal_all()
	assert_eq(reveal.opening, before, "the committed result is untouched")
	reveal.free()


func test_a_real_reveal_leaves_the_saved_profile_untouched_until_done() -> void:
	_dynasty_app()
	var ctl := app.dynasty
	var bought := ctl.buy_pack("bronze_pack")
	assert_true(bought.ok)
	var snapshot := ctl.profile().to_dict()
	var order: Array = bought.data["opening"]["cards"].map(func(e: Dictionary) -> String: return e["card_id"])
	app.dynasty_ui.show_tab("packs")
	FcDynastyScreensPacks.show_reveal(app.dynasty_ui, bought.data["opening"])
	var reveal: FcPackReveal = _find(app._root, FcPackReveal)[0]
	assert_true("Click the card" in reveal.status.text)
	reveal.reveal_next()
	assert_true(ctl.profile().to_dict() == snapshot, "revealing a card changes nothing in the profile")
	_find_button(reveal, "Skip animation").pressed.emit()
	assert_true(ctl.profile().to_dict() == snapshot, "skipping changes nothing either")
	assert_eq(reveal.effects_log.map(func(e: Dictionary) -> String: return e["card_id"]), order, "the order the pack was rolled in")
	assert_eq(ctl.pending_openings().size(), 1, "the opening is still pending until Done")
	_find_button(reveal, "Done").pressed.emit()
	assert_true(ctl.pending_openings().is_empty(), "Done acknowledges it")
	var after := ctl.profile().to_dict()
	for key in ["balances", "cards", "ledger", "pity", "rng_seed", "txn_counter", "roster"]:
		assert_eq(after[key], snapshot[key], "%s is exactly as the pack purchase left it" % key)


# --- effects, summary, duplicates ----------------------------------------------------------------------------------------------

func test_effect_strength_follows_rarity() -> void:
	var reveal := _reveal(["common", "uncommon", "rare", "epic", "legendary", "future_rarity"])
	reveal.reveal_all()
	var levels: Array = reveal.effects_log.map(func(e: Dictionary) -> int: return e["intensity"])
	assert_eq(levels, [0, 1, 2, 3, 4, 0], "common is plain, legendary is the biggest, an unknown rarity is quiet")
	reveal.free()


func test_a_skipped_or_untreed_reveal_is_quiet() -> void:
	var reveal := _reveal(["legendary"])
	reveal.reveal_next()
	assert_true(reveal.effects_log[0]["quiet"], "no particles, flash or shake without a live tree or when skipped")
	reveal.free()


func test_the_summary_lists_the_best_pull_first_and_keeps_ties_in_rolled_order() -> void:
	var reveal := _reveal(["common", "rare", "legendary", "epic", "rare"])
	reveal.reveal_all()
	var ids: Array = _find(reveal, FcCardFace).map(func(c: FcCardFace) -> String: return c.row["card_id"])
	assert_eq(ids, ["card_2", "card_3", "card_1", "card_4", "card_0"], "legendary, epic, then the two rares in rolled order, then common")
	assert_true((_find(reveal, FcCardFace)[0] as FcCardFace).inspected, "the best pull is highlighted")
	reveal.free()


func test_duplicates_are_marked_and_show_what_they_are_worth() -> void:
	var calls := {}
	var reveal := _reveal(["common", "rare", "common"], [true, false, false], calls)
	reveal.reveal_all()
	var faces := _find(reveal, FcCardFace)
	var by_id := {}
	for f in faces:
		by_id[f.row["card_id"]] = f
	assert_eq(by_id["card_0"].tag, "NEW")
	assert_eq(by_id["card_1"].tag, "DUPLICATE")
	assert_eq(by_id["card_1"].caption, "worth 20 shards", "a rare duplicate")
	assert_eq(by_id["card_2"].caption, "worth 5 shards", "a common duplicate")
	assert_eq(by_id["card_0"].caption, "", "a new card shows no value")
	assert_true("1 new card, 2 duplicates." in reveal.status.text, reveal.status.text)
	reveal.free()


func test_the_summary_text_handles_one_and_many() -> void:
	var one := _reveal(["common"], [false])
	one.reveal_all()
	assert_true("0 new cards, 1 duplicate." in one.status.text, one.status.text)
	var many := _reveal(["common", "common", "common"], [true, true, true])
	many.reveal_all()
	assert_true("3 new cards, 0 duplicates." in many.status.text, many.status.text)
	one.free()
	many.free()


func test_the_collection_update_shows_where_it_was_and_where_it_is() -> void:
	var calls := {}
	var reveal := _reveal(["common", "rare"], [true, true], calls)
	reveal.reveal_all()
	assert_eq(calls.get("progress"), 1)
	var texts := ""
	for l in _find(reveal, Label):
		texts += (l as Label).text + "\n"
	assert_true("Collection: 12 of 32 cards  (2 new)" in texts, texts)
	var bar: FcProgress = _find(reveal, FcProgress)[0]
	assert_eq(bar.value, 12.0, "outside a live tree the bar shows the final value")
	reveal.free()


func test_an_empty_pack_does_not_break_the_reveal() -> void:
	var reveal := _reveal([])
	reveal.reveal_all()
	assert_eq(reveal.stage, FcPackReveal.Stage.SUMMARY)
	assert_true("0 new cards, 0 duplicates." in reveal.status.text)
	reveal.free()
