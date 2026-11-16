extends FcTestCase
## Draft lottery rules and drawing.

func _teams(n: int) -> Array[int]:
	var out: Array[int] = []
	for i in n:
		out.append(i + 1)   # 1 is the worst record
	return out


func test_no_lottery_keeps_record_order() -> void:
	var r := FcDraftRules.new()
	assert_eq(FcDraftLottery.order(_teams(10), r, FcRng.new(1)), _teams(10))


func test_lottery_is_a_permutation_and_limits_falling() -> void:
	var r := FcDraftRules.suggest(30)
	assert_eq(r.lottery_teams, 14)
	assert_eq(r.lottery_picks, 4)
	for seed_value in 40:
		var order := FcDraftLottery.order(_teams(16), r, FcRng.new(seed_value))
		var sorted := order.duplicate()
		sorted.sort()
		assert_eq(sorted, _teams(16), "everyone appears exactly once")
		for pos in order.size():
			var team := order[pos]
			assert_true(pos + 1 <= team + r.lottery_picks, "a team falls at most %d places" % r.lottery_picks)
		for pos in range(r.lottery_picks, order.size()):
			assert_true(order[pos] > 0)
		# teams outside the lottery stay where they were
		for t in range(r.lottery_teams + 1, 17):
			assert_eq(order.find(t), t - 1)


func test_worst_teams_win_more_often() -> void:
	var r := FcDraftRules.suggest(30)
	var first_wins := {}
	var rng := FcRng.new(5)
	for i in 600:
		var winner := FcDraftLottery.order(_teams(16), r, rng)[0]
		first_wins[winner] = first_wins.get(winner, 0) + 1
	assert_true(first_wins.get(1, 0) > first_wins.get(7, 0), "worst team wins more than a middle team")
	assert_true(first_wins.get(1, 0) > first_wins.get(14, 0), "and more than the best lottery team")
	assert_true(first_wins.size() >= 6, "the lottery spreads the top pick around")


func test_lottery_is_reproducible() -> void:
	var r := FcDraftRules.suggest(30)
	assert_eq(FcDraftLottery.order(_teams(16), r, FcRng.new(9)), FcDraftLottery.order(_teams(16), r, FcRng.new(9)))


func test_rules_validate_and_save() -> void:
	var r := FcDraftRules.suggest(20)
	assert_eq(r.validate(), [] as Array[String])
	var back := FcDraftRules.from_dict(JSON.parse_string(JSON.stringify(r.to_dict())))
	assert_eq(back.lottery_teams, r.lottery_teams)
	assert_eq(back.lottery_picks, r.lottery_picks)
	assert_eq(back.odds_power, r.odds_power)
	assert_eq(FcDraftRules.from_dict({}).lottery_teams, 0, "old saves have no lottery")
	var bad := FcDraftRules.new()
	bad.lottery_teams = 5
	bad.lottery_picks = 9
	assert_true(not bad.validate().is_empty())


func test_generated_leagues_get_a_lottery_unless_switched_off() -> void:
	var data := FcGenerationData.load_default()
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = 8
	cfg.conference_count = 2
	cfg.divisions_per_conference = 1
	var world := FcWorldGenerator.new(data, FcDefinitionSet.load_default(), cfg).generate(3)
	assert_true(world.rules_of_league(1).draft.lottery_teams > 0)
	cfg.draft_lottery = false
	var world2 := FcWorldGenerator.new(data, FcDefinitionSet.load_default(), cfg).generate(3)
	assert_eq(world2.rules_of_league(1).draft.lottery_teams, 0)
