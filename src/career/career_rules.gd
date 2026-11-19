class_name FcCareerRules
extends RefCounted
## Career Mode progression rules: XP and levels, development and skill points, spending points on attributes under the body's
## ceilings, training, milestones and badges. PURE: every function takes the profile and player and returns what happened; none
## reads the UI, the clock or a global random number. A future server runs the same functions, and it is the only party that
## may award XP, points or currency: progression changes only through these functions, driven by simulation results.
##
## Results are plain dictionaries: {"ok": bool, "reason": String, ...} for actions, so a screen can show the reason.

static var _cache: Dictionary = {}


static func rules() -> Dictionary:
	if _cache.is_empty():
		var file := FileAccess.open("res://data/career/progression.json", FileAccess.READ)
		var parsed = FcChecks.parse_json(file.get_as_text()) if file != null else null
		_cache = parsed if parsed is Dictionary else {}
	return _cache


# --- levels and XP ----------------------------------------------------------------------------------------

## Total XP needed to reach `level` (level 1 needs 0).
static func xp_for_level(level: int) -> int:
	if level <= 1:
		return 0
	return roundi(float(rules()["xp_base"]) * pow(float(level - 1), float(rules()["xp_exponent"])))


## The level a total XP corresponds to (never above the maximum).
static func level_for_xp(xp: int) -> int:
	var level := 1
	while level < int(rules()["max_level"]) and xp >= xp_for_level(level + 1):
		level += 1
	return level


## {"level", "into_level", "needed", "fraction"} for showing a progress bar.
static func level_progress(xp: int) -> Dictionary:
	var level := level_for_xp(xp)
	if level >= int(rules()["max_level"]):
		return {"level": level, "into_level": 0, "needed": 0, "fraction": 1.0}
	var start := xp_for_level(level)
	var needed := xp_for_level(level + 1) - start
	return {"level": level, "into_level": xp - start, "needed": needed, "fraction": float(xp - start) / maxf(1.0, needed)}


## Points granted for reaching `level` (development, skill).
static func level_rewards(level: int) -> Dictionary:
	var r := rules()
	var dev := int(r["development_points_per_level"])
	if level % int(r["bonus_development_every_levels"]) == 0:
		dev += int(r["bonus_development_points"])
	var skill := 1 if level % int(r["skill_point_every_levels"]) == 0 else 0
	return {"development_points": dev, "skill_points": skill}


## Adds XP (from a validated source only: a game, training, a milestone), raises the level, and grants the points for every
## level crossed. Returns {"xp", "levels_gained", "development_points", "skill_points"} (amounts actually granted).
static func award_xp(profile: FcCareerProfile, amount: int) -> Dictionary:
	var gained := {"xp": 0, "levels_gained": 0, "development_points": 0, "skill_points": 0}
	if amount <= 0:
		return gained
	profile.xp += amount
	gained["xp"] = amount
	var new_level := level_for_xp(profile.xp)
	for level in range(profile.level + 1, new_level + 1):
		var rewards := level_rewards(level)
		profile.development_points += int(rewards["development_points"])
		profile.skill_points += int(rewards["skill_points"])
		gained["development_points"] += int(rewards["development_points"])
		gained["skill_points"] += int(rewards["skill_points"])
		gained["levels_gained"] += 1
	profile.level = maxi(profile.level, new_level)
	return gained


# --- games, training, milestones -------------------------------------------------------------------------------

## XP for one game line {"minutes", "points", "rebounds", "assists", "steals", "blocks", "turnovers", "won"}. Rewards doing the
## things that win (assists, defense, a win) with a floor and a cap, so neither a quiet night nor a huge one decides a career.
static func game_xp(line: Dictionary) -> int:
	var g: Dictionary = rules()["game_xp"]
	var minutes := float(line.get("minutes", 0))
	if minutes <= 0.0:
		return 0
	var raw := float(g["base"]) + float(g["points"]) * float(line.get("points", 0)) + float(g["rebounds"]) * float(line.get("rebounds", 0)) \
		+ float(g["assists"]) * float(line.get("assists", 0)) + float(g["steals"]) * float(line.get("steals", 0)) \
		+ float(g["blocks"]) * float(line.get("blocks", 0)) + float(g["turnovers"]) * float(line.get("turnovers", 0))
	raw *= minf(1.0, minutes / float(g["minutes_scale_at"]))
	if bool(line.get("won", false)):
		raw += float(g["win"])
	return clampi(roundi(raw), int(g["floor"]), int(g["cap"]))


## Milestones a game line completes that the profile has not claimed yet (keys in progression.json).
static func milestones_in_game(profile: FcCareerProfile, line: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if not profile.milestones.has("first_game"):
		out.append("first_game")
	if int(line.get("points", 0)) >= 10 and not profile.milestones.has("ten_point_game"):
		out.append("ten_point_game")
	var doubles := 0
	for stat in ["points", "rebounds", "assists", "steals", "blocks"]:
		if int(line.get(stat, 0)) >= 10:
			doubles += 1
	if doubles >= 2 and not profile.milestones.has("double_double"):
		out.append("double_double")
	return out


## Claims a milestone once: its XP, points and currency. Returns {"ok", "reason", "granted"}.
static func claim_milestone(profile: FcCareerProfile, key: String) -> Dictionary:
	var def: Dictionary = rules()["milestones"].get(key, {})
	if def.is_empty():
		return {"ok": false, "reason": "Unknown milestone."}
	if profile.milestones.has(key):
		return {"ok": false, "reason": "That milestone was already claimed."}
	profile.milestones.append(key)
	var granted := award_xp(profile, int(def.get("xp", 0)))
	profile.development_points += int(def.get("development_points", 0))
	granted["development_points"] += int(def.get("development_points", 0))
	profile.currency += int(def.get("currency", 0))
	granted["currency"] = int(def.get("currency", 0))
	return {"ok": true, "reason": "Milestone: %s." % def["name"], "granted": granted}


## Applies one played game: XP for the line plus any new milestones. Returns {"xp", "milestones": [keys], "levels_gained",
## "development_points", "skill_points"}.
static func apply_game(profile: FcCareerProfile, line: Dictionary) -> Dictionary:
	var total := award_xp(profile, game_xp(line))
	var claimed: Array[String] = []
	for key in milestones_in_game(profile, line):
		var r := claim_milestone(profile, key)
		if r["ok"]:
			claimed.append(key)
			for field in ["xp", "levels_gained", "development_points", "skill_points"]:
				total[field] += int(r["granted"].get(field, 0))
	total["milestones"] = claimed
	return total


## A training session in `year`: limited per season and worth less each time, so training is a choice and not a grind.
## Returns {"ok", "reason", "granted"}.
static func train(profile: FcCareerProfile, year: int) -> Dictionary:
	var t: Dictionary = rules()["training"]
	var used := int(profile.training_used.get(str(year), 0))
	if used >= int(t["sessions_per_season"]):
		return {"ok": false, "reason": "You have used all %d training sessions of this season." % int(t["sessions_per_season"])}
	var xp := roundi(float(t["xp"]) * pow(float(t["diminishing"]), used))
	profile.training_used[str(year)] = used + 1
	return {"ok": true, "reason": "Training done: +%d XP." % xp, "granted": award_xp(profile, xp)}


# --- attributes ---------------------------------------------------------------------------------------------

## Development points needed to raise an attribute that is now at `value` by one.
static func attribute_cost(value: int) -> int:
	var cost := 1
	for step in rules()["attribute_cost"]:
		if value >= int(step[0]):
			cost = int(step[1])
	return cost


## Raises one attribute of the career player by 1 if the points and the body's ceiling allow. Returns {"ok", "reason", "value", "cost"}.
static func raise_attribute(profile: FcCareerProfile, player: FcPlayer, key: String) -> Dictionary:
	if not player.attributes.get_catalog().has_key(key):
		return {"ok": false, "reason": "Unknown attribute."}
	var value := player.attributes.get_value(key)
	var ceiling := FcPlayerBuild.attribute_ceiling(key, FcPlayerBuild.spec_of(player, profile.build_potential))
	if value >= ceiling:
		return {"ok": false, "reason": "%s is at the most your body and potential allow (%d)." % [player.attributes.get_catalog().get_def(key).display_name, ceiling]}
	var cost := attribute_cost(value)
	if profile.development_points < cost:
		return {"ok": false, "reason": "That costs %d development points and you have %d." % [cost, profile.development_points]}
	profile.development_points -= cost
	player.attributes.set_value(key, value + 1)
	return {"ok": true, "reason": "Raised to %d." % (value + 1), "value": value + 1, "cost": cost}


# --- role: what the player asks of his coach ---------------------------------------------------------------------------

## Why the coach refuses a request ("" = accepted). A player must have earned a bigger role: to start he must be within
## `START_MARGIN` overall points of his team's fifth best player (a coach-meeting "role push" earlier widens that by
## `ROLE_PUSH_BONUS`), and to shoot first (+1 usage) or play more minutes (+1) he needs some reputation. Asking to come off
## the bench, to play less or to pass first is always allowed.
const START_MARGIN := 4.0
const ROLE_PUSH_BONUS := 5.0
const REPUTATION_FOR_MORE := 5

static func role_problem(profile: FcCareerProfile, player_overall: float, team_overalls: Array, role: String, minutes_pref: int, usage_pref: int) -> String:
	if not ["auto", "starter", "bench"].has(role) or absi(minutes_pref) > 1 or absi(usage_pref) > 1:
		return "That is not a valid request."
	if role == "starter":
		var sorted := team_overalls.duplicate()
		sorted.sort()
		sorted.reverse()
		var fifth := float(sorted[mini(4, sorted.size() - 1)]) if not sorted.is_empty() else 0.0
		var margin := START_MARGIN + (ROLE_PUSH_BONUS if profile.tags.has("role_push") else 0.0)
		if player_overall < fifth - margin:
			return "The coach says you are not ready to start: you are rated %d and his fifth starter is %d." % [roundi(player_overall), roundi(fifth)]
	if (usage_pref > 0 or minutes_pref > 0) and profile.reputation < REPUTATION_FOR_MORE:
		return "The coach wants you to earn it first: shooting first or playing more needs %d reputation (you have %d)." % [REPUTATION_FOR_MORE, profile.reputation]
	return ""


## The simulation inputs for a role request: {"role_bonus", "minutes_pref", "usage_pref"}.
static func role_inputs(profile: FcCareerProfile) -> Dictionary:
	var bonus := 0.0
	if profile.role == "starter":
		bonus = 15.0
	elif profile.role == "bench":
		bonus = -40.0
	return {"role_bonus": bonus, "minutes_pref": float(profile.minutes_pref), "usage_pref": float(profile.usage_pref)}


# --- contracts: the offer and what an agent can win ----------------------------------------------------------------------

## The player's negotiating strength (0-100): a veteran agent is solid, a flashy agent aggressive, no agent weaker.
static func agent_negotiation(profile: FcCareerProfile) -> float:
	if profile.tags.has("agent_flashy"):
		return 75.0
	if profile.tags.has("agent_loyal"):
		return 60.0
	return 40.0


## The team's offer for a new contract and the most it would pay if pushed:
## {"salary", "max_salary", "years"}. The offer is the market price for his value scaled 90-110% by how he ranks in the team's
## rotation (a clear rotation player gets full value); the agent and the player's reputation raise the ceiling by a few percent.
static func contract_terms(profile: FcCareerProfile, market_ask: int, player_overall: float, team_overalls: Array, years: int, cap: FcCapRules) -> Dictionary:
	var sorted := team_overalls.duplicate()
	sorted.sort()
	sorted.reverse()
	var eighth := float(sorted[mini(7, sorted.size() - 1)]) if not sorted.is_empty() else player_overall
	var scale := 0.9 + 0.2 * clampf((player_overall - eighth) / 20.0, 0.0, 1.0)
	var offer := clampi(roundi(market_ask * scale / 10000.0) * 10000, cap.min_player_salary, cap.max_player_salary)
	var push := (agent_negotiation(profile) - 50.0) / 50.0 * 0.08 + float(profile.reputation) / 100.0 * 0.05
	var ceiling := clampi(roundi(offer * (1.0 + push) / 10000.0) * 10000, offer, cap.max_player_salary)
	return {"salary": offer, "max_salary": maxi(offer, ceiling), "years": years}


# --- badges ----------------------------------------------------------------------------------------------------

## Why a badge cannot be unlocked now ("" = it can). Checks level, attribute minimums, prerequisite badges and skill points.
static func badge_problem(profile: FcCareerProfile, player: FcPlayer, key: String) -> String:
	var badge := FcBadges.get_badge(key)
	if badge.is_empty():
		return "Unknown badge."
	if profile.badges_owned.has(key):
		return "You already own this badge."
	var need: Dictionary = badge["requires"]
	if profile.level < int(need.get("level", 1)):
		return "Needs level %d." % int(need["level"])
	for attribute in need.get("attributes", {}):
		if player.attributes.get_value(attribute) < int(need["attributes"][attribute]):
			return "Needs %s %d (you have %d)." % [player.attributes.get_catalog().get_def(attribute).display_name, int(need["attributes"][attribute]), player.attributes.get_value(attribute)]
	for other in need.get("badges", []):
		if not profile.badges_owned.has(other):
			return "Needs the %s badge first." % FcBadges.get_badge(other).get("name", other)
	if profile.skill_points < int(badge["cost"]):
		return "Costs %d skill points and you have %d." % [int(badge["cost"]), profile.skill_points]
	return ""


static func unlock_badge(profile: FcCareerProfile, player: FcPlayer, key: String) -> Dictionary:
	var problem := badge_problem(profile, player, key)
	if problem != "":
		return {"ok": false, "reason": problem}
	profile.skill_points -= int(FcBadges.get_badge(key)["cost"])
	profile.badges_owned.append(key)
	return {"ok": true, "reason": "Unlocked %s." % FcBadges.get_badge(key)["name"]}


## Equips or unequips an owned badge (at most the build rules' limit at once).
static func set_badge_equipped(profile: FcCareerProfile, key: String, equipped: bool) -> Dictionary:
	if not profile.badges_owned.has(key):
		return {"ok": false, "reason": "You do not own that badge."}
	if equipped:
		if profile.badges_equipped.has(key):
			return {"ok": true, "reason": "Already equipped."}
		var maximum := int(FcBuildRules.rules()["max_badges_equipped"])
		if profile.badges_equipped.size() >= maximum:
			return {"ok": false, "reason": "You can equip at most %d badges." % maximum}
		profile.badges_equipped.append(key)
	else:
		profile.badges_equipped.erase(key)
	return {"ok": true, "reason": "Equipped." if equipped else "Unequipped."}


## The adjustment equipped badges give each composite rating, capped per composite: {"three": 2, ...}.
static func composite_bonus(equipped: Array) -> Dictionary:
	var total := {}
	for key in equipped:
		var effects: Dictionary = FcBadges.get_badge(str(key)).get("effects", {})
		for composite in effects:
			total[composite] = int(total.get(composite, 0)) + int(effects[composite])
	for composite in total:
		total[composite] = mini(int(total[composite]), FcBadges.bonus_cap())
	return total
