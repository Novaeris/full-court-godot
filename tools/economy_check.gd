extends SceneTree
## Long-run economy check: plays many seasons of an all-AI league and prints, every few
## seasons, the league's money picture (cap, revenue, payroll, profit, cash, ticket price,
## valuation). Used to prove the economy stays bounded over decades (milestone M2).
##
## Run:  ./tools/economy_check.ps1 [seasons=50] [seed=2026] [teams=12] [every=5]
## Exit code 1 if a long-run health check fails (see the end of the output).


func _initialize() -> void:
	var gen := FcWorldGenerator.create_default()
	var cfg := gen.config
	var seasons := 50
	var seed_value := 2026
	var every := 5
	for arg in OS.get_cmdline_user_args():
		var kv: PackedStringArray = arg.split("=", true, 1)
		if kv.size() != 2:
			continue
		match kv[0]:
			"seasons": seasons = int(kv[1])
			"seed": seed_value = int(kv[1])
			"teams": cfg.team_count = int(kv[1])
			"every": every = int(kv[1])
	if cfg.team_count > 40:
		cfg.areas = [] as Array[String]   # North America alone has too few cities for a 64-team league
	if cfg.team_count == 30:
		cfg.conference_count = 2
		cfg.divisions_per_conference = 3
	elif cfg.team_count == 64:
		cfg.conference_count = 4
		cfg.divisions_per_conference = 4
	elif cfg.team_count % 4 == 0:
		cfg.conference_count = 2
		cfg.divisions_per_conference = 2
	else:
		cfg.conference_count = 2
		cfg.divisions_per_conference = 1
	var world := gen.generate(seed_value)
	var rng := FcRng.new(seed_value).fork("money")
	var year := cfg.start_season
	var t0 := Time.get_ticks_msec()
	print("=== Economy, %d teams, seed %d, %d seasons ===" % [cfg.team_count, seed_value, seasons])
	print("%-8s %7s %8s %8s %8s %8s %8s %7s %8s %6s %6s %5s" % ["Season", "Cap", "Revenue", "Payroll", "AvgProf", "MaxProf", "MaxCash", "AvgCash", "Value", "Price", "Margin", "Loss"])
	var worst_margin := -1.0
	var late_profit_ratio := 0.0
	var late_cash_ratio := 0.0
	var late_payroll_ratio := 0.0
	var titles := {}
	var last_stats := {}
	var late_debt_ratio := 0.0
	var late_leverage := 0.0
	for i in seasons:
		var engine := FcSeasonEngine.for_league(world, 1)
		var season := engine.start_season(1, year, FcDate.new(year, 10, 20), rng.fork("s%d" % i))
		engine.play_full_season(season, rng.fork("p%d" % i))
		var stats := _stats(world, year)
		last_stats = stats
		if season.champion_id > 0:
			titles[season.champion_id] = int(titles.get(season.champion_id, 0)) + 1
		if i % every == 0 or i == seasons - 1:
			print("%-8s %6.0fM %7.0fM %7.0fM %7.1fM %7.1fM %7.0fM %6.0fM %7.0fM %6d %5.1f%% %5d" % [
				"%d" % year, stats["cap"] / 1e6, stats["revenue"] / 1e6, stats["payroll"] / 1e6, stats["profit"] / 1e6,
				stats["max_profit"] / 1e6, stats["max_cash"] / 1e6, stats["cash"] / 1e6, stats["value"] / 1e6,
				stats["price"], 100.0 * stats["margin"], stats["losers"]])
		if i >= seasons - 10:
			late_profit_ratio = maxf(late_profit_ratio, stats["max_profit"] / maxf(1.0, stats["cap"]))
			late_cash_ratio = maxf(late_cash_ratio, stats["max_cash"] / maxf(1.0, stats["cap"]))
			late_leverage = maxf(late_leverage, stats["max_leverage"])
			late_debt_ratio = maxf(late_debt_ratio, stats["max_debt"] / maxf(1.0, stats["cap"]))
			late_payroll_ratio = maxf(late_payroll_ratio, absf(stats["payroll"] / maxf(1.0, stats["cap"]) - 1.0))
		if i >= 5:   # the first seasons are the settling-in period of the model
			worst_margin = maxf(worst_margin, stats["margin"])
		if i < seasons - 1:
			FcOffseason.new(world).run(1, season, rng.fork("o%d" % i))
		year += 1
	print("Time: %.0f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	print("Highest league margin (after season 5) %.1f%%; in the last 10 seasons: biggest single-team profit %.2fx the cap, biggest cash pile %.2fx the cap, average payroll within %.0f%% of the cap." % [100.0 * worst_margin, late_profit_ratio, late_cash_ratio, 100.0 * late_payroll_ratio])
	var best_titles := 0
	for tid in titles:
		best_titles = maxi(best_titles, int(titles[tid]))
	print("DEBT:      average $%.0fM, largest $%.0fM (largest in the last 10 seasons: %.2fx the cap); highest debt share of a club's assets in the last 10 seasons: %.0f%%" % [last_stats["debt"] / 1e6, last_stats["max_debt"] / 1e6, late_debt_ratio, 100.0 * late_leverage])
	print("CASH:      average $%.0fM, largest $%.0fM" % [last_stats["cash"] / 1e6, last_stats["max_cash"] / 1e6])
	print("PROFIT:    average $%.1fM (margin %.1f%%), best club $%.0fM" % [last_stats["profit"] / 1e6, 100.0 * last_stats["margin"], last_stats["max_profit"] / 1e6])
	print("VALUATION: average $%.0fM" % (last_stats["value"] / 1e6))
	print("TITLES:    %d different champions in %d seasons, most by one club %d" % [titles.size(), seasons, best_titles])
	var failed := late_leverage > 0.6 or worst_margin > 0.20 or late_profit_ratio > 1.5 or late_cash_ratio > 4.0 or late_payroll_ratio > 0.25
	print("RESULT: %s" % ("FAIL (profit is running away)" if failed else "ok"))
	quit(1 if failed else 0)


func _stats(world: FcWorld, year: int) -> Dictionary:
	var rules := world.rules_of_league(1)
	var n := 0.0
	var rev := 0.0
	var pay := 0.0
	var profit := 0.0
	var max_profit := -1e18
	var cash := 0.0
	var max_cash := 0.0
	var value := 0.0
	var price := 0.0
	var losers := 0
	var debt := 0.0
	var max_debt := 0.0
	var max_leverage := 0.0
	for r in world.finances.all():
		if r.year != year:
			continue
		n += 1
		rev += r.total_revenue()
		pay += r.expenses["payroll"]
		profit += r.profit()
		max_profit = maxf(max_profit, r.profit())
		debt += r.debt_end
		max_debt = maxf(max_debt, r.debt_end)
		max_leverage = maxf(max_leverage, float(r.debt_end) / maxf(1.0, float(r.debt_end + r.valuation_end)))
		cash += r.cash_end
		max_cash = maxf(max_cash, r.cash_end)
		value += r.valuation_end
		price += r.ticket_price
		if r.profit() < 0:
			losers += 1
	return {"cap": rules.cap.salary_cap, "revenue": rev / n, "payroll": pay / n, "profit": profit / n, "max_profit": max_profit,
		"debt": debt / n, "max_debt": max_debt, "max_leverage": max_leverage, "cash": cash / n, "max_cash": max_cash, "value": value / n, "price": roundi(price / n), "margin": profit / maxf(1.0, rev), "losers": losers}
