extends FcTestCase
## Trading draft picks.

var g: FcGameController
var user_id: int
var ai_id: int


func before_each() -> void:
	var data := FcGenerationData.load_default()
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = 8
	cfg.conference_count = 2
	cfg.divisions_per_conference = 1
	cfg.roster_size = 12
	cfg.roster_min = 12
	cfg.free_agent_count = 10
	g = FcGameController.new_game(FcWorldGenerator.new(data, FcDefinitionSet.load_default(), cfg), 80, FcGameState.MODE_OWNER, 0)
	user_id = g.state.user_team_id
	ai_id = 1 if user_id != 1 else 2


func _pick(owner_id: int, year: int, round_number: int) -> Array:
	return [year, round_number, owner_id]


func test_every_team_owns_its_own_picks_at_the_start() -> void:
	var mine := g.tradable_picks(user_id)
	assert_eq(mine.size(), FcTradeDesk.PICK_YEARS * FcOffseason.DRAFT_ROUNDS)
	assert_eq(mine[0]["year"], 2027, "the first tradable draft follows this season")
	for p in mine:
		assert_eq(p["original"], user_id)


func test_giving_picks_away_for_free_is_accepted_and_ownership_moves() -> void:
	var w := g.state.world
	var r := g.propose_trade(ai_id, [], [], false, [_pick(user_id, 2027, 1)], [])
	assert_true(r["accepted"], r["reason"])
	assert_eq(w.pick_owner(2027, 1, user_id), ai_id)
	assert_eq(g.tradable_picks(user_id).size(), FcTradeDesk.PICK_YEARS * FcOffseason.DRAFT_ROUNDS - 1)
	var theirs := g.tradable_picks(ai_id)
	var found := false
	for p in theirs:
		if p["original"] == user_id and p["year"] == 2027 and p["round"] == 1:
			found = true
			assert_true("from" in p["label"])
	assert_true(found, "the other team now lists the pick")


func test_asking_for_a_valuable_pick_with_nothing_is_refused() -> void:
	var r := g.propose_trade(ai_id, [], [], false, [], [_pick(ai_id, 2027, 1)])
	assert_true(not r["accepted"] and "enough" in r["reason"], r["reason"])
	assert_eq(g.state.world.pick_owner(2027, 1, ai_id), ai_id)


func test_a_player_can_buy_a_pick_and_better_picks_cost_more() -> void:
	var w := g.state.world
	var rules := w.rules_of_league(1)
	var star := 0
	var best := -1.0
	var ratings := FcPlayerRatings.load_default()
	for pid in w.teams.get_by_id(user_id).roster.player_ids:
		var o := ratings.overall(w.players.get_by_id(pid))
		if o > best:
			best = o
			star = pid
	var second := g.propose_trade(ai_id, [star], [], true, [], [_pick(ai_id, 2027, 2)])
	assert_true(second["accepted"] or "salary" in second["reason"].to_lower() or "payroll" in second["reason"].to_lower() or "roster" in second["reason"].to_lower() or "cap" in second["reason"].to_lower(), second["reason"])
	var desk := FcTradeDesk.new(w)
	var strengths := desk._strength_fractions(w.leagues.get_by_id(1))
	var first_round := desk._picks_value([_pick(ai_id, 2027, 1)], 2027, strengths, false)
	var second_round := desk._picks_value([_pick(ai_id, 2027, 2)], 2027, strengths, false)
	assert_true(first_round > second_round * 3.0, "first-round picks are worth far more")
	assert_true(desk._picks_value([_pick(ai_id, 2029, 1)], 2027, strengths, false) <= first_round * 1.2, "far-away picks are not worth more than near ones by much")
	assert_true(desk._picks_value([_pick(ai_id, 2027, 1)], 2027, strengths, true) < first_round, "contenders value picks less")
	assert_true(rules != null)


func test_the_weakest_team_has_the_most_valuable_pick() -> void:
	var w := g.state.world
	var desk := FcTradeDesk.new(w)
	var strengths := desk._strength_fractions(w.leagues.get_by_id(1))
	var weakest := 0
	var strongest := 0
	for tid in strengths:
		if strengths[tid] == 0.0:
			weakest = tid
		if strengths[tid] == 1.0:
			strongest = tid
	assert_true(desk._picks_value([_pick(weakest, 2027, 1)], 2027, strengths, false) > desk._picks_value([_pick(strongest, 2027, 1)], 2027, strengths, false))


func test_invalid_pick_trades_are_refused() -> void:
	assert_true(not g.propose_trade(ai_id, [], [], true, [_pick(ai_id, 2027, 1)], [])["accepted"], "cannot give a pick you do not own")
	assert_true(not g.propose_trade(ai_id, [], [], true, [_pick(user_id, 2040, 1)], [])["accepted"], "too far ahead")
	assert_true(not g.propose_trade(ai_id, [], [], true, [_pick(user_id, 2026, 1)], [])["accepted"], "that draft is not available")
	assert_true(not g.propose_trade(ai_id, [], [], true, [_pick(user_id, 2027, 3)], [])["accepted"], "there is no third round")


func test_the_traded_pick_is_used_in_the_draft_and_pruned_after() -> void:
	var w := g.state.world
	assert_true(g.propose_trade(ai_id, [], [], false, [_pick(user_id, 2027, 1)], [])["accepted"])
	g.begin_offseason()
	g.draft_auto_rest()
	var found := false
	for row in g.season().draft:
		if row[0] == 1 and row[4] == user_id:
			found = true
			assert_eq(row[2], ai_id, "the new owner made the pick")
	assert_true(found, "the traded pick was used")
	assert_true(w.pick_owners.is_empty(), "ownership of a held draft is forgotten")
	assert_eq(g.first_tradable_pick_year(), 2028, "the next draft is 2028 after the window opens")
	assert_eq(w.validate(g.state.current_season), [] as Array[String])


func test_pick_ownership_is_saved() -> void:
	var w := g.state.world
	w.set_pick_owner(2027, 1, user_id, ai_id)
	var back := FcWorld.from_dict(JSON.parse_string(JSON.stringify(w.to_dict())), FcDefinitionSet.load_default())
	assert_eq(back.pick_owner(2027, 1, user_id), ai_id)
	assert_eq(back.pick_owner(2027, 2, user_id), user_id)
	w.set_pick_owner(2027, 1, user_id, user_id)
	assert_true(w.pick_owners.is_empty(), "giving a pick back to its original team removes the record")
