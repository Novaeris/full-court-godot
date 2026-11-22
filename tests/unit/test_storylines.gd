extends FcTestCase
## League storylines (Phase 3): headlines worked out from finished seasons and careers. A hand-built history with known champions,
## ranks, MVPs, a record season and a retired legend gives exact stories; a real played league checks shape, order and determinism.

var w: FcWorld
var lid: int
var t: Array


func before_each() -> void:
	var env := FcHistoryFixture.league()
	w = env["world"]
	lid = env["league_id"]
	t = env["teams"]
	_history()


## 2000-2013: t0 wins three in a row and MVP 8001 wins three in a row (setting a points record in 2002), t2 wins in 2005 and then misses the
## playoffs, t7 wins as the 8th seed in 2007, t3 goes from 7th to champion in 2008 and t1 finally wins in 2013. A legend retires in 2011.
func _history() -> void:
	var def: Array = t.duplicate()
	var mvp := FcHistoryFixture.retired_player(w, t[6], 2000, 3, 1500, 8001)
	mvp.status = FcPlayer.Status.ACTIVE
	mvp.retired_season = 0
	w.careers[8001] = [FcHistoryFixture.row(2000, t[6], 70, 1500, 300, 200), FcHistoryFixture.row(2001, t[6], 70, 1800, 300, 200), FcHistoryFixture.row(2002, t[6], 70, 3000, 300, 200)]
	FcHistoryFixture.season(w, lid, 2000, def, t[0], 8, 8001)
	FcHistoryFixture.season(w, lid, 2001, def, t[0], 8, 8001)
	FcHistoryFixture.season(w, lid, 2002, def, t[0], 8, 8001)
	FcHistoryFixture.season(w, lid, 2003, def, t[2])
	FcHistoryFixture.season(w, lid, 2004, def, t[3])
	FcHistoryFixture.season(w, lid, 2005, def, t[2])
	FcHistoryFixture.season(w, lid, 2006, [t[4], t[5], t[6], t[7], t[0], t[1], t[3], t[2]], t[4], 4)   # t2 falls out of the playoffs
	FcHistoryFixture.season(w, lid, 2007, [t[0], t[1], t[2], t[4], t[5], t[6], t[3], t[7]], t[7])
	FcHistoryFixture.season(w, lid, 2008, def, t[3])
	FcHistoryFixture.season(w, lid, 2009, def, t[0])
	FcHistoryFixture.season(w, lid, 2010, def, t[2])
	FcHistoryFixture.season(w, lid, 2011, def, t[0])
	FcHistoryFixture.season(w, lid, 2012, def, t[2])
	FcHistoryFixture.season(w, lid, 2013, def, t[1])
	FcHistoryFixture.retired_player(w, t[5], 2000, 12, 2600, 900020)   # 31,200 points: a Hall of Fame career, retired in 2011


func _find(kind: String, year: int) -> Dictionary:
	for item in FcStorylines.new(w, lid).all():
		if item["kind"] == kind and item["year"] == year:
			return item
	return {}


func test_back_to_back_and_three_peat() -> void:
	var two := _find("dynasty", 2001)
	assert_true(not two.is_empty() and str(two["headline"]).contains("repeat as champions"), "2001 is a repeat")
	assert_eq(two["team_ids"], [t[0]])
	var three := _find("dynasty", 2002)
	assert_true(not three.is_empty() and str(three["headline"]).contains("3rd straight title"), str(three.get("headline", "")))
	assert_true(three["weight"] > two["weight"], "a three-peat is the bigger story")
	assert_true(_find("dynasty", 2000).is_empty(), "a first title is not a dynasty")


func test_a_long_wait_ends() -> void:
	var s := _find("drought", 2013)
	assert_true(not s.is_empty(), "t1's first title after 13 seasons")
	assert_true(str(s["headline"]).contains("13-season wait"), str(s["headline"]))
	assert_eq(s["team_ids"], [t[1]])
	assert_true(_find("drought", 2005).is_empty(), "five seasons is not a drought")


func test_worst_to_first_and_cinderella() -> void:
	var up := _find("worst_to_first", 2008)
	assert_true(not up.is_empty(), "t3 was 7th of 8 the year before")
	assert_eq(up["team_ids"], [t[3]])
	assert_true(str(up["headline"]).contains("7 of 8"), str(up["headline"]))
	var low := _find("cinderella", 2007)
	assert_true(not low.is_empty() and str(low["headline"]).contains("8th seed"), "the 8th of 8 wins it all")
	assert_true(_find("cinderella", 2000).is_empty(), "a top seed winning is no surprise")


func test_the_champion_who_misses_the_playoffs() -> void:
	var s := _find("collapse", 2006)
	assert_true(not s.is_empty(), "the 2005 champion t2 finished last and out of the field in 2006")
	assert_eq(s["team_ids"], [t[2]])
	assert_true(_find("collapse", 2007).is_empty())


func test_repeat_mvps_and_the_record_season() -> void:
	var second := _find("mvp", 2001)
	assert_true(not second.is_empty() and str(second["headline"]).contains("second straight MVP"))
	var third := _find("mvp", 2002)
	assert_true(not third.is_empty() and str(third["headline"]).contains("3rd time"), str(third.get("headline", "")))
	assert_eq(third["player_ids"], [8001])
	var record := _find("record", 2002)
	assert_true(not record.is_empty() and str(record["headline"]).contains("points record"), "3,000 points in 2002 is the best season on file")
	assert_eq(record["player_ids"], [8001])


func test_a_legend_retires_and_the_number_is_retired() -> void:
	var legend := _find("legend", 2011)
	assert_true(not legend.is_empty() and str(legend["headline"]).contains("retires after 12 seasons"))
	assert_true(str(legend["text"]).contains("Hall of Famer"), "a score above the induction line")
	assert_eq(legend["weight"], 85)
	var jersey := _find("jersey", 2012)
	assert_true(not jersey.is_empty(), "the ceremony is the season after his last")
	assert_true(str(jersey["headline"]).contains("retire #%d" % FcFranchiseHistory.jersey_for(900020)), str(jersey["headline"]))
	assert_eq(jersey["team_ids"], [t[5]])


func test_the_list_is_ordered_filtered_and_repeatable() -> void:
	var s := FcStorylines.new(w, lid)
	var items := s.all()
	assert_true(items.size() > 12)
	for i in range(1, items.size()):
		var p: Dictionary = items[i - 1]
		var q: Dictionary = items[i]
		assert_true(p["year"] > q["year"] or (p["year"] == q["year"] and p["weight"] >= q["weight"]), "newest year first, bigger story first")
	assert_eq(FcStorylines.new(w, lid).all(), items, "the same history always tells the same stories")
	assert_eq(s.recent(3).size(), 3)
	assert_eq(s.recent(3), items.slice(0, 3))
	for item in s.for_team(t[2], 20):
		assert_true((item["team_ids"] as Array).has(t[2]))
	assert_true(s.for_team(t[2], 20).size() >= 2, "t2's title story, rivalries and collapse")
	for item in s.for_player(8001, 20):
		assert_true((item["player_ids"] as Array).has(8001))
	assert_true(s.for_player(8001, 20).size() >= 3)
	var early := FcStorylines.new(w, lid, 2005)
	for item in early.all():
		assert_true(item["year"] <= 2005, "nothing from after the cut-off year")
	assert_true(early.all().size() < items.size())
	for item in items:
		assert_true(str(item["headline"]) != "" and str(item["text"]) != "")
		assert_true(not str(item["headline"]).contains("%"), "no unfilled placeholder: %s" % item["headline"])


func test_an_empty_history_has_no_storylines() -> void:
	var fresh := FcHistoryFixture.league()
	var s := FcStorylines.new(fresh["world"], fresh["league_id"])
	assert_eq(s.all().size(), 0)
	assert_eq(s.recent(5).size(), 0)
	assert_eq(s.for_team(fresh["teams"][0]).size(), 0)


func test_a_real_played_league_has_well_formed_stories() -> void:
	var cfg := FcGenerationConfig.load_default(FcGenerationData.load_default())
	cfg.team_count = 8
	cfg.conference_count = 2
	cfg.divisions_per_conference = 1
	cfg.roster_size = 13
	cfg.free_agent_count = 15
	cfg.assistant_coaches = 1
	cfg.scouts = 0
	var g := FcGameController.new_game(FcWorldGenerator.new(FcGenerationData.load_default(), FcDefinitionSet.load_default(), cfg), 12, FcGameState.MODE_OWNER, 1)
	for i in 4:
		g.sim_playoffs()
		g.start_next_season()
	var items := FcStorylines.new(g.state.world, g.league_id).all()
	assert_true(items.size() > 0, "four seasons of real play make some stories")
	for item in items:
		assert_true(["dynasty", "drought", "worst_to_first", "cinderella", "collapse", "mvp", "record", "legend", "jersey", "rivalry"].has(item["kind"]))
		assert_true(str(item["headline"]).length() > 8)
