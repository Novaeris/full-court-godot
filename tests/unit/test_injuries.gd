extends FcTestCase
## Injuries: how often they happen, what they do to a game, how they are tracked over a season.

var data: FcGenerationData
var defs: FcDefinitionSet
var ratings: FcPlayerRatings
var world: FcWorld


func before_each() -> void:
	data = FcGenerationData.load_default()
	defs = FcDefinitionSet.load_default()
	ratings = FcPlayerRatings.load_default()
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = 8
	cfg.conference_count = 2
	cfg.divisions_per_conference = 1
	cfg.roster_size = 13
	cfg.free_agent_count = 5
	world = FcWorldGenerator.new(data, defs, cfg).generate(44)


func _team(team_id: int) -> FcGameTeam:
	return FcGameTeam.from_world(world, team_id, ratings)


func _injuries_in(games: int, tuning: Dictionary = {}, seed_value: int = 1) -> Array:
	var sim := FcGameSimulator.new(tuning)
	var rng := FcRng.new(seed_value)
	var out: Array = []
	for i in games:
		var box := sim.simulate(_team(1), _team(2), rng)
		out.append(box)
	return out


func test_injury_rate_is_realistic() -> void:
	var boxes := _injuries_in(300)
	var total := 0
	var severities: Array = []
	for b in boxes:
		total += b.injuries.size()
		for row in b.injuries:
			severities.append(row[1])
	var per_game := float(total) / boxes.size()
	assert_between(per_game, 0.05, 0.30, "injuries per game between two teams")
	var minor := severities.filter(func(g): return g <= 5).size()
	var serious := severities.filter(func(g): return g > 20).size()
	assert_true(minor > serious, "most injuries are minor")
	assert_true(severities.all(func(g): return g >= 1 and g <= 82))


func test_no_injuries_when_switched_off() -> void:
	for b in _injuries_in(60, {"injury_per_minute": 0.0}):
		assert_true(b.injuries.is_empty())


func test_an_injured_player_leaves_and_does_not_return() -> void:
	var found := 0
	for b in _injuries_in(150, {"injury_per_minute": 0.0015}, 3):
		for row in b.injuries:
			found += 1
			var line: FcPlayerGameStats = null
			for p in b.players:
				if p.player_id == row[0]:
					line = p
			assert_true(line != null)
			assert_true(line.seconds < 48 * 60, "he did not play the whole game")
			assert_true(row[2] != "", "the injury has a name")
		for side in 2:
			var seconds := 0
			for p in b.players_of(side):
				seconds += p.seconds
			var expected: int = 60 * (48 + 5 * b.overtimes) * 5
			assert_between(seconds, expected - 15.0, expected + 15.0, "five players on the court even with injuries")
	assert_true(found > 10, "the test produced injuries (%d)" % found)


func test_durable_players_get_hurt_less() -> void:
	var tough := 0
	var fragile := 0
	for round in 2:
		for pid in world.teams.get_by_id(1).roster.player_ids:
			world.players.get_by_id(pid).attributes.set_clamped("durability", 95 if round == 0 else 5)
		var count := 0
		for b in _injuries_in(200, {"injury_per_minute": 0.0008}, 5):
			for row in b.injuries:
				if world.teams.get_by_id(1).roster.contains(row[0]):
					count += 1
		if round == 0:
			tough = count
		else:
			fragile = count
	assert_true(fragile > tough * 1.5, "fragile players (%d) are hurt much more often than durable ones (%d)" % [fragile, tough])


func test_injured_players_are_left_out_of_the_lineup() -> void:
	var team: FcTeam = world.teams.get_by_id(1)
	var hurt: FcPlayer = world.players.get_by_id(team.roster.player_ids[0])
	hurt.games_out = 5
	hurt.injury = "sprained ankle"
	var g := _team(1)
	for p in g.players:
		assert_true(p.id != hurt.id, "the hurt player does not play")
	assert_eq(g.players.size(), team.roster.size() - 1)
	# a decimated roster still fields at least eight, the least hurt first
	for pid in team.roster.player_ids:
		var p: FcPlayer = world.players.get_by_id(pid)
		p.games_out = 3 + (pid % 7)
		p.injury = "injury"
	assert_eq(_team(1).players.size(), 8)


func test_injuries_are_tracked_through_a_season() -> void:
	var engine := FcSeasonEngine.for_league(world, 1)
	var rng := FcRng.new(6)
	var season := engine.start_season(1, 2026, FcDate.new(2026, 10, 20), rng)
	var seen_hurt := 0
	var most_out := 0
	var days := 0
	while not season.regular_season_complete():
		engine.play_day(season, rng)
		days += 1
		var hurt_now := 0
		for p in world.players.all():
			if p.games_out > 0:
				hurt_now += 1
				most_out = maxi(most_out, p.games_out)
			assert_true((p.games_out > 0) == (p.injury != ""), "state is consistent")
		seen_hurt = maxi(seen_hurt, hurt_now)
	assert_true(seen_hurt >= 1, "someone was hurt during the season")
	assert_true(seen_hurt <= 40, "but not an absurd number at once")
	assert_eq(world.validate(2026), [] as Array[String])
	# players recover: at least some of the earliest injuries are over by the end
	var still_out := world.players.all().filter(func(p): return p.games_out > 0).size()
	assert_true(still_out < seen_hurt + 1)


func test_injured_players_count_down_by_team_games() -> void:
	var engine := FcSeasonEngine.for_league(world, 1)
	var rng := FcRng.new(7)
	var season := engine.start_season(1, 2026, FcDate.new(2026, 10, 20), rng)
	var team: FcTeam = world.teams.get_by_id(season.games[0].home_id)
	var p: FcPlayer = world.players.get_by_id(team.roster.player_ids[team.roster.size() - 1])
	p.games_out = 3
	p.injury = "sprained ankle"
	var played_by_team := 0
	var day := 0
	while p.games_out > 0 and day < 60:
		for g in season.games_on_day(day):
			if g.involves(team.id):
				played_by_team += 1
		engine.play_day(season, rng)
		day += 1
	assert_true(p.games_out == 0 and p.injury == "", "he recovered")
	assert_true(played_by_team >= 3 and played_by_team <= 4, "after about three games of his team (%d)" % played_by_team)


func test_player_validation_and_saving_of_injuries() -> void:
	var p: FcPlayer = world.players.get_by_id(1)
	p.games_out = 4
	assert_true(not p.validate().is_empty(), "a hurt player needs an injury name")
	p.injury = "calf strain"
	assert_eq(p.validate(), [] as Array[String])
	var copy := FcPlayer.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())), defs)
	assert_eq(copy.games_out, 4)
	assert_eq(copy.injury, "calf strain")
	p.games_out = -1
	assert_true(not p.validate().is_empty())
	var old := FcTestData.player(9, defs).to_dict()
	old.erase("games_out")
	old.erase("injury")
	assert_eq(FcPlayer.from_dict(old, defs).games_out, 0, "saves from before injuries load healthy")


func test_the_offseason_heals_most_injuries() -> void:
	var engine := FcSeasonEngine.for_league(world, 1)
	var rng := FcRng.new(8)
	var season := engine.start_season(1, 2026, FcDate.new(2026, 10, 20), rng)
	engine.play_full_season(season, rng)
	var team: FcTeam = world.teams.get_by_id(1)
	var minor: FcPlayer = world.players.get_by_id(team.roster.player_ids[0])
	var major: FcPlayer = world.players.get_by_id(team.roster.player_ids[1])
	minor.games_out = 30
	minor.injury = "torn meniscus"
	major.games_out = 82
	major.injury = "torn ACL"
	FcOffseason.new(world).run(1, season, rng)
	assert_eq(minor.games_out, 0, "a 30-game injury heals over the summer")
	if major.status == FcPlayer.Status.ACTIVE:
		assert_eq(major.games_out, 22, "an 82-game injury carries into the next season")
	assert_eq(world.validate(2027), [] as Array[String])


func test_severe_injuries_cost_athleticism() -> void:
	var p: FcPlayer = world.players.get_by_id(1)
	for key in ["speed", "agility", "vertical", "stamina"]:
		p.attributes.set_clamped(key, 70)
	var engine := FcSeasonEngine.for_league(world, 1)
	var box := FcBoxScore.new()
	box.injuries = [[p.id, 75, "torn ACL"]]
	box.team_ids = [1, 2]
	engine._apply_injuries(box)
	for key in ["speed", "agility", "vertical", "stamina"]:
		assert_true(p.attributes.get_value(key) < 70 and p.attributes.get_value(key) >= 67, key)
	assert_eq(p.games_out, 75)
