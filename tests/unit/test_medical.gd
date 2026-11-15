extends FcTestCase
## Medical staff change how often players get hurt and how long they are out.

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
	world = FcWorldGenerator.new(data, defs, cfg).generate(52)


func _set_medical(team_id: int, prevention: int, rehab: int) -> void:
	for sc in world.staff_contracts_of_team(team_id, FcStaffRole.Id.MEDICAL):
		var m: FcStaffMember = world.staff.get_by_id(sc.staff_id)
		m.skills.set_clamped("injury_prevention", prevention)
		m.skills.set_clamped("rehabilitation", rehab)


func test_team_reads_its_medical_staff() -> void:
	_set_medical(1, 90, 20)
	var g := FcGameTeam.from_world(world, 1, ratings)
	assert_eq(g.tactics["injury_prevention"], 90.0)
	assert_eq(g.tactics["rehabilitation"], 20.0)
	var no_doctors := FcGameTeam.from_world(world, 2, ratings)
	for sc in world.staff_contracts_of_team(2, FcStaffRole.Id.MEDICAL):
		sc.status = FcContract.Status.TERMINATED
	var neutral := FcGameTeam.from_world(world, 2, ratings)
	assert_eq(neutral.tactics["injury_prevention"], 50.0, "no medical staff means neutral")
	assert_true(no_doctors != null)


func test_good_prevention_means_fewer_injuries() -> void:
	var counts := {}
	for level in [100, 0]:
		_set_medical(1, level, 50)
		var sim := FcGameSimulator.new({"injury_per_minute": 0.001})
		var rng := FcRng.new(4)
		var n := 0
		for i in 160:
			var box := sim.simulate(FcGameTeam.from_world(world, 1, ratings), FcGameTeam.from_world(world, 2, ratings), rng)
			for row in box.injuries:
				if world.teams.get_by_id(1).roster.contains(row[0]):
					n += 1
		counts[level] = n
	assert_true(counts[0] > counts[100] * 1.3, "poor medical staff (%d injuries) vs great (%d)" % [counts[0], counts[100]])


func test_good_rehabilitation_shortens_injuries() -> void:
	var engine := FcSeasonEngine.for_league(world, 1)
	var p: FcPlayer = world.players.get_by_id(world.teams.get_by_id(1).roster.player_ids[0])
	var results := {}
	for level in [100, 0]:
		_set_medical(1, 50, level)
		engine.refresh_teams()
		var box := FcBoxScore.new()
		box.team_ids = [1, 2]
		box.injuries = [[p.id, 40, "torn meniscus"]]
		engine._apply_injuries(box)
		results[level] = p.games_out
		p.games_out = 0
		p.injury = ""
	assert_true(results[100] < 40 and results[0] > 40, "great rehab returns him sooner (%d) than poor rehab (%d)" % [results[100], results[0]])
	assert_between(results[100], 33.0, 37.0)
