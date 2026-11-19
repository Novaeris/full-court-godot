extends SceneTree
## Career balance sweep: plays one career for every archetype (and several seeds), spending points the same simple way each time, and
## prints how each turned out: peak overall, the season of the peak, seasons played, best scoring average, final level, rating of the
## league's best player at that time. Used to check that archetypes are comparable and careers neither fizzle nor become absurd.
##
## Run:  godot_console --headless --path . --script res://tools/career_balance.gd -- [seeds=3] [teams=12] [seasons=20]
## Exit code 1 if an archetype's average peak falls outside the acceptable band (see BAND) or any run breaks a rule.

const BAND := [64.0, 86.0]   # the average peak overall of a career must stay inside this (a good starter to a clear star)

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
	var defs := FcDefinitionSet.load_default()
	print("%-18s %6s %6s %6s %6s %6s %6s" % ["Archetype", "Peak", "PeakAge", "Seasons", "BestPPG", "Level", "League best"])
	var all_peaks: Array = []
	for archetype in FcArchetypes.keys():
		var peaks := 0.0
		var peak_age := 0.0
		var length := 0.0
		var ppg := 0.0
		var level := 0.0
		var league_best := 0.0
		for i in seeds:
			var r := _career(defs, archetype, 200 + i, teams, seasons)
			peaks += r["peak"]
			peak_age += r["peak_age"]
			length += r["seasons"]
			ppg += r["ppg"]
			level += r["level"]
			league_best += r["league_best"]
		var n := float(seeds)
		print("%-18s %6.1f %6.1f %6.1f %6.1f %6.1f %6.1f" % [archetype, peaks / n, peak_age / n, length / n, ppg / n, level / n, league_best / n])
		all_peaks.append(peaks / n)
		if peaks / n < BAND[0] or peaks / n > BAND[1]:
			_problems.append("%s: average peak %.1f is outside %s" % [archetype, peaks / n, str(BAND)])
	var low: float = all_peaks.min()
	var high: float = all_peaks.max()
	print("Spread between archetypes: %.1f overall points (lowest %.1f, highest %.1f)" % [high - low, low, high])
	if high - low > 10.0:
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
	var ratings := FcPlayerRatings.load_default()
	var league_best := 0.0
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
		_spend(c, spec["attributes"].keys(), archetype)
		played += 1
		var overall: int = c.card()["overall"]
		if overall > peak:
			peak = overall
			peak_age = c.card()["age"]
		best_ppg = maxf(best_ppg, float(c.profile().history[c.profile().history.size() - 1]["points"]))
		var top := 0.0
		for p in c.state.world.players.all():
			if p.status == FcPlayer.Status.ACTIVE and p.id != c.profile().player_id:
				top = maxf(top, ratings.overall(p))
		league_best = maxf(league_best, top)
		var errors := c.state.validate()
		if not errors.is_empty():
			_problems.append("%s seed %d: invalid after season %d: %s" % [archetype, seed_value, i + 1, errors[0]])
			break
	return {"peak": float(peak), "peak_age": float(peak_age), "seasons": float(played), "ppg": best_ppg, "level": float(c.profile().level), "league_best": league_best}


## The same simple spending every time: the archetype's template attributes first (highest bonus first), badges when allowed.
func _spend(c: FcCareerController, _keys: Array, archetype: String) -> void:
	var bonus: Dictionary = FcArchetypes.get_archetype(archetype).get("bonus", {})
	var keys: Array = bonus.keys()
	if keys.is_empty():   # "custom": spread points over the physical and shooting basics
		keys = ["three_point", "layups", "perimeter_defense", "rebounding", "passing", "speed", "stamina"]
	keys.sort_custom(func(a, b): return int(bonus.get(a, 0)) > int(bonus.get(b, 0)))
	var progress := true
	while progress and c.profile().development_points > 0:
		progress = false
		for key in keys:
			if c.raise_attribute(key)["ok"]:
				progress = true
				break
	for badge in c.badge_list():
		if badge["problem"] == "" and not badge["owned"]:
			c.unlock_badge(badge["key"])
			c.equip_badge(badge["key"], true)
