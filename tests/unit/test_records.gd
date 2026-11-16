extends FcTestCase
## Record book and Hall of Fame.

var world: FcWorld
var records: FcRecords


func before_each() -> void:
	var data := FcGenerationData.load_default()
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = 8
	cfg.conference_count = 2
	cfg.divisions_per_conference = 1
	cfg.roster_size = 13
	cfg.free_agent_count = 5
	world = FcWorldGenerator.new(data, FcDefinitionSet.load_default(), cfg).generate(71)
	records = FcRecords.new(world, 1)


func _row(year: int, team: int, points: int) -> Array:
	var r: Array = [year, team, 70, 70 * 1800, points, 0, 0, 0, 0, 0, 0, 100, 400, 300, 50, 20, 0, 0]
	return r


func test_scores_grow_with_production_and_honours() -> void:
	var p: FcPlayer = world.players.all()[0]
	world.careers[p.id] = [_row(2026, 1, 1500)]
	var plain := records.score_of(p.id)
	assert_true(plain > 0.0)
	var s := FcSeason.new(world.ids.next_id(FcWorld.KIND_SEASON))
	s.league_id = 1
	s.year = 2026
	s.awards = {"mvp": p.id}
	s.champion_id = 1
	world.seasons.add(s)
	assert_true(records.score_of(p.id) >= plain + FcRecords.MVP_SCORE + FcRecords.TITLE_SCORE - 0.001)
	assert_eq(records.honours_of(p.id)["mvp"], 1)
	assert_eq(records.honours_of(p.id)["titles"], 1)


func test_hall_of_fame_needs_retirement_and_waiting_time() -> void:
	var p: FcPlayer = world.players.all()[0]
	var rows: Array = []
	for y in range(2026, 2040):
		rows.append(_row(y, 1, 2200))
	world.careers[p.id] = rows
	assert_true(records.score_of(p.id) >= FcRecords.INDUCTION_SCORE)
	assert_true(records.hall_of_fame(2050).is_empty(), "active players are never inducted")
	p.status = FcPlayer.Status.RETIRED
	assert_true(records.hall_of_fame(2040).is_empty(), "must wait after the last season")
	var hof := records.hall_of_fame(2041)
	assert_eq(hof.size(), 1)
	assert_eq(hof[0][1], p.id)
	assert_eq(hof[0][2], 2041)


func test_weak_careers_are_not_inducted() -> void:
	var p: FcPlayer = world.players.all()[0]
	world.careers[p.id] = [_row(2026, 1, 300), _row(2027, 1, 300)]
	p.status = FcPlayer.Status.RETIRED
	assert_true(records.hall_of_fame(2060).is_empty())


func test_single_season_records_sorted() -> void:
	var a: FcPlayer = world.players.all()[0]
	var b: FcPlayer = world.players.all()[1]
	world.careers[a.id] = [_row(2026, 1, 1800), _row(2027, 1, 2100)]
	world.careers[b.id] = [_row(2026, 2, 2400)]
	var top := records.single_season_records("points", 3)
	assert_eq(top.size(), 3)
	assert_eq(top[0], [2400, b.id, 2026])
	assert_eq(top[1], [2100, a.id, 2027])
	assert_eq(records.single_season_records("points", 2).size(), 2)
