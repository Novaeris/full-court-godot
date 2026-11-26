extends FcTestCase
## The Franchise Experience data foundation (M2 of D-077, save data version 5): stable game ids, compact result lines, day logs and the
## integrity checker, game logs, starts and shots at the rim, transactions, rating history, stored jersey numbers, owner objectives, sim
## preferences and the ledger, followed games and what a game may offer (FcGameAvailability), and the 4 -> 5 migration of a real old save.

const SAVE_DIR := "user://test_franchise_data"


func _config() -> FcGenerationConfig:
	var data := FcGenerationData.load_default()
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = 8
	cfg.conference_count = 2
	cfg.divisions_per_conference = 1
	cfg.roster_size = 13
	cfg.free_agent_count = 10
	cfg.assistant_coaches = 1
	cfg.scouts = 0
	return cfg


func _game(seed_value: int = 21) -> FcGameController:
	var data := FcGenerationData.load_default()
	return FcGameController.new_game(FcWorldGenerator.new(data, FcDefinitionSet.load_default(), _config()), seed_value, FcGameState.MODE_OWNER, 0)


func after_each() -> void:
	var dir := DirAccess.open(SAVE_DIR)
	if dir != null:
		for f in dir.get_files():
			dir.remove(f)


# --- game ids and result lines ------------------------------------------------------------------------------------

func test_every_game_gets_a_unique_stable_id_including_playoffs_and_the_next_season() -> void:
	var g := _game()
	var first := g.season()
	var seen := {}
	for game in first.games:
		assert_true(game.id > 0, "a scheduled game has an id")
		assert_true(not seen.has(game.id), "ids are unique")
		seen[game.id] = true
	g.sim_playoffs()
	for game in first.games:
		if game.series > 0:
			assert_true(game.id > 0 and not seen.has(game.id), "a playoff game gets a new id")
			seen[game.id] = true
	assert_eq(first.game_by_id(first.games[3].id), first.games[3])
	assert_eq(first.game_by_id(0), null)
	g.start_next_season()
	for game in g.season().games:
		assert_true(not seen.has(game.id), "a new season never reuses an id")
	assert_eq(FcSimIntegrity.check(g.state), [] as Array[String])


func test_a_played_game_keeps_a_compact_line_that_adds_up() -> void:
	var g := _game()
	g.advance_days(6)
	var checked := 0
	for game in g.season().games:
		if not game.played:
			continue
		checked += 1
		var line := game.line
		assert_eq((line["q"] as Array).size(), 2)
		var home_total := 0
		for v in line["q"][0]:
			home_total += int(v)
		assert_eq(home_total, game.home_score, "the periods add up to the score")
		assert_eq((line["top"] as Array).size(), 6, "three performers per team")
		var winner := game.winner_id()
		var pog_team := g.state.world.team_of_player(int(line["pog"]))
		assert_true(pog_team != null and pog_team.id == winner, "the player of the game is on the winning team")
		var round_trip := FcScheduledGame.from_dict(JSON.parse_string(JSON.stringify(game.to_dict())))
		assert_eq(round_trip.line, line, "the line survives JSON")
		assert_eq(round_trip.id, game.id)
	assert_true(checked > 0)


# --- day log and integrity ----------------------------------------------------------------------------------------

func test_each_processed_day_is_logged_and_the_integrity_check_passes() -> void:
	var g := _game()
	g.advance_days(10)
	var s := g.season()
	assert_eq(s.day_log.size(), 10, "one entry per processed day")
	var logged_games := 0
	for day in s.day_log:
		assert_true(s.day_log[day].has("c"), "regular-season days carry the standings checksum")
		logged_games += (s.day_log[day]["g"] as Array).size()
	assert_eq(logged_games, s.games_played_count(), "every played game is in exactly one day's log")
	assert_eq(FcSimIntegrity.check(g.state), [] as Array[String])
	g.sim_playoffs()
	assert_eq(FcSimIntegrity.check(g.state), [] as Array[String], "still consistent through the playoffs")


func test_the_integrity_check_catches_tampering() -> void:
	var g := _game()
	g.advance_days(5)
	var s := g.season()
	var future: FcScheduledGame = null
	for game in s.games:
		if game.day > s.next_day + 3:
			future = game
			break
	future.played = true
	future.home_score = 100
	future.away_score = 90
	var problems := FcSimIntegrity.check(g.state)
	assert_true(problems.any(func(p: String) -> bool: return p.contains("played before its day")), str(problems))
	future.played = false
	s.games[0].id = s.games[1].id
	assert_true(FcSimIntegrity.check(g.state).any(func(p: String) -> bool: return p.contains("used twice")))
	s.games[0].id = 999999
	var first_day: int = s.day_log.keys()[0]
	s.day_log[first_day]["c"] = 1
	assert_true(FcSimIntegrity.check(g.state).any(func(p: String) -> bool: return p.contains("disagrees with the results")))


func test_injuries_and_returns_are_logged_on_their_day() -> void:
	var g := _game(5)
	g.advance_days(60)
	var injuries := 0
	var returns := 0
	for day in g.season().day_log:
		injuries += (g.season().day_log[day]["i"] as Array).size()
		returns += (g.season().day_log[day]["r"] as Array).size()
	assert_true(injuries > 0, "sixty days bring injuries")
	assert_true(returns > 0, "and returns")
	for day in g.season().day_log:
		for row in g.season().day_log[day]["i"]:
			assert_true(int(row[1]) > 0 and str(row[2]) != "")


# --- game logs and new statistics -------------------------------------------------------------------------------------

func test_the_user_teams_players_get_game_logs_and_new_columns() -> void:
	var g := _game()
	g.advance_days(20)
	var s := g.season()
	var user := g.state.user_team_id
	var any := false
	for pid in s.game_logs:
		var team := g.state.world.team_of_player(int(pid))
		assert_true(team != null and team.id == user, "only the watched team is logged")
		assert_eq((s.game_logs[pid] as Array).size(), s.stats.games_played(int(pid)), "one row per game played")
		any = true
	assert_true(any)
	var rim_total := 0
	for pid in s.stats.lines:
		var l: Dictionary = s.stats.lines[pid]
		assert_true(int(l["rim_m"]) <= int(l["rim_a"]))
		assert_true(int(l["rim_a"]) <= int(l["fga"]) - int(l["tpa"]), "rim attempts are two-point attempts")
		assert_true(int(l["gs"]) <= int(l["gp"]))
		rim_total += int(l["rim_a"])
	assert_true(rim_total > 0, "shots at the rim are counted")
	var back := FcSeasonStats.from_dict(JSON.parse_string(JSON.stringify(s.stats.to_dict())))
	for pid in s.stats.lines:
		assert_eq(back.lines[pid]["rim_a"], s.stats.lines[pid]["rim_a"])
		assert_eq(back.lines[pid]["gs"], s.stats.lines[pid]["gs"])
	var old_row := FcSeasonStats.from_dict({"5": [1, "Old", 1, 60, 2, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]})
	assert_eq(old_row.lines[5]["rim_a"], 0, "seasons saved before the new columns read them as zero")


# --- transactions, ratings, numbers -----------------------------------------------------------------------------------

func test_signings_releases_and_trades_are_transactions_linked_to_the_news() -> void:
	var g := _game()
	var w := g.state.world
	var market := g.free_agent_market(10)
	market.sort_custom(func(a, b) -> bool: return int(a["ask"]) < int(b["ask"]))
	var signed := g.sign_free_agent(market[0]["player"].id, int(market[0]["ask"]), int(market[0]["years"]))
	assert_true(signed["signed"], str(signed))
	var roster: Array = w.teams.get_by_id(g.state.user_team_id).roster.player_ids.duplicate()
	var released := g.release_player(int(roster[0]))
	assert_true(released["released"], str(released))
	var kinds := w.transactions.map(func(t: Dictionary) -> String: return t["kind"])
	assert_true(kinds.has("release") and kinds.has("signing"), str(kinds))
	var ids := {}
	for t in w.transactions:
		assert_true(int(t["id"]) > 0 and not ids.has(t["id"]))
		ids[t["id"]] = true
		assert_eq(t["date"], g.state.current_date.to_iso())
	var linked := w.news.filter(func(n: Dictionary) -> bool: return n.has("txn"))
	assert_eq(linked.size(), 2, "each transaction has its news item")
	assert_eq(w.transactions_on(g.state.current_date.to_iso()).size(), 2)
	assert_eq(FcRosterNumbers.problems(w, g.state.current_season), [] as Array[String], "the new player got a free number")
	var back := FcWorld.from_dict(JSON.parse_string(JSON.stringify(w.to_dict())), FcDefinitionSet.load_default())
	assert_eq(back.transactions, w.transactions)
	assert_eq(back.news.filter(func(n: Dictionary) -> bool: return n.has("txn")).size(), 2)


func test_ratings_are_recorded_when_a_season_ends() -> void:
	var g := _game()
	g.sim_playoffs()
	var w := g.state.world
	var rostered: int = w.teams.get_by_id(g.state.user_team_id).roster.player_ids[0]
	var rows: Array = w.rating_history.get(rostered, [])
	assert_eq(rows.size(), 1)
	assert_eq(int(rows[0][0]), g.season().year)
	assert_true(int(rows[0][1]) > 0 and int(rows[0][2]) > 0)
	w.record_rating(rostered, g.season().year, 50, 60)
	assert_eq((w.rating_history[rostered] as Array).size(), 1, "the same year is replaced, not added")


func test_jersey_numbers_are_unique_on_every_roster_and_survive_the_offseason() -> void:
	var g := _game()
	var w := g.state.world
	assert_eq(FcRosterNumbers.problems(w, g.state.current_season), [] as Array[String])
	for t in w.teams.all():
		for pid in t.roster.player_ids:
			var p: FcPlayer = w.players.get_by_id(pid)
			assert_true(p.jersey_number >= 1 and p.jersey_number <= 99)
	var p0: FcPlayer = w.players.get_by_id(w.teams.get_by_id(g.state.user_team_id).roster.player_ids[0])
	var kept := p0.jersey_number
	g.sim_playoffs()
	g.start_next_season()
	assert_eq(FcRosterNumbers.problems(w, g.state.current_season), [] as Array[String], "after the draft, free agency and trades")
	if w.team_of_player(p0.id) != null and w.team_of_player(p0.id).id == g.state.user_team_id:
		assert_eq(p0.jersey_number, kept, "a player who stays keeps his number")
	# a clash: two teammates with the same number are separated, the lower id keeping it
	var team: FcTeam = w.teams.get_by_id(g.state.user_team_id)
	var a: FcPlayer = w.players.get_by_id(team.roster.player_ids[0])
	var b: FcPlayer = w.players.get_by_id(team.roster.player_ids[1])
	b.jersey_number = a.jersey_number
	FcRosterNumbers.ensure_team(w, team.id)
	assert_true(a.jersey_number != b.jersey_number)
	# a pinned number (the Career player's choice) wins
	var wanted := a.jersey_number
	FcRosterNumbers.ensure_team(w, team.id, [], {b.id: wanted})
	assert_eq(b.jersey_number, wanted, "the pinned player gets his number")
	assert_true(a.jersey_number != wanted, "and the teammate who wore it moves")
	assert_eq(FcRosterNumbers.problems(w, g.state.current_season, {b.id: wanted}).size(), 0)


# --- objectives, preferences, ledger --------------------------------------------------------------------------------

func test_owner_objectives_are_set_once_and_judged_at_the_end() -> void:
	var g := _game()
	var list := g.objectives()
	assert_true(list.size() >= 2, "a season starts with objectives")
	assert_eq(list[0]["kind"], "wins")
	for o in list:
		assert_eq(o["status"], FcOwnerObjectives.STATUS_OPEN)
	var copy := list.duplicate(true)
	g.advance_days(15)
	g._ensure_objectives()
	assert_eq(g.objectives(), copy, "never regenerated during the season")
	var year := g.state.current_season
	var rep_before := g.owner_reputation()
	g.begin_offseason()
	var judged: Array = g.state.owner_objectives[year]
	for o in judged:
		assert_true(o["status"] == FcOwnerObjectives.STATUS_MET or o["status"] == FcOwnerObjectives.STATUS_MISSED)
	assert_true(rep_before >= 0)
	var back := FcGameState.from_dict(JSON.parse_string(JSON.stringify(g.state.to_dict())), FcDefinitionSet.load_default())
	assert_eq(back.owner_objectives[year], judged)


func test_objective_rules() -> void:
	var list := FcOwnerObjectives.generate({"games": 80, "expected_wins": 50.0, "last_wins": 44, "last_profit": 12_000_000, "has_books": true, "playoff_teams": 8, "teams": 16})
	assert_eq(list[0]["target"], 50)
	assert_eq(list[1]["kind"], "playoffs")
	assert_eq(list[1]["target"], 2, "a strong team must win a round")
	assert_eq(list[2]["kind"], "profit")
	var weak := FcOwnerObjectives.generate({"games": 80, "expected_wins": 30.0, "last_wins": 20, "has_books": false, "playoff_teams": 8, "teams": 16})
	assert_eq(weak[0]["target"], 30)
	assert_true(not weak.any(func(o) -> bool: return o["kind"] == "playoffs"), "a weak team is not asked for the playoffs")
	assert_true(not weak.any(func(o) -> bool: return o["kind"] == "profit"), "no books, no profit goal")
	var judged := FcOwnerObjectives.evaluate(list, {"wins": 52, "playoff_round": 1, "profit": 20_000_000, "young_minutes": 12.0})
	assert_eq(judged.map(func(o) -> String: return o["status"]), ["met", "missed", "met", "missed"])
	assert_eq(FcOwnerObjectives.reputation_delta(judged), 3 - 2 + 3 - 2)


func test_sim_preferences_and_the_ledger() -> void:
	var g := _game()
	assert_eq(g.state.sim_pref("speed"), "normal")
	assert_eq(g.state.sim_pref("autosave_days"), 7)
	g.state.sim_prefs["speed"] = "fast"
	g.state.sim_prefs["pause_injuries"] = false
	assert_true(g.state.ledger_mark("event:2026:deadline", "2027-02-10"))
	assert_true(not g.state.ledger_mark("event:2026:deadline", "2027-02-11"), "a key is processed once")
	assert_eq(g.state.ledger["event:2026:deadline"], "2027-02-10", "the first date wins")
	var back := FcGameState.from_dict(JSON.parse_string(JSON.stringify(g.state.to_dict())), FcDefinitionSet.load_default())
	assert_eq(back.sim_pref("speed"), "fast")
	assert_eq(back.sim_pref("pause_injuries"), false)
	assert_true(back.ledger_has("event:2026:deadline"))


# --- availability and followed games -----------------------------------------------------------------------------------

func test_game_availability_follows_the_stored_data() -> void:
	var g := _game()
	var s := g.season()
	var user := g.state.user_team_id
	var next := g.next_user_game()
	var caps := FcGameAvailability.capabilities(s, next, user, next)
	assert_true(caps["preview"] and caps["watch_live"] and caps["user_game"])
	assert_true(not caps["replay"] and not caps["box_score"], "nothing to replay before the game")
	var later: FcScheduledGame = null
	var other: FcScheduledGame = null
	for game in s.games:
		if game.involves(user) and game.id != next.id and later == null:
			later = game
		if not game.involves(user) and game.day > 2 and other == null:
			other = game
	assert_true(not FcGameAvailability.capabilities(s, later, user, next)["watch_live"], "only the next game can be watched live")
	var other_caps := FcGameAvailability.capabilities(s, other, user, next)
	assert_true(other_caps["follow"] and not other_caps["user_game"])
	s.followed.append(other.id)
	g.advance_days(other.day + 1)
	var played := FcGameAvailability.capabilities(s, other, user, g.next_user_game())
	assert_true(played["replay"] and played["box_score"] and played["play_by_play"], "a followed game is recorded")
	assert_eq(FcGameAvailability.stored_box(s, other)["game_id"], other.id)
	assert_true(played["result_line"] and played["final_score"])
	var unfollowed: FcScheduledGame = null
	for game in s.games:
		if game.played and not game.involves(user) and not s.followed.has(game.id):
			unfollowed = game
			break
	var plain := FcGameAvailability.capabilities(s, next, user, g.next_user_game())
	assert_true(plain["replay"], "the user's played game has its replay")
	var other_plain := FcGameAvailability.capabilities(s, unfollowed, user, g.next_user_game())
	assert_true(not other_plain["replay"] and not other_plain["box_score"] and other_plain["result_line"], "an unfollowed game has only its line")


# --- the 4 -> 5 migration ------------------------------------------------------------------------------------------------

func test_a_real_version_4_save_loads_with_ids_numbers_and_a_clean_integrity_check() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var text := FileAccess.get_file_as_string("res://tests/fixtures/save_v4_owner.sav")
	assert_true(text.length() > 1000, "the fixture exists")
	var f := FileAccess.open(SAVE_DIR.path_join("old.sav"), FileAccess.WRITE)
	f.store_string(text)
	f.close()
	var result := FcSaveManager.new(SAVE_DIR).load_slot("old", FcDefinitionSet.load_default())
	assert_true(result.is_ok(), result.message)
	var state := result.state
	var seen := {}
	var top := 0
	for season in state.world.seasons.all():
		for game in season.games:
			assert_true(game.id > 0 and not seen.has(game.id), "every old game got a unique id")
			seen[game.id] = true
			top = maxi(top, game.id)
		for entry in season.recent_boxes:
			assert_true(int(entry.get("game_id", 0)) > 0, "old box scores are linked to their games")
			var game: FcScheduledGame = season.game_by_id(int(entry["game_id"]))
			assert_eq(game.day, int(entry["day"]))
	assert_eq(state.world.ids.issued_count(FcScheduledGame.KIND), top, "the counter continues after the last id")
	var c := FcGameController.resume(state)
	assert_eq(FcRosterNumbers.problems(state.world, state.current_season), [] as Array[String], "numbers are given out on load")
	assert_eq(FcSimIntegrity.check(state), [] as Array[String])
	assert_true(c.objectives().size() >= 2, "an old Owner save gets this season's objectives")
	c.advance_days(3)
	assert_eq(FcSimIntegrity.check(state), [] as Array[String], "and keeps playing consistently")
	for game in c.season().games:
		if game.played and game.day >= c.season().next_day - 3:
			assert_true(not game.line.is_empty(), "games played after loading get their line")
	var resaved := FcSaveManager.new(SAVE_DIR).save("again", state)
	assert_true(resaved.is_ok())
	var again := FcSaveManager.new(SAVE_DIR).load_slot("again", FcDefinitionSet.load_default())
	assert_true(again.is_ok(), again.message)
	assert_eq(JSON.stringify(again.state.to_dict()), JSON.stringify(state.to_dict()), "a saved version-5 game loads back exactly")


func test_the_same_seed_gives_the_same_season() -> void:
	var a := _game(77)
	var b := _game(77)
	a.advance_days(12)
	b.advance_days(12)
	assert_eq(JSON.stringify(a.state.to_dict()), JSON.stringify(b.state.to_dict()))
