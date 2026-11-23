extends FcTestCase
## Arena presentation (Broadcast pass 2, M5): the arena identity is valid and built from the game's own team facts, the crowd plan is
## deterministic and follows loyalty (home fans on the home side, away fans in their block, sizes within range), and the player introductions
## use only the recorded starters and the lineup card's own numbers.

const SEEDS := [3, 12, 77]
var world: FcWorld
var ratings: FcPlayerRatings


func before_each() -> void:
	var data := FcGenerationData.load_default()
	var defs := FcDefinitionSet.load_default()
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = 4
	cfg.conference_count = 1
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


func _identity(home_abbr: String = "HOU", home_name: String = "Houston Sentinels") -> Dictionary:
	return FcArenaIdentity.make({"home": {"abbr": home_abbr, "name": home_name, "color": Color("3B2F8F")}, "away": {"abbr": "MEX", "name": "Mexico City Bonfires", "color": Color("8B1E2D")}})


# --- identity ---------------------------------------------------------------------------------------------------------------------

func test_the_arena_identity_file_is_valid() -> void:
	assert_eq(FcArenaIdentity.problems(), [])


func test_identity_comes_from_the_games_own_team_facts() -> void:
	var id := _identity()
	assert_eq(id["home_abbr"], "HOU")
	assert_eq(id["home_nickname"], "SENTINELS")
	assert_eq(id["home_color"], Color("3B2F8F"))
	assert_eq(id["away_color"], Color("8B1E2D"))
	assert_true(id["accent"] != id["home_color"], "the floor trim is a lighter relative of the home colour")
	var messages: Array = id["led_messages"]
	assert_true(messages.has("HOU") and messages.has("SENTINELS") and messages.has("HOU  vs  MEX"), "messages are filled from the teams: %s" % str(messages))
	for m in messages:
		assert_true(str(m) != "" and not str(m).contains("{"), "no unfilled placeholder in %s" % m)
	assert_eq((id["side_home_share"] as Array).size(), 4)
	assert_eq(id["key"], "arena:HOU")
	assert_true(_identity("DAL", "Dallas Ramparts")["key"] != id["key"], "another team is another arena")


func test_identity_never_fails_for_a_blank_team() -> void:
	var id := FcArenaIdentity.make({})
	assert_true(not (id["led_messages"] as Array).is_empty())
	assert_eq(id["home_nickname"], "")
	assert_eq(FcArenaIdentity.nickname_of("Spurs"), "SPURS")
	assert_eq(FcArenaIdentity.nickname_of("  Mexico City Bonfires "), "BONFIRES")


func test_identity_for_a_real_box_score() -> void:
	var t := _timeline(12)
	var id := FcArenaIdentity.for_box(t.model.box, Color("112233"), Color("445566"))
	assert_eq(id["home_abbr"], str(t.model.box.abbreviations[0]))
	assert_eq(id["away_abbr"], str(t.model.box.abbreviations[1]))


# --- crowd plan -------------------------------------------------------------------------------------------------------------------

func _fans(count_per_side: int) -> Dictionary:
	var sides: Array = []
	var alongs: Array = []
	for side in 4:
		for k in count_per_side:
			sides.append(side)
			alongs.append((float(k) + 0.5) / float(count_per_side))
	return {"sides": sides, "alongs": alongs}


func test_the_crowd_plan_is_deterministic_and_within_range() -> void:
	var id := _identity()
	var f := _fans(600)
	var a := FcCrowdPlan.plan(id, f["sides"], f["alongs"])
	assert_eq(a, FcCrowdPlan.plan(id, f["sides"], f["alongs"]), "same arena, same crowd")
	assert_eq(a["colors"].size(), 2400)
	for s in a["scales"]:
		assert_true(float(s) >= float(id["scale_min"]) - 0.0001 and float(s) <= float(id["scale_max"]) + 0.0001)
	var other := FcCrowdPlan.plan(_identity("DAL", "Dallas Ramparts"), f["sides"], f["alongs"])
	assert_true(a["colors"] != other["colors"], "another arena seats its fans differently")


func test_fans_follow_loyalty() -> void:
	var id := _identity()
	var count := 800
	var by_side: Array = []
	for side in 4:
		var sides: Array = []
		var alongs: Array = []
		for k in count:
			sides.append(side)
			alongs.append((float(k) + 0.5) / float(count))
		by_side.append(FcCrowdPlan.shares_of(id, FcCrowdPlan.plan(id, sides, alongs)))
	assert_true(by_side[0]["home"] > by_side[2]["home"] and by_side[0]["home"] > by_side[3]["home"], "the near sideline is the most loyal")
	assert_true(by_side[3]["away"] > by_side[0]["away"], "the right end holds the visiting fans")
	for side in 4:
		var sh: Dictionary = by_side[side]
		assert_true(absf(float(sh["home"]) + float(sh["away"]) + float(sh["neutral"]) - 1.0) < 0.0001)
	assert_true(by_side[0]["home"] > 0.6 and by_side[0]["home"] < 0.85, "close to the configured 72%%: %s" % str(by_side[0]["home"]))
	# the away block: the far part of the right end is mostly visitors
	var sides2: Array = []
	var alongs2: Array = []
	for k in 600:
		sides2.append(3)
		alongs2.append(0.6 + 0.4 * float(k) / 600.0)
	var block := FcCrowdPlan.shares_of(id, FcCrowdPlan.plan(id, sides2, alongs2))
	assert_true(block["home"] < 0.2 and block["away"] > block["home"], "the away block: %s" % str(block))
	assert_eq(FcCrowdPlan.home_share(id, 3, 0.9), minf(0.30, float(id["away_block_share"])))


# --- player introductions ------------------------------------------------------------------------------------------------------------

func test_introductions_use_the_recorded_starters_and_the_lineup_cards_numbers() -> void:
	for s in SEEDS:
		var t := _timeline(s)
		var steps := FcPlayerIntroductions.plan(t)
		assert_eq(steps.size(), 10, "five starters a side")
		assert_eq(steps, FcPlayerIntroductions.plan(t), "deterministic")
		var card := FcBroadcastGraphics.lineup_card(t)
		for k in 10:
			var step: Dictionary = steps[k]
			assert_eq(int(step["side"]), 1 if k < 5 else 0, "visitors first, then the home team")
			var rows: Array = card["sides"][int(step["side"])]["rows"]
			var found := false
			for row in rows:
				if str(row[1]) == str(step["name"]):
					found = true
					assert_eq(str(row[0]), str(step["number"]) if int(step["number"]) > 0 else "", "the number is the lineup card's")
					assert_eq(str(row[2]), str(step["position"]))
			assert_true(found, "%s is on the lineup card" % step["name"])
			var shot: Dictionary = step["shot"]
			assert_true(bool(shot["critical"]) and shot["preset"] == FcCameraDirector.PRESET_CLOSEUP and FcCourtLayout.inside_court(shot["focus"]))
			assert_eq(step["spotlight"]["kind"], "introduction")
			assert_eq(FcSpotlightModel.stat_text(step["spotlight"]), "", "an introduction states no statistic")
		assert_true(is_equal_approx(FcPlayerIntroductions.total_seconds(steps), 10.0 * FcPlayerIntroductions.SECONDS_PER_PLAYER))
	assert_eq(FcPlayerIntroductions.plan(null), [])
