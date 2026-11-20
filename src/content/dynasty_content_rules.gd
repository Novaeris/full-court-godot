class_name FcDynastyContentRules
extends RefCounted
## The Dynasty-specific part of content validation: what a pack's odds, a card's price, a challenge, a season (with its
## milestones and tournaments) and the economy config must look like. Called by FcContentValidator for every definition,
## so a release that breaks these rules is never published and never loaded.
##
## Rule of thumb: anything that changes how a definition works must be declared in `requires_features`, so an older game
## refuses it instead of misreading it.

const CURRENCIES := ["credits", "tokens", "shards"]
const RARITY_ORDER := ["common", "uncommon", "rare", "epic", "legendary"]
const ODDS_TOTAL := 10000
const CHALLENGE_CATEGORIES := ["scoring", "shooting", "playmaking", "defense", "rebounding", "team_composition", "collection"]
## Game statistics an objective may count (see FcDynastyChallenges).
const STATS := ["points", "rebounds", "assists", "steals", "blocks", "threes", "free_throws"]
const OBJECTIVE_TYPES := ["stat", "wins", "win_margin", "collection"]
const REWARD_KEYS := ["credits", "tokens", "shards", "card_ids", "pack_ids"]
const COLLECTION_METRICS := ["unique_cards", "rarity_cards", "duplicates"]
const TOURNAMENT_TEAMS := 7
const PLACEMENTS := ["champion", "finalist", "semifinal", "quarterfinal"]


static func rarity_rank(rarity: String) -> int:
	return RARITY_ORDER.find(rarity)


static func _has_feature(data: Dictionary, feature: String) -> bool:
	var feats = data.get("requires_features", [])
	return feats is Array and feats.has(feature)


static func _int(value: Variant, fallback: int = -1) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, floorf(value)):
		return int(value)
	return fallback


# --- players and cards ------------------------------------------------------------------------------------------

static func check_player(path: String, data: Dictionary, definitions: FcDefinitionSet, errors: Array[String]) -> void:
	if data.has("secondary_position"):
		var sec := str(data["secondary_position"])
		if not ["PG", "SG", "SF", "PF", "C"].has(sec) or sec == str(data.get("position", "")):
			errors.append("%s: secondary_position must be a position different from the primary one" % path)
	if data.has("badges"):
		var badges = data["badges"]
		if not (badges is Array):
			errors.append("%s: badges must be a list" % path)
		else:
			for b in badges:
				if FcBadges.get_badge(str(b)).is_empty():
					errors.append("%s: unknown badge '%s'" % [path, str(b)])
	if data.has("tendencies"):
		var t = data["tendencies"]
		if not (t is Dictionary):
			errors.append("%s: tendencies must be an object" % path)
		else:
			for key in t:
				var v := _int(t[key])
				if v < 0 or v > 100:
					errors.append("%s: tendency '%s' must be a whole number from 0 to 100" % [path, str(key)])
				elif definitions != null and not definitions.tendencies.has_key(str(key)):
					errors.append("%s: unknown tendency '%s'" % [path, str(key)])
	if data.has("team") and (str(data["team"]).strip_edges().is_empty() or str(data["team"]).length() > 60):
		errors.append("%s: team must be 1-60 characters" % path)


static func check_card(path: String, data: Dictionary, definitions: FcDefinitionSet, errors: Array[String]) -> void:
	if data.has("attributes") or data.has("badges") or data.has("tendencies"):
		# an edition may carry its own ratings, badges and tendencies on top of the player's
		if not _has_feature(data, "card_overrides_v1"):
			errors.append("%s: attributes, badges and tendencies on a card need requires_features to include card_overrides_v1" % path)
		if data.has("attributes"):
			if not (data["attributes"] is Dictionary):
				errors.append("%s: attributes must be an object" % path)
			else:
				for key in data["attributes"]:
					var v := _int(data["attributes"][key])
					if v < 0 or v > 100:
						errors.append("%s: attribute '%s' must be a whole number from 0 to 100" % [path, str(key)])
					elif definitions != null and not definitions.attributes.has_key(str(key)):
						errors.append("%s: unknown attribute '%s'" % [path, str(key)])
		var shell := {"badges": data.get("badges", []), "tendencies": data.get("tendencies", {})}
		var sub_errors: Array[String] = []
		check_player(path, shell, definitions, sub_errors)
		errors.append_array(sub_errors)
	if data.has("edition") and (str(data["edition"]).strip_edges().is_empty() or str(data["edition"]).length() > 40):
		errors.append("%s: edition must be 1-40 characters" % path)
	if data.has("price") or data.has("acquirable"):
		if not _has_feature(data, "card_market_v1"):
			errors.append("%s: price and acquirable need requires_features to include card_market_v1" % path)
		if data.has("acquirable") and not (data["acquirable"] is bool):
			errors.append("%s: acquirable must be true or false" % path)
	if data.has("price"):
		errors.append_array(_price_problems(path, data["price"]))


static func _price_problems(path: String, price: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not (price is Dictionary) or not CURRENCIES.has(str(price.get("currency", ""))) or _int(price.get("amount")) < 0:
		errors.append("%s: price must be {\"currency\": credits|tokens|shards, \"amount\": whole number >= 0}" % path)
	return errors


# --- packs -------------------------------------------------------------------------------------------------------

static func check_pack(path: String, data: Dictionary, cards: Dictionary, errors: Array[String]) -> void:
	var odds_keys := ["price", "cards_per_pack", "odds", "guarantees", "pity"]
	var uses := false
	for k in odds_keys:
		if data.has(k):
			uses = true
	if not uses:
		return
	if not _has_feature(data, "pack_odds_v1"):
		errors.append("%s: price, odds, guarantees and pity need requires_features to include pack_odds_v1" % path)
	errors.append_array(_price_problems(path, data.get("price")))
	var count := _int(data.get("cards_per_pack"))
	if count < 1 or count > 20:
		errors.append("%s: cards_per_pack must be a whole number from 1 to 20" % path)
	var pool_rarities := {}
	for cid in data.get("card_ids", []):
		if cards.has(str(cid)):
			pool_rarities[str(cards[str(cid)].get("rarity", ""))] = true
	var odds = data.get("odds", null)
	if not (odds is Dictionary):
		errors.append("%s: odds must list a whole-number weight for each rarity, adding up to %d" % [path, ODDS_TOTAL])
		return
	var total := 0
	for rarity in odds:
		var w := _int(odds[rarity])
		if not RARITY_ORDER.has(str(rarity)) or w < 0:
			errors.append("%s: odds '%s' is not a rarity with a whole weight >= 0" % [path, str(rarity)])
			continue
		total += w
		if w > 0 and not pool_rarities.has(str(rarity)):
			errors.append("%s: odds give %s a chance but the pack's cards include none" % [path, str(rarity)])
	if total != ODDS_TOTAL:
		errors.append("%s: odds add up to %d, they must add up to %d" % [path, total, ODDS_TOTAL])
	var g = data.get("guarantees", [])
	if not (g is Array):
		errors.append("%s: guarantees must be a list" % path)
	else:
		var slots := 0
		for entry in g:
			var rank := rarity_rank(str(entry.get("min_rarity", ""))) if entry is Dictionary else -1
			var n := _int(entry.get("count")) if entry is Dictionary else -1
			if rank < 0 or n < 1:
				errors.append("%s: each guarantee needs a min_rarity and a count of at least 1" % path)
				continue
			slots += n
			var has_eligible := false
			for r in pool_rarities:
				if rarity_rank(str(r)) >= rank:
					has_eligible = true
			if not has_eligible:
				errors.append("%s: a %s guarantee has no card in the pack to give" % [path, str(entry["min_rarity"])])
		if slots > count:
			errors.append("%s: guarantees need %d cards but a pack holds only %d" % [path, slots, count])
	if data.has("pity"):
		var pity = data["pity"]
		if not (pity is Dictionary) or rarity_rank(str(pity.get("rarity", ""))) < 0 or _int(pity.get("after")) < 1:
			errors.append("%s: pity needs a rarity and an 'after' count of at least 1" % path)
		elif not pool_rarities.has(str(pity["rarity"])):
			errors.append("%s: pity names %s but the pack's cards include none" % [path, str(pity["rarity"])])


# --- rewards, objectives, challenges -----------------------------------------------------------------------------

static func reward_problems(path: String, rewards: Variant, cards: Dictionary, packs: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if not (rewards is Dictionary):
		errors.append("%s: rewards must be an object" % path)
		return errors
	for key in rewards:
		if not REWARD_KEYS.has(str(key)):
			errors.append("%s: unknown reward '%s'" % [path, str(key)])
	for c in CURRENCIES:
		if rewards.has(c) and _int(rewards[c]) < 0:
			errors.append("%s: reward %s must be a whole number >= 0" % [path, c])
	for key in ["card_ids", "pack_ids"]:
		if rewards.has(key):
			if not (rewards[key] is Array):
				errors.append("%s: reward %s must be a list" % [path, key])
				continue
			for id in rewards[key]:
				if key == "card_ids" and not cards.has(str(id)):
					errors.append("%s: reward card '%s' is not a card in this release" % [path, str(id)])
				if key == "pack_ids" and not packs.has(str(id)):
					errors.append("%s: reward pack '%s' is not a pack in this release" % [path, str(id)])
	return errors


static func objective_problems(path: String, obj: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not (obj is Dictionary) or not OBJECTIVE_TYPES.has(str(obj.get("type", ""))):
		errors.append("%s: objective.type must be one of %s" % [path, ", ".join(OBJECTIVE_TYPES)])
		return errors
	if _int(obj.get("target")) < 1:
		errors.append("%s: objective.target must be a whole number of at least 1" % path)
	match str(obj["type"]):
		"stat":
			if not STATS.has(str(obj.get("stat", ""))):
				errors.append("%s: objective.stat must be one of %s" % [path, ", ".join(STATS)])
			var scope := str(obj.get("scope", "team"))
			var mode := str(obj.get("mode", "single_game"))
			if not ["team", "player"].has(scope) or not ["single_game", "cumulative"].has(mode):
				errors.append("%s: objective.scope is team|player and objective.mode is single_game|cumulative" % path)
			elif scope == "player" and mode == "cumulative":
				errors.append("%s: a player-scope objective must be single_game" % path)
		"collection":
			if not COLLECTION_METRICS.has(str(obj.get("metric", ""))):
				errors.append("%s: objective.metric must be one of %s" % [path, ", ".join(COLLECTION_METRICS)])
			if str(obj.get("metric", "")) == "rarity_cards" and rarity_rank(str(obj.get("rarity", ""))) < 0:
				errors.append("%s: a rarity_cards objective needs a rarity" % path)
	return errors


static func restriction_problems(path: String, r: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not (r is Dictionary):
		errors.append("%s: restrictions must be an object" % path)
		return errors
	for key in r:
		if key == "max_rarity":
			if rarity_rank(str(r[key])) < 0:
				errors.append("%s: restrictions.max_rarity must be a rarity" % path)
		elif key in ["max_overall", "min_overall"]:
			if _int(r[key]) < 1 or _int(r[key]) > 100:
				errors.append("%s: restrictions.%s must be 1-100" % [path, key])
		else:
			errors.append("%s: unknown restriction '%s'" % [path, str(key)])
	return errors


static func check_challenge(path: String, data: Dictionary, cards: Dictionary, packs: Dictionary, errors: Array[String]) -> void:
	if not _has_feature(data, "challenge_v1"):
		errors.append("%s: challenges need requires_features to include challenge_v1" % path)
	if str(data.get("title", "")).strip_edges().is_empty():
		errors.append("%s: title is required" % path)
	if not CHALLENGE_CATEGORIES.has(str(data.get("category", ""))):
		errors.append("%s: category must be one of %s" % [path, ", ".join(CHALLENGE_CATEGORIES)])
	errors.append_array(objective_problems(path, data.get("objective")))
	errors.append_array(reward_problems(path, data.get("rewards", {}), cards, packs))
	if data.has("restrictions"):
		errors.append_array(restriction_problems(path, data["restrictions"]))
	if data.has("season_points") and _int(data["season_points"]) < 0:
		errors.append("%s: season_points must be a whole number >= 0" % path)


# --- seasons and tournaments ------------------------------------------------------------------------------------

static func check_season(path: String, data: Dictionary, cards: Dictionary, packs: Dictionary,
		challenges: Dictionary, errors: Array[String]) -> void:
	if not _has_feature(data, "season_v1"):
		errors.append("%s: seasons need requires_features to include season_v1" % path)
	if str(data.get("name", "")).strip_edges().is_empty():
		errors.append("%s: name is required" % path)
	for cid in data.get("challenge_ids", []):
		if not challenges.has(str(cid)):
			errors.append("%s: challenge '%s' is not a challenge in this release" % [path, str(cid)])
	var seen := {}
	for m in data.get("milestones", []):
		if not (m is Dictionary) or str(m.get("id", "")).is_empty() or _int(m.get("points")) < 1:
			errors.append("%s: each milestone needs an id and points of at least 1" % path)
			continue
		if seen.has(str(m["id"])):
			errors.append("%s: duplicate milestone id '%s'" % [path, str(m["id"])])
		seen[str(m["id"])] = true
		errors.append_array(reward_problems("%s milestone %s" % [path, str(m["id"])], m.get("rewards", {}), cards, packs))
	for o in data.get("objectives", []):
		if not (o is Dictionary) or str(o.get("id", "")).is_empty() or _int(o.get("points")) < 1:
			errors.append("%s: each season objective needs an id and points of at least 1" % path)
			continue
		if seen.has("o:" + str(o["id"])):
			errors.append("%s: duplicate objective id '%s'" % [path, str(o["id"])])
		seen["o:" + str(o["id"])] = true
		errors.append_array(objective_problems("%s objective %s" % [path, str(o["id"])], o.get("objective")))
	var tseen := {}
	for t in data.get("tournaments", []):
		_check_tournament(path, t, cards, packs, tseen, errors)


static func _check_tournament(path: String, t: Variant, cards: Dictionary, packs: Dictionary, seen: Dictionary, errors: Array[String]) -> void:
	if not (t is Dictionary) or str(t.get("tournament_id", "")).is_empty() or str(t.get("name", "")).is_empty():
		errors.append("%s: each tournament needs a tournament_id and a name" % path)
		return
	var tid := str(t["tournament_id"])
	if seen.has(tid):
		errors.append("%s: duplicate tournament_id '%s'" % [path, tid])
	seen[tid] = true
	var label := "%s tournament %s" % [path, tid]
	if t.has("entry_fee"):
		errors.append_array(_price_problems(label, t["entry_fee"]))
	var teams = t.get("teams", [])
	if not (teams is Array) or teams.size() != TOURNAMENT_TEAMS:
		errors.append("%s: a tournament needs exactly %d opposing teams (you are the eighth)" % [label, TOURNAMENT_TEAMS])
	else:
		for team in teams:
			if not (team is Dictionary) or str(team.get("name", "")).strip_edges().is_empty():
				errors.append("%s: every team needs a name" % label)
				continue
			if team.has("rating") and (_int(team["rating"]) < 30 or _int(team["rating"]) > 99):
				errors.append("%s: team rating must be 30-99" % label)
			if team.has("card_ids"):
				var ids = team["card_ids"]
				if not (ids is Array) or ids.size() != 13:
					errors.append("%s: team '%s' card_ids must list exactly 13 cards" % [label, str(team["name"])])
				else:
					for id in ids:
						if not cards.has(str(id)):
							errors.append("%s: team card '%s' is not a card in this release" % [label, str(id)])
			elif not team.has("rating"):
				errors.append("%s: team '%s' needs card_ids or a rating" % [label, str(team["name"])])
	var rewards = t.get("rewards", {})
	if not (rewards is Dictionary):
		errors.append("%s: rewards must map placements to rewards" % label)
	else:
		for place in rewards:
			if not PLACEMENTS.has(str(place)):
				errors.append("%s: unknown placement '%s' (use %s)" % [label, str(place), ", ".join(PLACEMENTS)])
			else:
				errors.append_array(reward_problems("%s %s" % [label, str(place)], rewards[place], cards, packs))


# --- support -------------------------------------------------------------------------------------------------------

static func check_support(path: String, data: Dictionary, cards: Dictionary, packs: Dictionary, errors: Array[String]) -> void:
	if str(data.get("support_id", "")) != "dynasty_config":
		return
	if not _has_feature(data, "dynasty_config_v1"):
		errors.append("%s: dynasty_config needs requires_features to include dynasty_config_v1" % path)
	var sp := str(data.get("starter_pack_id", ""))
	if sp != "" and not packs.has(sp):
		errors.append("%s: starter_pack_id '%s' is not a pack in this release" % [path, sp])
	for id in data.get("starter_card_ids", []):
		if not cards.has(str(id)):
			errors.append("%s: starter card '%s' is not a card in this release" % [path, str(id)])
	for key in ["starter_credits", "starter_tokens", "starter_shards"]:
		if data.has(key) and _int(data[key]) < 0:
			errors.append("%s: %s must be a whole number >= 0" % [path, key])
	var rarities: Dictionary = data.get("shards_per_duplicate", {}) if data.get("shards_per_duplicate") is Dictionary else {}
	for r in rarities:
		if rarity_rank(str(r)) < 0 or _int(rarities[r]) < 0:
			errors.append("%s: shards_per_duplicate '%s' is not a rarity with a whole amount" % [path, str(r)])
