extends FcTestCase
## The owner's draft: scouted board, user picks, saving mid-draft.

func _game(seed_value: int = 50) -> FcGameController:
	var data := FcGenerationData.load_default()
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = 8
	cfg.conference_count = 2
	cfg.divisions_per_conference = 1
	cfg.roster_size = 12
	cfg.roster_min = 12
	cfg.free_agent_count = 10
	cfg.assistant_coaches = 1
	cfg.scouts = 2
	return FcGameController.new_game(FcWorldGenerator.new(data, FcDefinitionSet.load_default(), cfg), seed_value, FcGameState.MODE_OWNER, 0)


func _results_of(g: FcGameController) -> Array:
	return g.season().draft.duplicate(true)


func test_the_draft_starts_with_the_user_on_the_clock() -> void:
	var g := _game()
	g.begin_offseason()
	assert_eq(g.phase(), FcGameController.PHASE_DRAFT)
	var status := g.draft_status()
	assert_true(status["user_on_clock"] and not status["complete"], "the AI picks until it is the user's turn")
	assert_eq(status["total"], 16)
	assert_eq(g.draft_results().size(), status["pick"] - 1, "everyone before the user has picked")
	assert_eq(g.state.validate(), [] as Array[String], "the world is valid mid-draft")


func test_board_is_scouted_ranked_and_has_ranges() -> void:
	var g := _game()
	g.begin_offseason()
	var board := g.draft_board()
	assert_eq(board.size(), 16 + FcOffseason.UNDRAFTED_EXTRA - g.draft_results().size())
	for i in range(1, board.size()):
		assert_true(board[i - 1]["report"]["value"] >= board[i]["report"]["value"], "best first")
	for entry in board:
		var r: Dictionary = entry["report"]
		assert_true(r["ovr_low"] <= r["ovr"] and r["ovr"] <= r["ovr_high"])
		assert_true(r["pot_low"] <= r["pot"] and r["pot"] <= r["pot_high"])
		assert_eq(entry["player"].status, FcPlayer.Status.PROSPECT)
	assert_eq(g.draft_board()[0]["player"].id, board[0]["player"].id, "the board does not change when redrawn")


func test_ranges_usually_contain_the_truth_and_better_scouts_narrow_them() -> void:
	var g := _game(51)
	g.begin_offseason()
	var off := FcOffseason.new(g.state.world)
	var ratings := FcPlayerRatings.load_default()
	var inside := 0
	var total := 0
	for entry in g.draft_board():
		var p: FcPlayer = entry["player"]
		var r: Dictionary = entry["report"]
		total += 1
		if r["ovr_low"] <= ratings.overall(p) and ratings.overall(p) <= r["ovr_high"]:
			inside += 1
	assert_true(float(inside) / total > 0.6, "ranges hold the truth most of the time (%d of %d)" % [inside, total])
	# scouts sharpen the view
	var team := g.state.user_team_id
	for sc in g.state.world.staff_contracts_of_team(team, FcStaffRole.Id.SCOUT):
		g.state.world.staff.get_by_id(sc.staff_id).skills.set_clamped("scouting_accuracy", 0)
	var blurry := off.scouting_report(team, g.draft_board()[0]["player"], 2027)
	for sc in g.state.world.staff_contracts_of_team(team, FcStaffRole.Id.SCOUT):
		g.state.world.staff.get_by_id(sc.staff_id).skills.set_clamped("scouting_accuracy", 100)
	var sharp := off.scouting_report(team, g.draft_board()[0]["player"], 2027)
	assert_true(sharp["ovr_high"] - sharp["ovr_low"] <= blurry["ovr_high"] - blurry["ovr_low"], "better scouts, narrower ranges")


func test_user_pick_adds_the_player_and_the_draft_moves_on() -> void:
	var g := _game(52)
	g.begin_offseason()
	var w := g.state.world
	var team: FcTeam = w.teams.get_by_id(g.state.user_team_id)
	var choice: FcPlayer = g.draft_board()[3]["player"]
	var before := team.roster.size()
	var r := g.user_draft_pick(choice.id)
	assert_true(r["ok"], r["reason"])
	assert_true(team.roster.contains(choice.id), "the prospect joined the team")
	assert_eq(choice.status, FcPlayer.Status.ACTIVE)
	assert_true(w.active_contract_of(choice.id) != null, "with a rookie contract")
	assert_true(team.roster.size() >= before)
	assert_true(not g.user_draft_pick(choice.id)["ok"], "cannot draft him again (or out of turn)")
	var status := g.draft_status()
	assert_true(status["user_on_clock"] and status["round"] == 2, "the AI teams picked on, and the user is up in round 2")
	g.draft_auto_rest()
	assert_eq(g.phase(), FcGameController.PHASE_OFFSEASON)
	assert_eq(g.season().draft.size(), 16)
	assert_eq(g.state.validate(), [] as Array[String])


func test_staff_pick_equals_the_automatic_draft() -> void:
	var a := _game(53)
	a.begin_offseason()
	a.draft_auto_rest()
	var b := _game(53)
	b.begin_offseason()
	assert_true(b.draft_staff_pick()["ok"])
	b.draft_auto_rest()
	assert_eq(_results_of(a), _results_of(b), "letting the staff pick is the same as the automatic draft")


func test_the_draft_can_be_saved_and_resumed_mid_way() -> void:
	var a := _game(54)
	a.begin_offseason()
	assert_true(a.draft_staff_pick()["ok"])
	var manager := FcSaveManager.new("user://test_saves_draft")
	assert_true(a.autosave(manager).is_ok())
	var loaded := manager.load_slot(FcSaveManager.AUTOSAVE_SLOT, FcDefinitionSet.load_default())
	assert_true(loaded.is_ok(), loaded.message)
	var b := FcGameController.resume(loaded.state)
	assert_eq(b.phase(), FcGameController.PHASE_DRAFT)
	assert_eq(b.draft_results(), a.draft_results())
	assert_eq(b.draft_status()["pick"], a.draft_status()["pick"])
	a.draft_auto_rest()
	b.draft_auto_rest()
	assert_eq(_results_of(a), _results_of(b), "the resumed draft ends the same way")
	manager.delete_slot(FcSaveManager.AUTOSAVE_SLOT)
	DirAccess.remove_absolute("user://test_saves_draft")


func test_signings_and_trades_wait_until_the_draft_is_over() -> void:
	var g := _game(55)
	g.begin_offseason()
	var fa := g.free_agent_market(3)
	assert_true(not g.sign_free_agent(fa[0]["player"].id)["signed"])
	assert_true(not g.propose_trade(2, [], [], true)["accepted"])


func test_leaving_the_draft_unfinished_lets_the_staff_finish_it() -> void:
	var g := _game(56)
	g.begin_offseason()
	var report := g.start_next_season()
	assert_eq(g.state.current_season, 2027)
	assert_eq(report["drafted"], 16)
	assert_eq(g.state.offseason_stage, 0)
	assert_true(g.state.draft_state.is_empty())


func test_draft_state_defaults_in_old_saves() -> void:
	var g := FcGameState.new(FcWorld.new(FcDefinitionSet.load_default()), FcRng.new(1))
	var old := g.to_dict()
	old.erase("draft_state")
	assert_true(FcGameState.from_dict(old, FcDefinitionSet.load_default()).draft_state.is_empty())


func test_workouts_sharpen_a_prospect_report() -> void:
	var g := _game(57)
	g.begin_offseason()
	assert_eq(g.draft_workouts_left(), FcOffseason.WORKOUT_SLOTS)
	var target: FcPlayer = g.draft_board()[2]["player"]
	var before := {}
	for entry in g.draft_board():
		if entry["player"].id == target.id:
			before = entry["report"]
	var r := g.invite_to_workout(target.id)
	assert_true(r["ok"], r["reason"])
	assert_eq(g.draft_workouts_left(), FcOffseason.WORKOUT_SLOTS - 1)
	var after := {}
	for entry in g.draft_board():
		if entry["player"].id == target.id:
			after = entry["report"]
	assert_true(after["worked_out"] and not before["worked_out"])
	assert_true(after["ovr_high"] - after["ovr_low"] < before["ovr_high"] - before["ovr_low"], "the range is narrower after a workout")
	assert_true(after["character"] != "", "and a character note appears")
	assert_true(not g.invite_to_workout(target.id)["ok"], "no second workout for the same player")


func test_workout_slots_are_limited_and_saved() -> void:
	var g := _game(58)
	g.begin_offseason()
	var board := g.draft_board()
	for i in FcOffseason.WORKOUT_SLOTS:
		assert_true(g.invite_to_workout(board[i]["player"].id)["ok"])
	assert_true(not g.invite_to_workout(board[FcOffseason.WORKOUT_SLOTS]["player"].id)["ok"], "only a few workouts")
	var manager := FcSaveManager.new("user://test_saves_workout")
	assert_true(g.autosave(manager).is_ok())
	var loaded := manager.load_slot(FcSaveManager.AUTOSAVE_SLOT, FcDefinitionSet.load_default())
	assert_true(loaded.is_ok(), loaded.message)
	var again := FcGameController.resume(loaded.state)
	assert_eq(again.draft_workouts_left(), 0, "the workouts survive saving")
	manager.delete_slot(FcSaveManager.AUTOSAVE_SLOT)
	DirAccess.remove_absolute("user://test_saves_workout")
