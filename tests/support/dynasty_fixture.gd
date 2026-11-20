class_name FcDynastyFixture
extends RefCounted
## TEST FIXTURE ONLY (not official content): a fully invented Dynasty release (30 players with names like "Test Alpha",
## several editions, packs, challenges, a season with an eight-team tournament, an economy config) built through the
## same release format the game loads. Official players come only from Creator Studio.

const ROOT := "user://test_dynasty_content"
const POSITIONS := ["PG", "SG", "SF", "PF", "C"]
const NAMES := ["Alpha", "Bravo", "Cobalt", "Delta", "Ember", "Flint", "Gale", "Harbor", "Iron", "Jade",
	"Kilo", "Lumen", "Mason", "Nova", "Onyx", "Pike", "Quill", "Ridge", "Slate", "Tide",
	"Umber", "Vale", "Wren", "Xenon", "Yarrow", "Zephyr", "Birch", "Coral", "Dune", "Echo"]
const PLAYER_COUNT := 30


static func base_of(i: int) -> int:
	return 50 + (i * 13) / 10


static func rarity_of(base: int) -> String:
	if base < 60:
		return "common"
	if base < 70:
		return "uncommon"
	if base < 78:
		return "rare"
	if base < 84:
		return "epic"
	return "legendary"


static func player_id(i: int) -> String:
	return "test_%s" % NAMES[i].to_lower()


static func card_id(i: int, edition: String = "base") -> String:
	return "%s_%s" % [player_id(i), edition]


static func _json(dir: String, rel: String, data: Dictionary) -> void:
	FcSafeFile.write_text(dir.path_join(rel), JSON.stringify(data, "\t", true))


## Writes the invented release's definition files. `variant` changes one thing so two releases differ.
## `layout` (optional) replaces the players' positions: layout[i] = [primary, secondary or ""] for player i (players beyond it keep the default).
static func write_content(dir: String, variant: int = 0, layout: Array = []) -> void:
	var defs := FcDefinitionSet.load_default()
	var keys := defs.attributes.keys()
	for i in PLAYER_COUNT:
		var attrs := {}
		for k in keys:
			attrs[k] = base_of(i)
		var pdef := {
			"player_id": player_id(i), "display_name": "Test %s" % NAMES[i], "position": POSITIONS[i % 5],
			"attributes": attrs, "team": "Test Squad %d" % (i % 3),
		}
		if i % 4 == 0:
			pdef["secondary_position"] = POSITIONS[(i + 1) % 5]
		if i < layout.size():
			pdef["position"] = layout[i][0]
			pdef.erase("secondary_position")
			if str(layout[i][1]) != "":
				pdef["secondary_position"] = layout[i][1]
		if i % 5 == 0:
			pdef["badges"] = ["catch_and_shoot"]
		_json(dir, "players/%s.json" % player_id(i), pdef)
		var card := {"card_id": card_id(i), "player_id": player_id(i), "title": "Test %s" % NAMES[i], "edition": "Base Edition",
			"rarity": rarity_of(base_of(i)), "revision": 1, "requires_features": ["card_rarity_v1"]}
		if i >= 15:
			card["price"] = {"currency": "credits", "amount": 100 * (i - 10)}
			card["requires_features"] = ["card_rarity_v1", "card_market_v1"]
		_json(dir, "cards/%s.json" % card_id(i), card)
	# a second, stronger edition of players 3 and 8 (a different card for the same player)
	for i in [3, 8]:
		var attrs2 := {}
		for k in keys:
			attrs2[k] = base_of(i) + 20
		_json(dir, "cards/%s.json" % card_id(i, "allstar"), {
			"card_id": card_id(i, "allstar"), "player_id": player_id(i), "title": "Test %s" % NAMES[i], "edition": "All-Star Edition",
			"rarity": "epic", "revision": 1, "attributes": attrs2, "requires_features": ["card_rarity_v1", "card_overrides_v1"]})
	var starter_ids: Array = []
	for i in 15:
		starter_ids.append(card_id(i))
	_json(dir, "packs/starter_pack.json", {"pack_id": "starter_pack", "name": "Starter Pack", "card_ids": starter_ids, "requires_features": ["pack_fixed_v1"]})
	var all_cards: Array = []
	for i in PLAYER_COUNT:
		all_cards.append(card_id(i))
	all_cards.append(card_id(3, "allstar"))
	all_cards.append(card_id(8, "allstar"))
	_json(dir, "packs/bronze_pack.json", {
		"pack_id": "bronze_pack", "name": "Bronze Pack", "price": {"currency": "credits", "amount": 500}, "cards_per_pack": 3,
		"odds": {"common": 6000, "uncommon": 2500, "rare": 1000, "epic": 400, "legendary": 100},
		"guarantees": [{"min_rarity": "uncommon", "count": 1}], "card_ids": all_cards, "requires_features": ["pack_odds_v1"]})
	_json(dir, "packs/elite_pack.json", {
		"pack_id": "elite_pack", "name": "Elite Pack", "price": {"currency": "tokens", "amount": 5}, "cards_per_pack": 5,
		"odds": {"common": 0, "uncommon": 3000, "rare": 4500, "epic": 2000, "legendary": 500},
		"guarantees": [{"min_rarity": "rare", "count": 2}], "pity": {"rarity": "epic", "after": 4},
		"card_ids": all_cards, "requires_features": ["pack_odds_v1"]})
	_json(dir, "packs/free_pack.json", {
		"pack_id": "free_pack", "name": "Reward Pack", "price": {"currency": "credits", "amount": 0}, "cards_per_pack": 2,
		"odds": {"common": 10000}, "card_ids": starter_ids, "requires_features": ["pack_odds_v1"]})
	var cats := [
		["score_100", "scoring", {"type": "stat", "stat": "points", "scope": "team", "mode": "single_game", "target": 100}, {"credits": 300}],
		["triples", "shooting", {"type": "stat", "stat": "threes", "scope": "team", "mode": "single_game", "target": 10}, {"credits": 300}],
		["dimes", "playmaking", {"type": "stat", "stat": "assists", "scope": "team", "mode": "cumulative", "target": 40}, {"credits": 400, "tokens": 1}],
		["locks", "defense", {"type": "stat", "stat": "steals", "scope": "team", "mode": "cumulative", "target": 10}, {"credits": 300}],
		["glass", "rebounding", {"type": "stat", "stat": "rebounds", "scope": "player", "mode": "single_game", "target": 10}, {"credits": 300}],
		["win_three", "team_composition", {"type": "wins", "target": 3}, {"pack_ids": ["free_pack"]}],
		["underdogs", "team_composition", {"type": "wins", "target": 1}, {"credits": 500}],
		["collector", "collection", {"type": "collection", "metric": "unique_cards", "target": 20}, {"tokens": 2}],
	]
	for c in cats:
		var data := {"challenge_id": c[0], "title": "Test %s" % c[0], "description": "A test challenge.", "category": c[1], "objective": c[2],
			"rewards": c[3], "season_points": 10, "requires_features": ["challenge_v1"]}
		if c[0] == "underdogs":
			data["restrictions"] = {"max_rarity": "rare"}
		_json(dir, "challenges/%s.json" % c[0], data)
	var teams: Array = []
	for t in 7:
		teams.append({"name": "Test Rival %d" % (t + 1), "abbreviation": "TR%d" % (t + 1), "rating": 55 + t * 3})
	_json(dir, "seasonal/season_one.json", {
		"season_id": "season_one", "name": "Test Season One", "active": true, "description": "A fixture season.",
		"challenge_ids": ["score_100", "triples", "win_three"],
		"milestones": [
			{"id": "m1", "name": "Warm up", "points": 10, "rewards": {"credits": 200}},
			{"id": "m2", "name": "Rolling", "points": 30, "rewards": {"tokens": 3}}],
		"objectives": [{"id": "wins5", "title": "Win 5 games", "points": 20, "objective": {"type": "wins", "target": 5}}],
		"tournaments": [{"tournament_id": "test_cup", "name": "Test Cup", "entry_fee": {"currency": "credits", "amount": 100},
			"teams": teams, "rewards": {"champion": {"credits": 1000, "tokens": 5}, "finalist": {"credits": 500}, "semifinal": {"credits": 250}, "quarterfinal": {"credits": 100}}}],
		"requires_features": ["season_v1"]})
	_json(dir, "support/dynasty_config.json", {"support_id": "dynasty_config", "starter_pack_id": "starter_pack",
		"starter_credits": 2000 + variant, "starter_tokens": 5, "requires_features": ["dynasty_config_v1"]})


## Builds a sealed release from the fixture and returns an FcDynastyCatalog for it, or null if it did not validate.
## `layout` as in write_content. `validate` false builds the catalog even if the publish validator would reject the release (to prove
## the game side refuses such a release by itself).
static func catalog(variant: int = 0, release_id: String = "fcr_0123456789abcdef", layout: Array = [], validate: bool = true) -> FcDynastyCatalog:
	var draft := ROOT.path_join("draft_%d" % variant)
	var release := ROOT.path_join("release_%d" % variant)
	FcSafeFile.remove_tree(draft)
	FcSafeFile.remove_tree(release)
	write_content(draft, variant, layout)
	var m := FcContentFixture.build_release(draft, release, release_id, "", 1 + variant)
	var defs := FcDefinitionSet.load_default()
	var checked := FcContentValidator.check_definitions(release, _paths(m), defs)
	if validate and not checked["problems"].is_empty():
		push_error("fixture invalid: %s" % str(checked["problems"]))
		return null
	return FcDynastyCatalog.build(FcContentCatalog.build(m, release, checked["defs"]), defs)


static func _paths(m: FcContentManifest) -> Array[String]:
	var out: Array[String] = []
	for e in m.files:
		out.append(e["path"])
	return out


static func wipe() -> void:
	FcSafeFile.remove_tree(ROOT)
