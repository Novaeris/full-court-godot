class_name FcDynastyConfig
extends RefCounted
## Economy and rule numbers for Dynasty Mode: the defaults in data/dynasty/economy.json, overridden key by key by the
## loaded release's support definition "dynasty_config". Nothing in a screen or service hardcodes these.

const DEFAULT_PATH := "res://data/dynasty/economy.json"
const CURRENCIES := ["credits", "tokens", "shards"]
const NON_CONFIG_KEYS := ["support_id", "requires_features", "name", "display_name", "title"]

var values: Dictionary = {}


static func load_defaults() -> Dictionary:
	var file := FileAccess.open(DEFAULT_PATH, FileAccess.READ)
	var parsed = FcChecks.parse_json(file.get_as_text()) if file != null else null
	return parsed if parsed is Dictionary else {}


## `override` is the release's dynasty_config definition ({} when it has none).
static func build(override: Dictionary = {}) -> FcDynastyConfig:
	var c := FcDynastyConfig.new()
	c.values = load_defaults()
	for key in override:
		if not NON_CONFIG_KEYS.has(key):
			c.values[key] = override[key]
	return c


func get_int(path: Array, fallback: int = 0) -> int:
	var v = _dig(path)
	return int(v) if v is int or v is float else fallback


func get_value(path: Array, fallback = null):
	var v = _dig(path)
	return v if v != null else fallback


func _dig(path: Array):
	var cur = values
	for key in path:
		if cur is Dictionary and cur.has(key):
			cur = cur[key]
		elif cur is Array and int(key) >= 0 and int(key) < cur.size():
			cur = cur[int(key)]
		else:
			return null
	return cur


func shards_for(rarity: String) -> int:
	return get_int(["shards_per_duplicate", rarity], 0)


func game_reward(won: bool) -> int:
	return get_int(["game_reward", "win" if won else "loss"], 0)


func mastery_max() -> int:
	return get_int(["mastery", "max_level"], 0)


## Shards needed to raise a card from `level` to `level + 1` (0-based level).
func mastery_cost(level: int) -> int:
	return get_int(["mastery", "shard_cost", level], 0)


func mastery_frame(level: int) -> String:
	return str(get_value(["mastery", "frames", level], "none"))


func opponent_levels() -> Array:
	return get_value(["opponent_offsets"], [])


func team_weights() -> Array:
	return get_value(["team_overall_weights"], [])


func starter_pack_id() -> String:
	return str(get_value(["starter_pack_id"], ""))
