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
	profile.skill_points += int(def.get("skill_points", 0))
	granted["skill_points"] += int(def.get("skill_points", 0))
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


## The overall a build is capped at: the potential the player was created with (or his current one for a player with no profile value).
static func overall_cap(profile: FcCareerProfile, player: FcPlayer) -> int:
	return profile.build_potential if profile.build_potential > 0 else player.development.potential


## The player's overall as the screens show it (rounded, the same number the cap and the milestone use).
static func overall_now(player: FcPlayer) -> int:
	return roundi(FcPlayerRatings.load_default().overall(player))


## What raising one attribute by 1 would do, computed once and used by both the preview and the real raise so they cannot disagree:
## {"ok", "reason", "blocked" ("" | "unknown" | "ceiling" | "potential" | "points"), "cost", "value", "overall_now", "overall_after", "gain"}.
## `gain` is the real change in the (unrounded) overall; the cap uses the rounded overall after the raise, so a player can never
## show more than his potential.
static func raise_preview(profile: FcCareerProfile, player: FcPlayer, key: String) -> Dictionary:
	var out := {"ok": false, "reason": "", "blocked": "", "cost": 0, "value": 0, "overall_now": 0.0, "overall_after": 0.0, "gain": 0.0}
	if not player.attributes.get_catalog().has_key(key):
		out["reason"] = "Unknown attribute."
		out["blocked"] = "unknown"
		return out
	var ratings := FcPlayerRatings.load_default()
	var value := player.attributes.get_value(key)
	var name: String = player.attributes.get_catalog().get_def(key).display_name
	var before := ratings.overall(player)
	out["value"] = value
	out["cost"] = attribute_cost(value)
	out["overall_now"] = before
	var ceiling := FcPlayerBuild.attribute_ceiling(key, FcPlayerBuild.spec_of(player, profile.build_potential))
	if value >= ceiling:
		out["reason"] = "%s is at the most your body allows (%d)." % [name, ceiling]
		out["blocked"] = "ceiling"
		out["overall_after"] = before
		return out
	player.attributes.set_value(key, value + 1)
	var after := ratings.overall(player)
	player.attributes.set_value(key, value)   # a preview never changes the player
	out["overall_after"] = after
	out["gain"] = after - before
	var cap := overall_cap(profile, player)
	if roundi(after) > cap:
		out["reason"] = "You are at your potential overall (%d): raising %s would pass it. Raise a skill that matters less, or keep your points for later when age lowers your rating." % [cap, name]
		out["blocked"] = "potential"
		return out
	if profile.development_points < int(out["cost"]):
		out["reason"] = "That costs %d development points and you have %d." % [int(out["cost"]), profile.development_points]
		out["blocked"] = "points"
		return out
	out["ok"] = true
	out["reason"] = "+1 %s for %d point%s: overall %+.1f." % [name, int(out["cost"]), "" if int(out["cost"]) == 1 else "s", float(out["gain"])]
	return out


## Raises one attribute of the career player by 1 if the preview allows it. Returns {"ok", "reason", "value", "cost"}.
static func raise_attribute(profile: FcCareerProfile, player: FcPlayer, key: String) -> Dictionary:
	var preview := raise_preview(profile, player, key)
	if not preview["ok"]:
		return {"ok": false, "reason": preview["reason"]}
	profile.development_points -= int(preview["cost"])
	player.attributes.set_value(key, int(preview["value"]) + 1)
	return {"ok": true, "reason": "Raised to %d." % (int(preview["value"]) + 1), "value": int(preview["value"]) + 1, "cost": int(preview["cost"])}


## The most useful upgrade now: the highest overall gain per development point among attributes the body and the potential still
## allow (affordable or not; ties go to the attribute whose key sorts first). Returns {} when nothing can be raised.
static func best_next_upgrade(profile: FcCareerProfile, player: FcPlayer) -> Dictionary:
	var best := {}
	var best_score := -1.0
	var keys: Array = player.attributes.get_catalog().keys()
	keys.sort()
	for key in keys:
		var p := raise_preview(profile, player, key)
		if p["blocked"] in ["unknown", "ceiling", "potential"]:
			continue
		var score := float(p["gain"]) / float(p["cost"])
		if score > best_score + 0.000001:
			best_score = score
			best = {"key": key, "name": player.attributes.get_catalog().get_def(key).display_name, "gain": p["gain"], "cost": p["cost"], "affordable": p["ok"]}
	return best


## Progress toward potential: {"overall", "potential", "to_go", "fraction", "at_potential"}. At potential means within the
## milestone threshold (1 point) of it.
static func potential_progress(profile: FcCareerProfile, player: FcPlayer) -> Dictionary:
	var overall := overall_now(player)
	var potential := overall_cap(profile, player)
	return {"overall": overall, "potential": potential, "to_go": maxi(0, potential - overall), "fraction": clampf(float(overall) / maxf(1.0, potential), 0.0, 1.0),
		"at_potential": overall >= potential - int(rules()["potential_threshold"])}


## Claims the one-time "max potential reached" milestone when the player is within the threshold of his potential, and flags the
## banner for the screens. Returns the claim result, or {"ok": false} if it is not due (or was already claimed).
static func check_potential(profile: FcCareerProfile, player: FcPlayer) -> Dictionary:
	if profile.milestones.has("potential_reached") or not potential_progress(profile, player)["at_potential"]:
		return {"ok": false, "reason": ""}
	var claimed := claim_milestone(profile, "potential_reached")
	if claimed["ok"]:
		profile.potential_banner_pending = true
	return claimed


## The development points a season's automatic growth is worth to the player: growth points times `growth_to_points`, rounded.
static func growth_to_points(growth_points: float) -> int:
	return roundi(growth_points * float(rules()["growth_to_points"]))


# --- prospect: scouting and draft position ---------------------------------------------------------------------------

## How highly scouts rate a prospect: mostly what he is now, some of what he can become (0.6 overall, 0.4 potential).
static func prospect_score(overall: int, potential: int) -> float:
	return 0.6 * float(overall) + 0.4 * float(potential)


## The pick a prospect is projected to go (1 = first) among `picks` picks: a score of 50 or less goes last, 85 or more first,
## and the seeded `jitter` (a whole number, usually -2 to 2) is the draft-night surprise. Pure, so the same player always gets the same range.
static func projected_pick(score: float, picks: int, jitter: int) -> int:
	if picks <= 1:
		return 1
	var share := clampf((score - 50.0) / 35.0, 0.0, 1.0)
	return clampi(1 + roundi((1.0 - share) * float(picks - 1)) + jitter, 1, picks)


## A plain scouting line for the prospect screen.
static func scouting_note(pick: int, picks: int) -> String:
	var share := float(pick - 1) / float(maxi(picks - 1, 1))
	if share <= 0.15:
		return "Scouts see a future star: a top pick."
	if share <= 0.5:
		return "A solid first-round talent."
	if share <= 0.85:
		return "A late pick: you will have to earn your place."
	return "Scouts doubt you: expect to go last. Prove them wrong."


# --- role: what the player asks of his coach ---------------------------------------------------------------------------

# --- sponsorships ----------------------------------------------------------------------------------------------------------

const SPONSOR_MIN_REPUTATION := 5
const COSMETIC_COST := 150

## Offers for a season (derived from the profile and year, so nothing is stored): up to three {"sponsor", "amount", "years", "edge"}.
## Nobody sponsors an unknown player (reputation under 5). A "safe" brand pays steadily; a "bold" brand pays 60% more for fewer
## years but costs the player 1 reputation and 1 chemistry every season (its image is controversial).
static func sponsor_offers(profile: FcCareerProfile, year: int, rng: FcRng, names: Array) -> Array:
	var out: Array = []
	if profile.reputation < SPONSOR_MIN_REPUTATION or names.is_empty():
		return out
	var base := mini(2500, 150 + 25 * profile.reputation)
	var pool := names.duplicate()
	for i in 3:
		if pool.is_empty():
			break
		var name := str(pool.pop_at(rng.range_int(0, pool.size() - 1)))
		if profile.sponsor_deal.get("sponsor", "") == name:
			continue
		var bold := i == 2
		out.append({"sponsor": name, "amount": roundi(base * (1.6 if bold else 1.0) * rng.range_float(0.9, 1.1) / 10.0) * 10,
			"years": rng.range_int(1, 2) if bold else rng.range_int(2, 3), "edge": "bold" if bold else "safe"})
	return out


## Signs one of the offers. One deal at a time. Returns {"ok", "reason"}.
static func sign_sponsor(profile: FcCareerProfile, offer: Dictionary) -> Dictionary:
	if not profile.sponsor_deal.is_empty():
		return {"ok": false, "reason": "You already have a sponsor: %s." % profile.sponsor_deal["sponsor"]}
	profile.sponsor_deal = {"sponsor": offer["sponsor"], "amount": int(offer["amount"]), "years_left": int(offer["years"]), "edge": str(offer["edge"])}
	return {"ok": true, "reason": "Signed with %s: %d currency a season for %d season%s." % [offer["sponsor"], int(offer["amount"]), int(offer["years"]), "" if int(offer["years"]) == 1 else "s"]}


## One season of the deal: pays the amount, applies the brand's image (a bold brand costs reputation and chemistry) and runs the
## contract down. Paid once per season (guarded by `sponsor_paid_year`). Returns {"paid", "reputation", "chemistry"}.
static func pay_sponsor(profile: FcCareerProfile, year: int) -> Dictionary:
	var result := {"paid": 0, "reputation": 0, "chemistry": 0}
	if profile.sponsor_deal.is_empty() or profile.sponsor_paid_year == year:
		return result
	profile.sponsor_paid_year = year
	profile.currency += int(profile.sponsor_deal["amount"])
	result["paid"] = int(profile.sponsor_deal["amount"])
	if profile.sponsor_deal["edge"] == "bold":
		var rep_before := profile.reputation
		profile.reputation = maxi(0, profile.reputation - 1)
		profile.chemistry = maxi(0, profile.chemistry - 1)
		result["reputation"] = profile.reputation - rep_before
		result["chemistry"] = -1
	profile.sponsor_deal["years_left"] = int(profile.sponsor_deal["years_left"]) - 1
	if int(profile.sponsor_deal["years_left"]) <= 0:
		profile.sponsor_deal = {}
	return result


## Ends the deal early: the brand is unhappy, so it costs 1 reputation.
static func drop_sponsor(profile: FcCareerProfile) -> Dictionary:
	if profile.sponsor_deal.is_empty():
		return {"ok": false, "reason": "You have no sponsor."}
	var name := str(profile.sponsor_deal["sponsor"])
	profile.sponsor_deal = {}
	profile.reputation = maxi(0, profile.reputation - 1)
	return {"ok": true, "reason": "You ended the deal with %s. Breaking it cost 1 reputation." % name}


## Spends currency on a new look (a cosmetic: it never changes the player's ability). Returns {"ok", "reason"}.
static func change_appearance(profile: FcCareerProfile, part: String, option: String) -> Dictionary:
	var options: Dictionary = FcBuildRules.rules()["appearance"]
	if not options.has(part) or not (options[part] as Array).has(option):
		return {"ok": false, "reason": "That is not an available look."}
	if str(profile.appearance.get(part, "")) == option:
		return {"ok": false, "reason": "You already have that look."}
	if profile.currency < COSMETIC_COST:
		return {"ok": false, "reason": "A new look costs %d currency and you have %d." % [COSMETIC_COST, profile.currency]}
	profile.currency -= COSMETIC_COST
	profile.appearance[part] = option
	return {"ok": true, "reason": "New look: %s %s." % [part.replace("_", " "), option.replace("_", " ")]}


# --- rivalries -----------------------------------------------------------------------------------------------------------

## A game score for comparing two players' nights: points plus the other things that win.
static func game_score(line: Dictionary) -> float:
	return float(line.get("points", 0)) + 1.2 * float(line.get("rebounds", 0)) + 1.5 * float(line.get("assists", 0)) \
		+ 2.0 * float(line.get("steals", 0)) + 2.0 * float(line.get("blocks", 0)) - 1.5 * float(line.get("turnovers", 0))


## Chooses a rival from [[player id, overall], ...] (players on OTHER teams): a seeded pick among the three closest to
## `my_overall`, so a rival is a real peer. Returns 0 if there are no candidates.
static func pick_rival(candidates: Array, my_overall: float, rng: FcRng) -> int:
	if candidates.is_empty():
		return 0
	var sorted := candidates.duplicate()
	sorted.sort_custom(func(a, b):
		var da := absf(float(a[1]) - my_overall)
		var db := absf(float(b[1]) - my_overall)
		return da < db if da != db else int(a[0]) < int(b[0]))
	var top := sorted.slice(0, mini(3, sorted.size()))
	return int(top[rng.range_int(0, top.size() - 1)][0])


## Scores a night against the rival: the better game score wins the duel. A win pays XP (and every third win a point of
## reputation); a loss costs nothing but the record. Returns {"won", "xp", "reputation"}.
static func duel(profile: FcCareerProfile, my_line: Dictionary, rival_line: Dictionary) -> Dictionary:
	var won := game_score(my_line) > game_score(rival_line)
	var result := {"won": won, "xp": 0, "reputation": 0}
	if won:
		profile.rival_wins += 1
		result["xp"] = 30
		award_xp(profile, 30)
		if profile.rival_wins % 3 == 0:
			profile.reputation += 1
			result["reputation"] = 1
	else:
		profile.rival_losses += 1
	return result


## How the season changes the relationships. `context` = {"rank": his rank by overall on his team (1 = best), "win_pct": the
## team's winning share, "games": games he played}. The coach trusts a player who is among his best (and plays); a player who sits
## below the rotation loses trust. Teammates bond over winning and over community work, and are put off by an outspoken player.
## Returns {"coach_trust", "chemistry", "development_points"} (the changes); a close team (chemistry 70+) also grants a development point.
static func relationships_after_season(profile: FcCareerProfile, context: Dictionary) -> Dictionary:
	var rank := int(context.get("rank", 8))
	var trust := 0
	if rank <= 5:
		trust += 3
	elif rank <= 8:
		trust += 1
	else:
		trust -= 2
	if int(context.get("games", 0)) < 10:
		trust -= 2
	if profile.tags.has("role_push"):
		trust -= 1
	if profile.tags.has("hardball"):
		trust -= 1
	var bond := 0
	var win_pct := float(context.get("win_pct", 0.5))
	if win_pct >= 0.55:
		bond += 3
	elif win_pct < 0.40:
		bond -= 2
	if profile.tags.has("community"):
		bond += 2
	if profile.tags.has("outspoken"):
		bond -= 2
	var before_trust := profile.coach_trust
	var before_chemistry := profile.chemistry
	profile.coach_trust = clampi(profile.coach_trust + trust, 0, 100)
	profile.chemistry = clampi(profile.chemistry + bond, 0, 100)
	var points := 0
	if profile.chemistry >= 70:
		points = 1
		profile.development_points += 1
	return {"coach_trust": profile.coach_trust - before_trust, "chemistry": profile.chemistry - before_chemistry, "development_points": points}


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
		var margin := START_MARGIN + (ROLE_PUSH_BONUS if profile.tags.has("role_push") else 0.0) + float(profile.coach_trust - 50) / 10.0   # trust: +-5 points
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
	var push := (agent_negotiation(profile) - 50.0) / 50.0 * 0.08 + float(profile.reputation) / 100.0 * 0.05 + float(profile.coach_trust - 50) / 50.0 * 0.03
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
