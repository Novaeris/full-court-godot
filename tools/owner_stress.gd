extends SceneTree
## Owner stress test: plays the same league with three fixed owner strategies and prints, for each, the books over the
## seasons: operating profit (restructuring write-offs are NOT included), debt, cash, franchise value and restructurings.
## Strategies are fixed so results are comparable between runs:
##   careful   the GM runs everything on a normal budget; the ticket price follows the suggestion every season; no projects, no loans.
##   naive     the GM runs everything on an AGGRESSIVE budget; the owner never touches prices (they only follow inflation),
##             builds seats and suites whenever cash allows, and borrows whenever cash is short.
##   reckless  aggressive budget, borrows to the limit every season, starts every project, charges 60% of the suggested price,
##             10 promotion nights, no marketing, pays itself every dividend it can.
## Run:  godot_console --headless --path . --script res://tools/owner_stress.gd -- [seasons=30] [teams=12] [seeds=101,102]
## Exit code 1 if any run ends with an invalid league or negative money (the owner must always keep control).

const STRATEGIES := ["careful", "naive", "reckless"]


func _initialize() -> void:
	var seasons := 30
	var teams := 12
	var seeds: Array = [101, 102]
	for arg in OS.get_cmdline_user_args():
		var kv: PackedStringArray = arg.split("=", true, 1)
		if kv.size() != 2:
			continue
		match kv[0]:
			"seasons": seasons = int(kv[1])
			"teams": teams = int(kv[1])
			"seeds": seeds = Array(kv[1].split(",")).map(func(x): return int(x))
	var failed := false
	var table: Array = []
	for strategy in STRATEGIES:
		for seed_value in seeds:
			var row := _run(strategy, seed_value, seasons, teams)
			table.append(row)
			if row["problem"] != "":
				failed = true
	print("")
	print("%-9s %5s %7s %6s %11s %9s %9s %9s %9s %9s" % ["Strategy", "Seed", "Seasons", "Rescue", "Written off", "Op.profit", "Debt", "Cash", "Value", "Paid out"])
	for row in table:
		print("%-9s %5d %7d %6d %10.0fM %8.0fM %8.0fM %8.0fM %8.0fM %8.0fM %s" % [
			row["strategy"], row["seed"], row["seasons"], row["restructurings"], row["written_off"] / 1e6, row["profit"] / 1e6,
			row["debt"] / 1e6, row["cash"] / 1e6, row["value"] / 1e6, row["paid_out"] / 1e6, row["problem"]])
	print("Op.profit = the sum of operating profit over all seasons (restructuring write-offs excluded).")
	print("RESULT: %s" % ("FAIL" if failed else "ok"))
	quit(1 if failed else 0)


func _run(strategy: String, seed_value: int, seasons: int, teams: int) -> Dictionary:
	var gen := FcWorldGenerator.create_default()
	gen.config.team_count = teams
	gen.config.conference_count = 2
	gen.config.divisions_per_conference = 2 if teams % 4 == 0 else 1
	var g := FcGameController.new_game(gen, seed_value, FcGameState.MODE_OWNER, 0)
	for key in FcGameState.DELEGATION_KEYS:
		g.set_delegation(key, true)
	g.set_direction("balanced", "normal" if strategy == "careful" else "aggressive")
	var finance := FcFinanceEngine.new(g.state.world)
	var total_profit := 0
	var problem := ""
	for i in seasons:
		_decide(g, strategy)
		g.sim_playoffs()
		var rec := finance.record_of(g.state.user_team_id, g.state.current_season)
		if rec != null:
			total_profit += rec.profit()
		g.begin_offseason()
		if g.state.offseason_stage == 2:
			g.draft_auto_rest()
		var errors := g.state.validate()
		if not errors.is_empty():
			problem = "INVALID after season %d: %s" % [i + 1, errors[0]]
			break
		g.start_next_season()
	var b := g.business()
	if b.cash < 0 or b.debt < 0:
		problem = "negative money"
	var written := 0
	for row in g.state.owner_career["restructurings"]:
		written += int(row[2])
	return {"strategy": strategy, "seed": seed_value, "seasons": seasons, "restructurings": g.state.owner_career["restructurings"].size(),
		"written_off": written, "profit": total_profit, "debt": b.debt, "cash": b.cash, "value": b.valuation, "paid_out": b.distributions, "problem": problem}


func _decide(g: FcGameController, strategy: String) -> void:
	var b := g.business()
	match strategy:
		"careful":
			g.set_ticket_price(g.suggested_ticket_price())
		"naive":
			g.start_arena_project("expand_seating")
			g.start_arena_project("luxury_suites")
			if b.cash < 50000000:
				g.borrow(g.loan_limit() - b.debt)
		"reckless":
			g.set_ticket_price(maxi(1, roundi(g.suggested_ticket_price() * 0.6)))
			g.set_promotion_nights(10)
			g.set_marketing_budget(0)
			g.borrow(g.loan_limit() - b.debt)
			for key in ["expand_seating", "luxury_suites", "practice_facility", "medical_center", "new_arena"]:
				g.start_arena_project(key)
			var limit := g.dividend_limit()
			if limit > 0:
				g.take_dividend(limit)
