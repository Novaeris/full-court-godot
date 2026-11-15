extends SceneTree
## Plays seasons and prints the money side of the league: every team's revenue,
## expenses, profit, attendance, ticket price, brand and valuation for the last
## season, plus league-wide averages to check the business model is balanced.
##
## Run:  ./tools/finances.ps1 [seasons=3] [seed=2026] [teams=30] [conferences=2] [divisions=3]


func _initialize() -> void:
	var gen := FcWorldGenerator.create_default()
	var cfg := gen.config
	var seasons := 2
	var seed_value := 2026
	for arg in OS.get_cmdline_user_args():
		var kv: PackedStringArray = arg.split("=", true, 1)
		if kv.size() != 2:
			continue
		match kv[0]:
			"seasons": seasons = int(kv[1])
			"seed": seed_value = int(kv[1])
			"teams": cfg.team_count = int(kv[1])
			"conferences": cfg.conference_count = int(kv[1])
			"divisions": cfg.divisions_per_conference = int(kv[1])
	var world := gen.generate(seed_value)
	var rng := FcRng.new(seed_value).fork("money")
	var year := cfg.start_season
	for i in seasons:
		var engine := FcSeasonEngine.for_league(world, 1)
		var season := engine.start_season(1, year, FcDate.new(year, 10, 20), rng.fork("s%d" % i))
		engine.play_full_season(season, rng.fork("p%d" % i))
		if i < seasons - 1:
			FcOffseason.new(world).run(1, season, rng.fork("o%d" % i))
		year += 1
	year -= 1
	var rules := world.rules_of_league(1)
	print("=== Finances, season %d-%02d (cap $%.0fM, millions of dollars) ===" % [year, (year + 1) % 100, rules.cap.salary_cap / 1e6])
	print("%-4s %-24s %4s %7s %6s %5s %5s | %7s %7s %7s | %6s %6s %6s %6s | %7s %7s" % ["", "Team", "W", "Attend", "Price", "Brand", "Intr", "Revenue", "Expense", "Profit", "Gate", "Merch", "Spons", "Payrl", "Cash", "Value"])
	var rows: Array = []
	for t in world.teams.all():
		rows.append(world.finances.all().filter(func(r): return r.team_id == t.id and r.year == year)[0])
	rows.sort_custom(func(a, b): return a.profit() > b.profit())
	var total_rev := 0.0
	var total_profit := 0.0
	var losses := 0
	for r in rows:
		var t: FcTeam = world.teams.get_by_id(r.team_id)
		total_rev += r.total_revenue()
		total_profit += r.profit()
		if r.profit() < 0:
			losses += 1
		print("%-4s %-24s %4d %7d %6d %5d %5d | %7.1f %7.1f %7.1f | %6.1f %6.1f %6.1f %6.1f | %7.1f %7.1f" % [
			t.identity.abbreviation, t.identity.nickname, r.wins, r.average_attendance, r.ticket_price, r.brand_end, r.fan_interest_end,
			r.total_revenue() / 1e6, r.total_expenses() / 1e6, r.profit() / 1e6,
			(r.revenue["tickets"] + r.revenue["playoffs"]) / 1e6, r.revenue["merchandise"] / 1e6, r.revenue["sponsorship"] / 1e6,
			r.expenses["payroll"] / 1e6, r.cash_end / 1e6, r.valuation_end / 1e6])
	var n := float(rows.size())
	var cap: float = rules.cap.salary_cap
	print("")
	print("League averages: revenue $%.0fM (%.2fx the cap), profit $%.1fM (%.1f%% margin), %d of %d teams lost money." % [
		total_rev / n / 1e6, total_rev / n / cap, total_profit / n / 1e6, 100.0 * total_profit / total_rev, losses, rows.size()])
	var best: FcFinanceRecord = rows[0]
	var worst: FcFinanceRecord = rows[rows.size() - 1]
	print("Most profitable: %s $%.0fM | least: %s $%.0fM | highest revenue $%.0fM, lowest $%.0fM" % [
		world.teams.get_by_id(best.team_id).identity.nickname, best.profit() / 1e6,
		world.teams.get_by_id(worst.team_id).identity.nickname, worst.profit() / 1e6,
		rows.map(func(r): return r.total_revenue()).max() / 1e6, rows.map(func(r): return r.total_revenue()).min() / 1e6])
	var taxed := rows.filter(func(r): return r.expenses["luxury_tax"] > 0).size()
	var shared := 0.0
	for r in rows:
		shared += r.revenue["tax_share"]
	print("%d teams paid luxury tax; $%.1fM was shared among teams under the cap." % [taxed, shared / 1e6])
	quit(0)
