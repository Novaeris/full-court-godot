extends SceneTree
## Career balance sweep: plays one career for every archetype (and several seeds), spending points the same simple way each time, and
## prints how each turned out: peak overall, the season of the peak, seasons played, best scoring average, final level, rating of the
## league's best player at that time. Used to check that archetypes are comparable and careers neither fizzle nor become absurd.
##
## Run:  godot_console --headless --path . --script res://tools/career_balance.gd -- [seeds=3] [teams=12] [seasons=20] [strategy=focused|even|template|low_weight]
## strategy: how the development points are spent (see tools/career_growth_study.gd): focused = best overall gain per point (default),
## even = always the lowest attribute, template = the archetype's strengths only, low_weight = the attributes that count least first.
## The band and spread checks apply to focused and even only (template and low_weight are deliberately weak comparisons). Exit code 1 if an archetype's average peak falls outside the acceptable band (see BAND), the focused careers do not get within
## 3 overall points of potential, or any run breaks a rule.

const BAND := [64.0, 86.0]   # the average peak overall of a career must stay inside this (a good starter to a clear star)
var _strategy := "focused"

var _problems: Array[String] = []


func _initialize() -> void:
	var seeds := 3
	var teams := 12
	var seasons := 20
	for arg in OS.get_cmdline_user_args():
		var kv: PackedStringArray = arg.split("=", true, 1)
		if kv.size() != 2:
			continue
		match kv[0]:
			"seeds": seeds = int(kv[1])
			"teams": teams = int(kv[1])
			"seasons": seasons = int(kv[1])
			"strategy": _strategy = kv[1]
	var defs := FcDefinitionSet.load_default()
	print("Spending strategy: %s" % _strategy)
	print("%-18s %6s %6s %6s %6s %6s %6s %6s" % ["Archetype", "Peak", "Pot", "PeakAge", "Seasons", "BestPPG", "Level", "Unspent"])
	var all_peaks: Array = []
	for archetype in FcArchetypes.keys():
		var peaks := 0.0
		var peak_age := 0.0
		var length := 0.0
		var ppg := 0.0
		var level := 0.0
		var potential := 0.0
		var unspent := 0.0
		for i in seeds:
			var r := _career(defs, archetype, 200 + i, teams, seasons)
			peaks += r["peak"]
			peak_age += r["peak_age"]
			length += r["seasons"]
			ppg += r["ppg"]
			level += r["level"]
			potential += r["potential"]
			unspent += r["unspent"]
		var n := float(seeds)
		print("%-18s %6.1f %6.1f %6.1f %6.1f %6.1f %6.1f %6.1f" % [archetype, peaks / n, potential / n, peak_age / n, length / n, ppg / n, level / n, unspent / n])
		all_peaks.append(peaks / n)
		if _strategy == "focused" and peaks / n < potential / n - 3.0:
			_problems.append("%s: focused careers peak at %.1f, more than 3 below the potential %.1f" % [archetype, peaks / n, potential / n])
		if _strategy in ["focused", "even"] and (peaks / n < BAND[0] or peaks / n > BAND[1]):
			_problems.append("%s: average peak %.1f is outside %s" % [archetype, peaks / n, str(BAND)])
	var low: float = all_peaks.min()
	var high: float = all_peaks.max()
	print("Spread between archetypes: %.1f overall points (lowest %.1f, highest %.1f)" % [high - low, low, high])
	if _strategy in ["focused", "even"] and high - low > 10.0:
		_problems.append("archetypes differ by %.1f overall points at their peak (more than 10)" % (high - low))
	print("--- %d problem(s)" % _problems.size())
	for p in _problems:
		print("  * " + p)
	quit(1 if not _problems.is_empty() else 0)


func _career(defs: FcDefinitionSet, archetype: String, seed_value: int, teams: int, seasons: int) -> Dictionary:
	var position: int = int(FcArchetypes.get_archetype(archetype)["positions"][0])
	var spec := FcPlayerBuild.default_spec(archetype, position, defs)
	spec["first_name"] = "Bal"
	spec["last_name"] = "Ance"
	var c: FcCareerController = FcCareerController.new_career(spec, seed_value, teams)["controller"]
	c.join_team(c.draft_team())
	var peak := 0
	var peak_age := 0
	var best_ppg := 0.0
	var played := 0
	var unspent := 0
	for i in seasons:
		if c.is_retired():
			break
		var pending := c.pending_event()
		if not pending.is_empty():
			c.answer_event(pending["choices"][0]["key"])
		var result := c.finish_season()
		if result.get("contract_pending", false):
			var talks := c.contract_offer()
			if not c.answer_contract("counter", int(talks["max_salary"]))["ok"]:
				c.answer_contract("accept")
			result = c.finish_season()
		if not result["ok"]:
			_problems.append("%s seed %d: season %d failed" % [archetype, seed_value, i + 1])
			break
		_spend(c, archetype)
		played += 1
		var overall: int = c.card()["overall"]
		if overall > peak:
			peak = overall
			peak_age = c.card()["age"]
		best_ppg = maxf(best_ppg, float(c.profile().history[c.profile().history.size() - 1]["points"]))
		var errors := c.state.validate()
		if not errors.is_empty():
			_problems.append("%s seed %d: invalid after season %d: %s" % [archetype, seed_value, i + 1, errors[0]])
			break
	return {"peak": float(peak), "peak_age": float(peak_age), "seasons": float(played), "ppg": best_ppg, "level": float(c.profile().level), "potential": float(c.profile().build_potential), "unspent": float(c.profile().development_points)}


## Spends the points the chosen way (the same code the growth study uses) and unlocks badges as soon as they are allowed.
func _spend(c: FcCareerController, archetype: String) -> void:
	var study = load("res://tools/career_growth_study.gd")
	study._spend(c, _strategy, archetype)
	for badge in c.badge_list():
		if badge["problem"] == "" and not badge["owned"]:
			c.unlock_badge(badge["key"])
			c.equip_badge(badge["key"], true)
