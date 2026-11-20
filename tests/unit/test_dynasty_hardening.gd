extends FcTestCase
## Dynasty hardening (docs/DYNASTY_HARDENING.md): (1) save slots that exist only as a temp file or a backup are discoverable and
## recoverable; (2) a release is only playable if it can field a legal starting lineup, with ONE rule shared by the publish validator,
## the catalog and the automatic lineup; (3) the economy enforces request-level idempotency for every caller.

const DIR := "user://test_dynasty_hardening"

var store: FcDynastyStore


func before_each() -> void:
	FcSafeFile.remove_tree(DIR)
	FcDynastyFixture.wipe()
	store = FcDynastyStore.new(DIR)


func after_each() -> void:
	FcSafeFile.remove_tree(DIR)
	FcDynastyFixture.wipe()
	FcDynastyEnv.cleanup()


func _profile(credits: int = 0) -> FcDynastyProfile:
	var p := FcDynastyProfile.create("Harbor Kings", "hbk", 12345, "fcr_test")
	if credits > 0:
		FcDynastyEconomy.apply(p, "grant", "x", {"credits": credits})
	return p


func _path(slot: String, suffix: String = "") -> String:
	return DIR.path_join(slot + ".dyn" + suffix)


# =====================================================================================================================
# 1. save-slot discovery and recovery
# =====================================================================================================================

func test_a_slot_that_only_has_a_backup_is_listed_found_and_recovered() -> void:
	assert_true(store.save("slot_a", _profile(7)).ok)
	assert_true(store.save("slot_a", _profile(9)).ok, "the second save keeps the first as a backup")
	# a crash after the old file was rotated to .bak but before the new one was installed leaves only the backup
	DirAccess.remove_absolute(_path("slot_a"))
	assert_true(FileAccess.file_exists(_path("slot_a", ".bak")) and not FileAccess.file_exists(_path("slot_a")))
	assert_eq(store.list_slots(), ["slot_a"], "the profile picker can find it")
	assert_true(store.has_slot("slot_a"), "and has_slot agrees")
	var r := store.load_slot("slot_a")
	assert_true(r.ok, "it loads")
	assert_eq(r.data["recovered_from"], "backup")
	assert_eq(r.data["profile"].balance("credits"), 7, "with the previous good save")


func test_a_slot_that_only_has_a_temp_file_is_listed_found_and_recovered() -> void:
	assert_true(store.save("slot_t", _profile(5)).ok)
	# an interrupted first save: only the verified temp file exists
	assert_eq(DirAccess.rename_absolute(_path("slot_t"), _path("slot_t", ".tmp")), OK)
	assert_true(not FileAccess.file_exists(_path("slot_t")))
	assert_eq(store.list_slots(), ["slot_t"])
	assert_true(store.has_slot("slot_t"))
	var r := store.load_slot("slot_t")
	assert_true(r.ok and r.data["recovered_from"] == "temp", "recovered from the temp file")
	assert_eq(r.data["profile"].balance("credits"), 5)


func test_every_representation_of_one_slot_is_listed_once_and_the_list_is_sorted() -> void:
	assert_true(store.save("zeta", _profile(1)).ok)
	assert_true(store.save("zeta", _profile(2)).ok)   # zeta.dyn and zeta.dyn.bak
	FcSafeFile.write_text(_path("zeta", ".tmp"), "not a real temp file")   # and a third representation
	assert_true(store.save("alpha", _profile(3)).ok)
	assert_true(store.save("mid_slot", _profile(4)).ok)
	DirAccess.rename_absolute(_path("mid_slot"), _path("mid_slot", ".bak"))
	assert_eq(store.list_slots(), ["alpha", "mid_slot", "zeta"], "each slot once, in order")


func test_invalid_names_are_never_listed_or_found() -> void:
	for name in ["Bad Slot.dyn", "UPPER.dyn.bak", "has-dash.dyn.tmp", "with space.dyn.bak", "..dyn", ".dyn", "x" + "y".repeat(40) + ".dyn"]:
		FcSafeFile.write_text(DIR.path_join(name), "x")
	FcSafeFile.write_text(DIR.path_join("notes.txt"), "x")
	FcSafeFile.write_text(DIR.path_join("slot_ok.dyn.old"), "x")   # an unrelated suffix
	assert_eq(store.list_slots(), [], "none of these are Dynasty slots")
	assert_true(not store.has_slot("Bad Slot") and not store.has_slot("UPPER") and not store.has_slot(""), "has_slot refuses invalid names")
	assert_true(store.save("good_one", _profile()).ok)
	assert_eq(store.list_slots(), ["good_one"])


func test_discovery_never_deletes_or_changes_a_recoverable_file() -> void:
	assert_true(store.save("keep", _profile(3)).ok)
	assert_true(store.save("keep", _profile(4)).ok)
	FcSafeFile.write_text(_path("only_tmp", ".tmp"), "garbage that cannot be loaded")
	var before := {}
	for f in DirAccess.open(DIR).get_files():
		before[f] = FileAccess.get_file_as_string(DIR.path_join(f))
	store.list_slots()
	store.has_slot("keep")
	store.has_slot("only_tmp")
	var after := {}
	for f in DirAccess.open(DIR).get_files():
		after[f] = FileAccess.get_file_as_string(DIR.path_join(f))
	assert_eq(after, before, "listing and checking changed nothing on disk")


func test_a_listed_slot_that_is_not_loadable_reports_damage_instead_of_vanishing() -> void:
	FcSafeFile.write_text(_path("broken", ".bak"), "garbage")
	assert_eq(store.list_slots(), ["broken"], "it is visible so the player can see and delete it")
	assert_eq(store.load_slot("broken").code, "corrupt", "but loading says it is damaged (checksums are not weakened)")
	store.delete_slot("broken")
	assert_eq(store.list_slots(), [], "delete_slot removes every representation")


func test_the_saved_file_wins_over_a_temp_file_and_the_temp_over_the_backup() -> void:
	assert_true(store.save("order", _profile(1)).ok)
	assert_true(store.save("order", _profile(2)).ok)   # order.dyn (2) and order.dyn.bak (1)
	assert_eq(store.load_slot("order").data["recovered_from"], "", "the saved file is first")
	FcSafeFile.write_text(_path("order", ".tmp"), FileAccess.get_file_as_string(_path("order", ".bak")))
	DirAccess.remove_absolute(_path("order"))
	var r := store.load_slot("order")
	assert_eq(r.data["recovered_from"], "temp", "with no saved file the verified temp file comes before the backup")


func test_a_new_profile_never_takes_a_slot_that_still_has_a_recoverable_file() -> void:
	FcDynastyFixture.wipe()
	var content := FcContentService.new(FcPreferences.new("user://test_prefs_hardening.cfg"), FcDefinitionSet.load_default())
	var ctl := FcDynastyController.new(content, FcDefinitionSet.load_default(), store)
	ctl.catalog = FcDynastyFixture.catalog()
	# dynasty_1 survives only as a temp file, dynasty_2 only as a backup
	FcSafeFile.write_text(_path("dynasty_1", ".tmp"), "recoverable?")
	FcSafeFile.write_text(_path("dynasty_2", ".bak"), "recoverable?")
	var made := ctl.create_profile("New Kings", "NWK")
	assert_true(made.ok, made.message)
	assert_true(FileAccess.file_exists(_path("dynasty_3")), "the new profile went to dynasty_3")
	assert_eq(FileAccess.get_file_as_string(_path("dynasty_1", ".tmp")), "recoverable?", "the temp file was not overwritten")
	DirAccess.remove_absolute("user://test_prefs_hardening.cfg")


# =====================================================================================================================
# 2. can the release field a legal starting lineup?
# =====================================================================================================================

func _layout_all(primary: String, secondary: String = "") -> Array:
	var out: Array = []
	for i in FcDynastyFixture.PLAYER_COUNT:
		out.append([primary, secondary])
	return out


## 30 players; `special` maps a player index to [primary, secondary]; everyone else is a point guard.
func _layout(special: Dictionary) -> Array:
	var out := _layout_all("PG")
	for i in special:
		out[i] = special[i]
	return out


func _players(layout: Array) -> Array:
	var out: Array = []
	for i in layout.size():
		out.append({"player_id": "p%d" % i, "position": layout[i][0], "secondary": layout[i][1]})
	return out


func test_the_five_starter_positions_match_the_roster_slots() -> void:
	var from_roster: Array = []
	for pos_id in FcDynastyRoster.SLOT_POSITIONS:
		from_roster.append(FcPosition.abbreviation(pos_id))
	assert_eq(FcDynastyContentRules.STARTER_POSITIONS, from_roster, "the shared rule and the roster agree on the five slots")
	assert_eq(FcDynastyCatalog.MIN_PLAYABLE_CARDS, FcDynastyContentRules.MIN_PLAYABLE_PLAYERS)
	assert_eq(FcDynastyContentRules.MIN_PLAYABLE_PLAYERS, FcDynastyRoster.SIZE, "13 distinct players for 13 slots")


func test_rule_a_release_with_all_five_primary_positions_is_fine() -> void:
	var layout := _layout({0: ["SG", ""], 1: ["SF", ""], 2: ["PF", ""], 3: ["C", ""]})
	assert_eq(FcDynastyContentRules.lineup_problem(_players(layout)), "")
	var matched := FcDynastyContentRules.match_starters(_players(layout))
	assert_true(not matched.has(-1), "every slot is filled")
	assert_eq(matched.size(), 5)


func test_rule_secondary_positions_count() -> void:
	# nobody is a primary SF or PF, but two players list them as secondary positions
	var layout := _layout({0: ["SG", ""], 1: ["C", ""], 2: ["PG", "SF"], 3: ["SG", "PF"]})
	assert_eq(FcDynastyContentRules.lineup_problem(_players(layout)), "", "secondary positions can fill starter slots")
	var matched := FcDynastyContentRules.match_starters(_players(layout))
	assert_true(not matched.has(-1))
	assert_true(matched[2] in [2, 3] and matched[3] in [2, 3] and matched[2] != matched[3], "SF and PF went to the two secondary-position players")


func test_rule_thirteen_point_guards_cannot_field_a_team() -> void:
	var players := _players(_layout_all("PG")).slice(0, 13)
	var problem := FcDynastyContentRules.lineup_problem(players)
	assert_true(problem != "", "13 distinct players are not enough on their own")
	assert_true("SG" in problem and "SF" in problem and "PF" in problem and "C" in problem, "it names the positions nobody can fill: " + problem)
	assert_true("PG 13" in problem, "and says how many players can start at each position")
	assert_true("Add players" in problem, "and what to do about it")
	assert_eq(FcDynastyContentRules.match_starters(players).count(-1), 4, "only the PG slot can be filled")


func test_rule_a_release_missing_one_position_is_refused() -> void:
	var layout: Array = []
	for i in 20:
		layout.append([["PG", "SG", "SF", "PF"][i % 4], ""])   # nobody plays C
	var problem := FcDynastyContentRules.lineup_problem(_players(layout))
	assert_true(problem != "" and "nobody left for C" in problem, problem)
	assert_true("C 0" in problem)


func test_rule_one_player_cannot_fill_two_starter_slots() -> void:
	# the only SF and the only PF are the SAME player (SF/PF): one slot stays empty
	var layout := _layout({0: ["SF", "PF"], 1: ["SG", ""], 2: ["C", ""]})
	var problem := FcDynastyContentRules.lineup_problem(_players(layout))
	assert_true(problem != "", "a player cannot start twice")
	assert_true("only 4 of the 5" in problem, problem)
	var matched := FcDynastyContentRules.match_starters(_players(layout))
	assert_eq(matched.count(-1), 1, "exactly one slot is left empty")
	var used := matched.filter(func(i: int) -> bool: return i >= 0)
	var unique := {}
	for i in used:
		unique[i] = true
	assert_eq(unique.size(), used.size(), "and no player was used twice")


func test_rule_enough_players_but_not_enough_positional_coverage() -> void:
	# 30 players, but every one is a PG or a C: SG, SF and PF are uncovered
	var layout: Array = []
	for i in 30:
		layout.append([("PG" if i % 2 == 0 else "C"), ""])
	var problem := FcDynastyContentRules.lineup_problem(_players(layout))
	assert_true("only 2 of the 5" in problem and "SG" in problem, problem)


func test_rule_two_editions_of_one_player_count_once() -> void:
	var players := _players(_layout({0: ["SG", ""], 1: ["SF", ""], 2: ["PF", ""], 3: ["C", ""]}))
	players.append({"player_id": "p3", "position": "C", "secondary": ""})   # a second edition of p3
	var matched := FcDynastyContentRules.match_starters(players)
	assert_true(not matched.has(-1))
	assert_true(matched.count(players.size() - 1) == 0, "the duplicate edition is never used as a second starter")
	var few := [{"player_id": "a", "position": "PG", "secondary": ""}, {"player_id": "a", "position": "PG", "secondary": ""}]
	assert_true("1 different players" in FcDynastyContentRules.lineup_problem(few), "distinct players are what is counted")


func test_rule_fewer_than_thirteen_players_keeps_the_old_message() -> void:
	var problem := FcDynastyContentRules.lineup_problem(_players(_layout_all("PG")).slice(0, 12))
	assert_true("12 different players" in problem and "at least 13" in problem, problem)


func test_rule_is_deterministic_and_finds_a_maximum_assignment() -> void:
	var rng := FcRng.new(4242)
	var positions := FcDynastyContentRules.STARTER_POSITIONS
	for round in 120:
		var players: Array = []
		for i in rng.range_int(5, 8):
			var primary: String = positions[rng.range_int(0, 4)]
			var secondary: String = positions[rng.range_int(0, 4)] if rng.range_int(0, 2) == 0 else ""
			players.append({"player_id": "r%d_%d" % [round, i], "position": primary, "secondary": secondary if secondary != primary else ""})
		var got := FcDynastyContentRules.match_starters(players)
		assert_eq(got, FcDynastyContentRules.match_starters(players), "the same input gives the same answer")
		var matched_count := 5 - got.count(-1)
		assert_eq(matched_count, _brute_force_max(players), "round %d: the matching is a maximum matching" % round)
		for slot in 5:
			if got[slot] >= 0:
				var p: Dictionary = players[got[slot]]
				assert_true(p["position"] == positions[slot] or p["secondary"] == positions[slot], "a starter really plays the slot's position")


func _brute_force_max(players: Array) -> int:
	return _search(players, 0, {}, 0)


func _search(players: Array, slot: int, used: Dictionary, count: int) -> int:
	if slot == 5:
		return count
	var best := _search(players, slot + 1, used, count)   # leave this slot empty
	var want: String = FcDynastyContentRules.STARTER_POSITIONS[slot]
	for i in players.size():
		if not used.has(i) and (players[i]["position"] == want or players[i]["secondary"] == want):
			used[i] = true
			best = maxi(best, _search(players, slot + 1, used, count + 1))
			used.erase(i)
	return best


func test_catalog_is_playable_only_when_a_legal_lineup_exists() -> void:
	var ok := FcDynastyFixture.catalog()
	assert_true(ok.is_playable(), "the normal fixture release is playable")
	assert_eq(ok.playable_problem(), "")
	assert_eq(ok.lineup_problem(), "")
	var guards := FcDynastyFixture.catalog(0, "fcr_0123456789abcdef", _layout_all("PG"), false)
	assert_true(guards != null and not guards.is_playable(), "30 point guards: enough players, but not playable")
	var why := guards.playable_problem()
	assert_true("cannot field a legal starting lineup" in why and "SG" in why, why)
	var no_c := FcDynastyFixture.catalog(0, "fcr_0123456789abcdef", _layout({0: ["SG", ""], 1: ["SF", ""], 2: ["PF", ""]}), false)
	assert_true(not no_c.is_playable() and "nobody left for C" in no_c.playable_problem(), "a missing position")
	var shared := FcDynastyFixture.catalog(0, "fcr_0123456789abcdef", _layout({0: ["SF", "PF"], 1: ["SG", ""], 2: ["C", ""]}), false)
	assert_true(not shared.is_playable(), "one SF/PF player cannot cover two slots")
	var secondary := FcDynastyFixture.catalog(0, "fcr_0123456789abcdef", _layout({0: ["SG", ""], 1: ["C", ""], 2: ["PG", "SF"], 3: ["SG", "PF"]}), false)
	assert_true(secondary.is_playable(), "secondary positions make a release playable")


func test_a_small_release_keeps_its_old_message_and_is_not_playable() -> void:
	var catalog := FcDynastyFixture.catalog()
	assert_true(catalog.is_playable())
	var starter := FcDynastyCatalog.build(null, FcDefinitionSet.load_default())
	assert_true(not starter.is_playable(), "no release at all")
	assert_eq(starter.playable_problem(), "No content release is loaded.")


func test_the_publish_validator_rejects_a_release_that_cannot_field_a_lineup() -> void:
	var draft := DIR.path_join("draft_bad")
	FcDynastyFixture.write_content(draft, 0, _layout_all("PG"))
	var problems := _validate(draft)
	assert_true(problems.any(func(p: String) -> bool: return p.begins_with("release: ") and "cannot field a legal starting lineup" in p), "rejected before publication: " + str(problems))
	var good := DIR.path_join("draft_good")
	FcDynastyFixture.write_content(good, 0)
	assert_eq(_validate(good), [], "a release with positional coverage still validates")
	var secondary := DIR.path_join("draft_secondary")
	FcDynastyFixture.write_content(secondary, 0, _layout({0: ["SG", ""], 1: ["C", ""], 2: ["PG", "SF"], 3: ["SG", "PF"]}))
	assert_eq(_validate(secondary), [], "and so does one that relies on secondary positions")


func _validate(draft: String) -> Array:
	var defs := FcDefinitionSet.load_default()
	var m := FcContentFixture.build_release(draft, DIR.path_join("rel_" + draft.get_file()), "fcr_0123456789abcdef", "", 1)
	var paths: Array[String] = []
	for e in m.files:
		paths.append(e["path"])
	return FcContentValidator.check_definitions(DIR.path_join("rel_" + draft.get_file()), paths, defs)["problems"]


func test_a_release_with_few_players_is_still_publishable() -> void:
	# a release without Dynasty content (or with a handful of cards) stays valid: only 13+ players must be fieldable
	var ids := [{"player_id": "a", "position": "PG", "secondary": ""}, {"player_id": "b", "position": "PG", "secondary": ""}]
	assert_true(FcDynastyContentRules.lineup_problem(ids) != "", "the game still says it is not playable")
	var errors: Array[String] = []
	FcContentValidator._check_lineup_coverage({"card": {"c1": {"player_id": "a"}, "c2": {"player_id": "b"}}, "player": {"a": {"position": "PG"}, "b": {"position": "PG"}}}, errors)
	assert_eq(errors, [], "the validator does not reject releases below the 13-player threshold")


func test_a_playable_release_fills_all_thirteen_slots_with_a_valid_lineup() -> void:
	for layout in [[], _layout({0: ["SG", ""], 1: ["C", ""], 2: ["PG", "SF"], 3: ["SG", "PF"]}), _layout({0: ["SF", "PF"], 1: ["SG", "PG"], 2: ["C", ""], 3: ["PF", ""], 4: ["SF", ""]})]:
		var catalog := FcDynastyFixture.catalog(0, "fcr_0123456789abcdef", layout, false)
		assert_true(catalog.is_playable(), "this release is playable")
		var profile := FcDynastyProfile.create("All Cards", "ALL", 99, catalog.release_id())
		for id in catalog.card_ids():
			FcDynastyCollection.grant_card(profile, id, 1, catalog.snapshot_of(id), "tx_test")
		FcDynastyLineup.auto_fill(profile, catalog)
		assert_eq(FcDynastyLineup.problems(profile, catalog), [], "the automatic lineup is legal for every playable release")
		for slot in FcDynastyRoster.SIZE:
			assert_true(str(profile.roster.slots[slot]) != "", "slot %d is filled (bench and reserve need no particular position)" % slot)


func test_the_automatic_lineup_agrees_with_the_shared_rule_on_adversarial_pools() -> void:
	# an owned pool where the best card per slot would block a legal five: the repair step must still find it
	var catalog := FcDynastyFixture.catalog(0, "fcr_0123456789abcdef", _layout({0: ["SG", "PG"], 1: ["SG", ""], 2: ["SF", "PF"], 3: ["PF", ""], 4: ["C", ""], 5: ["SF", ""]}), false)
	var profile := FcDynastyProfile.create("Tight", "TGT", 7, catalog.release_id())
	var all := catalog.card_ids()
	for id in all:
		FcDynastyCollection.grant_card(profile, id, 1, catalog.snapshot_of(id), "tx_test")
	var rec := FcDynastyLineup.recommend(profile, catalog)
	for slot in FcDynastyRoster.STARTERS:
		assert_true(rec[slot] != "", "starter slot %d is filled" % slot)
		assert_true(FcDynastyLineup.eligible(catalog.view(rec[slot]), slot), "and by a player who can play it")


# =====================================================================================================================
# 3. economy idempotency
# =====================================================================================================================

func test_the_same_request_changes_balances_only_once() -> void:
	var p := _profile()
	var first := FcDynastyEconomy.apply(p, "grant", "x", {"credits": 100}, [], "req_a")
	assert_true(first.ok and first.data["replayed"] == false, "the first time it is a new transaction")
	var again := FcDynastyEconomy.apply(p, "grant", "x", {"credits": 100}, [], "req_a")
	assert_true(again.ok, "a retry succeeds")
	assert_eq(again.data["replayed"], true, "and says it was a repeat")
	assert_eq(p.balance("credits"), 100, "the credits were granted once")
	assert_eq(p.ledger.size(), 1, "one ledger entry")
	assert_eq(p.txn_counter, 1, "the counter moved once")
	assert_eq(again.data["txn"], first.data["txn"], "the original transaction is returned")
	assert_eq(again.data["txn"]["txn_id"], "tx_000001")


func test_a_repeated_spend_is_not_charged_twice() -> void:
	var p := _profile(1000)
	var a := FcDynastyEconomy.spend(p, "buy", "pack", {"credits": 400}, ["card_a"], "buy_1")
	var b := FcDynastyEconomy.spend(p, "buy", "pack", {"credits": 400}, ["card_a"], "buy_1")
	assert_true(a.ok and b.ok and b.data["replayed"])
	assert_eq(p.balance("credits"), 600, "charged once")
	assert_eq(p.ledger.size(), 2, "the grant and one purchase")


func test_reusing_a_request_id_for_a_different_transaction_is_refused() -> void:
	var p := _profile()
	FcDynastyEconomy.apply(p, "grant", "x", {"credits": 100}, ["c1"], "req_b")
	var ledger_size := p.ledger.size()
	var counter := p.txn_counter
	for variant in [
		["grant", "x", {"credits": 999}, ["c1"]],     # different amount
		["grant", "x", {"tokens": 100}, ["c1"]],      # different currency
		["bonus", "x", {"credits": 100}, ["c1"]],     # different kind
		["grant", "y", {"credits": 100}, ["c1"]],     # different reference
		["grant", "x", {"credits": 100}, ["c2"]],     # different cards
		["grant", "x", {"credits": 100}, []],         # missing cards
		["grant", "x", {"credits": 100, "tokens": 1}, ["c1"]],   # an extra currency
	]:
		var r := FcDynastyEconomy.apply(p, variant[0], variant[1], variant[2], variant[3], "req_b")
		assert_true(not r.ok and r.code == "request_conflict", "refused: " + str(variant))
	assert_eq(p.balance("credits"), 100, "nothing changed")
	assert_eq(p.balance("tokens"), 0)
	assert_eq(p.ledger.size(), ledger_size)
	assert_eq(p.txn_counter, counter)


func test_different_request_ids_are_independent() -> void:
	var p := _profile()
	FcDynastyEconomy.apply(p, "grant", "x", {"credits": 10}, [], "one")
	FcDynastyEconomy.apply(p, "grant", "x", {"credits": 10}, [], "two")
	assert_eq(p.balance("credits"), 20, "two ids, two transactions, even with the same parameters")
	assert_eq(p.ledger.size(), 2)
	assert_eq(p.txn_counter, 2)


func test_without_a_request_id_every_call_is_a_new_transaction() -> void:
	var p := _profile()
	var a := FcDynastyEconomy.apply(p, "grant", "x", {"credits": 10})
	var b := FcDynastyEconomy.apply(p, "grant", "x", {"credits": 10})
	assert_true(a.data["replayed"] == false and b.data["replayed"] == false)
	assert_eq(p.balance("credits"), 20)
	assert_eq(p.ledger.size(), 2)
	assert_true(p.processed_requests.is_empty(), "nothing is remembered without an id")


func test_a_failed_transaction_does_not_reserve_its_request_id() -> void:
	var p := _profile()
	var failed := FcDynastyEconomy.spend(p, "buy", "pack", {"credits": 50}, [], "try_1")
	assert_true(not failed.ok and failed.code == "insufficient_funds")
	assert_true(not p.processed_requests.has("try_1"), "the failure left no trace")
	assert_eq(p.txn_counter, 0)
	FcDynastyEconomy.apply(p, "grant", "x", {"credits": 80})
	var retried := FcDynastyEconomy.spend(p, "buy", "pack", {"credits": 50}, [], "try_1")
	assert_true(retried.ok and retried.data["replayed"] == false, "the same id works once the player can afford it")
	assert_eq(p.balance("credits"), 30)
	var unknown := FcDynastyEconomy.apply(p, "grant", "x", {"gold": 5}, [], "try_2")
	assert_true(not unknown.ok and not p.processed_requests.has("try_2"), "an unknown currency reserves nothing either")


func test_a_conflicting_reuse_after_a_failure_is_not_a_conflict() -> void:
	var p := _profile()
	assert_true(not FcDynastyEconomy.spend(p, "buy", "a", {"credits": 5}, [], "reuse").ok)
	var other := FcDynastyEconomy.apply(p, "grant", "b", {"credits": 7}, [], "reuse")
	assert_true(other.ok and other.data["replayed"] == false, "the failed request never owned the id")


func test_a_replay_still_works_after_the_ledger_trimmed_the_original() -> void:
	var p := _profile()
	FcDynastyEconomy.apply(p, "grant", "first", {"credits": 1}, [], "old_request")
	var limit := FcDynastyConfig.build().get_int(["ledger_limit"], 400)
	for i in limit + 5:
		FcDynastyEconomy.apply(p, "grant", "filler", {"credits": 1})
	assert_true(not p.ledger.any(func(t: Dictionary) -> bool: return t["txn_id"] == "tx_000001"), "the first entry was trimmed")
	var credits := p.balance("credits")
	var counter := p.txn_counter
	var again := FcDynastyEconomy.apply(p, "grant", "first", {"credits": 1}, [], "old_request")
	assert_true(again.ok and again.data["replayed"], "still recognised as a repeat")
	assert_eq(again.data["txn"]["txn_id"], "tx_000001", "with its transaction id")
	assert_eq(p.balance("credits"), credits, "no credit granted again")
	assert_eq(p.txn_counter, counter)


func test_the_economy_contract_survives_saving_and_loading() -> void:
	var p := _profile()
	FcDynastyEconomy.apply(p, "grant", "x", {"credits": 25}, [], "persisted")
	assert_true(store.save("idem", p).ok)
	var loaded: FcDynastyProfile = store.load_slot("idem").data["profile"]
	var again := FcDynastyEconomy.apply(loaded, "grant", "x", {"credits": 25}, [], "persisted")
	assert_true(again.ok and again.data["replayed"], "a retry after restarting the game is still a repeat")
	assert_eq(loaded.balance("credits"), 25)


func test_callers_do_not_repeat_their_work_when_a_request_is_replayed() -> void:
	var env := FcDynastyEnv.make()
	var catalog := env.catalog
	var profile := env.profile()
	# a reward granted twice with the same request id
	var rewards := {"credits": 300, "card_ids": [FcDynastyFixture.card_id(20)]}
	var credits := profile.balance("credits")
	var first := env.session.commit(func() -> FcDynastyResult: return FcDynastyRewards.grant(profile, catalog, rewards, "test_reward", "r1", "reward:r1"))
	assert_true(first.ok)
	var after_first := profile.balance("credits")
	var copies := profile.quantity_of(FcDynastyFixture.card_id(20))
	var second := env.session.commit(func() -> FcDynastyResult: return FcDynastyRewards.grant(profile, catalog, rewards, "test_reward", "r1", "reward:r1"))
	assert_true(second.ok and second.data.get("repeated", false), "the repeat is reported")
	assert_eq(profile.balance("credits"), after_first, "no second payment")
	assert_eq(profile.quantity_of(FcDynastyFixture.card_id(20)), copies, "no second copy of the card")
	assert_eq(after_first, credits + 300)
	# a pack bought twice with the same request id opens once
	env.fund("credits", 2000)
	var opened := env.session.commit(func() -> FcDynastyResult: return FcDynastyPacks.buy_and_open(profile, catalog, "bronze_pack", "buy:fixed"))
	assert_true(opened.ok)
	var balance := profile.balance("credits")
	var openings := profile.pack_openings.size()
	var repeat := env.session.commit(func() -> FcDynastyResult: return FcDynastyPacks.buy_and_open(profile, catalog, "bronze_pack", "buy:fixed"))
	assert_true(repeat.ok and repeat.data.get("repeated", false), "the repeat returns the original opening")
	assert_eq(profile.balance("credits"), balance, "no second charge")
	assert_eq(profile.pack_openings.size(), openings, "no second opening")
	# duplicate conversion and direct purchase keep their own protection
	env.give(FcDynastyFixture.card_id(1))
	var conv := env.session.commit(func() -> FcDynastyResult: return FcDynastyCollection.convert_duplicate(profile, catalog.config, FcDynastyFixture.card_id(1), "common", "conv:once"))
	var shards := profile.balance("shards")
	var conv2 := env.session.commit(func() -> FcDynastyResult: return FcDynastyCollection.convert_duplicate(profile, catalog.config, FcDynastyFixture.card_id(1), "common", "conv:once"))
	assert_true(conv.ok and conv2.ok and conv2.data.get("repeated", false))
	assert_eq(profile.balance("shards"), shards, "converted once")
	var bought := env.session.commit(func() -> FcDynastyResult: return FcDynastyMarket.acquire(profile, catalog, FcDynastyFixture.card_id(16), "acq:once"))
	var owned := profile.quantity_of(FcDynastyFixture.card_id(16))
	var credits_now := profile.balance("credits")
	var bought2 := env.session.commit(func() -> FcDynastyResult: return FcDynastyMarket.acquire(profile, catalog, FcDynastyFixture.card_id(16), "acq:once"))
	assert_true(bought.ok and bought2.ok and bought2.data.get("repeated", false))
	assert_eq(profile.quantity_of(FcDynastyFixture.card_id(16)), owned, "bought once")
	assert_eq(profile.balance("credits"), credits_now)
