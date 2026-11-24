extends FcTestCase
## Broadcast pass 2, M7: production from templates. Every shipped template is valid and its segments all build; the game shows (pregame,
## halftime, postgame, championship) say only what the recorded game says (the tests recompute the numbers); "Full Court Tonight" says only what
## the saved league data says (recomputed here from the raw results); nothing is hard-coded per show, and nothing changes the game.

const SEEDS := [3, 12, 77]
var world: FcWorld
var ratings: FcPlayerRatings


func before_each() -> void:
	var data := FcGenerationData.load_default()
	var defs := FcDefinitionSet.load_default()
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = 8
	cfg.conference_count = 2
	cfg.divisions_per_conference = 1
	cfg.free_agent_count = 0
	world = FcWorldGenerator.new(data, defs, cfg).generate(31415)
	ratings = FcPlayerRatings.load_default()


func _timeline(seed_value: int) -> FcBroadcastTimeline:
	var ids := world.teams.ids()
	var sim := FcGameSimulator.new()
	sim.recorder = FcGameEventLog.new()
	var box := sim.simulate(FcGameTeam.from_world(world, ids[0], ratings), FcGameTeam.from_world(world, ids[1], ratings), FcRng.new(seed_value))
	return FcBroadcastTimeline.build(FcReplayModel.build(sim.recorder, box))


## A season with `days` days played and the first team's games kept (box scores), like an Owner league.
func _season(days: int) -> Dictionary:
	var league_id: int = world.leagues.ids()[0]
	var engine := FcSeasonEngine.for_league(world, league_id)
	var watched: int = world.teams.ids()[0]
	engine.watched_teams = [watched] as Array[int]
	var season := engine.start_season(league_id, 2026, FcDate.new(2026, 10, 20), FcRng.new(7))
	engine.play_days(season, days, FcRng.new(8))
	return {"engine": engine, "season": season, "league": world.leagues.get_by_id(league_id), "watched": watched}


func _input(s: Dictionary, week_start: int, week_end: int) -> Dictionary:
	var names := {}
	var abbrs := {}
	for id in (s["league"] as FcLeague).all_team_ids():
		names[id] = world.team_display_name(id)
		abbrs[id] = world.teams.get_by_id(id).identity.abbreviation
	var entries: Array = []
	for e in (s["season"] as FcSeason).recent_boxes:
		entries.append({"day": int(e["day"]), "series": int(e["series"]), "box": FcBoxScore.from_dict(e["box"])})
	var games: Array = []
	games.assign((s["season"] as FcSeason).games)
	return {"games": games, "league": s["league"], "names": names, "abbrs": abbrs, "week_start": week_start, "week_end": week_end, "box_entries": entries, "cutoff": 2}


# --- templates ----------------------------------------------------------------------------------------------------------------------

func test_every_shipped_template_is_valid_and_has_only_known_segments() -> void:
	for id in FcProductionTemplate.IDS:
		var t := FcProductionTemplate.load_template(id)
		assert_eq(FcProductionTemplate.problems(t), [], "%s is valid" % id)
		assert_eq(t["id"], id)
	assert_eq(FcProductionTemplate.load_template("full_court_tonight")["scope"], "week")
	assert_eq(FcProductionTemplate.load_template("nope"), {})


func test_template_problems_are_caught() -> void:
	assert_true(not FcProductionTemplate.problems({}).is_empty())
	var bad := {"id": "x", "title": "X", "scope": "game", "segments": [{"type": "headlines", "seconds": 5}, {"type": "matchup", "seconds": 0}, {"type": "matchup", "seconds": 3}]}
	var problems := FcProductionTemplate.problems(bad)
	assert_true(problems.size() >= 3, str(problems))
	assert_true(not FcProductionTemplate.problems({"id": "x", "title": "X", "scope": "week", "segments": []}).is_empty())
	assert_true(not FcProductionTemplate.problems({"id": "x", "title": "X", "scope": "planet", "segments": [{"type": "matchup", "seconds": 1}]}).is_empty())


# --- game shows ----------------------------------------------------------------------------------------------------------------------

func test_every_game_show_builds_every_segment_deterministically() -> void:
	for s in SEEDS:
		var t := _timeline(s)
		for id in ["pregame", "halftime", "postgame", "championship"]:
			var plan := FcProductionPlan.build(id, t, {"series_label": "Finals: A 4, B 2"})
			assert_true(not plan.is_empty(), id)
			assert_eq(plan, FcProductionPlan.build(id, t, {"series_label": "Finals: A 4, B 2"}), "deterministic")
			var template := FcProductionTemplate.load_template(id)
			assert_eq((plan["segments"] as Array).size(), (template["segments"] as Array).size())
			var total := 0.0
			for k in (plan["segments"] as Array).size():
				var seg: Dictionary = plan["segments"][k]
				assert_eq(seg["type"], template["segments"][k]["type"], "the template decides the order")
				assert_true(str(seg["title"]) != "" and float(seg["seconds"]) > 0.0)
				assert_true(bool(seg["available"]) or str(seg["note"]) != "", "an empty segment says why")
				assert_true(seg["source"] in [FcPresentationEvent.SIM_RECORDED, FcPresentationEvent.DERIVED_FROM_RECORDED])
				total += float(seg["seconds"])
			assert_true(is_equal_approx(total, float(plan["total_seconds"])))
	assert_eq(FcProductionPlan.build("pregame", null), {})
	assert_eq(FcProductionPlan.build("full_court_tonight", _timeline(3)), {}, "a week show is not a game show")


func _segment(plan: Dictionary, type: String) -> Dictionary:
	for seg in plan["segments"]:
		if seg["type"] == type:
			return seg
	return {}


func test_the_postgame_numbers_are_the_box_score() -> void:
	for s in SEEDS:
		var t := _timeline(s)
		var box := t.model.box
		var plan := FcProductionPlan.build("postgame", t)
		assert_eq(plan["index"], t.size() - 1, "postgame is at the end of the game")
		var final := _segment(plan, "final_score")
		assert_eq([int(final["facts"]["home"]), int(final["facts"]["away"])], [box.scores[0], box.scores[1]])
		assert_true(str(final["lines"][0]).contains("%d" % box.scores[0]) and str(final["lines"][0]).contains("%d" % box.scores[1]))
		# the line score adds up to the totals
		var rows: Array = _segment(plan, "line_score")["rows"]
		assert_eq(rows.size(), 3)
		for side in 2:
			var sum := 0
			for c in range(1, (rows[side + 1] as Array).size() - 1):
				sum += int(rows[side + 1][c])
			assert_eq(sum, box.scores[side], "the periods add up to the final score")
			assert_eq(int(rows[side + 1][(rows[side + 1] as Array).size() - 1]), box.scores[side])
		# player of the game is the best by the stated formula (ties: more points, then the lower id)
		var best: FcPlayerGameStats = null
		var best_value := -1
		for p in box.players:
			var v: int = p.points + p.oreb + p.dreb + p.ast + p.stl + p.blk
			if best == null or v > best_value or (v == best_value and (p.points > best.points or (p.points == best.points and p.player_id < best.player_id))):
				best = p
				best_value = v
		var pog := _segment(plan, "player_of_game")
		assert_eq(int(pog["facts"]["player_id"]), best.player_id)
		assert_eq(int(pog["facts"]["value"]), best_value)
		assert_eq(int(pog["facts"]["points"]), best.points)
		assert_true(str(pog["lines"][1]).contains("points + rebounds"), "the formula is stated")
		# milestones are real
		for m in _segment(plan, "milestones")["facts"]["milestones"]:
			assert_eq(int(t.snapshot(int(m["index"]))["milestone"]["points"]), int(m["points"]))
		# team comparison equals the box totals
		var card := _segment(plan, "team_comparison")
		assert_eq(int(card["facts"]["home"]["fgm"]), box.team_totals(0)["fgm"])
		assert_eq(int(card["facts"]["away"]["reb"]), box.team_totals(1)["oreb"] + box.team_totals(1)["dreb"])


func test_halftime_is_at_the_half_and_only_uses_what_has_happened() -> void:
	for s in SEEDS:
		var t := _timeline(s)
		var plan := FcProductionPlan.build("halftime", t)
		var index := int(plan["index"])
		assert_eq(int(t.model.entries[index]["type"]), FcGameEventLog.EV_PERIOD_END)
		assert_eq(int(t.model.entries[index]["x"]) * 2, t.model.quarters)
		var snap := t.snapshot(index)
		assert_eq(int(_segment(plan, "halftime_score")["facts"]["home"]), int(snap["home"]))
		assert_eq(int(_segment(plan, "storyline")["facts"]["lead_changes"]), int(snap["lead_changes"]))
		for ref in _segment(plan, "highlights")["facts"]["refs"]:
			assert_true(int(ref["end"]) <= index, "no highlight from the second half")
		assert_true(float(snap["home"]) < float(t.model.box.scores[0]) + 1.0)


func test_pregame_shows_the_matchup_and_the_starters() -> void:
	var t := _timeline(12)
	var plan := FcProductionPlan.build("pregame", t)
	assert_eq(plan["index"], t.model.start_index())
	var matchup := _segment(plan, "matchup")
	assert_true(str(matchup["lines"][0]).contains(str(t.model.box.team_names[1])) and str(matchup["lines"][0]).contains(str(t.model.box.team_names[0])))
	var lineups := _segment(plan, "lineups")
	assert_eq((lineups["rows"] as Array).size(), 10, "ten starters")
	var card := FcBroadcastGraphics.lineup_card(t)
	for side in 2:
		for r in card["sides"][side]["rows"]:
			var found := false
			for row in lineups["rows"]:
				if row[2] == r[1] and row[1] == r[0] and row[3] == r[2]:
					found = true
			assert_true(found, "%s is in the show" % r[1])


func test_the_championship_names_the_winner_and_the_series() -> void:
	var t := _timeline(12)
	var plan := FcProductionPlan.build("championship", t, {"series_label": "Finals: Houston Sentinels 4, Mexico City Bonfires 2"})
	var trophy := _segment(plan, "trophy")
	var home_won := t.model.box.scores[0] > t.model.box.scores[1]
	assert_eq(int(trophy["facts"]["champion_side"]), 0 if home_won else 1, "the champion is the winner of the game")
	assert_true(str(trophy["lines"][0]).contains(str(t.model.box.team_names[0 if home_won else 1])))
	assert_true(str(trophy["lines"][1]).contains("Finals"))
	var without := _segment(FcProductionPlan.build("championship", t), "trophy")
	assert_eq((without["lines"] as Array).size(), 2, "no series label, no series line")


func test_building_a_show_changes_nothing() -> void:
	var t := _timeline(12)
	var before := t.model.entries.duplicate(true)
	var scores := t.model.box.scores.duplicate()
	for id in ["pregame", "halftime", "postgame", "championship"]:
		FcProductionPlan.build(id, t)
	assert_eq(t.model.entries, before)
	assert_eq(t.model.box.scores, scores)


# --- Full Court Tonight ----------------------------------------------------------------------------------------------------------------

func test_the_weekly_show_builds_every_segment_from_saved_results() -> void:
	var s := _season(40)
	var season: FcSeason = s["season"]
	var input := _input(s, season.next_day - 7, season.next_day - 1)
	var plan := FcWeeklyRecap.build(input)
	assert_true(not plan.is_empty())
	assert_eq(plan, FcWeeklyRecap.build(input), "deterministic")
	var template := FcProductionTemplate.load_template("full_court_tonight")
	assert_eq((plan["segments"] as Array).size(), (template["segments"] as Array).size())
	for k in (plan["segments"] as Array).size():
		var seg: Dictionary = plan["segments"][k]
		assert_eq(seg["type"], template["segments"][k]["type"])
		assert_true(bool(seg["available"]) or str(seg["note"]) != "")
	var headlines := _segment(plan, "headlines")
	assert_true((headlines["lines"] as Array).size() >= 2, str(headlines["lines"]))


func test_game_of_the_week_is_the_most_exciting_played_game() -> void:
	var s := _season(40)
	var season: FcSeason = s["season"]
	var ws := season.next_day - 7
	var we := season.next_day - 1
	var plan := FcWeeklyRecap.build(_input(s, ws, we))
	var gow := _segment(plan, "game_of_the_week")
	var best_score := -1000
	for g in season.games:
		if g.played and g.series == 0 and g.day >= ws and g.day <= we:
			best_score = maxi(best_score, FcWeeklyRecap.excitement(g))
	assert_eq(int(gow["facts"]["excitement"]), best_score)
	var found := false
	for g in season.games:
		if g.played and g.day == int(gow["facts"]["day"]) and g.home_id == int(gow["facts"]["home_id"]) and g.away_id == int(gow["facts"]["away_id"]):
			assert_eq([g.home_score, g.away_score], [int(gow["facts"]["home_score"]), int(gow["facts"]["away_score"])], "the score is the saved score")
			found = true
	assert_true(found, "it is a real game")


func test_upsets_are_real_results_where_the_worse_record_won() -> void:
	var s := _season(60)
	var season: FcSeason = s["season"]
	var ws := maxi(0, season.next_day - 21)
	var we := season.next_day - 1
	var input := _input(s, ws, we)
	var plan := FcWeeklyRecap.build(input)
	var before_games: Array[FcScheduledGame] = []
	for g in season.games:
		if g.played and g.series == 0 and g.day < ws:
			before_games.append(g)
	var before := FcStandings.compute(s["league"], before_games)
	var ups: Array = _segment(plan, "upsets")["facts"]["upsets"]
	for u in ups:
		var found := false
		for g in season.games:
			if g.played and g.series == 0 and g.day == int(u["day"]) and g.winner_id() == int(u["winner"]) and g.loser_id() == int(u["loser"]):
				found = true
		assert_true(found, "the upset game exists")
		assert_true(before.win_pct(int(u["loser"])) - before.win_pct(int(u["winner"])) >= FcWeeklyRecap.UPSET_GAP - 0.0001, "the winner really had the much worse record")
		assert_true(before.games_played(int(u["winner"])) >= FcWeeklyRecap.MIN_GAMES_FOR_UPSET)


func test_streaks_and_standings_equal_the_standings_engine() -> void:
	var s := _season(50)
	var season: FcSeason = s["season"]
	var input := _input(s, season.next_day - 7, season.next_day - 1)
	var plan := FcWeeklyRecap.build(input)
	var after := FcStandings.compute(s["league"], season.games)
	for st in _segment(plan, "streaks")["facts"]["streaks"]:
		assert_eq(int(st["streak"]), int(after.records[int(st["team"])]["streak"]))
		assert_true(absi(int(st["streak"])) >= FcWeeklyRecap.STREAK_MIN)
	var race: Array = _segment(plan, "standings_race")["facts"]["standings"]
	assert_eq(race.size(), (s["league"] as FcLeague).team_count())
	for row in race:
		assert_eq([int(row["w"]), int(row["l"])], [int(after.records[int(row["team"])]["w"]), int(after.records[int(row["team"])]["l"])])
	# ranks run 1..n within each conference and follow the engine's order
	for conference in (s["league"] as FcLeague).conferences:
		var order := after.conference_ranking(conference)
		for i in order.size():
			var match_row := race.filter(func(r: Dictionary) -> bool: return int(r["team"]) == order[i])
			assert_eq(int(match_row[0]["rank"]), i + 1)
	var rows: Array = _segment(plan, "standings_race")["rows"]
	var marks := rows.filter(func(r: Array) -> bool: return str(r[3]) == "last in" or str(r[3]) == "first out")
	assert_eq(marks.size(), 4, "the cutoff line is marked in both conferences")


func test_marquee_matchups_are_scheduled_unplayed_games_ranked_by_record() -> void:
	var s := _season(0)
	(s["engine"] as FcSeasonEngine).play_days(s["season"], int((s["season"] as FcSeason).total_days() / 2.0), FcRng.new(8))   # half the season: there are games ahead
	var season: FcSeason = s["season"]
	var we := season.next_day - 1
	var plan := FcWeeklyRecap.build(_input(s, we - 6, we))
	var seg := _segment(plan, "marquee_matchups")
	assert_true(bool(seg["available"]))
	var last := 1000.0
	for g in seg["facts"]["games"]:
		var found := false
		for sg in season.games:
			if not sg.played and sg.series == 0 and sg.day == int(g["day"]) and sg.home_id == int(g["home_id"]) and sg.away_id == int(g["away_id"]):
				found = true
		assert_true(found and int(g["day"]) > we and int(g["day"]) <= we + 7, "an upcoming scheduled game")
		assert_true(float(g["combined"]) <= last + 0.0001, "best combined record first")
		last = float(g["combined"])


func test_player_segments_use_only_kept_boxes_and_say_so() -> void:
	var s := _season(40)
	var season: FcSeason = s["season"]
	var ws := season.next_day - 14
	var we := season.next_day - 1
	var input := _input(s, ws, we)
	var plan := FcWeeklyRecap.build(input)
	var pow_seg := _segment(plan, "player_of_the_week")
	var best := _segment(plan, "best_performances")
	assert_true(bool(pow_seg["available"]) and bool(best["available"]), "the watched team's boxes were kept")
	assert_true(str(pow_seg["lines"][1]).contains("only for the team you follow"), "the limit is stated")
	var totals := {}
	for e in input["box_entries"]:
		if int(e["day"]) < ws or int(e["day"]) > we:
			continue
		for p in (e["box"] as FcBoxScore).players:
			totals[p.player_id] = int(totals.get(p.player_id, 0)) + FcWeeklyRecap.line_value(p)
	var top := 0
	for pid in totals:
		top = maxi(top, int(totals[pid]))
	assert_eq(int(pow_seg["facts"]["total"]), top, "the player of the week has the highest total")
	var last := 100000
	for l in best["facts"]["lines"]:
		assert_true(int(l["value"]) <= last, "best first")
		last = int(l["value"])
	# without boxes the segments say why
	input["box_entries"] = []
	var none := FcWeeklyRecap.build(input)
	assert_true(not bool(_segment(none, "player_of_the_week")["available"]))
	assert_true(str(_segment(none, "player_of_the_week")["note"]).contains("box scores"))


func test_a_quiet_week_and_a_fresh_season_never_fail() -> void:
	var s := _season(0)
	var input := _input(s, 0, 0)
	var plan := FcWeeklyRecap.build(input)
	assert_true(not plan.is_empty())
	assert_true(not bool(_segment(plan, "game_of_the_week")["available"]))
	assert_true(str(_segment(plan, "headlines")["lines"][0]).contains("quiet week"))
	assert_eq(_segment(plan, "upsets")["facts"]["upsets"], [])


func test_the_weekly_show_changes_no_saved_data() -> void:
	var s := _season(30)
	var season: FcSeason = s["season"]
	var before := season.to_dict()
	FcWeeklyRecap.build(_input(s, season.next_day - 7, season.next_day - 1))
	assert_eq(season.to_dict(), before)


# --- the panel -----------------------------------------------------------------------------------------------------------------------------------

func test_the_panel_steps_through_segments_and_auto_advances_on_each_segments_length() -> void:
	var t := _timeline(12)
	var plan := FcProductionPlan.build("postgame", t)
	var panel := FcProductionPanel.new()
	panel.show_plan(plan)
	assert_true(panel.visible and panel.segment_index == 0)
	assert_true(panel.summary().contains("Final"), panel.summary())
	panel.next()
	assert_eq(panel.segment_index, 1)
	panel.previous()
	panel.previous()
	assert_eq(panel.segment_index, 0, "no going before the first")
	panel.set_auto(true)
	panel.advance(float(plan["segments"][0]["seconds"]) - 0.1)
	assert_eq(panel.segment_index, 0, "not yet")
	panel.advance(0.2)
	assert_eq(panel.segment_index, 1, "the next one after its length")
	for i in 40:
		panel.advance(30.0)
	assert_eq(panel.segment_index, panel.segment_count() - 1, "it stops on the last segment")
	assert_true(not panel.auto, "and switches auto off")
	panel.show_plan({})
	assert_true(not panel.visible)
	panel.free()
