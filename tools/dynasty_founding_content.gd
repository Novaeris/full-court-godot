class_name FcDynastyFoundingContent
extends RefCounted
## The "Founding Series": the first complete, playable Dynasty content release (D-055). Forty original, invented players
## (names, teams and ratings are fictional; any resemblance to real people is coincidence and a lawyer should still review them,
## CLAUDE.md rule 9), their cards and editions, packs, challenges, a season with two tournaments and the economy configuration.
##
## It is DATA written into a Creator Studio style draft and then published through the real FcPublisher by
## tools/build_starter_content.gd. Nothing here changes the game's economy or pack mechanics: it only uses them.
## The founder may replace any of it from Creator Studio at any time; a newer published release always wins over this bundled one.

const TIERS := ["common", "uncommon", "rare", "epic", "legendary"]
## Rating level (the average of an invented player's attributes before the archetype shapes them) per rarity tier.
const TIER_LEVEL := {"common": 56, "uncommon": 65, "rare": 73, "epic": 81, "legendary": 90}

## attribute shape of each play style: points added to (or taken from) the player's level.
const ARCHETYPES := {
	"floor_general": {"passing": 22, "ball_handling": 18, "basketball_iq": 16, "decision_making": 14, "leadership": 10, "offensive_awareness": 8, "speed": 4,
		"strength": -12, "blocks": -18, "interior_defense": -15, "rebounding": -14, "dunking": -10},
	"scoring_guard": {"three_point": 16, "mid_range": 14, "ball_handling": 14, "layups": 14, "shot_selection": 8, "free_throw": 8, "agility": 8, "speed": 8,
		"interior_defense": -16, "blocks": -16, "rebounding": -12, "strength": -10},
	"pest_guard": {"perimeter_defense": 22, "steals": 22, "speed": 14, "agility": 12, "stamina": 10, "ball_handling": 8, "passing": 6,
		"close_finishing": -8, "blocks": -14, "rebounding": -10, "three_point": -4},
	"sharpshooter": {"three_point": 24, "free_throw": 14, "mid_range": 10, "shot_selection": 10, "offensive_awareness": 8,
		"strength": -10, "blocks": -14, "interior_defense": -12, "rebounding": -10, "dunking": -8},
	"slasher": {"layups": 20, "dunking": 18, "close_finishing": 14, "speed": 12, "agility": 12, "vertical": 12,
		"three_point": -8, "shot_selection": -4, "free_throw": -4},
	"three_and_d": {"three_point": 14, "perimeter_defense": 16, "steals": 10, "defensive_awareness": 10, "stamina": 8, "consistency": 6,
		"ball_handling": -4, "passing": -4, "dunking": -4},
	"wing_scorer": {"mid_range": 14, "three_point": 10, "layups": 12, "ball_handling": 8, "shot_selection": 8, "offensive_awareness": 8, "vertical": 6,
		"interior_defense": -6, "blocks": -8},
	"two_way_wing": {"perimeter_defense": 14, "defensive_awareness": 12, "three_point": 6, "passing": 4, "strength": 4, "stamina": 8,
		"competitive_mentality": 8, "durability": 6},
	"point_forward": {"passing": 16, "ball_handling": 10, "basketball_iq": 14, "decision_making": 12, "rebounding": 8, "offensive_awareness": 8, "strength": 4,
		"three_point": -2},
	"stretch_four": {"three_point": 16, "mid_range": 10, "free_throw": 8, "offensive_awareness": 6, "rebounding": 4, "dunking": -4, "speed": -2, "blocks": -6},
	"bruiser": {"rebounding": 22, "strength": 20, "interior_defense": 14, "close_finishing": 14, "durability": 10, "defensive_awareness": 4,
		"three_point": -22, "ball_handling": -18, "speed": -8, "free_throw": -10, "passing": -8},
	"athletic_four": {"dunking": 20, "vertical": 16, "speed": 10, "agility": 8, "close_finishing": 12, "blocks": 8, "rebounding": 10,
		"three_point": -14, "ball_handling": -10, "shot_selection": -8},
	"rim_protector": {"blocks": 26, "interior_defense": 24, "rebounding": 16, "vertical": 12, "strength": 12, "defensive_awareness": 8,
		"three_point": -26, "ball_handling": -24, "passing": -12, "speed": -14, "agility": -10, "free_throw": -12, "mid_range": -14},
	"post_scorer": {"close_finishing": 22, "strength": 16, "layups": 10, "mid_range": 4, "offensive_awareness": 10, "rebounding": 8,
		"three_point": -18, "speed": -12, "ball_handling": -14, "steals": -10},
	"stretch_big": {"three_point": 8, "mid_range": 14, "free_throw": 10, "passing": 6, "rebounding": 6, "interior_defense": 6, "blocks": 4,
		"dunking": -6, "speed": -10, "ball_handling": -10},
	"glass_cleaner": {"rebounding": 26, "strength": 14, "close_finishing": 8, "vertical": 8, "durability": 8, "work_ethic": 10, "interior_defense": 8,
		"three_point": -24, "ball_handling": -20, "passing": -10, "speed": -12},
}

## Tendencies and badges per play style (badge keys come from data/career/badges.json).
const STYLE_EXTRAS := {
	"floor_general": {"badges": ["pick_and_roll_maestro"], "tendencies": {"pass_tendency": 78, "drive_tendency": 45, "three_point_tendency": 40}},
	"scoring_guard": {"badges": ["ankle_breaker"], "tendencies": {"drive_tendency": 65, "mid_range_tendency": 60, "three_point_tendency": 55}},
	"pest_guard": {"badges": ["clamps"], "tendencies": {"gamble_tendency": 70, "pass_tendency": 60}},
	"sharpshooter": {"badges": ["catch_and_shoot", "corner_specialist"], "tendencies": {"three_point_tendency": 85, "drive_tendency": 25}},
	"slasher": {"badges": ["posterizer"], "tendencies": {"drive_tendency": 85, "three_point_tendency": 20}},
	"three_and_d": {"badges": ["corner_specialist", "clamps"], "tendencies": {"three_point_tendency": 70, "foul_tendency": 35}},
	"wing_scorer": {"badges": ["catch_and_shoot"], "tendencies": {"mid_range_tendency": 65, "drive_tendency": 55, "three_point_tendency": 50}},
	"two_way_wing": {"badges": ["clamps"], "tendencies": {"drive_tendency": 50, "pass_tendency": 50}},
	"point_forward": {"badges": ["pick_and_roll_maestro"], "tendencies": {"pass_tendency": 72, "post_tendency": 35}},
	"stretch_four": {"badges": ["catch_and_shoot"], "tendencies": {"three_point_tendency": 68, "post_tendency": 20}},
	"bruiser": {"badges": ["rebound_chaser"], "tendencies": {"post_tendency": 75, "offensive_rebound_tendency": 80, "foul_tendency": 60}},
	"athletic_four": {"badges": ["posterizer"], "tendencies": {"drive_tendency": 70, "offensive_rebound_tendency": 65}},
	"rim_protector": {"badges": ["rim_protector"], "tendencies": {"post_tendency": 60, "foul_tendency": 55}},
	"post_scorer": {"badges": [], "tendencies": {"post_tendency": 85, "three_point_tendency": 5}},
	"stretch_big": {"badges": ["catch_and_shoot"], "tendencies": {"three_point_tendency": 60, "post_tendency": 40}},
	"glass_cleaner": {"badges": ["rebound_chaser"], "tendencies": {"offensive_rebound_tendency": 90, "post_tendency": 55}},
}

## [display name, primary, secondary ("" = none), play style, rarity, level adjustment, home club]
const PLAYERS := [
	["Ian Marlowe", "PG", "SG", "floor_general", "common", 0, "Savannah Mariners"],
	["Teodor Brask", "PG", "", "pest_guard", "common", 1, "Duluth Frost"],
	["Kellan Drummond", "PG", "SG", "scoring_guard", "uncommon", 0, "Reno Cinders"],
	["Rafael Oyelaran", "PG", "SG", "floor_general", "uncommon", 1, "Akron Foundry"],
	["Dominic Strand", "PG", "", "pest_guard", "rare", 0, "Boise Ironclads"],
	["Mateo Quillfeather", "PG", "SG", "scoring_guard", "rare", 1, "Tucson Mirage"],
	["Ansel Voss", "PG", "", "floor_general", "epic", 0, "Omaha Stampede"],
	["Jericho Hale", "PG", "SG", "scoring_guard", "legendary", 0, "Tulsa Wildfire"],
	["Cyrus Tallwood", "SG", "SF", "three_and_d", "common", 0, "Spokane Rapids"],
	["Nico Brandvold", "SG", "PG", "sharpshooter", "common", 1, "Duluth Frost"],
	["Evander Pike", "SG", "", "slasher", "uncommon", 0, "Fresno Embers"],
	["Lucian Marchetti", "SG", "SF", "sharpshooter", "uncommon", 1, "Wichita Gale"],
	["Bram Lindqvist", "SG", "SF", "three_and_d", "rare", 0, "Mobile Tempest"],
	["Zaire Colburn", "SG", "PG", "slasher", "rare", 1, "Provo Summit"],
	["Silas Ravenscroft", "SG", "SF", "sharpshooter", "epic", 0, "Laredo Outlaws"],
	["Kofi Adebanjo", "SG", "SF", "slasher", "epic", 1, "Reno Cinders"],
	["Hollis Granger", "SF", "SG", "two_way_wing", "common", 0, "Akron Foundry"],
	["Piers Calloway", "SF", "PF", "wing_scorer", "common", 1, "Boise Ironclads"],
	["Tomas Eriksen", "SF", "PF", "three_and_d", "uncommon", 0, "Savannah Mariners"],
	["Amari Fontaine", "SF", "SG", "wing_scorer", "uncommon", 1, "Tucson Mirage"],
	["Gideon Wrenfield", "SF", "PF", "two_way_wing", "rare", 0, "Spokane Rapids"],
	["Luca Santovena", "SF", "SG", "wing_scorer", "rare", 1, "Fresno Embers"],
	["Remy Delacourt", "SF", "PF", "point_forward", "epic", 0, "Wichita Gale"],
	["Anders Kjell", "SF", "PF", "two_way_wing", "legendary", 0, "Omaha Stampede"],
	["Boone Harlan", "PF", "C", "bruiser", "common", 0, "Mobile Tempest"],
	["Quentin Ashdown", "PF", "SF", "stretch_four", "common", 1, "Provo Summit"],
	["Otis Pemberton", "PF", "C", "athletic_four", "uncommon", 0, "Laredo Outlaws"],
	["Viktor Haldane", "PF", "SF", "stretch_four", "uncommon", 1, "Tulsa Wildfire"],
	["Emeka Durand", "PF", "C", "bruiser", "rare", 0, "Akron Foundry"],
	["Joaquin Mireles", "PF", "SF", "athletic_four", "rare", 1, "Duluth Frost"],
	["Magnus Ferrow", "PF", "C", "stretch_four", "epic", 0, "Boise Ironclads"],
	["Thaddeus Lane", "PF", "C", "athletic_four", "epic", 1, "Savannah Mariners"],
	["Dmitri Kalloway", "C", "PF", "glass_cleaner", "common", 0, "Reno Cinders"],
	["Wendell Oakes", "C", "", "post_scorer", "common", 1, "Spokane Rapids"],
	["Barnaby Stroud", "C", "PF", "rim_protector", "uncommon", 0, "Tucson Mirage"],
	["Ibrahim Soltani", "C", "", "post_scorer", "uncommon", 1, "Fresno Embers"],
	["Felix Aranguren", "C", "PF", "stretch_big", "rare", 0, "Wichita Gale"],
	["Marcellus Tindall", "C", "", "rim_protector", "rare", 1, "Mobile Tempest"],
	["Soren Valdis", "C", "PF", "stretch_big", "epic", 0, "Provo Summit"],
	["Augustin Delmar", "C", "PF", "rim_protector", "legendary", 0, "Laredo Outlaws"],
]

## Extra editions of existing players: [player name, edition name, rarity, boost on the style's six main attributes]
const EDITIONS := [
	["Dominic Strand", "Lockdown Edition", "epic", 9],
	["Bram Lindqvist", "Corner Edition", "epic", 9],
	["Emeka Durand", "Enforcer Edition", "epic", 9],
	["Felix Aranguren", "Pace-and-Space Edition", "epic", 9],
	["Jericho Hale", "Anniversary Edition", "legendary", 5],
	["Augustin Delmar", "Anniversary Edition", "legendary", 5],
]

## The fifteen cards of the starter collection (every position has at least three; the lineup can be filled on day one).
const STARTER_PLAYERS := ["Ian Marlowe", "Teodor Brask", "Kellan Drummond", "Cyrus Tallwood", "Nico Brandvold", "Evander Pike",
	"Hollis Granger", "Piers Calloway", "Tomas Eriksen", "Boone Harlan", "Quentin Ashdown", "Otis Pemberton",
	"Dmitri Kalloway", "Wendell Oakes", "Barnaby Stroud"]

## Market prices in credits for the players below the epic tier (epic and legendary cards come only from packs and rewards).
const MARKET_PRICE := {"common": 500, "uncommon": 1200, "rare": 3500}

const RIVALS := [
	["Savannah Mariners", "SAV"], ["Duluth Frost", "DUL"], ["Reno Cinders", "REN"], ["Akron Foundry", "AKR"], ["Boise Ironclads", "BOI"],
	["Tucson Mirage", "TUC"], ["Omaha Stampede", "OMA"], ["Tulsa Wildfire", "TUL"], ["Spokane Rapids", "SPO"], ["Fresno Embers", "FRE"],
	["Wichita Gale", "WIC"], ["Mobile Tempest", "MOB"], ["Provo Summit", "PRO"], ["Laredo Outlaws", "LAR"]]


static func slug(name: String) -> String:
	return name.to_lower().replace(" ", "_").replace("-", "_")


static func card_id(player_name: String, edition: String = "") -> String:
	return "%s_%s" % [slug(player_name), "base" if edition == "" else slug(edition).trim_suffix("_edition")]


static func attributes_for(index: int, style: String, rarity: String, adjust: int, keys: Array) -> Dictionary:
	var rng := FcRng.new(9000 + index)
	var base: int = int(TIER_LEVEL[rarity]) + adjust - 8
	var shape: Dictionary = ARCHETYPES[style]
	var out := {}
	for k in keys:
		out[k] = clampi(base + int(shape.get(k, 0)) + rng.range_int(-3, 3), 20, 99)
	return out


static func player_definition(index: int, keys: Array) -> Dictionary:
	var p: Array = PLAYERS[index]
	var style := str(p[3])
	var extras: Dictionary = STYLE_EXTRAS[style]
	var d := {
		"player_id": slug(str(p[0])), "display_name": p[0], "position": p[1],
		"attributes": attributes_for(index, style, str(p[4]), int(p[5]), keys),
		"tendencies": extras["tendencies"], "team": p[6],
	}
	if str(p[2]) != "":
		d["secondary_position"] = p[2]
	if not (extras["badges"] as Array).is_empty():
		d["badges"] = extras["badges"]
	return d


static func _index_of(player_name: String) -> int:
	for i in PLAYERS.size():
		if PLAYERS[i][0] == player_name:
			return i
	return -1


## Writes every definition of the release into a draft through `save` (a Callable (relative path, data) -> void).
static func write_all(save: Callable, keys: Array) -> void:
	var all_cards: Array = []
	var base_cards: Array = []
	var pool_by_tier := {}
	for i in PLAYERS.size():
		var p: Array = PLAYERS[i]
		var pdef := player_definition(i, keys)
		save.call("players/%s.json" % pdef["player_id"], pdef)
		var cid := card_id(str(p[0]))
		var card := {"card_id": cid, "player_id": pdef["player_id"], "title": p[0], "edition": "Founding Edition", "rarity": p[4],
			"revision": 1, "requires_features": ["card_rarity_v1"]}
		if MARKET_PRICE.has(str(p[4])):
			card["price"] = {"currency": "credits", "amount": MARKET_PRICE[p[4]]}
			card["requires_features"] = ["card_rarity_v1", "card_market_v1"]
		save.call("cards/%s.json" % cid, card)
		all_cards.append(cid)
		base_cards.append(cid)
	for e in EDITIONS:
		var idx := _index_of(str(e[0]))
		var p2: Array = PLAYERS[idx]
		var shape: Dictionary = ARCHETYPES[str(p2[3])]
		var top: Array = shape.keys().filter(func(k: String) -> bool: return int(shape[k]) > 0)
		top.sort_custom(func(a: String, b: String) -> bool: return int(shape[a]) > int(shape[b]))
		var base_attrs: Dictionary = player_definition(idx, keys)["attributes"]
		var over := {}
		for k in top.slice(0, 6):
			over[k] = clampi(int(base_attrs[k]) + int(e[3]), 20, 99)
		var cid := card_id(str(e[0]), str(e[1]))
		save.call("cards/%s.json" % cid, {"card_id": cid, "player_id": slug(str(e[0])), "title": e[0], "edition": e[1], "rarity": e[2],
			"revision": 1, "attributes": over, "requires_features": ["card_rarity_v1", "card_overrides_v1"]})
		all_cards.append(cid)
	var starter_ids: Array = []
	for n in STARTER_PLAYERS:
		starter_ids.append(card_id(n))
	var commons_uncommons: Array = []
	for i in PLAYERS.size():
		if PLAYERS[i][4] in ["common", "uncommon"]:
			commons_uncommons.append(card_id(str(PLAYERS[i][0])))
	save.call("packs/starter_pack.json", {"pack_id": "starter_pack", "name": "Founding Starter Collection", "card_ids": starter_ids,
		"requires_features": ["pack_fixed_v1"]})
	save.call("packs/rookie_pack.json", {"pack_id": "rookie_pack", "name": "Rookie Pack", "price": {"currency": "credits", "amount": 500},
		"cards_per_pack": 3, "odds": {"common": 6500, "uncommon": 2800, "rare": 600, "epic": 90, "legendary": 10},
		"guarantees": [{"min_rarity": "uncommon", "count": 1}], "card_ids": all_cards, "requires_features": ["pack_odds_v1"]})
	save.call("packs/pro_pack.json", {"pack_id": "pro_pack", "name": "Pro Pack", "price": {"currency": "credits", "amount": 1800},
		"cards_per_pack": 4, "odds": {"common": 3500, "uncommon": 4000, "rare": 2000, "epic": 450, "legendary": 50},
		"guarantees": [{"min_rarity": "rare", "count": 1}], "card_ids": all_cards, "requires_features": ["pack_odds_v1"]})
	save.call("packs/elite_pack.json", {"pack_id": "elite_pack", "name": "Elite Pack", "price": {"currency": "tokens", "amount": 8},
		"cards_per_pack": 5, "odds": {"common": 0, "uncommon": 2500, "rare": 5000, "epic": 2000, "legendary": 500},
		"guarantees": [{"min_rarity": "rare", "count": 2}], "pity": {"rarity": "epic", "after": 5},
		"card_ids": all_cards, "requires_features": ["pack_odds_v1"]})
	save.call("packs/reward_pack.json", {"pack_id": "reward_pack", "name": "Reward Pack", "price": {"currency": "credits", "amount": 0},
		"cards_per_pack": 2, "odds": {"common": 7000, "uncommon": 3000}, "card_ids": commons_uncommons, "requires_features": ["pack_odds_v1"]})
	var challenges := [
		["century_mark", "Century Mark", "scoring", "Score 100 points or more in one game.", {"type": "stat", "stat": "points", "scope": "team", "mode": "single_game", "target": 100}, {"credits": 300}, {}],
		["downtown", "Downtown", "shooting", "Make 10 three-pointers in one game.", {"type": "stat", "stat": "threes", "scope": "team", "mode": "single_game", "target": 10}, {"credits": 350}, {}],
		["at_the_line", "At the Line", "shooting", "Make 30 free throws across your games.", {"type": "stat", "stat": "free_throws", "scope": "team", "mode": "cumulative", "target": 30}, {"credits": 300}, {}],
		["sharing_the_ball", "Sharing the Ball", "playmaking", "Record 40 assists across your games.", {"type": "stat", "stat": "assists", "scope": "team", "mode": "cumulative", "target": 40}, {"credits": 400, "tokens": 1}, {}],
		["lockdown", "Lockdown", "defense", "Record 10 steals across your games.", {"type": "stat", "stat": "steals", "scope": "team", "mode": "cumulative", "target": 10}, {"credits": 300}, {}],
		["the_wall", "The Wall", "defense", "Record 8 blocks across your games.", {"type": "stat", "stat": "blocks", "scope": "team", "mode": "cumulative", "target": 8}, {"credits": 350}, {}],
		["glass_eaters", "Glass Eater", "rebounding", "Have one player grab 12 rebounds in a game.", {"type": "stat", "stat": "rebounds", "scope": "player", "mode": "single_game", "target": 12}, {"credits": 400}, {}],
		["first_wins", "First Wins", "team_composition", "Win 3 games.", {"type": "wins", "target": 3}, {"pack_ids": ["reward_pack"]}, {}],
		["ten_wins", "Ten Wins", "team_composition", "Win 10 games.", {"type": "wins", "target": 10}, {"credits": 600, "pack_ids": ["rookie_pack"]}, {}],
		["statement_win", "Statement Win", "team_composition", "Win a game by 15 points or more.", {"type": "win_margin", "target": 15}, {"credits": 500}, {}],
		["underdogs", "Underdogs", "team_composition", "Win 3 games with no card above rare.", {"type": "wins", "target": 3}, {"tokens": 2}, {"max_rarity": "rare"}],
		["collector", "Collector", "collection", "Collect 25 different cards.", {"type": "collection", "metric": "unique_cards", "target": 25}, {"tokens": 2}, {}],
		["rare_finds", "Rare Finds", "collection", "Own 5 rare cards.", {"type": "collection", "metric": "rarity_cards", "rarity": "rare", "target": 5}, {"pack_ids": ["pro_pack"]}, {}],
		["duplicates_pay", "Spare Parts", "collection", "Hold 5 duplicate cards.", {"type": "collection", "metric": "duplicates", "target": 5}, {"shards": 50}, {}],
	]
	var challenge_ids: Array = []
	for c in challenges:
		var data := {"challenge_id": c[0], "title": c[1], "description": c[3], "category": c[2], "objective": c[4], "rewards": c[5],
			"season_points": 10, "requires_features": ["challenge_v1"]}
		if not (c[6] as Dictionary).is_empty():
			data["restrictions"] = c[6]
		save.call("challenges/%s.json" % c[0], data)
		challenge_ids.append(c[0])
	save.call("seasonal/founding_season.json", {
		"season_id": "founding_season", "name": "Founding Season", "active": true,
		"description": "The first season of Full Court Dynasty: play games, finish challenges and win both tournaments.",
		"challenge_ids": challenge_ids,
		"milestones": [
			{"id": "tip_off", "name": "Tip-off", "points": 20, "rewards": {"credits": 300}},
			{"id": "rolling", "name": "Rolling", "points": 50, "rewards": {"tokens": 3}},
			{"id": "contender", "name": "Contender", "points": 90, "rewards": {"pack_ids": ["pro_pack"]}},
			{"id": "champion_run", "name": "Champion Run", "points": 140, "rewards": {"pack_ids": ["elite_pack"], "credits": 1000}}],
		"objectives": [
			{"id": "wins_5", "title": "Win 5 games", "points": 15, "objective": {"type": "wins", "target": 5}},
			{"id": "wins_20", "title": "Win 20 games", "points": 30, "objective": {"type": "wins", "target": 20}}],
		"tournaments": [
			{"tournament_id": "founders_cup", "name": "Founders Cup", "entry_fee": {"currency": "credits", "amount": 200},
				"teams": _rival_teams(0, 52, 3), "rewards": {"champion": {"credits": 2500, "tokens": 5}, "finalist": {"credits": 1200},
					"semifinal": {"credits": 600}, "quarterfinal": {"credits": 250}}},
			{"tournament_id": "pro_invitational", "name": "Pro Invitational", "entry_fee": {"currency": "tokens", "amount": 2},
				"teams": _rival_teams(7, 64, 3), "rewards": {"champion": {"tokens": 12, "pack_ids": ["elite_pack"]}, "finalist": {"tokens": 6},
					"semifinal": {"tokens": 3}, "quarterfinal": {"credits": 800}}}],
		"requires_features": ["season_v1"]})
	save.call("support/dynasty_config.json", {"support_id": "dynasty_config", "starter_pack_id": "starter_pack",
		"starter_credits": 2000, "starter_tokens": 5, "requires_features": ["dynasty_config_v1"]})


static func _rival_teams(offset: int, first_rating: int, step: int) -> Array:
	var out: Array = []
	for t in 7:
		var r: Array = RIVALS[offset + t]
		out.append({"name": r[0], "abbreviation": r[1], "rating": first_rating + t * step})
	return out
