extends FcTestCase
## Dynasty content integration: schema extensions are validated, cards become views, editions stay separate,
## owned cards survive release changes, empty content is handled.

var catalog: FcDynastyCatalog


func before_each() -> void:
	FcDynastyFixture.wipe()
	catalog = FcDynastyFixture.catalog()


func after_each() -> void:
	FcDynastyFixture.wipe()


func _problems_for(mutate: Callable) -> Array[String]:
	var dir := FcDynastyFixture.ROOT.path_join("mut")
	FcSafeFile.remove_tree(dir)
	FcDynastyFixture.write_content(dir)
	mutate.call(dir)
	return FcContentValidator.draft_problems(dir, FcDefinitionSet.load_default())


func _edit(dir: String, rel: String, key: String, value: Variant) -> void:
	var d: Dictionary = FcSafeFile.read_json_object(dir.path_join(rel))
	if value == null:
		d.erase(key)
	else:
		d[key] = value
	FcSafeFile.write_text(dir.path_join(rel), JSON.stringify(d, "\t", true))


func test_fixture_release_validates_and_loads() -> void:
	assert_true(catalog != null, "the fixture release is valid under the extended rules")
	assert_eq(catalog.card_ids().size(), 32, "30 base cards + 2 extra editions")
	assert_true(catalog.is_playable(), "enough cards and players to field a team")
	assert_eq(catalog.release_id(), "fcr_0123456789abcdef", "release id exposed")
	assert_eq(catalog.active_season_id(), "season_one", "the active season is found")


func test_multiple_editions_of_one_player_stay_separate() -> void:
	var base := catalog.view(FcDynastyFixture.card_id(3))
	var star := catalog.view(FcDynastyFixture.card_id(3, "allstar"))
	assert_eq(base["player_id"], star["player_id"], "same fictional player")
	assert_true(star["overall"] > base["overall"] + 15, "the edition has its own rating")
	assert_eq(star["edition"], "All-Star Edition", "edition name")
	assert_true(base["card_id"] != star["card_id"], "different card ids")


func test_card_view_carries_what_the_simulation_uses() -> void:
	var v := catalog.view(FcDynastyFixture.card_id(0))
	assert_eq(v["attributes"].size(), 28, "all 28 attributes")
	assert_eq(v["badges"], ["catch_and_shoot"], "badges published on the player")
	assert_eq(v["secondary"], "SG", "secondary position")
	assert_eq(v["position"], "PG", "position")
	assert_eq(int(catalog.composite_bonus(FcDynastyFixture.card_id(0)).get("three", 0)), 2, "badge bonus uses the Career rules")
	var p := catalog.make_player(FcDynastyFixture.card_id(0), 7)
	assert_eq(p.attributes.get_value("three_point"), FcDynastyFixture.base_of(0), "attributes copied exactly")
	assert_eq(roundi(FcPlayerRatings.load_default().overall(p)), v["overall"], "overall is the simulation's own rating")


func test_market_and_pack_listings_come_from_content() -> void:
	assert_eq(catalog.market_card_ids().size(), 15, "only priced cards are for sale")
	assert_eq(catalog.buyable_packs(), ["bronze_pack", "elite_pack", "free_pack"], "packs with a published price")
	assert_eq(catalog.view(FcDynastyFixture.card_id(0))["acquirable"], false, "no price, no direct purchase")


func test_invalid_definitions_are_rejected() -> void:
	var odds := _problems_for(func(d): _edit(d, "packs/bronze_pack.json", "odds", {"common": 5000, "rare": 1000}))
	assert_true(str(odds).contains("add up to"), "odds must total 10000: %s" % str(odds))
	var missing := _problems_for(func(d): _edit(d, "packs/elite_pack.json", "odds", {"uncommon": 5000, "rare": 4000, "epic": 900, "legendary": 100, "common": 0}))
	assert_true(missing.is_empty(), "valid odds pass")
	var feature := _problems_for(func(d): _edit(d, "packs/bronze_pack.json", "requires_features", []))
	assert_true(str(feature).contains("pack_odds_v1"), "price/odds need the feature declared")
	var price := _problems_for(func(d): _edit(d, "cards/test_zephyr_base.json", "price", {"currency": "gold", "amount": 5}))
	assert_true(str(price).contains("price must be"), "bad currency")
	var badge := _problems_for(func(d): _edit(d, "players/test_alpha.json", "badges", ["not_a_badge"]))
	assert_true(str(badge).contains("unknown badge"), "unknown badge")
	var challenge := _problems_for(func(d): _edit(d, "challenges/score_100.json", "objective", {"type": "stat", "stat": "dunks", "target": 3}))
	assert_true(str(challenge).contains("objective.stat"), "unknown stat")
	var reward := _problems_for(func(d): _edit(d, "challenges/score_100.json", "rewards", {"card_ids": ["nobody"]}))
	assert_true(str(reward).contains("not a card"), "reward card must exist")
	var teams := _problems_for(func(d):
		var s: Dictionary = FcSafeFile.read_json_object(d.path_join("seasonal/season_one.json"))
		s["tournaments"][0]["teams"].pop_back()
		FcSafeFile.write_text(d.path_join("seasonal/season_one.json"), JSON.stringify(s, "\t", true)))
	assert_true(str(teams).contains("exactly 7"), "a tournament needs seven opponents")
	var pity := _problems_for(func(d): _edit(d, "packs/elite_pack.json", "pity", {"rarity": "epic", "after": 0}))
	assert_true(str(pity).contains("pity"), "pity needs a positive count")
	var unsupported := _problems_for(func(d): _edit(d, "challenges/triples.json", "requires_features", ["challenge_v1", "time_travel_v9"]))
	assert_true(str(unsupported).contains("unsupported feature"), "unknown features fail closed")


func test_missing_artwork_gives_an_empty_path_not_an_error() -> void:
	assert_eq(catalog.view(FcDynastyFixture.card_id(0))["art_path"], "", "no art published: empty path for the polished fallback")


func test_unavailable_owned_cards_show_placeholders_and_are_kept() -> void:
	var p := FcDynastyProfile.create("T", "TT", 1, "fcr_a")
	var card := FcDynastyFixture.card_id(4)
	FcDynastyCollection.grant_card(p, card, 1, catalog.snapshot_of(card), "tx_1")
	# a later release without that card
	var later := FcDynastyFixture.catalog(1, "fcr_1123456789abcdef")
	later._views.erase(card)
	var split := FcDynastyOnboarding.sync_release(p, later)
	assert_eq(split["unavailable"], 1, "the card is reported unavailable")
	assert_eq(p.quantity_of(card), 1, "ownership is kept")
	var ph := later.owned_view(card, p.cards[card])
	assert_true(not ph["available"] and ph["name"] == "Test Ember", "a placeholder built from the remembered identity")
	assert_eq(p.release_history, ["fcr_a", "fcr_1123456789abcdef"], "release provenance is recorded")
	assert_eq(p.cards[card]["snapshot"]["title"], "Test Ember", "history is not rewritten")


func test_changed_revision_is_flagged_not_silently_applied() -> void:
	var p := FcDynastyProfile.create("T", "TT", 1, "fcr_a")
	var card := FcDynastyFixture.card_id(5)
	FcDynastyCollection.grant_card(p, card, 1, catalog.snapshot_of(card), "tx_1")
	catalog._views[card]["revision"] = 2
	assert_eq(FcDynastyOnboarding.sync_release(p, catalog)["changed"], 1, "a newer revision is reported")
	assert_true(catalog.owned_view(card, p.cards[card])["revision_changed"], "the view says the definition changed")
	assert_eq(int(p.cards[card]["revision"]), 1, "the owned record keeps the revision it was obtained at")


func test_starter_collection_comes_from_published_config() -> void:
	var p := FcDynastyProfile.create("T", "TT", 1, catalog.release_id())
	var r := FcDynastyOnboarding.grant_starter(p, catalog)
	assert_true(r.ok, "starter granted")
	assert_eq(p.unique_owned(), 15, "the published starter pack's cards")
	assert_eq(p.balance("credits"), 2000, "published starting credits")
	assert_eq(p.balance("tokens"), 5, "published starting tokens")
	var again := FcDynastyOnboarding.grant_starter(p, catalog)
	assert_true(again.ok and again.data.get("repeated", false) and p.unique_owned() == 15 and p.balance("credits") == 2000, "granting twice changes nothing")


func test_empty_release_gets_an_onboarding_message() -> void:
	var empty := FcDynastyCatalog.build(FcContentCatalog.new(), FcDefinitionSet.load_default())
	assert_true(not empty.is_playable(), "no cards, not playable")
	assert_true(empty.playable_problem().contains("no player cards"), "the message says what to do")
	var none := FcDynastyCatalog.build(null, FcDefinitionSet.load_default())
	assert_true(none.playable_problem() != "", "no catalog at all is also explained")
