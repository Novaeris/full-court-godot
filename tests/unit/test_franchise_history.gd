extends FcTestCase
## Franchise history (Phase 3): the season log, franchise records, leaders and retired numbers, worked out from finished seasons and
## career rows. Hand-built seasons give exact answers; a real played league checks the invariants on real data.

var env: Dictionary
var w: FcWorld
var lid: int
var t: Array


func before_each() -> void:
	env = FcHistoryFixture.league()
	w = env["world"]
	lid = env["league_id"]
	t = env["teams"]


## Every team of the league, best record first, with `first` at the front in the order given.
func _order(first: Array) -> Array:
	var order: Array = first.duplicate()
	for id in t:
		if not order.has(id):
			order.append(id)
	return order


# --- season log and summary ------------------------------------------------------------------------------------------------

func test_the_log_and_the_summary_of_hand_built_seasons() -> void:
	# t0 wins 2000 and 2001, loses the final in 2002 (t1 wins), is the 8th seed and out in round 1 in 2003, and misses a four-team field in 2004
	FcHistoryFixture.season(w, lid, 2000, _order([t[0]]), t[0])
	FcHistoryFixture.season(w, lid, 2001, _order([t[0]]), t[0])
	FcHistoryFixture.season(w, lid, 2002, _order([t[0], t[1]]), t[1])
	FcHistoryFixture.season(w, lid, 2003, [t[1], t[2], t[3], t[4], t[5], t[6], t[7], t[0]], t[1])
	FcHistoryFixture.season(w, lid, 2004, [t[1], t[2], t[3], t[4], t[5], t[6], t[7], t[0]], t[1], 4)
	var h := FcFranchiseHistory.new(w, lid)
	var log := h.season_log(t[0])
	assert_eq(log.size(), 5)
	assert_eq([log[0]["result"], log[1]["result"], log[2]["result"]], ["Champions", "Champions", "Lost the final"])
	assert_eq(log[3]["result"], "Lost in round 1", "the 8th seed is out in the first round")
	assert_eq(log[4]["result"], "Missed the playoffs", "outside a four-team field")
	assert_eq([log[0]["rank"], log[3]["rank"]], [1, 8])
	assert_eq([log[0]["wins"], log[0]["losses"]], [60, 22], "wins and losses come from the final standings")
	var s := h.summary(t[0])
	assert_eq(s["seasons"], 5)
	assert_eq(s["titles"], 2)
	assert_eq(s["title_years"], [2000, 2001])
	assert_eq(s["finals"], 3, "two titles and a lost final")
	assert_eq(s["playoffs"], 4)
	assert_eq(s["drought"], 3, "three seasons since the last title")
	assert_eq(s["playoff_streak"], 0, "the latest season missed the playoffs")
	assert_eq(s["best"]["year"], 2000)
	assert_eq(s["worst"]["year"], 2003)
	assert_eq(h.summary(t[1])["titles"], 3)
	assert_eq(h.summary(t[1])["drought"], 0, "the reigning champion has no drought")
	assert_eq(h.summary(t[1])["playoff_streak"], 5)


func test_every_season_has_exactly_one_champion_and_one_runner_up() -> void:
	for i in 6:
		FcHistoryFixture.season(w, lid, 2000 + i, _order([t[i % 8]]), t[i % 8])
	var h := FcFranchiseHistory.new(w, lid)
	var champions := 0
	var finals := 0
	for team in t:
		champions += int(h.summary(team)["titles"])
		finals += int(h.summary(team)["finals"])
	assert_eq(champions, 6)
	assert_eq(finals, 12, "a champion and a runner-up each season")


func test_unfinished_and_other_league_seasons_are_ignored() -> void:
	var unfinished := FcHistoryFixture.season(w, lid, 2000, _order([t[0]]), t[0])
	unfinished.status = FcSeason.Status.PLAYOFFS
	var elsewhere := FcHistoryFixture.season(w, lid + 99, 2001, _order([t[0]]), t[0])
	assert_true(elsewhere != null)
	var h := FcFranchiseHistory.new(w, lid)
	assert_eq(h.season_log(t[0]).size(), 0)
	assert_eq(h.summary(t[0])["titles"], 0)
	assert_eq(h.summary(t[0])["best"], null, "no seasons, no best year")


func test_a_real_played_league_obeys_the_invariants() -> void:
	var g := FcGameController.new_game(FcWorldGenerator.new(FcGenerationData.load_default(), FcDefinitionSet.load_default(), _cfg()), 12, FcGameState.MODE_OWNER, 1)
	for i in 3:
		g.sim_playoffs()
		g.start_next_season()
	var h := FcFranchiseHistory.new(g.state.world, g.league_id)
	var seasons := h.seasons()
	assert_true(seasons.size() >= 3)
	var titles := 0
	for team in g.state.world.teams.ids():
		var log := h.season_log(team)
		assert_eq(log.size(), seasons.size(), "every team has a row for every finished season")
		for row in log:
			assert_true(row["rank"] >= 1 and row["rank"] <= row["teams"])
			assert_true(row["wins"] + row["losses"] > 10, "a real season of games (an 8-team league plays a short schedule)")
			if row["champion"]:
				titles += 1
				assert_eq(row["result"], "Champions")
			if not row["playoffs"]:
				assert_eq(row["result"], "Missed the playoffs")
	assert_eq(titles, seasons.size(), "one champion per finished season")


# --- leaders -----------------------------------------------------------------------------------------------------------------------

func test_franchise_leaders_count_only_seasons_with_the_team() -> void:
	w.careers[7001] = [FcHistoryFixture.row(2000, t[0], 70, 1500, 300, 100), FcHistoryFixture.row(2001, t[0], 70, 1800, 350, 120), FcHistoryFixture.row(2002, t[1], 70, 2500, 400, 200)]
	w.careers[7002] = [FcHistoryFixture.row(2000, t[0], 60, 900, 700, 50)]
	var h := FcFranchiseHistory.new(w, lid)
	assert_eq(h.leaders(t[0], "points", 5), [[3300, 7001, 2], [900, 7002, 1]], "the 2002 season with another team does not count")
	assert_eq(h.leaders(t[0], "rebounds", 1), [[700, 7002, 1]], "7001 has 650 rebounds with t0, 7002 has 700")
	assert_eq(h.leaders(t[1], "points", 5), [[2500, 7001, 1]])
	var with := h.with_team(7001, t[0])
	assert_eq([with["seasons"], with["first"], with["last"], with["points"], with["gp"]], [2, 2000, 2001, 3300, 140])
	assert_eq(h.season_records(t[0], "points", 2), [[1800, 7001, 2001], [1500, 7001, 2000]], "best single seasons with the team, best first")
	assert_eq(h.primary_team(7001), t[0], "two seasons with t0 beat one with t1")


# --- retired numbers ---------------------------------------------------------------------------------------------------------------

func test_a_franchise_legend_gets_his_number_retired_the_season_after() -> void:
	FcHistoryFixture.retired_player(w, t[0], 2000, 9, 2000, 900001)
	var h := FcFranchiseHistory.new(w, lid)
	assert_eq(h.retired_numbers(t[0], 2008).size(), 0, "not before his career is over and a season has passed")
	var out := h.retired_numbers(t[0], 2009)
	assert_eq(out.size(), 1)
	assert_eq(out[0]["player_id"], 900001)
	assert_eq(out[0]["ceremony"], 2009, "the season after his last (2008)")
	assert_eq([out[0]["first"], out[0]["last"], out[0]["seasons"]], [2000, 2008, 9])
	assert_true(out[0]["number"] >= 1 and out[0]["number"] <= 99)
	assert_eq(out[0]["number"], FcFranchiseHistory.jersey_for(900001), "his own number when it is free")
	assert_eq(h.retired_numbers(t[1], 2020).size(), 0, "another team retires nothing for him")


func test_the_rules_for_a_retired_number() -> void:
	FcHistoryFixture.retired_player(w, t[0], 2000, 5, 2600, 900002)    # strong but only five seasons
	FcHistoryFixture.retired_player(w, t[0], 2000, 9, 400, 900003)     # long but weak
	var active := FcHistoryFixture.retired_player(w, t[0], 2000, 9, 2000, 900004)
	active.status = FcPlayer.Status.ACTIVE   # still playing
	active.retired_season = 0
	var h := FcFranchiseHistory.new(w, lid)
	assert_eq(h.retired_numbers(t[0], 2030).size(), 0, "too few seasons, too weak a career or still playing: no number")
	# a player split between two teams is honoured only by the one he spent most seasons with
	var split := FcHistoryFixture.retired_player(w, t[2], 2000, 8, 2600, 900005)
	var rows: Array = w.careers[900005]
	for i in 3:
		rows.append(FcHistoryFixture.row(2008 + i, t[3], 70, 2600, 300, 200))
	split.retired_season = 2010
	var after := FcFranchiseHistory.new(w, lid)
	assert_eq(after.primary_team(900005), t[2], "eight seasons beat three")
	assert_eq(after.retired_numbers(t[2], 2030).size(), 1, "his main team honours him")
	assert_eq(after.retired_numbers(t[3], 2030).size(), 0, "and the team he left for three seasons does not")


func test_two_legends_never_share_a_number() -> void:
	var wanted := FcFranchiseHistory.jersey_for(900010)
	var other := 900011
	while FcFranchiseHistory.jersey_for(other) != wanted:
		other += 1   # an id whose own preferred number collides with the first
	FcHistoryFixture.retired_player(w, t[0], 2000, 9, 2000, 900010)
	FcHistoryFixture.retired_player(w, t[0], 2001, 9, 2000, other)
	var out := FcFranchiseHistory.new(w, lid).retired_numbers(t[0], 2030)
	assert_eq(out.size(), 2)
	assert_true(out[0]["number"] != out[1]["number"], "numbers %d and %d" % [out[0]["number"], out[1]["number"]])
	assert_eq(out[0]["player_id"], 900010, "the first to be honoured keeps his own number")
	assert_eq(out[1]["number"], out[0]["number"] % 99 + 1, "the second takes the next free one")


func test_jersey_numbers_are_steady_and_in_range() -> void:
	for id in range(1, 400):
		var n := FcFranchiseHistory.jersey_for(id)
		assert_true(n >= 1 and n <= 99)
		assert_eq(FcFranchiseHistory.jersey_for(id), n)


func _cfg() -> FcGenerationConfig:
	var cfg := FcGenerationConfig.load_default(FcGenerationData.load_default())
	cfg.team_count = 8
	cfg.conference_count = 2
	cfg.divisions_per_conference = 1
	cfg.roster_size = 13
	cfg.free_agent_count = 15
	cfg.assistant_coaches = 1
	cfg.scouts = 0
	return cfg
