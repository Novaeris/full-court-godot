class_name FcRevealSpec
extends RefCounted
## The pack-opening presentation numbers, per rarity, read from data/ui/reveal_effects.json (so a designer rebalances a reveal without
## touching code, and a rarity published later by a content release still reveals: unknown ids use the common spec).
## PRESENTATION ONLY: nothing here is read by the pack-opening rules, the odds, the economy or the saved opening record.

const PATH := "res://data/ui/reveal_effects.json"
const FALLBACK_RARITY := {"flip": 0.3, "tease": 0.0, "dim": 0.0, "glow": 0.0, "sweep": false, "particles": 0, "flash": 0.0, "shake": 0.0, "rays": 0, "shockwave": false, "banner": false, "name_plate": false, "hold": 0.0, "haptic": 0, "swell": false, "hit": false}
const FALLBACK_CAPS := {"particles": 160, "flashes_per_second": 3, "rays_at_once": 2, "banners_at_once": 1}
const FALLBACK_STAGES := {"present_pulse": 1.6, "tear": 0.5, "emerge": 0.55, "emerge_stagger": 0.07, "spotlight_in": 0.22, "settle": 0.3}
const FALLBACK_AUDIO := {"swell": "reveal_swell", "hit": "reveal_hit", "min_gap_after_big": 0.9}

static var _cache: Dictionary = {}


static func _data() -> Dictionary:
	if _cache.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
		_cache = parsed if parsed is Dictionary else {"rarities": {"common": FALLBACK_RARITY}}
	return _cache


## The spec of a rarity: every key present (missing ones come from the common fallback), an unknown rarity gets the common spec.
static func of(rarity: String) -> Dictionary:
	var rarities: Dictionary = _data().get("rarities", {})
	var out := FALLBACK_RARITY.duplicate()
	out.merge(rarities.get(rarity, rarities.get("common", {})), true)
	return out


static func caps() -> Dictionary:
	var out := FALLBACK_CAPS.duplicate()
	out.merge(_data().get("caps", {}), true)
	return out


static func stages() -> Dictionary:
	var out := FALLBACK_STAGES.duplicate()
	out.merge(_data().get("stages", {}), true)
	return out


static func audio() -> Dictionary:
	var out := FALLBACK_AUDIO.duplicate()
	out.merge(_data().get("audio", {}), true)
	return out


## The rarity ids the file describes (tests check each one against FcRarityStyle).
static func rarity_ids() -> Array:
	return _data().get("rarities", {}).keys()
