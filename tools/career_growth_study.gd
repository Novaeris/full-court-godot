extends SceneTree
## Measures how far different spending strategies get a Career Mode player toward his potential when the offseason's automatic growth
## is handed to him as development points (the league's own growth formula, no noise, no decline: ages 19 to the peak).
## Strategies: focused (best overall gain per point), even (always the lowest attribute), template (the archetype's strengths first),
## low_weight (the attributes that count least in overall first).
##
## Run:  godot_console --headless --path . --script res://tools/career_growth_study.gd -- [archetype=all] [potential=0]
## Prints, per archetype and strategy: final overall, potential, the age potential was reached (or -), points left unspent.

const STRATEGIES := ["focused", "even", "template", "low_weight"]


func _initialize() -> void:
	var only := "all"
	var potential_override := 0
	for arg in OS.get_cmdline_user_args():
		var kv: PackedStringArray = arg.split("=", true, 1)
		if kv.size() == 2:
			match kv[0]:
				"archetype": only = kv[1]
				"potential": potential_override = int(kv[1])
	var defs := FcDefinitionSet.load_default()
	print("%-17s %-10s %5s %5s %7s %6s" % ["Archetype", "Strategy", "Final", "Pot", "AtAge", "Unspent"])
	for archetype in FcArchetypes.keys():
		if only != "all" and archetype != only:
			continue
		for strategy in STRATEGIES:
			var r := run(defs, archetype, strategy, potential_override)
			print("%-17s %-10s %5d %5d %7s %6d" % [archetype, strategy, r["final"], r["potential"], str(r["age"]) if r["age"] > 0 else "-", r["unspent"]])
	quit(0)


## One study run; also used by the tests. Returns {"final", "potential", "age", "unspent", "start"}.
static func run(defs: FcDefinitionSet, archetype: String, strategy: String, potential_override: int = 0) -> Dictionary:
	var position: int = int(FcArchetypes.get_archetype(archetype)["positions"][0])
	var spec := FcPlayerBuild.default_spec(archetype, position, defs)
	spec["first_name"] = "Study"
	spec["last_name"] = "Player"
	if potential_override > 0:
		spec["potential"] = mini(potential_override, FcPlayerBuild.potential_cap(spec))
	var c: FcCareerController = FcCareerController.new_career(spec, 11, 12)["controller"]
	var player := c.player()
	var profile := c.profile()
	var progression := FcPlayerProgression.new(defs, FcPlayerRatings.load_default())
	var start := FcCareerRules.overall_now(player)
	var reached := 0
	var age := 19
	while age <= player.development.peak_age:
		var growth := progression.growth_points_for(player, age, 50.0)
		profile.development_points += FcCareerRules.growth_to_points(growth)
		_spend(c, strategy, archetype)
		if reached == 0 and FcCareerRules.overall_now(player) >= FcCareerRules.overall_cap(profile, player) - 1:
			reached = age
		age += 1
	return {"final": FcCareerRules.overall_now(player), "potential": FcCareerRules.overall_cap(profile, player), "age": reached, "unspent": profile.development_points, "start": start}


static func _spend(c: FcCareerController, strategy: String, archetype: String) -> void:
	var profile := c.profile()
	var player := c.player()
	var keys: Array = player.attributes.get_catalog().keys()
	keys.sort()
	var weights: Dictionary = FcPlayerRatings.load_default().overall_weights
	match strategy:
		"focused":
			while profile.development_points > 0:
				var best := FcCareerRules.best_next_upgrade(profile, player)
				if best.is_empty() or not best["affordable"] or not FcCareerRules.raise_attribute(profile, player, best["key"])["ok"]:
					break
		"even":
			var progress := true
			while progress and profile.development_points > 0:
				progress = false
				var order := keys.duplicate()
				order.sort_custom(func(a, b): return player.attributes.get_value(a) < player.attributes.get_value(b) if player.attributes.get_value(a) != player.attributes.get_value(b) else a < b)
				for key in order:
					if FcCareerRules.raise_attribute(profile, player, key)["ok"]:
						progress = true
						break
		"template":
			var bonus: Dictionary = FcArchetypes.get_archetype(archetype).get("bonus", {})
			var order2: Array = bonus.keys()
			order2.sort_custom(func(a, b): return int(bonus[a]) > int(bonus[b]) if int(bonus[a]) != int(bonus[b]) else a < b)
			var progress2 := true
			while progress2 and profile.development_points > 0 and not order2.is_empty():
				progress2 = false
				for key in order2:
					if FcCareerRules.raise_attribute(profile, player, key)["ok"]:
						progress2 = true
						break
		"low_weight":
			var order3 := keys.duplicate()
			order3.sort_custom(func(a, b): return int(weights[a]) < int(weights[b]) if int(weights[a]) != int(weights[b]) else a < b)
			var progress3 := true
			while progress3 and profile.development_points > 0:
				progress3 = false
				for key in order3:
					if FcCareerRules.raise_attribute(profile, player, key)["ok"]:
						progress3 = true
						break
