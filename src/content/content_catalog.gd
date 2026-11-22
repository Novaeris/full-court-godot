class_name FcContentCatalog
extends RefCounted
## The verified definitions of one loaded content release, ready for Dynasty to use.
##
## Everything is keyed by stable content ids. Saves keep only those ids (never copies of the
## definitions), so what a card or player IS always comes from the release that is loaded.

var release_id: String = ""
var content_version: int = 0
var release_dir: String = ""
## {id: Dictionary} per kind.
var players: Dictionary = {}
var cards: Dictionary = {}
var packs: Dictionary = {}
var challenges: Dictionary = {}
var seasonal: Dictionary = {}
var sets: Dictionary = {}
var support: Dictionary = {}


static func build(manifest: FcContentManifest, directory: String, defs: Dictionary) -> FcContentCatalog:
	var c := FcContentCatalog.new()
	c.release_id = manifest.release_id
	c.content_version = manifest.content_version
	c.release_dir = directory
	c.players = defs["player"]
	c.cards = defs["card"]
	c.packs = defs["pack"]
	c.challenges = defs["challenge"]
	c.seasonal = defs["seasonal"]
	c.sets = defs.get("set", {})
	c.support = defs["support"]
	return c


func has_card(card_id: String) -> bool:
	return cards.has(card_id)


func get_card(card_id: String) -> Dictionary:
	return cards.get(card_id, {})


func get_player(player_id: String) -> Dictionary:
	return players.get(player_id, {})


## The underlying player of a card ({} if the card is unknown).
func player_for_card(card_id: String) -> Dictionary:
	return get_player(str(get_card(card_id).get("player_id", "")))


## Full path of a card's artwork inside the release, or "" when it has none.
func art_path(card_id: String) -> String:
	var art := str(get_card(card_id).get("art", ""))
	if art.is_empty() or not FcSafeFile.is_safe_relative_path(art):
		return ""
	return release_dir.path_join(art)


## Splits ids a collection owns into cards this release defines and cards it does not
## (kept, shown as unavailable, and back again with a later release or a rollback).
func ownership_view(owned_card_ids: Array) -> Dictionary:
	var available: Array[String] = []
	var unavailable: Array[String] = []
	for id in owned_card_ids:
		if cards.has(str(id)):
			available.append(str(id))
		else:
			unavailable.append(str(id))
	return {"available": available, "unavailable": unavailable}
