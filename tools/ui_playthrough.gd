extends SceneTree
## A long scripted playthrough of Owner Mode through the real UI code (FcApp), to find rough
## edges: it creates a league, plays seasons, and at every stage uses the owner features
## (extensions, free agents, trades, picks, the draft, loans, projects, GM delegation, saving
## and loading) while checking that the game state stays valid.
##
## Run:  godot_console --headless --path . --script res://tools/ui_playthrough.gd -- seasons=3 teams=30 seed=7 [reprice=1] [expand=1]
## It prints one line per stage and a list of problems; exit code 1 if any problem was found.

var _app: FcApp
var _problems: Array[String] = []
var _t0 := 0
var _reprice := false
var _expand := false


func _initialize() -> void:
	var seasons := 3
	var teams := 30
	var seed_text := "7"
	for arg in OS.get_cmdline_user_args():
		var kv: PackedStringArray = arg.split("=", true, 1)
		if kv.size() != 2:
			continue
		match kv[0]:
			"seasons": seasons = int(kv[1])
			"teams": teams = int(kv[1])
			"seed": seed_text = kv[1]
			"reprice": _reprice = kv[1] == "1"
			"expand": _expand = kv[1] == "1"
	_t0 = Time.get_ticks_msec()
	_app = FcApp.new()
	_app.saves = FcSaveManager.new("user://playthrough_saves")
	root.add_child(_app)
	_app.setup()
	var structure := {"conferences": 2, "divisions": 3}
	if teams != 30:
		structure = {"conferences": 2, "divisions": 2} if teams % 4 == 0 else {"conferences": 2, "divisions": 1}
	if not _app.on_create_league({"teams": teams, "conferences": structure["conferences"], "divisions": structure["divisions"], "free_agents": 30, "seed": seed_text, "name": "Playthrough"}):
		_fail("could not create the league")
		_finish()
		return
	_app.on_start_game(_app._pending_state.world.teams.ids()[3])
	var c := _app.controller
	_check("start")
	for year in seasons:
		_log("=== season %d ===" % c.state.current_season)
		_play_regular_season(c)
		_use_in_season_features(c)
		_app.on_sim_playoffs()
		_check("playoffs done")
		var report := c.owner_report()
		var card := c.gm_report()
		var books := c.league_finances()
		var mine := {}
		var avg_price := 0.0
		for entry in books:
			avg_price += entry["price"] / float(books.size())
			if entry["team"] == c.state.user_team_id:
				mine = entry
		_ok("LEAGUE: profit rank %d of %d, revenue rank %d, ticket $%d (league average $%d), attendance %d" % [mine["profit_rank"], books.size(), mine["revenue_rank"], mine["price"], roundi(avg_price), mine["attendance"]])
		_ok("RESULT: %d wins (expected %d), profit %s, payroll %s, approval %d, GM grade %s, rounds won %d" % [report["wins"], report["expected_wins"], FcUiTables.money(report["profit"]), FcUiTables.money(c.state.world.payroll_of_team(c.state.user_team_id, c.state.current_season)), report["approval"], card.get("grade", "-"), report["playoff_rounds_won"]])
		_offseason(c, year)
	_log("final: season %d, %s" % [c.state.current_season, _summary(c)])
	_finish()


func _play_regular_season(c: FcGameController) -> void:
	if _reprice:
		c.set_ticket_price(c.suggested_ticket_price())
	_app.on_advance(30)
	_check("30 days in")
	_app.on_advance(30)
	_check("60 days in")
	_app.on_sim_regular()
	_check("regular season done")


## Things an owner does during the season.
func _use_in_season_features(c: FcGameController) -> void:
	var w := c.state.world
	# every tab must build
	for name in FcApp.TAB_NAMES:
		var tab := _app.build_tab(name)
		if tab == null:
			_fail("tab %s did not build" % name)
		else:
			tab.free()
	var b := c.business()
	_ok("tabs build; cash %s, debt %s" % [FcUiTables.money(b.cash), FcUiTables.money(b.debt)])
	var r := c.borrow(5000000)
	_ok("borrow: %s" % r["reason"])
	_ok("repay: %s" % c.repay_debt(5000000)["reason"])
	c.set_concession_price(110)
	c.set_merch_tier(1)
	_ok("arena project: %s" % c.start_arena_project("luxury_suites")["reason"])
	# a trade offer to the strongest rival
	var rival := c.standings().league_ranking()[0]
	if rival == c.state.user_team_id:
		rival = c.standings().league_ranking()[1]
	var team: FcTeam = w.teams.get_by_id(c.state.user_team_id)
	var worst := team.roster.player_ids[team.roster.size() - 1]
	_ok("trade check: %s" % c.propose_trade(rival, [worst], [], true)["reason"])
	_ok("pick gift check: %s" % c.propose_trade(rival, [], [], true, [[c.first_tradable_pick_year(), 2, c.state.user_team_id]], [])["reason"])
	_check("in-season features")


func _offseason(c: FcGameController, year: int) -> void:
	var w := c.state.world
	# contracts: agree to keep the best expiring players
	var expiring := c.expiring_players()
	var kept := 0
	for e in expiring:
		if kept < 3 and c.extend_contract(e["player"].id)["ok"]:
			kept += 1
	_ok("%d expiring contracts, %d extended" % [expiring.size(), kept])
	# alternate between doing everything by hand and letting the GM do it
	var delegate := year % 2 == 1
	for key in FcGameState.DELEGATION_KEYS:
		c.set_delegation(key, delegate)
	c.set_direction(["win_now", "balanced", "rebuild"][year % 3], ["frugal", "normal", "aggressive"][year % 3])
	_app.on_next_season()   # the owners meeting opens first
	if c.phase() == FcGameController.PHASE_MEETING:
		var items := c.meeting_items()
		_ok("owners meeting: %s" % "; ".join(items.map(func(e): return "%s (%d-%d, needs %d)" % [e["item"]["title"], e["tally"]["yes"], e["tally"]["no"], e["tally"]["needed"]])))
		if _expand:
			# push for an expansion: propose it, vote yes, and lobby the owners who lean against it
			c.state.meeting["influence"] = 10
			c.propose_item("expansion")
			c.cast_meeting_vote("expansion", true)
			for entry in c.meeting_items():
				if entry["item"]["id"] == "expansion":
					for v in entry["tally"]["votes"]:
						if not v["yes"]:
							c.lobby_owner("expansion", v["team"])
		for e in items:
			if not (_expand and e["item"]["id"] == "expansion"):
				c.cast_meeting_vote(e["item"]["id"], year % 2 == 0)
		_app.on_close_meeting()
		_check("meeting closed")
		if c.phase() == FcGameController.PHASE_EXPANSION:
			var status := c.expansion_status()
			_ok("expansion approved: %d teams, %d new, %d picks each" % [status["size"], status["new_teams"], status["picks_per_team"]])
			_app.on_run_expansion()
			_check("expansion draft run")
			_ok("the league now has %d teams; owner lost %d players" % [c.state.world.leagues.get_by_id(c.league_id).team_count(), c.state.expansion_log.filter(func(r): return r[4] == c.state.user_team_id).size()])
	_app.on_next_season()   # warning or begin offseason
	if c.state.offseason_stage == 0:
		_app.on_next_season()
	_check("offseason begun (%s)" % c.phase())
	if c.phase() == FcGameController.PHASE_DRAFT:
		var board := c.draft_board()
		_ok("draft board of %d prospects, workouts left %d" % [board.size(), c.draft_workouts_left()])
		c.invite_to_workout(board[0]["player"].id)
		var picked := c.user_draft_pick(c.draft_board()[0]["player"].id)
		_ok("pick: %s" % picked["reason"])
		_save_load_check(c, "mid-draft")
		if c.phase() == FcGameController.PHASE_DRAFT:
			_app.on_draft_auto()
	_check("draft finished (%s)" % c.phase())
	# free agency window
	if c.phase() == FcGameController.PHASE_OFFSEASON:
		var market := c.free_agent_market(10)
		var signed := 0
		for entry in market:
			if signed < 2 and c.sign_free_agent(entry["player"].id)["signed"]:
				signed += 1
		_ok("window: signed %d of the best free agents; GM log: %s" % [signed, "; ".join(c.gm_log())])
		_save_load_check(c, "free-agency window")
		_app.on_next_season()
	_check("new season started")
	if c.state.current_season > 2026 and c.state.world.news.is_empty():
		_fail("no news at all")


## Saves the game, loads it into a fresh controller and compares what matters.
func _save_load_check(c: FcGameController, label: String) -> void:
	var manager := FcSaveManager.new("user://playthrough_saves")
	var saved := c.autosave(manager)
	if not saved.is_ok():
		_fail("%s: save failed: %s" % [label, saved.message])
		return
	var loaded := manager.load_slot(FcSaveManager.AUTOSAVE_SLOT, FcDefinitionSet.load_default())
	if not loaded.is_ok():
		_fail("%s: load failed: %s" % [label, loaded.message])
		return
	var again := FcGameController.resume(loaded.state)
	if again.phase() != c.phase() or again.state.current_season != c.state.current_season:
		_fail("%s: loaded game is in a different phase (%s vs %s)" % [label, again.phase(), c.phase()])
	var problems := again.state.validate()
	if not problems.is_empty():
		_fail("%s: loaded state invalid: %s" % [label, "; ".join(problems.slice(0, 3))])
	_ok("%s: saved and reloaded fine" % label)


func _check(label: String) -> void:
	var problems := _app.controller.state.validate()
	if problems.is_empty():
		_log("  ok   %s" % label)
	else:
		_fail("%s: %s" % [label, "; ".join(problems.slice(0, 3))])


func _summary(c: FcGameController) -> String:
	var b := c.business()
	return "cash %s, debt %s, value %s, roster %d" % [FcUiTables.money(b.cash), FcUiTables.money(b.debt), FcUiTables.money(b.valuation), c.state.world.teams.get_by_id(c.state.user_team_id).roster.size()]


func _ok(text: String) -> void:
	_log("  ..   " + text)


func _fail(text: String) -> void:
	_problems.append(text)
	_log("  FAIL " + text)


func _log(text: String) -> void:
	print(text)


func _finish() -> void:
	var seconds := (Time.get_ticks_msec() - _t0) / 1000.0
	print("--- finished in %.0f s, %d problem(s)" % [seconds, _problems.size()])
	for p in _problems:
		print("  * " + p)
	var dir := DirAccess.open("user://playthrough_saves")
	if dir != null:
		for f in dir.get_files():
			dir.remove(f)
	quit(1 if not _problems.is_empty() else 0)
