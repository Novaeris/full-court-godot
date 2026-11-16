extends SceneTree
## Plays several seasons as the owner of one team with a scripted strategy and prints
## the books each season, so the business decisions (arena projects, loans, sponsorship
## style, ticket price) can be checked for balance.
##
## Run:  ./tools/owner_playthrough.ps1 [seasons=8] [seed=2026] [teams=30] [strategy=none|builder|loans|performance]
## strategy:
##   none         changes nothing (baseline)
##   builder      starts seating expansion and suites as soon as cash allows
##   loans        borrows to the limit once, then repays when cash is high
##   performance  uses the performance sponsorship deal


func _initialize() -> void:
	var gen := FcWorldGenerator.create_default()
	var seasons := 8
	var seed_value := 2026
	var strategy := "none"
	for arg in OS.get_cmdline_user_args():
		var kv: PackedStringArray = arg.split("=", true, 1)
		if kv.size() != 2:
			continue
		match kv[0]:
			"seasons": seasons = int(kv[1])
			"seed": seed_value = int(kv[1])
			"teams": gen.config.team_count = int(kv[1])
			"strategy": strategy = kv[1]
	var game := FcGameController.new_game(gen, seed_value, FcGameState.MODE_OWNER, 0)
	var w := game.state.world
	var team: FcTeam = w.teams.get_by_id(game.state.user_team_id)
	print("=== %s, strategy '%s', seed %d ===" % [w.team_display_name(team.id), strategy, seed_value])
	print("%-8s %4s %8s %8s %8s %8s %8s %6s %6s" % ["Season", "Wins", "Revenue", "Profit", "Cash", "Debt", "Value", "Seats", "Suites"])
	for i in seasons:
		_decide(game, strategy)
		game.sim_playoffs()
		var rec: FcFinanceRecord = null
		for r in w.finances.all():
			if r.team_id == team.id and r.year == game.state.current_season:
				rec = r
		var arena: FcArena = w.arenas.get_by_id(team.arena_id)
		print("%-8s %4d %7.1fM %7.1fM %7.1fM %7.1fM %7.1fM %6d %6d" % [
			"%d-%02d" % [rec.year, (rec.year + 1) % 100], rec.wins, rec.total_revenue() / 1e6, rec.profit() / 1e6,
			rec.cash_end / 1e6, rec.debt_end / 1e6, rec.valuation_end / 1e6, arena.capacity, game.business().suites_level])
		if i < seasons - 1:
			game.start_next_season()
	quit(0)


func _decide(game: FcGameController, strategy: String) -> void:
	# every strategy keeps its players: agree to re-sign everyone whose contract ends
	for entry in game.expiring_players():
		game.extend_contract(entry["player"].id)
	match strategy:
		"builder":
			game.start_arena_project("luxury_suites")
			game.start_arena_project("expand_seating")
		"loans":
			var b := game.business()
			if b.debt == 0 and b.cash < 100000000:
				game.borrow(game.loan_limit())
			elif b.cash > 150000000:
				game.repay_debt(b.debt)
		"performance":
			game.set_sponsor_plan(2)
