class_name FcBroadcastStyle
extends RefCounted
## The broadcast identity kit (Broadcast pass 2, M2): one place that says how long each graphic takes to come in, stay and leave, which
## transitions exist, which graphic kinds get the gold edge and which get a player spotlight. Data lives in data/ui/broadcast_identity.json;
## colours and type sizes stay in FcUiTokens. Reduced motion (FcUiMotion.reduced) swaps to the `reduced_timings_ms` set so nothing slides.
## Pure and cached: reading it changes nothing.

const PATH := "res://data/ui/broadcast_identity.json"
const REQUIRED_TIMINGS := ["lower_third", "spotlight", "stats_overlay", "camera_ease", "camera_whip"]

static var _data: Dictionary = {}


## The parsed file ({} when missing or damaged; every accessor then falls back to safe defaults, so a broken file never breaks a replay).
static func data() -> Dictionary:
	if _data.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_data = parsed if parsed is Dictionary else {}
	return _data


## {in, hold, out} in SECONDS for a named graphic. Unknown names give an instant, short-lived default.
static func timing(name: String, reduced: bool = false) -> Dictionary:
	var set_name := "reduced_timings_ms" if reduced else "timings_ms"
	var found: Dictionary = (data().get(set_name, {}) as Dictionary).get(name, {})
	return {"in": float(found.get("in", 0)) / 1000.0, "hold": float(found.get("hold", 2000)) / 1000.0, "out": float(found.get("out", 0)) / 1000.0}


static func transitions() -> Array:
	return (data().get("transitions", ["cut"]) as Array).duplicate()


static func gold_kinds() -> Array:
	return ((data().get("lower_third", {}) as Dictionary).get("gold_kinds", []) as Array).duplicate()


static func spotlight_kinds() -> Array:
	return ((data().get("spotlight", {}) as Dictionary).get("kinds", []) as Array).duplicate()


## [[timeline field, label], ...] shown on a player spotlight, in order.
static func spotlight_stats() -> Array:
	return ((data().get("spotlight", {}) as Dictionary).get("stat_fields", [["points", "PTS"]]) as Array).duplicate()


static func shot_clock_max() -> int:
	return int((data().get("scoreboard", {}) as Dictionary).get("shot_clock_max", 24))


static func scoreboard_text(key: String, fallback: String = "") -> String:
	return str((data().get("scoreboard", {}) as Dictionary).get(key, fallback))


static func stats_rows() -> Array:
	return ((data().get("stats_overlay", {}) as Dictionary).get("row_labels", []) as Array).duplicate()


# --- camera direction (M3) ----------------------------------------------------------------------------------------------------

static func camera_rules() -> Dictionary:
	return (data().get("camera", {}) as Dictionary)


## Seconds a non-critical shot must stay up before another can take the camera.
static func min_shot_seconds() -> float:
	return float(camera_rules().get("min_shot_seconds", 0.8))


static func max_switches_per_10s() -> int:
	return int(camera_rules().get("max_switches_per_10s", 5))


## Seconds before a preset may be taken again (0 for a preset with no cooldown).
static func cooldown(preset: String) -> float:
	return float((camera_rules().get("cooldowns_s", {}) as Dictionary).get(preset, 0.0))


static func whip_rate_factor() -> float:
	return float(camera_rules().get("whip_rate_factor", 3.0))


static func camera_styles() -> Array:
	return (camera_rules().get("styles", {"standard": {}}) as Dictionary).keys()


static func default_camera_style() -> String:
	return str(camera_rules().get("default_style", "standard"))


## {hold, cooldown, ease} multipliers of a director style ("standard" when the name is unknown).
static func camera_style(name: String) -> Dictionary:
	var styles: Dictionary = camera_rules().get("styles", {})
	var found: Dictionary = styles.get(name, styles.get("standard", {}))
	return {"hold": float(found.get("hold", 1.0)), "cooldown": float(found.get("cooldown", 1.0)), "ease": float(found.get("ease", 1.0))}


## Everything wrong with the file, as readable sentences (empty = valid). Tests call this so a bad edit fails loudly.
static func problems() -> Array[String]:
	var out: Array[String] = []
	var d := data()
	if d.is_empty():
		out.append("the identity file is missing or not valid JSON")
		return out
	for name in REQUIRED_TIMINGS:
		for set_name in ["timings_ms", "reduced_timings_ms"]:
			var t: Variant = (d.get(set_name, {}) as Dictionary).get(name)
			if not (t is Dictionary):
				out.append("%s has no entry for %s" % [set_name, name])
				continue
			for part in ["in", "hold", "out"]:
				if not (t as Dictionary).has(part) or float((t as Dictionary)[part]) < 0.0:
					out.append("%s.%s.%s must be a number of at least 0" % [set_name, name, part])
	if transitions().is_empty() or not transitions().has("cut"):
		out.append("transitions must include \"cut\"")
	if min_shot_seconds() <= 0.0 or max_switches_per_10s() <= 0:
		out.append("camera.min_shot_seconds and camera.max_switches_per_10s must be positive")
	if not camera_styles().has(default_camera_style()):
		out.append("camera.default_style must name one of the styles")
	if shot_clock_max() <= 0:
		out.append("scoreboard.shot_clock_max must be positive")
	return out
