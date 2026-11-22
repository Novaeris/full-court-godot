extends FcTestCase
## Published sets and Studio tournaments (Phase 5, D-067): the shared time window, the set publish rules (one set per card, timed sets,
## one base set), what a closed set does to the store (packs leave, owned cards stay), and tournaments of 4, 8, 16 and 32 with an
## optional entry window.

const DAY := 86400
const START := 1700000000

var env: FcDynastyEnv
var now_value: int


func before_each() -> void:
	env = FcDynastyEnv.make(515)
	now_value = START


func after_each() -> void:
	FcSafeFile.remove_tree(FcDynastyEnv.DIR)


## A catalog over the fixture release with the given sets, reading time from `now_value`.
func _with_sets(sets: Dictionary) -> FcDynastyCatalog:
	env.catalog.content.sets = sets
	var cat := FcDynastyCatalog.build(env.catalog.content, env.catalog.defs)
	cat.clock = func() -> int: return now_value
	env.catalog = cat
	return cat


func _holiday(starts: int, ends: int) -> Dictionary:
	return {"holiday": {"set_id": "holiday", "name": "Holiday Set", "kind": "timed", "starts_at": starts, "ends_at": ends,
		"card_ids": [FcDynastyFixture.card_id(20)], "pack_ids": ["bronze_pack"], "requires_features": ["set_v1"]}}


# --- the window ----------------------------------------------------------------------------------------------------------------

func test_a_window_is_upcoming_then_active_then_ended() -> void:
	var def := {"starts_at": 1000, "ends_at": 2000}
	assert_eq(FcContentWindow.status(def, 999), "upcoming")
	assert_eq(FcContentWindow.status(def, 1000), "active", "the start moment is open")
	assert_eq(FcContentWindow.status(def, 1999), "active")
	assert_eq(FcContentWindow.status(def, 2000), "ended", "the end moment is already closed")
	assert_eq(FcContentWindow.status({}, 5), "always", "no window means always open")
	assert_true(FcContentWindow.is_open({}, 5) and FcContentWindow.is_open(def, 1500))
	assert_true(not FcContentWindow.is_open(def, 999) and not FcContentWindow.is_open(def, 2000))
	assert_eq(FcContentWindow.describe({"starts_at": 0 + 1, "ends_at": 1 + 3 * DAY}, 1), "Ends in 3 days")
	assert_eq(FcContentWindow.describe({"starts_at": 1, "ends_at": 1 + 5 * 3600}, 1), "Ends in 5 hours")
	assert_eq(FcContentWindow.describe({"starts_at": 1 + 2 * 3600, "ends_at": 1 + 3 * DAY}, 1), "Starts in 2 hours")
	assert_eq(FcContentWindow.describe(def, 2500), "Ended")
	assert_eq(FcContentWindow.describe({}, 5), "")


func test_window_problems_are_reported() -> void:
	assert_true(FcContentWindow.problems("p", {"starts_at": 10, "ends_at": 20}).is_empty())
	assert_true(not FcContentWindow.problems("p", {"starts_at": 20, "ends_at": 20}).is_empty(), "an empty window")
	assert_true(not FcContentWindow.problems("p", {"starts_at": 20, "ends_at": 10}).is_empty(), "ends before it starts")
	assert_true(not FcContentWindow.problems("p", {"ends_at": "soon"}).is_empty(), "not a number")
	assert_true(not FcContentWindow.problems("p", {"starts_at": 0}).is_empty(), "zero is not a time")


# --- set publish rules -----------------------------------------------------------------------------------------------------

func _set_problems(data: Dictionary, cards: Dictionary = {"a": {}, "b": {}}, packs: Dictionary = {}) -> Array[String]:
	var errors: Array[String] = []
	FcDynastyContentRules.check_set("sets/x.json", data, cards, packs, errors)
	return errors


func _good_set() -> Dictionary:
	return {"set_id": "x", "name": "X", "card_ids": ["a", "b"], "requires_features": ["set_v1"]}


func test_a_good_set_passes_and_the_rules_catch_each_mistake() -> void:
	assert_eq(_set_problems(_good_set()), [])
	var timed := _good_set()
	timed.merge({"kind": "timed", "starts_at": 10, "ends_at": 20})
	assert_eq(_set_problems(timed), [], "a timed set with a window")
	var no_window := _good_set()
	no_window["kind"] = "timed"
	assert_true(not _set_problems(no_window).is_empty(), "timed needs a window")
	var permanent_window := _good_set()
	permanent_window["starts_at"] = 10
	assert_true(not _set_problems(permanent_window).is_empty(), "a permanent set has no window")
	var base_timed := timed.duplicate()
	base_timed["base"] = true
	assert_true(not _set_problems(base_timed).is_empty(), "the base set must be permanent")
	var no_feature := _good_set()
	no_feature["requires_features"] = []
	assert_true(not _set_problems(no_feature).is_empty(), "needs set_v1")
	var bad_kind := _good_set()
	bad_kind["kind"] = "seasonal"
	assert_true(not _set_problems(bad_kind).is_empty())
	var ghost := _good_set()
	ghost["card_ids"] = ["a", "ghost"]
	assert_true(not _set_problems(ghost).is_empty(), "a card the release lacks")
	var empty := _good_set()
	empty["card_ids"] = []
	assert_true(not _set_problems(empty).is_empty())
	var unnamed := _good_set()
	unnamed["name"] = " "
	assert_true(not _set_problems(unnamed).is_empty())


func test_a_pack_may_only_hold_cards_of_its_own_set() -> void:
	var packs := {"p": {"card_ids": ["a", "b"]}, "q": {"card_ids": ["a", "c"]}}
	var s := _good_set()
	s["pack_ids"] = ["p"]
	assert_eq(_set_problems(s, {"a": {}, "b": {}, "c": {}}, packs), [])
	s["pack_ids"] = ["q"]
	assert_true(not _set_problems(s, {"a": {}, "b": {}, "c": {}}, packs).is_empty(), "q holds c, which is outside the set")
	s["pack_ids"] = ["nope"]
	assert_true(not _set_problems(s, {"a": {}, "b": {}}, packs).is_empty(), "a pack the release lacks")


func test_a_card_is_in_one_set_a_pack_is_sold_by_one_set_and_there_is_one_base() -> void:
	var errors: Array[String] = []
	FcDynastyContentRules.check_set_membership({"s1": {"card_ids": ["a"], "pack_ids": ["p"]}, "s2": {"card_ids": ["b"], "pack_ids": ["q"]}}, {}, errors)
	assert_eq(errors, [], "separate sets are fine")
	FcDynastyContentRules.check_set_membership({"s1": {"card_ids": ["a", "b"]}, "s2": {"card_ids": ["b"]}}, {}, errors)
	assert_eq(errors.size(), 1, "a card in two sets")
	assert_true("belongs to one set only" in errors[0])
	errors.clear()
	FcDynastyContentRules.check_set_membership({"s1": {"card_ids": ["a"], "pack_ids": ["p"]}, "s2": {"card_ids": ["b"], "pack_ids": ["p"]}}, {}, errors)
	assert_eq(errors.size(), 1, "a pack sold by two sets")
	errors.clear()
	FcDynastyContentRules.check_set_membership({"s1": {"base": true, "card_ids": ["a"]}, "s2": {"base": true, "card_ids": ["b"]}}, {}, errors)
	assert_eq(errors.size(), 1, "two base sets")


func test_the_bundled_release_has_a_permanent_base_set_of_every_card() -> void:
	var report := FcContentValidator.validate_release_dir("res://data/content_starter", FcVersion.GAME_VERSION, FcDefinitionSet.load_default())
	assert_true(report.is_ok(), str(report.problems))
	var sets_dir := "res://data/content_starter/sets/founding_series.json"
	assert_true(FileAccess.file_exists(sets_dir), "the Founding Series set ships")
	var def: Dictionary = FcSafeFile.read_json_object(sets_dir)
	assert_eq(def["kind"], "permanent")
	assert_true(bool(def["base"]))
	assert_eq((def["card_ids"] as Array).size(), 46, "all 46 Founding cards")
	assert_eq(FcContentWindow.status(def, START), "always", "never expires")


# --- what a closed set does ----------------------------------------------------------------------------------------------------

func test_a_timed_set_sells_its_pack_only_while_open() -> void:
	var cat := _with_sets(_holiday(START + DAY, START + 15 * DAY))
	assert_eq(cat.set_of_pack("bronze_pack"), "holiday")
	assert_eq(cat.set_of_card(FcDynastyFixture.card_id(20)), "holiday")
	assert_eq(cat.set_status("holiday"), "upcoming")
	assert_true(not cat.buyable_packs().has("bronze_pack"), "not for sale before it starts")
	env.fund("credits", 5000)
	var early := env.session.commit(func() -> FcDynastyResult: return FcDynastyPacks.buy_and_open(env.session.profile, cat, "bronze_pack", "r_early"))
	assert_eq(early.code, "set_not_open")
	now_value = START + 2 * DAY
	assert_eq(cat.set_status("holiday"), "active")
	assert_true(cat.buyable_packs().has("bronze_pack"), "on sale during the window")
	var opened := env.session.commit(func() -> FcDynastyResult: return FcDynastyPacks.buy_and_open(env.session.profile, cat, "bronze_pack", "r_ok"))
	assert_true(opened.ok, opened.message)
	now_value = START + 15 * DAY
	assert_eq(cat.set_status("holiday"), "ended")
	assert_true(not cat.buyable_packs().has("bronze_pack"), "the pack leaves when the set ends")
	assert_true(cat.buyable_packs().has("elite_pack"), "other packs are unaffected")
	var late := env.session.commit(func() -> FcDynastyResult: return FcDynastyPacks.buy_and_open(env.session.profile, cat, "bronze_pack", "r_late"))
	assert_eq(late.code, "set_not_open")


func test_cards_already_owned_stay_after_the_set_ends() -> void:
	var cat := _with_sets(_holiday(START, START + DAY))
	env.fund("credits", 5000)
	var got := env.session.commit(func() -> FcDynastyResult: return FcDynastyMarket.acquire(env.session.profile, cat, FcDynastyFixture.card_id(20), "m1"))
	assert_true(got.ok, "the set card is for sale while the set is open")
	var owned := env.profile().quantity_of(FcDynastyFixture.card_id(20))
	assert_eq(owned, 1)
	now_value = START + 3 * DAY
	assert_true(not cat.market_card_ids().has(FcDynastyFixture.card_id(20)), "no longer sold")
	var again := env.session.commit(func() -> FcDynastyResult: return FcDynastyMarket.acquire(env.session.profile, cat, FcDynastyFixture.card_id(20), "m2"))
	assert_eq(again.code, "set_not_open")
	assert_eq(env.profile().quantity_of(FcDynastyFixture.card_id(20)), owned, "owned cards stay forever")
	assert_true(cat.has_card(FcDynastyFixture.card_id(20)), "the card definition stays in the release, so it can still be used")


func test_a_set_can_return_when_republished_with_a_new_window() -> void:
	var cat := _with_sets(_holiday(START, START + DAY))
	now_value = START + 2 * DAY
	assert_true(not cat.buyable_packs().has("bronze_pack"))
	var back := _with_sets(_holiday(START + 10 * DAY, START + 24 * DAY))
	now_value = START + 11 * DAY
	assert_true(back.buyable_packs().has("bronze_pack"), "a re-release opens it again")


func test_the_server_time_decides_for_online_requests() -> void:
	var cat := _with_sets(_holiday(START + DAY, START + 15 * DAY))
	env.fund("credits", 5000)
	now_value = START   # the device clock says it has not started
	var online := env.session.commit(func() -> FcDynastyResult: return FcDynastyPacks.buy_and_open(env.session.profile, cat, "bronze_pack", "srv", START + 2 * DAY))
	assert_true(online.ok, "an explicit server time wins over the device clock")


func test_the_pack_listing_shows_the_set_and_its_end() -> void:
	var cat := _with_sets(_holiday(START, START + 3 * DAY + 100))
	var listing := FcDynastyController.new(null, env.catalog.defs, env.store)
	listing.catalog = cat
	listing.session = env.session
	var found := false
	for pk in listing.pack_listing():
		if pk["pack_id"] == "bronze_pack":
			found = true
			assert_eq(pk["set_name"], "Holiday Set")
			assert_eq(pk["window"], "Ends in 3 days")
		else:
			assert_eq(pk["window"], "", "a pack outside any set shows nothing")
	assert_true(found)


# --- tournaments ---------------------------------------------------------------------------------------------------------------

func _cup(size: int, extra: Dictionary = {}) -> Dictionary:
	var teams: Array = []
	for t in size - 1:
		teams.append({"name": "Cup Rival %d" % (t + 1), "abbreviation": "CR%d" % (t + 1), "rating": 55 + (t % 9) * 3})
	var cup := {"tournament_id": "cup_%d" % size, "name": "Cup %d" % size, "entry_fee": {"currency": "credits", "amount": 50}, "size": size,
		"teams": teams, "rewards": {"champion": {"credits": 900}, "finalist": {"credits": 400}, "semifinal": {"credits": 200}, "quarterfinal": {"credits": 100}, "early": {"credits": 25}}}
	cup.merge(extra, true)
	return cup


func _install(cups: Array) -> void:
	env.catalog.content.seasonal["season_one"]["tournaments"] = cups
	env.catalog.clock = func() -> int: return now_value


func _enter(id: String) -> FcDynastyResult:
	return env.session.commit(func() -> FcDynastyResult: return FcDynastyTournament.enter(env.session.profile, env.catalog, id))


func _next() -> FcDynastyResult:
	return env.session.commit(func() -> FcDynastyResult: return FcDynastyTournament.play_next(env.session.profile, env.catalog))


func test_round_counts_and_names_follow_the_bracket_size() -> void:
	assert_eq([FcDynastyTournament.rounds_for(4), FcDynastyTournament.rounds_for(8), FcDynastyTournament.rounds_for(16), FcDynastyTournament.rounds_for(32)], [2, 3, 4, 5])
	var run := {"teams": []}
	run["teams"].resize(32)
	var names: Array[String] = []
	for r in 5:
		names.append(FcDynastyTournament.round_name(run, r))
	assert_eq(names, ["Round of 32", "Round of 16", "Quarterfinals", "Semifinals", "Final"])
	assert_eq(FcDynastyTournament.placement_for_exit(run, 4), "finalist")
	assert_eq(FcDynastyTournament.placement_for_exit(run, 3), "semifinal")
	assert_eq(FcDynastyTournament.placement_for_exit(run, 2), "quarterfinal")
	assert_eq(FcDynastyTournament.placement_for_exit(run, 1), "early")
	assert_eq(FcDynastyTournament.placement_for_exit(run, 0), "early")
	run["teams"].resize(4)
	assert_eq([FcDynastyTournament.round_name(run, 0), FcDynastyTournament.round_name(run, 1)], ["Semifinals", "Final"])
	assert_eq(FcDynastyTournament.placement_for_exit(run, 0), "semifinal")


func test_brackets_of_every_size_play_to_a_result() -> void:
	for size in [4, 8, 16, 32]:
		env = FcDynastyEnv.make(900 + size)
		_install([_cup(size)])
		env.fund("credits", 1000)
		var entered := _enter("cup_%d" % size)
		assert_true(entered.ok, "%d: %s" % [size, entered.message])
		var run := FcDynastyTournament.active(env.profile())
		assert_eq(run["teams"].size(), size, "%d teams" % size)
		assert_eq(run["rounds"][0].size(), size >> 1, "%d: first round matches" % size)
		var finished := false
		var played := 0
		while not finished and played < 6:
			var step := _next()
			assert_true(step.ok, "%d match %d: %s" % [size, played, step.message])
			played += 1
			finished = step.data["finished"]
		assert_true(finished, "%d finishes" % size)
		assert_true(played <= FcDynastyTournament.rounds_for(size), "%d: at most one match per round" % size)
		var hist: Array = env.profile().tournament["history"]
		assert_eq(hist.size(), 1)
		assert_true(FcDynastyContentRules.PLACEMENTS.has(str(hist[0]["placement"])), "%d: a known placement" % size)


func test_a_champion_of_a_sixteen_bracket_won_four_matches() -> void:
	# play many seeds until one run goes the distance, proving the longest path works
	for s in 40:
		env = FcDynastyEnv.make(2000 + s)
		_install([_cup(16, {"teams": _weak_teams(15)})])
		env.fund("credits", 1000)
		_enter("cup_16")
		var played := 0
		var last: FcDynastyResult
		while played < 4:
			last = _next()
			played += 1
			if last.data["finished"]:
				break
		if last.data["finished"] and last.data["run"]["placement"] == "champion":
			assert_eq(played, 4, "four rounds for sixteen teams")
			assert_eq(env.profile().tournament["history"][0]["placement"], "champion")
			return
	assert_true(false, "no seed produced a champion; the weak teams should be beatable")


func _weak_teams(n: int) -> Array:
	var teams: Array = []
	for t in n:
		teams.append({"name": "Weak %d" % t, "abbreviation": "W%d" % t, "rating": 31})
	return teams


func test_an_early_exit_pays_the_early_reward() -> void:
	env = FcDynastyEnv.make(11)
	_install([_cup(32, {"teams": _strong_teams(31)})])
	env.fund("credits", 1000)
	assert_true(_enter("cup_32").ok)
	var step := _next()
	assert_true(step.ok)
	assert_true(step.data["finished"], "a lineup facing the strongest teams loses in the first round")
	assert_eq(step.data["run"]["placement"], "early")
	assert_eq(step.data["rewards"], {"credits": 25}, "the early reward from the published definition")


func _strong_teams(n: int) -> Array:
	var teams: Array = []
	for t in n:
		teams.append({"name": "Strong %d" % t, "abbreviation": "S%d" % t, "rating": 99})
	return teams


func test_an_entry_window_closes_a_tournament() -> void:
	_install([_cup(8, {"starts_at": START + DAY, "ends_at": START + 3 * DAY})])
	env.fund("credits", 1000)
	assert_eq(_enter("cup_8").code, "tournament_closed", "before it opens")
	now_value = START + 2 * DAY
	assert_true(_enter("cup_8").ok, "open in the window")
	now_value = START + 9 * DAY
	assert_true(_next().ok, "a run already begun can be finished after the window closes")


func test_a_closed_tournament_is_not_listed() -> void:
	_install([_cup(8, {"starts_at": START + DAY, "ends_at": START + 3 * DAY}), _cup(4)])
	var listing := FcDynastyController.new(null, env.catalog.defs, env.store)
	listing.catalog = env.catalog
	listing.session = env.session
	var ids: Array = listing.tournament_listing().map(func(t: Dictionary) -> String: return str(t["tournament_id"]))
	assert_eq(ids, ["cup_4"], "the upcoming cup is hidden")
	now_value = START + 2 * DAY
	var open_ids: Array = listing.tournament_listing().map(func(t: Dictionary) -> String: return str(t["tournament_id"]))
	assert_eq(open_ids, ["cup_8", "cup_4"])
	assert_eq(listing.tournament_listing()[0]["window"], "Ends in 24 hours")


# --- tournament publish rules ----------------------------------------------------------------------------------------------

func _season_problems(cups: Array, features: Array = ["season_v1", "tournament_v2"]) -> Array[String]:
	var errors: Array[String] = []
	var season := {"season_id": "s", "name": "S", "tournaments": cups, "requires_features": features}
	FcDynastyContentRules.check_season("seasonal/s.json", season, {}, {}, {}, errors)
	return errors


func test_tournament_sizes_and_windows_are_validated() -> void:
	for size in [4, 8, 16, 32]:
		assert_eq(_season_problems([_cup(size)]), [], "size %d is allowed" % size)
	assert_true(not _season_problems([_cup(6)]).is_empty(), "6 is not a bracket size")
	var wrong := _cup(16)
	wrong["teams"] = _weak_teams(7)
	assert_true(not _season_problems([wrong]).is_empty(), "a bracket of 16 needs 15 opponents")
	assert_true(not _season_problems([_cup(16)], ["season_v1"]).is_empty(), "a size needs tournament_v2")
	assert_true(not _season_problems([_cup(8, {"starts_at": 10, "ends_at": 5})]).is_empty(), "a backwards window")
	assert_eq(_season_problems([_cup(8, {"starts_at": 10, "ends_at": 50})]), [])
	var original := _cup(8)
	original.erase("size")
	assert_eq(_season_problems([original], ["season_v1"]), [], "the original eight-team cup needs no new feature")
