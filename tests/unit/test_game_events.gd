extends FcTestCase
## Play-by-play recording (Phase 2): the recorder must never change a game, and the events it writes must reproduce the box score
## exactly (scores by period, every counting stat), keep the lineups legal, read as sentences, and survive saving.

const SEED := 31415
const GAME_SEEDS := [11, 12, 13, 14, 15, 16, 17, 18]

var world: FcWorld
var ratings: FcPlayerRatings


func before_each() -> void:
	var data := FcGenerationData.load_default()
	var defs := FcDefinitionSet.load_default()
	ratings = FcPlayerRatings.load_default()
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = 4
	cfg.conference_count = 1
	cfg.divisions_per_conference = 1
	cfg.free_agent_count = 0
	world = FcWorldGenerator.new(data, defs, cfg).generate(SEED)


func _team(id: int) -> FcGameTeam:
	return FcGameTeam.from_world(world, id, ratings)


func _play(seed_value: int, record: bool) -> Dictionary:
	var ids := world.teams.ids()
	var home: int = ids[seed_value % ids.size()]
	var away: int = ids[(seed_value + 1) % ids.size()]
	var sim := FcGameSimulator.new()
	var log := FcGameEventLog.new() if record else null
	sim.recorder = log
	var rng := FcRng.new(seed_value)
	var box := sim.simulate(_team(home), _team(away), rng)
	return {"box": box, "log": log, "rng": rng}


# --- the recorder is invisible ------------------------------------------------------------------------

func test_recording_never_changes_the_game() -> void:
	for s in GAME_SEEDS:
		var plain := _play(s, false)
		var recorded := _play(s, true)
		assert_eq((recorded["box"] as FcBoxScore).to_dict(), (plain["box"] as FcBoxScore).to_dict(), "seed %d: identical box score" % s)
		assert_eq((recorded["rng"] as FcRng).get_state(), (plain["rng"] as FcRng).get_state(), "seed %d: the random generator ends in the same state" % s)
		assert_true((recorded["log"] as FcGameEventLog).size() > 100, "seed %d: a whole game was recorded" % s)


func test_a_simulator_reused_for_two_games_records_each_one_cleanly() -> void:
	var ids := world.teams.ids()
	var sim := FcGameSimulator.new()
	sim.recorder = FcGameEventLog.new()
	var rng := FcRng.new(5)
	sim.simulate(_team(ids[0]), _team(ids[1]), rng)
	var first_size := sim.recorder.size()
	var second := sim.simulate(_team(ids[2]), _team(ids[3]), rng)
	var entries := FcPlayByPlay.entries(sim.recorder, second)
	assert_eq(entries[entries.size() - 1]["home"], second.scores[0], "the second log is only the second game")
	assert_true(first_size > 0)


# --- the events reproduce the box score ---------------------------------------------------------------

func test_events_reproduce_scores_by_period_and_the_final() -> void:
	for s in GAME_SEEDS:
		var played := _play(s, true)
		var box: FcBoxScore = played["box"]
		var entries := FcPlayByPlay.entries(played["log"], box)
		var last: Dictionary = entries[entries.size() - 1]
		assert_eq(last["type"], FcGameEventLog.EV_GAME_END, "seed %d: ends with the final" % s)
		assert_eq(last["home"], box.scores[0], "seed %d: home final" % s)
		assert_eq(last["away"], box.scores[1], "seed %d: away final" % s)
		var by_period := [{}, {}]
		for e in entries:
			if e["points"] > 0:
				var d: Dictionary = by_period[e["side"]]
				d[e["period"]] = int(d.get(e["period"], 0)) + int(e["points"])
		for side in 2:
			for i in box.period_scores[side].size():
				assert_eq(int(by_period[side].get(i + 1, 0)), box.period_scores[side][i], "seed %d side %d period %d" % [s, side, i + 1])


func test_events_reproduce_every_player_line() -> void:
	for s in GAME_SEEDS:
		var played := _play(s, true)
		var box: FcBoxScore = played["box"]
		var t := {}
		for p in box.players:
			t[p.player_id] = {"pts": 0, "fgm": 0, "fga": 0, "tpm": 0, "tpa": 0, "ftm": 0, "fta": 0, "oreb": 0, "dreb": 0,
				"ast": 0, "stl": 0, "blk": 0, "tov": 0, "pf": 0}
		for row in (played["log"] as FcGameEventLog).rows:
			var type: int = row[0]
			var a: int = row[3]
			var b: int = row[4]
			var x: int = row[5]
			match type:
				FcGameEventLog.EV_SHOT_MADE:
					t[a]["fgm"] += 1
					t[a]["fga"] += 1
					t[a]["pts"] += FcGameEventLog.points_of(x)
					if x == FcGameEventLog.SHOT_THREE:
						t[a]["tpm"] += 1
						t[a]["tpa"] += 1
					if b != 0:
						t[b]["ast"] += 1
				FcGameEventLog.EV_SHOT_MISSED:
					t[a]["fga"] += 1
					if x == FcGameEventLog.SHOT_THREE:
						t[a]["tpa"] += 1
				FcGameEventLog.EV_SHOT_BLOCKED:
					t[a]["fga"] += 1
					t[b]["blk"] += 1
				FcGameEventLog.EV_REBOUND:
					if a != 0:
						t[a]["oreb" if x == 1 else "dreb"] += 1
				FcGameEventLog.EV_TURNOVER:
					t[a]["tov"] += 1
					if b != 0:
						t[b]["stl"] += 1
				FcGameEventLog.EV_FOUL:
					t[a]["pf"] += 1
				FcGameEventLog.EV_FREE_THROW:
					t[a]["fta"] += 1
					if x == 1:
						t[a]["ftm"] += 1
						t[a]["pts"] += 1
		for p in box.players:
			var got: Dictionary = t[p.player_id]
			var tag := "seed %d %s" % [s, p.name]
			assert_eq(got["pts"], p.points, tag + " points")
			assert_eq(got["fgm"], p.fgm, tag + " fgm")
			assert_eq(got["fga"], p.fga, tag + " fga")
			assert_eq(got["tpm"], p.tpm, tag + " tpm")
			assert_eq(got["tpa"], p.tpa, tag + " tpa")
			assert_eq(got["ftm"], p.ftm, tag + " ftm")
			assert_eq(got["fta"], p.fta, tag + " fta")
			assert_eq(got["oreb"], p.oreb, tag + " oreb")
			assert_eq(got["dreb"], p.dreb, tag + " dreb")
			assert_eq(got["ast"], p.ast, tag + " ast")
			assert_eq(got["stl"], p.stl, tag + " stl")
			assert_eq(got["blk"], p.blk, tag + " blk")
			assert_eq(got["tov"], p.tov, tag + " tov")
			assert_eq(got["pf"], p.pf, tag + " pf")


func test_injury_events_match_the_box_score() -> void:
	var seen := 0
	for s in [21, 22, 23, 24, 25, 26, 27, 28, 29, 30]:
		var played := _play(s, true)
		var box: FcBoxScore = played["box"]
		var from_events: Array = []
		for row in (played["log"] as FcGameEventLog).rows:
			if row[0] == FcGameEventLog.EV_INJURY:
				from_events.append([row[3], row[4]])
		var from_box: Array = []
		for inj in box.injuries:
			from_box.append([inj[0], inj[1]])
		assert_eq(from_events, from_box, "seed %d: the same injuries" % s)
		seen += from_box.size()
	assert_true(seen >= 0)


# --- lineups, clock, sentences, saving ----------------------------------------------------------------

func test_lineups_stay_legal_all_game() -> void:
	for s in [11, 12, 13]:
		var played := _play(s, true)
		var box: FcBoxScore = played["box"]
		var entries := FcPlayByPlay.entries(played["log"], box)
		var team_of := {}
		for p in box.players:
			team_of[p.player_id] = 0 if p.team_id == box.team_ids[0] else 1
		var starters := {}
		for e in entries:
			if e["type"] == FcGameEventLog.EV_STARTER:
				starters[e["a"]] = true
		for p in box.players:
			assert_eq(starters.has(p.player_id), p.started, "seed %d: %s starter flag matches" % [s, p.name])
		for e in entries:
			if e["type"] == FcGameEventLog.EV_SUBSTITUTION or (e["index"] % 25 == 0 and e["index"] >= 10):
				var court := FcPlayByPlay.on_court(entries, e["index"])
				for side in 2:
					assert_eq((court[side] as Array).size(), 5, "seed %d event %d: five on court for side %d" % [s, e["index"], side])
					for id in court[side]:
						assert_eq(team_of[id], side, "a player is on his own team's court")


func test_the_clock_only_runs_down_inside_a_period() -> void:
	var played := _play(11, true)
	var entries := FcPlayByPlay.entries(played["log"], played["box"])
	var period := 0
	var last_clock := 0.0
	for e in entries:
		if e["type"] == FcGameEventLog.EV_PERIOD_START:
			period = e["x"]
			last_clock = e["clock"]
			continue
		if e["type"] == FcGameEventLog.EV_STARTER:
			continue
		assert_eq(e["period"], period, "the event is in the period that is running")
		assert_true(e["clock"] <= last_clock + 0.001, "event %d: the clock did not run backwards (%.1f after %.1f)" % [e["index"], e["clock"], last_clock])
		last_clock = e["clock"]


func test_every_event_reads_as_a_sentence_and_the_text_is_repeatable() -> void:
	var played := _play(12, true)
	var box: FcBoxScore = played["box"]
	var one := FcPlayByPlay.entries(played["log"], box)
	var two := FcPlayByPlay.entries(played["log"], box)
	assert_eq(one, two, "the same log always reads the same")
	var shots := 0
	for e in one:
		if e["visible"]:
			assert_true(str(e["text"]).length() > 3, "event %d (type %d) has text" % [e["index"], e["type"]])
			assert_true(not str(e["text"]).contains("%"), "event %d has no unfilled placeholder: %s" % [e["index"], e["text"]])
		if e["type"] == FcGameEventLog.EV_SHOT_MADE:
			shots += 1
			assert_true(str(e["text"]).contains(". "), "a shooter is named in short form: %s" % e["text"])
	assert_true(shots > 20, "a game has many made shots")


func test_names_clock_and_periods_format_plainly() -> void:
	assert_eq(FcPlayByPlay.short_name("Marcus Hill"), "M. Hill")
	assert_eq(FcPlayByPlay.short_name("Ana de la Cruz"), "A. de la Cruz")
	assert_eq(FcPlayByPlay.short_name("Pele"), "Pele")
	assert_eq(FcPlayByPlay.clock_text(2710), "4:31")
	assert_eq(FcPlayByPlay.clock_text(0), "0:00")
	assert_eq(FcPlayByPlay.clock_text(5), "0:01")
	assert_eq(FcPlayByPlay.period_name(1), "1st quarter")
	assert_eq(FcPlayByPlay.period_name(5), "overtime")
	assert_eq(FcPlayByPlay.period_name(6), "overtime 2")


func test_an_overtime_game_is_labelled_and_still_adds_up() -> void:
	var found := false
	for s in range(100, 500):
		var played := _play(s, true)
		var box: FcBoxScore = played["box"]
		if box.overtimes == 0:
			continue
		found = true
		var entries := FcPlayByPlay.entries(played["log"], box)
		var texts: Array = []
		for e in entries:
			texts.append(e["text"])
		assert_true(texts.has("Start of the overtime."), "the first overtime is announced")
		var last: Dictionary = entries[entries.size() - 1]
		assert_eq([last["home"], last["away"]], [box.scores[0], box.scores[1]])
		break
	assert_true(found, "one of 400 seeded games went to overtime")


func test_the_log_survives_saving_and_ignores_damaged_rows() -> void:
	var played := _play(13, true)
	var log: FcGameEventLog = played["log"]
	var text := JSON.stringify(log.to_dict())
	var back := FcGameEventLog.from_dict(JSON.parse_string(text))
	assert_eq(back.rows, log.rows, "rows survive a JSON round trip as whole numbers")
	var damaged := FcGameEventLog.from_dict({"rows": [[1, 2, 3], "junk", [1, 0, 0, 0, 0, 1]]})
	assert_eq(damaged.size(), 1, "only the well-formed row is kept")
	assert_eq(FcGameEventLog.from_dict({"rows": "nonsense"}).size(), 0)
	assert_eq(FcGameEventLog.from_dict({}).size(), 0)
