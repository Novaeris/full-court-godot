extends FcTestCase
## Packs (odds, guarantees, pity, determinism, safety), direct acquisition and duplicate handling.

var env: FcDynastyEnv


func before_each() -> void:
	env = FcDynastyEnv.make()


func after_each() -> void:
	FcDynastyEnv.cleanup()


func _buy(pack_id: String, request: String) -> FcDynastyResult:
	return env.session.commit(func() -> FcDynastyResult:
		return FcDynastyPacks.buy_and_open(env.session.profile, env.catalog, pack_id, request))


func test_rolls_are_deterministic_for_a_fixed_seed() -> void:
	var a := FcDynastyPacks.roll(env.catalog, "bronze_pack", FcRng.new(11), 0)
	var b := FcDynastyPacks.roll(env.catalog, "bronze_pack", FcRng.new(11), 0)
	var c := FcDynastyPacks.roll(env.catalog, "bronze_pack", FcRng.new(12), 0)
	assert_eq(a, b, "same seed, same cards")
	assert_eq(a["cards"].size(), 3, "cards_per_pack")
	var different := false
	for s in range(12, 40):
		if FcDynastyPacks.roll(env.catalog, "bronze_pack", FcRng.new(s), 0)["cards"] != a["cards"]:
			different = true
	assert_true(different, "other seeds give other packs")
	assert_true(c["cards"].size() == 3, "any seed fills the pack")


func test_guarantees_always_hold_and_odds_are_respected() -> void:
	var counts := {"common": 0, "uncommon": 0, "rare": 0, "epic": 0, "legendary": 0}
	var total := 0
	for s in 400:
		var cards: Array = FcDynastyPacks.roll(env.catalog, "bronze_pack", FcRng.new(1000 + s), 0)["cards"]
		var best := 0
		for id in cards:
			var rarity: String = env.catalog.view(id)["rarity"]
			counts[rarity] += 1
			total += 1
			best = maxi(best, FcDynastyContentRules.rarity_rank(rarity))
		assert_true(best >= 1, "bronze pack %d has at least an uncommon" % s)
	assert_true(counts["common"] > counts["uncommon"] and counts["uncommon"] > counts["rare"], "published odds shape the results: %s" % str(counts))
	assert_true(counts["rare"] > 0, "rarer cards do appear")
	for s in 200:
		var rares := 0
		for id in FcDynastyPacks.roll(env.catalog, "elite_pack", FcRng.new(5000 + s), 0)["cards"]:
			if FcDynastyContentRules.rarity_rank(env.catalog.view(id)["rarity"]) >= 2:
				rares += 1
		assert_true(rares >= 2, "elite pack guarantees two rares")


func test_pity_forces_an_epic_after_enough_misses_and_resets() -> void:
	# pity after 4 packs: the 4th pack (counter 3) must contain an epic or better
	for s in 60:
		var out := FcDynastyPacks.roll(env.catalog, "elite_pack", FcRng.new(9000 + s), 3)
		var hit := false
		for id in out["cards"]:
			if FcDynastyContentRules.rarity_rank(env.catalog.view(id)["rarity"]) >= 3:
				hit = true
		assert_true(hit and out["pity"] == 0, "pity pack %d delivers an epic and resets the counter" % s)
	var miss := FcDynastyPacks.roll(env.catalog, "elite_pack", FcRng.new(1), 0)
	assert_true(miss["pity"] in [0, 1], "the counter grows by one on a miss, or resets on a natural hit")


func test_reveal_order_puts_the_best_card_last() -> void:
	for s in 50:
		var cards: Array = FcDynastyPacks.roll(env.catalog, "elite_pack", FcRng.new(300 + s), 0)["cards"]
		var ranks: Array = cards.map(func(id): return FcDynastyContentRules.rarity_rank(env.catalog.view(id)["rarity"]))
		var sorted := ranks.duplicate()
		sorted.sort()
		assert_eq(ranks, sorted, "cards are revealed from lowest to highest rarity")


func test_buying_a_pack_pays_delivers_and_records() -> void:
	var before_credits := env.profile().balance("credits")
	var before_cards := 0
	for id in env.profile().cards:
		before_cards += env.profile().quantity_of(str(id))
	var r := _buy("bronze_pack", "req_a")
	assert_true(r.ok, "bought: %s" % r.message)
	var p := env.profile()
	assert_eq(p.balance("credits"), before_credits - 500, "price paid from published content")
	var after_cards := 0
	for id in p.cards:
		after_cards += p.quantity_of(str(id))
	assert_eq(after_cards, before_cards + 3, "the three cards are in the collection")
	var opening: Dictionary = r.data["opening"]
	assert_eq(opening["cards"].size(), 3, "a record of what was awarded")
	assert_true(not opening["revealed"], "stored before it is revealed")
	assert_eq(p.pack_openings.size(), 1, "persisted record")
	var saved: FcDynastyProfile = env.store.load_slot("env").data["profile"]
	assert_eq(saved.pack_openings.size(), 1, "the opening survives a reload (an interrupted animation can resume)")
	assert_eq(FcDynastyPacks.pending_openings(saved).size(), 1, "shows up as unrevealed")
	var ack := env.session.commit(func() -> FcDynastyResult: return FcDynastyPacks.acknowledge(env.session.profile, opening["opening_id"]))
	assert_true(ack.ok and FcDynastyPacks.pending_openings(env.profile()).is_empty(), "acknowledged")


func test_the_same_request_never_pays_or_grants_twice() -> void:
	var first := _buy("bronze_pack", "req_dup")
	var credits := env.profile().balance("credits")
	var again := _buy("bronze_pack", "req_dup")
	assert_true(again.ok and again.data.get("repeated", false), "the repeat is recognised")
	assert_eq(again.data["opening"]["opening_id"], first.data["opening"]["opening_id"], "same opening returned")
	assert_eq(env.profile().balance("credits"), credits, "no second payment")
	assert_eq(env.profile().pack_openings.size(), 1, "no second record")


func test_cannot_buy_without_funds_and_nothing_is_consumed() -> void:
	var r := _buy("elite_pack", "req_poor")  # 5 tokens; the starter gives exactly 5, so spend them first
	assert_true(r.ok, "starter tokens buy one elite pack")
	var poor := _buy("elite_pack", "req_poor2")
	assert_eq(poor.code, "insufficient_funds", "refused")
	assert_eq(env.profile().balance("tokens"), 0, "no negative balance")
	assert_eq(env.profile().pack_openings.size(), 1, "no pack was created")
	assert_eq(_buy("starter_pack", "req_x").code, "not_for_sale", "a pack without a price cannot be bought")
	assert_eq(_buy("nope", "req_y").code, "unknown_pack", "unknown pack")


func test_a_failed_save_loses_nothing_and_grants_nothing() -> void:
	var broken_store := FcDynastyStore.new("user://test_dynasty_play/x")
	var s := FcDynastySession.new(env.profile(), broken_store, "bad slot!")
	var credits := s.profile.balance("credits")
	var cards := s.profile.unique_owned()
	var r := s.commit(func() -> FcDynastyResult: return FcDynastyPacks.buy_and_open(s.profile, env.catalog, "bronze_pack", "r"))
	assert_eq(r.code, "save_failed", "the failure is reported")
	assert_eq(s.profile.balance("credits"), credits, "currency untouched")
	assert_eq(s.profile.unique_owned(), cards, "no cards granted")
	assert_eq(s.profile.pack_openings.size(), 0, "no ghost opening")


func test_reward_packs_are_free_and_recorded() -> void:
	var r := env.session.commit(func() -> FcDynastyResult:
		return FcDynastyRewards.grant(env.session.profile, env.catalog, {"credits": 10, "pack_ids": ["free_pack"]}, "test", "ref", "rq"))
	assert_true(r.ok and r.data["openings"].size() == 1, "reward pack opened")
	assert_eq(env.profile().balance("credits"), 2010, "credits from the same bundle")


func test_direct_acquisition_uses_published_prices() -> void:
	var card := FcDynastyFixture.card_id(20)  # priced 1000 credits
	var before := env.profile().balance("credits")
	var r := env.session.commit(func() -> FcDynastyResult: return FcDynastyMarket.acquire(env.session.profile, env.catalog, card, "acq1"))
	assert_true(r.ok, "bought")
	assert_eq(env.profile().balance("credits"), before - 1000, "published price")
	assert_eq(env.profile().quantity_of(card), 1, "card owned")
	var again := env.session.commit(func() -> FcDynastyResult: return FcDynastyMarket.acquire(env.session.profile, env.catalog, card, "acq1"))
	assert_true(again.data.get("repeated", false) and env.profile().quantity_of(card) == 1, "a repeated request grants nothing")
	var unpriced := env.session.commit(func() -> FcDynastyResult: return FcDynastyMarket.acquire(env.session.profile, env.catalog, FcDynastyFixture.card_id(1), "acq2"))
	assert_eq(unpriced.code, "not_for_sale", "no price, no sale")
	env.session.commit(func() -> FcDynastyResult: return FcDynastyEconomy.spend(env.session.profile, "t", "t", {"credits": env.profile().balance("credits")}))
	var broke := env.session.commit(func() -> FcDynastyResult: return FcDynastyMarket.acquire(env.session.profile, env.catalog, FcDynastyFixture.card_id(21), "acq3"))
	assert_eq(broke.code, "insufficient_funds", "cannot afford")


func test_duplicates_convert_or_master_without_touching_ratings() -> void:
	var card := FcDynastyFixture.card_id(2)
	var before_view := env.catalog.view(card).duplicate(true)
	env.give(card)
	assert_eq(env.profile().quantity_of(card), 2, "a duplicate")
	var conv := env.session.commit(func() -> FcDynastyResult:
		return FcDynastyCollection.convert_duplicate(env.session.profile, env.catalog.config, card, env.catalog.view(card)["rarity"], "c1"))
	assert_true(conv.ok and env.profile().balance("shards") == env.catalog.config.shards_for("common"), "shards paid per the card's rarity")
	env.give(card)
	env.fund("shards", 100)
	var m := env.session.commit(func() -> FcDynastyResult: return FcDynastyCollection.apply_mastery(env.session.profile, env.catalog.config, card, "m1"))
	assert_true(m.ok, "mastery applied")
	assert_eq(env.catalog.view(card), before_view, "the card's overall, attributes and badges are unchanged: mastery is cosmetic")
	assert_eq(env.catalog.config.mastery_frame(1), "bronze", "frame comes from config")


func test_collection_challenge_reacts_to_pack_rewards() -> void:
	# starter 15 + packs; the collector challenge needs 20 distinct cards
	env.fund("credits", 20000)
	var guard := 0
	while env.profile().unique_owned() < 20 and guard < 30:
		guard += 1
		env.session.commit(func() -> FcDynastyResult:
			var r := FcDynastyPacks.buy_and_open(env.session.profile, env.catalog, "bronze_pack", "loop_%d" % guard)
			if r.ok:
				FcDynastyMarket.collection_changed(env.session.profile, env.catalog)
			return r)
	var state := FcDynastyChallenges.state_of(env.profile(), "collector")
	assert_true(state["done"], "owning 20 different cards completes the collection challenge")
