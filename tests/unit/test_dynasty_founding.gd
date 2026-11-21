extends FcTestCase
## The bundled Founding Series release (D-055) is the first complete, playable Dynasty content. These tests load it the way a fresh
## install does (empty content folder -> bundled release) and check the promises of the content milestone: a legal starting five, a
## sensible rating spread, published odds and guarantees, a working starter collection, challenges, market, a season and tournaments.
## The long end-to-end run (packs, games, tournaments, save and reload) is tools/dynasty_initial_check.gd.

const DIR := "user://test_dynasty_founding"

var ctl: FcDynastyController


func before_each() -> void:
	FcSafeFile.remove_tree(DIR)
	var defs := FcDefinitionSet.load_default()
	var prefs := FcPreferences.new(DIR.path_join("prefs.cfg"))
	prefs.content_root = DIR.path_join("content")
	var service := FcContentService.new(prefs, defs)
	ctl = FcDynastyController.new(service, defs, FcDynastyStore.new(DIR.path_join("profiles")))


func after_each() -> void:
	FcSafeFile.remove_tree(DIR)


func test_a_fresh_install_loads_a_playable_release() -> void:
	assert_true(ctl.content.report.used_starter and ctl.content.report.has_content(), "the bundled release loads")
	assert_true(ctl.catalog.is_playable(), "playable: %s" % ctl.catalog.lineup_problem())
	assert_true(ctl.catalog.distinct_players() >= 13, "at least 13 players")
	assert_eq(ctl.catalog.distinct_players(), 40, "forty original players")


func test_the_pool_has_every_position_every_rarity_and_a_spread_of_ratings() -> void:
	var by_pos := {}
	var by_rarity := {}
	for id in ctl.catalog.card_ids():
		var v := ctl.catalog.view(id)
		by_pos[v["position"]] = int(by_pos.get(v["position"], 0)) + 1
		by_rarity[v["rarity"]] = int(by_rarity.get(v["rarity"], 0)) + 1
	for pos in FcDynastyContentRules.STARTER_POSITIONS:
		assert_true(int(by_pos.get(pos, 0)) >= 6, "%s has at least six cards" % pos)
	for r in FcDynastyContentRules.RARITY_ORDER:
		assert_true(int(by_rarity.get(r, 0)) >= 3, "%s has at least three cards" % r)
	# a higher rarity is stronger on average and the legendary tier clearly tops the common one
	var mean := {}
	for r in by_rarity:
		var sum := 0
		for id in ctl.catalog.card_ids():
			if ctl.catalog.view(id)["rarity"] == r:
				sum += int(ctl.catalog.view(id)["overall"])
		mean[r] = sum / int(by_rarity[r])
	var order := FcDynastyContentRules.RARITY_ORDER
	for i in range(1, order.size()):
		assert_true(mean[order[i]] > mean[order[i - 1]], "%s averages higher than %s" % [order[i], order[i - 1]])
	assert_true(mean["legendary"] - mean["common"] >= 25, "legendary is far above common")


func test_a_new_profile_gets_the_starter_collection_and_a_legal_lineup() -> void:
	assert_true(ctl.create_profile("Founders", "FND", "f58c29", 4242).ok)
	assert_eq(ctl.profile().unique_owned(), 15, "fifteen starter cards")
	assert_true(ctl.lineup_problems().is_empty(), "the lineup is legal: %s" % str(ctl.lineup_problems()))
	assert_eq(ctl.profile().balance("credits"), 2000)
	var roster := ctl.roster_view()
	var filled := 0
	for row in roster:
		if not row["card"].is_empty():
			filled += 1
	assert_eq(filled, 13, "a full 13-player roster: five starters, seven bench, one reserve")


func test_pack_odds_guarantees_and_pity_are_published_and_valid() -> void:
	assert_true(ctl.create_profile("Founders", "FND", "f58c29", 7).ok)
	var by_id := {}
	for row in ctl.pack_listing():
		by_id[row["pack_id"]] = row
	for id in ["rookie_pack", "pro_pack", "elite_pack", "reward_pack"]:
		assert_true(by_id.has(id), "%s is on sale" % id)
		var total := 0
		for r in by_id[id]["odds"]:
			total += int(by_id[id]["odds"][r])
		assert_eq(total, FcDynastyContentRules.ODDS_TOTAL, "%s odds add up to 10000" % id)
	assert_true(not by_id["elite_pack"]["guarantees"].is_empty() and not by_id["elite_pack"]["pity"].is_empty(), "the elite pack has a guarantee and pity")
	# the guarantee holds over many rolls: an Elite Pack always carries two rare-or-better cards
	for s in 200:
		var roll := FcDynastyPacks.roll(ctl.catalog, "elite_pack", FcRng.new(s), 0)
		var good := 0
		for cid in roll["cards"]:
			if FcDynastyContentRules.rarity_rank(str(ctl.catalog.view(cid)["rarity"])) >= 2:
				good += 1
		assert_true(good >= 2, "seed %d: the Elite Pack guarantee gives two rare-or-better cards" % s)
	# pity: the pack that is due (the 5th without an epic) always holds an epic or better
	for s in 200:
		var due := FcDynastyPacks.roll(ctl.catalog, "elite_pack", FcRng.new(1000 + s), 4)
		var best := 0
		for cid in due["cards"]:
			best = maxi(best, FcDynastyContentRules.rarity_rank(str(ctl.catalog.view(cid)["rarity"])))
		assert_true(best >= 3, "seed %d: a pack that is due for pity holds an epic or better" % s)


func test_challenges_market_season_and_tournaments_are_all_present() -> void:
	assert_true(ctl.catalog.challenges().size() >= 12, "challenges: %d" % ctl.catalog.challenges().size())
	var categories := {}
	for id in ctl.catalog.challenges():
		categories[ctl.catalog.challenges()[id]["category"]] = true
	for c in FcDynastyContentRules.CHALLENGE_CATEGORIES:
		assert_true(categories.has(c), "a %s challenge exists" % c)
	assert_true(ctl.catalog.market_card_ids().size() >= 20, "the market sells cards")
	for id in ctl.catalog.market_card_ids():
		assert_true(FcDynastyContentRules.rarity_rank(str(ctl.catalog.view(id)["rarity"])) <= 2, "%s: only common to rare cards are sold directly" % id)
	assert_eq(ctl.catalog.active_season_id(), "founding_season")
	assert_eq((ctl.catalog.season("founding_season")["tournaments"] as Array).size(), 2, "two tournaments")


func test_a_short_session_plays_claims_and_survives_a_reload() -> void:
	assert_true(ctl.create_profile("Founders", "FND", "f58c29", 99).ok)
	for i in 6:
		assert_true(ctl.play_quick_game("easy").ok, "game %d" % i)
	var claimed := 0
	for row in ctl.challenge_listing():
		if row["completed"] and not row["claimed"] and ctl.claim_challenge(row["id"]).ok:
			claimed += 1
	assert_true(claimed > 0, "at least one challenge was claimed after six games")
	var slot: String = ctl.session.slot
	var credits := ctl.profile().balance("credits")
	ctl.close_profile()
	assert_true(ctl.open_profile(slot).ok, "reopens")
	assert_eq(ctl.profile().balance("credits"), credits, "the balance survived the reload")
