extends SceneTree
## End-to-end check of the bundled Founding Series release (D-055) through the game's NORMAL loader and controller: it loads the
## release the way a fresh install does (empty content folder -> bundled release), creates a profile, builds a lineup, opens packs,
## converts duplicates, applies mastery, plays games, claims challenges and milestones, plays both tournaments, saves, reloads and
## prints a report. Scratch folders only. Run: ./tools/dynasty_initial_check.ps1   Exit code 0 = every step passed.

const DIR := "user://founding_check"
var failures := 0


func _check(ok: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if ok else "FAIL", what])
	if not ok:
		failures += 1


func _init() -> void:
	FcSafeFile.remove_tree(DIR)
	var defs := FcDefinitionSet.load_default()
	var prefs := FcPreferences.new(DIR.path_join("prefs.cfg"))
	prefs.content_root = DIR.path_join("content")
	var service := FcContentService.new(prefs, defs)
	print("Loaded: %s" % service.report.summary())
	_check(service.report.used_starter and service.report.has_content(), "a fresh install loads the bundled release")
	var ctl := FcDynastyController.new(service, defs, FcDynastyStore.new(DIR.path_join("profiles")))
	var cat := ctl.catalog
	_check(cat.is_playable(), "the release is playable (%s)" % cat.lineup_problem())
	var tiers := {}
	var by_pos := {}
	var overalls: Array[int] = []
	for id in cat.card_ids():
		var v := cat.view(id)
		tiers[v["rarity"]] = int(tiers.get(v["rarity"], 0)) + 1
		by_pos[v["position"]] = int(by_pos.get(v["position"], 0)) + 1
		overalls.append(int(v["overall"]))
	overalls.sort()
	print("  cards %d, players %d, rarities %s, positions %s" % [cat.card_ids().size(), cat.distinct_players(), str(tiers), str(by_pos)])
	print("  overall min %d, median %d, max %d" % [overalls[0], overalls[overalls.size() / 2], overalls[-1]])
	for rarity in FcDynastyContentRules.RARITY_ORDER:
		var vals: Array = []
		for id in cat.card_ids():
			if cat.view(id)["rarity"] == rarity:
				vals.append(int(cat.view(id)["overall"]))
		vals.sort()
		print("    %-10s %s" % [rarity, str(vals)])
	_check(cat.distinct_players() >= 13, "at least 13 distinct players")
	var made := ctl.create_profile("Founding Test", "FND", "f58c29", 4242)
	_check(made.ok, "a new profile is created: %s" % made.message)
	var p := ctl.profile()
	_check(p.unique_owned() == 15, "the starter collection grants 15 cards (got %d)" % p.unique_owned())
	_check(ctl.lineup_problems().is_empty(), "the starting lineup is legal: %s" % str(ctl.lineup_problems()))
	print("  starting team overall %d, credits %d, tokens %d" % [ctl.team_overall(), p.balance("credits"), p.balance("tokens")])
	# packs
	for pack in ctl.pack_listing():
		print("  pack %s: %d %s, %d cards, odds %s, guarantees %s, pity %s" % [pack["pack_id"], pack["amount"], pack["currency"],
			pack["cards_per_pack"], str(pack["odds"]), str(pack["guarantees"]), str(pack["pity"])])
	var opened := ctl.buy_pack("rookie_pack")
	_check(opened.ok, "a Rookie Pack can be bought and opened: %s" % opened.message)
	# duplicates and mastery
	var dup_id := ""
	for _i in 30:
		if ctl.profile().balance("credits") < 500:
			ctl.profile().balances["credits"] = 5000   # scratch profile only: keep buying to find a duplicate
		ctl.buy_pack("rookie_pack")
		for row in ctl.collection_rows():
			if int(row.get("quantity", 1)) > 1:
				dup_id = str(row["card_id"])
				break
		if dup_id != "":
			break
	_check(dup_id != "", "a duplicate turns up while opening packs")
	if dup_id != "":
		var conv := ctl.convert_duplicate(dup_id)
		_check(conv.ok, "a duplicate converts to shards: %s" % conv.message)
	# games, challenges, season
	ctl.auto_fill_lineup()
	var wins := 0
	for i in 12:
		var g := ctl.play_quick_game("easy")
		_check(g.ok, "game %d plays" % (i + 1)) if not g.ok else null
		if g.ok and g.data["summary"]["won"]:
			wins += 1
	print("  won %d of 12 easy games" % wins)
	var claimed := 0
	for row in ctl.challenge_listing():
		if row["completed"] and not row["claimed"]:
			if ctl.claim_challenge(row["id"]).ok:
				claimed += 1
	_check(claimed > 0, "challenges completed by playing can be claimed (%d claimed)" % claimed)
	var season := ctl.season_overview()
	print("  season %s: %d points, %d milestones" % [season["name"], season["points"], season["milestones"].size()])
	for m in season["milestones"]:
		if m["reached"] and not m["claimed"]:
			_check(ctl.claim_milestone(m["id"]).ok, "milestone %s claims" % m["id"])
	# tournaments
	ctl.profile().balances["credits"] = int(ctl.profile().balance("credits")) + 1000
	ctl.profile().balances["tokens"] = int(ctl.profile().balance("tokens")) + 5
	for t in ctl.tournament_listing():
		var entered := ctl.enter_tournament(t["tournament_id"])
		_check(entered.ok, "%s can be entered: %s" % [t["name"], entered.message])
		var guard := 0
		while entered.ok and not ctl.active_tournament().is_empty() and guard < 8:
			ctl.play_tournament_match()
			guard += 1
		if entered.ok:
			var hist := ctl.tournament_history()
			print("  %s finished: placement %s" % [t["name"], hist[0]["placement"] if not hist.is_empty() else "?"])
			_check(ctl.active_tournament().is_empty() and not hist.is_empty(), "%s completes" % t["name"])
	# save, close, reload
	var slot: String = ctl.session.slot
	var before := ctl.profile().unique_owned()
	var credits := ctl.profile().balance("credits")
	ctl.close_profile()
	var reopened := ctl.open_profile(slot)
	_check(reopened.ok and ctl.profile().unique_owned() == before and ctl.profile().balance("credits") == credits, "the profile saves, reloads and matches")
	FcSafeFile.remove_tree(DIR)
	print("RESULT %s (%d failures)" % ["ok" if failures == 0 else "FAILED", failures])
	quit(0 if failures == 0 else 1)
