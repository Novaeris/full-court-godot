class_name FcDynastyCatalog
extends RefCounted
## Dynasty's read-only window onto the loaded content release: every card as a "view" (a plain Dictionary with the
## player's name, edition, position, rating, attributes, badges, artwork and price), plus packs, challenges, seasons
## and the economy config. Services and screens ask this; they never open content files or keep their own card data.
##
## Card overall is the simulation's own rating (FcPlayerRatings.overall of the card's attributes), rounded for display.

const MIN_PLAYABLE_CARDS := FcDynastyContentRules.MIN_PLAYABLE_PLAYERS

var content: FcContentCatalog
var defs: FcDefinitionSet
var ratings: FcPlayerRatings
var config: FcDynastyConfig
var _views: Dictionary = {}
## The time source for timed sets (whole unix seconds). Offline play uses the device clock; the online server passes its own time to the
## services instead (D-067). Tests replace it.
var clock: Callable = func() -> int: return int(Time.get_unix_time_from_system())
var _card_set: Dictionary = {}   # card_id -> set_id
var _pack_set: Dictionary = {}   # pack_id -> set_id


static func build(content_catalog: FcContentCatalog, definitions: FcDefinitionSet, rating_calculator: FcPlayerRatings = null) -> FcDynastyCatalog:
	var c := FcDynastyCatalog.new()
	c.content = content_catalog
	c.defs = definitions
	c.ratings = rating_calculator if rating_calculator != null else FcPlayerRatings.load_default()
	c.config = FcDynastyConfig.build(content_catalog.support.get("dynasty_config", {}) if content_catalog != null else {})
	if content_catalog != null:
		for id in content_catalog.cards:
			c._views[id] = c._make_view(str(id))
		for sid in content_catalog.sets:
			for cid in content_catalog.sets[sid].get("card_ids", []):
				c._card_set[str(cid)] = str(sid)
			for pid in content_catalog.sets[sid].get("pack_ids", []):
				c._pack_set[str(pid)] = str(sid)
	return c


func release_id() -> String:
	return content.release_id if content != null else ""


func has_card(card_id: String) -> bool:
	return _views.has(card_id)


## Every card id in the release, sorted.
func card_ids() -> Array[String]:
	var out: Array[String] = []
	for id in _views:
		out.append(str(id))
	out.sort()
	return out


## The view of a card in the release ({} if it is not in it).
func view(card_id: String) -> Dictionary:
	return _views.get(card_id, {})


## A view for ANY card an owner may hold: the live release definition when there is one, otherwise a placeholder built from
## the snapshot kept when the card was first obtained (marked `available: false`, never usable in a lineup).
func owned_view(card_id: String, record: Dictionary) -> Dictionary:
	if _views.has(card_id):
		var v: Dictionary = _views[card_id].duplicate()
		v["revision_changed"] = int(record.get("revision", v["revision"])) != int(v["revision"])
		return v
	var s: Dictionary = record.get("snapshot", {})
	return {
		"card_id": card_id, "available": false, "player_id": "", "name": str(s.get("player_name", card_id)),
		"title": str(s.get("title", card_id)), "edition": str(s.get("edition", "")), "rarity": str(s.get("rarity", "common")),
		"position": str(s.get("position", "")), "position_id": 0, "secondary": "", "secondary_id": 0,
		"overall": int(s.get("overall", 0)), "attributes": {}, "tendencies": {}, "badges": [], "team": "",
		"art_path": "", "price": {}, "acquirable": false, "revision": int(record.get("revision", 1)), "revision_changed": false,
	}


## What to remember about a card when it is first owned.
func snapshot_of(card_id: String) -> Dictionary:
	var v := view(card_id)
	return {"title": v.get("title", card_id), "player_name": v.get("name", card_id), "rarity": v.get("rarity", "common"),
		"position": v.get("position", ""), "overall": v.get("overall", 0), "edition": v.get("edition", "")}


func overall_of(card_id: String) -> int:
	return int(view(card_id).get("overall", 0))


func packs() -> Dictionary:
	return content.packs if content != null else {}


## The current time in whole seconds (the injectable clock).
func now() -> int:
	return int(clock.call())


## Every published set, {set_id: definition}.
func sets() -> Dictionary:
	return content.sets if content != null else {}


## The set a card belongs to ("" when it is in none, which means always available).
func set_of_card(card_id: String) -> String:
	return str(_card_set.get(card_id, ""))


## The set that sells a pack ("" when none).
func set_of_pack(pack_id: String) -> String:
	return str(_pack_set.get(pack_id, ""))


## The status (always | upcoming | active | ended) of a set at `at` (default: now).
func set_status(set_id: String, at: int = -1) -> String:
	return FcContentWindow.status(sets().get(set_id, {}), now() if at < 0 else at)


## Whether a pack may be bought at `at` (default: now): its set, if any, must be open. Owned cards never depend on this.
func pack_available(pack_id: String, at: int = -1) -> bool:
	var sid := set_of_pack(pack_id)
	return sid == "" or FcContentWindow.is_open(sets().get(sid, {}), now() if at < 0 else at)


## Whether a card may be bought directly at `at` (default: now): its set, if any, must be open.
func card_available(card_id: String, at: int = -1) -> bool:
	var sid := set_of_card(card_id)
	return sid == "" or FcContentWindow.is_open(sets().get(sid, {}), now() if at < 0 else at)


## Packs a player can buy: those with a published price whose set is open.
func buyable_packs(at: int = -1) -> Array[String]:
	var out: Array[String] = []
	for id in packs():
		if packs()[id].has("price") and pack_available(str(id), at):
			out.append(str(id))
	out.sort()
	return out


## Cards with a published price that may be bought directly (their set is open).
func market_card_ids(at: int = -1) -> Array[String]:
	var out: Array[String] = []
	for id in _views:
		if bool(_views[id]["acquirable"]) and card_available(str(id), at):
			out.append(str(id))
	out.sort()
	return out


func challenges() -> Dictionary:
	return content.challenges if content != null else {}


func seasons() -> Dictionary:
	return content.seasonal if content != null else {}


## The season the release marks `"active": true` (the first by id), else the first season, else "".
func active_season_id() -> String:
	var ids: Array = seasons().keys()
	ids.sort()
	for id in ids:
		if bool(seasons()[id].get("active", false)):
			return str(id)
	return str(ids[0]) if not ids.is_empty() else ""


func season(season_id: String) -> Dictionary:
	return seasons().get(season_id, {})


## Number of different players behind the release's cards (a roster needs 13 different players).
func distinct_players() -> int:
	var seen := {}
	for id in _views:
		seen[_views[id]["player_id"]] = true
	return seen.size()


## Whether the release has enough cards to field a team and opponents (see onboarding in the hub).
func is_playable() -> bool:
	return _views.size() >= MIN_PLAYABLE_CARDS and distinct_players() >= MIN_PLAYABLE_CARDS and lineup_problem() == ""


## The shared rule (FcDynastyContentRules.lineup_problem) applied to this release's players: "" when it can field a legal team.
func lineup_problem() -> String:
	var players: Array = []
	var seen := {}
	for id in _views:
		var v: Dictionary = _views[id]
		if not seen.has(v["player_id"]):
			seen[v["player_id"]] = true
			players.append({"player_id": v["player_id"], "position": v.get("position", ""), "secondary": v.get("secondary", "")})
	return FcDynastyContentRules.lineup_problem(players)


## Why the release is not playable, or "" if it is.
func playable_problem() -> String:
	if content == null:
		return "No content release is loaded."
	if _views.is_empty():
		return "The loaded content release has no player cards yet. Publish cards from Creator Studio to start."
	if _views.size() < MIN_PLAYABLE_CARDS or distinct_players() < MIN_PLAYABLE_CARDS:
		return "The loaded content release has %d cards from %d players; Dynasty needs at least %d different players to field a team." % [_views.size(), distinct_players(), MIN_PLAYABLE_CARDS]
	return lineup_problem()


# --- building players for the simulation ----------------------------------------------------------------------

## A simulation FcPlayer for a card (attributes and tendencies exactly as published; unlisted ones use the catalog default).
func make_player(card_id: String, player_id: int) -> FcPlayer:
	var v := view(card_id)
	var p := FcPlayer.new(player_id, defs)
	var name_parts := str(v.get("name", card_id)).split(" ", false, 1)
	p.identity.first_name = name_parts[0] if name_parts.size() > 0 else card_id
	p.identity.last_name = name_parts[1] if name_parts.size() > 1 else "-"
	p.identity.country = "Fiction"
	p.primary_position = int(v.get("position_id", FcPosition.Id.SF))
	p.secondary_position = int(v.get("secondary_id", FcPosition.Id.NONE))
	for key in v.get("attributes", {}):
		p.attributes.set_clamped(str(key), int(v["attributes"][key]))
	for key in v.get("tendencies", {}):
		p.tendencies.set_clamped(str(key), int(v["tendencies"][key]))
	return p


## The composite rating bonus a card's badges give in games (Career rules: small and capped).
func composite_bonus(card_id: String) -> Dictionary:
	return FcCareerRules.composite_bonus(view(card_id).get("badges", []))


func _make_view(card_id: String) -> Dictionary:
	var card: Dictionary = content.get_card(card_id)
	var pdef: Dictionary = content.player_for_card(card_id)
	var position_id := _position_id(str(pdef.get("position", "SF")))
	var secondary := str(pdef.get("secondary_position", ""))
	var price: Dictionary = card.get("price", {}) if card.get("price") is Dictionary else {}
	var view := {
		"card_id": card_id, "available": true, "player_id": str(card.get("player_id", "")),
		"name": str(pdef.get("display_name", card_id)), "title": str(card.get("title", card_id)),
		"edition": str(card.get("edition", card.get("title", ""))), "rarity": str(card.get("rarity", "common")),
		"position": FcPosition.abbreviation(position_id), "position_id": position_id,
		"secondary": secondary, "secondary_id": _position_id(secondary) if secondary != "" else FcPosition.Id.NONE,
		"badges": (card["badges"] if card.get("badges") is Array else (pdef["badges"] if pdef.get("badges") is Array else [])).duplicate(),
		"team": str(pdef.get("team", "")), "art_path": content.art_path(card_id),
		"price": price, "acquirable": not price.is_empty() and bool(card.get("acquirable", true)),
		"revision": int(card.get("revision", 1)), "revision_changed": false,
		"tendencies": {}, "attributes": {}, "overall": 0,
	}
	var player := FcPlayer.new(1, defs)
	# the player's published ratings, then this edition's own on top
	for source in [pdef, card]:
		for key in source.get("attributes", {}):
			player.attributes.set_clamped(str(key), int(source["attributes"][key]))
		for key in source.get("tendencies", {}):
			player.tendencies.set_clamped(str(key), int(source["tendencies"][key]))
	for key in defs.attributes.keys():
		view["attributes"][key] = player.attributes.get_value(str(key))
	for key in defs.tendencies.keys():
		view["tendencies"][key] = player.tendencies.get_value(str(key))
	view["overall"] = roundi(ratings.overall(player))
	return view


static func _position_id(abbr: String) -> int:
	for id in FcPosition.ABBREVIATIONS:
		if FcPosition.ABBREVIATIONS[id] == abbr and int(id) != 0:
			return int(id)
	return FcPosition.Id.SF
