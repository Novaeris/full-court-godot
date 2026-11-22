class_name FcCareerMedia
extends RefCounted
## Public image for Career Mode (data/career/media.json): fan_favor, media_image and hype, each 0 to 100. Great games make hype and a few
## fans, a season moves fan favour with winning and stardom and titles, the choices a player has made (their tags) keep nudging the press
## and the crowd, and the numbers decide how much a sponsor will pay. Pure and seeded by nothing: the same career always gets the same
## numbers and headlines. The numbers all live in the data file; this class only applies them.

const KEYS := ["fan_favor", "media_image", "hype"]

static var _cache: Dictionary = {}


static func rules() -> Dictionary:
	if _cache.is_empty():
		var file := FileAccess.open("res://data/career/media.json", FileAccess.READ)
		var parsed = FcChecks.parse_json(file.get_as_text()) if file != null else null
		_cache = parsed if parsed is Dictionary else {}
	return _cache


static func _num(path: Array, fallback: float) -> float:
	var node: Variant = rules()
	for key in path:
		if node is Dictionary and (node as Dictionary).has(key):
			node = (node as Dictionary)[key]
		else:
			return fallback
	return float(node)


## Gives a new profile its starting image.
static func start(profile: FcCareerProfile) -> void:
	profile.fan_favor = int(_num(["start", "fan_favor"], 50))
	profile.media_image = int(_num(["start", "media_image"], 50))
	profile.hype = int(_num(["start", "hype"], 0))


## Adds `effects` ({"fan_favor", "media_image", "hype"}, any subset) to the profile, keeping each between 0 and 100. Returns what
## actually changed: {key: delta}.
static func apply(profile: FcCareerProfile, effects: Dictionary) -> Dictionary:
	var changes := {}
	for key in KEYS:
		if not effects.has(key):
			continue
		var before := int(profile.get(key))
		var after := clampi(before + int(effects[key]), 0, 100)
		profile.set(key, after)
		if after != before:
			changes[key] = after - before
	return changes


## Whether a game line is worth a headline: "triple_double" (10+ in points, rebounds and assists), "notable_points" (35+ points) or "".
static func notable_kind(line: Dictionary) -> String:
	var need := int(_num(["notable_game", "triple_double"], 10))
	if int(line.get("points", 0)) >= need and int(line.get("rebounds", 0)) >= need and int(line.get("assists", 0)) >= need:
		return "triple_double"
	if int(line.get("points", 0)) >= int(_num(["notable_game", "points"], 35)):
		return "notable_points"
	return ""


## A game's effect on the public image. Returns {} for an ordinary game, or {"kind", "headline", "changes"} (the headline is also kept).
static func on_game(profile: FcCareerProfile, line: Dictionary, year: int, player_name: String, team_name: String, opponent: String) -> Dictionary:
	var kind := notable_kind(line)
	if kind == "":
		return {}
	var changes := apply(profile, {"hype": int(_num(["notable_game", "hype"], 4)), "fan_favor": int(_num(["notable_game", "fan_favor"], 1))})
	var text := headline(kind, year, {"name": player_name, "team": team_name, "opponent": opponent, "points": int(line.get("points", 0)), "award": ""})
	add_headline(profile, year, text)
	return {"kind": kind, "headline": text, "changes": changes}


## The season's effect on the public image, applied once per season (guarded by `profile.public_year`). `context`:
## {"win_pct" (0-1), "points" (per game), "champion" (bool)}. Returns {"fan_favor", "media_image", "hype"} as the deltas, or {} if the season
## was already applied.
static func after_season(profile: FcCareerProfile, year: int, context: Dictionary) -> Dictionary:
	if profile.public_year == year:
		return {}
	profile.public_year = year
	var before := {"fan_favor": profile.fan_favor, "media_image": profile.media_image, "hype": profile.hype}
	var fan := roundi((float(context.get("win_pct", 0.5)) - _num(["season", "win_pct_baseline"], 0.5)) * _num(["season", "fan_per_win_pct"], 30.0))
	var hype_gain := 0
	if bool(context.get("champion", false)):
		fan += int(_num(["season", "title_fan"], 6))
		hype_gain += int(_num(["season", "title_hype"], 8))
	if float(context.get("points", 0.0)) >= _num(["season", "star_ppg"], 20.0):
		fan += int(_num(["season", "star_fan"], 2))
		hype_gain += int(_num(["season", "star_hype"], 3))
	# the crowd forgets: fan favour drifts back toward where it started, and yesterday's buzz fades
	var home := int(_num(["start", "fan_favor"], 50))
	var drift := int(_num(["season", "fan_drift_toward_start"], 1))
	if profile.fan_favor > home:
		fan -= mini(drift, profile.fan_favor - home)
	elif profile.fan_favor < home:
		fan += mini(drift, home - profile.fan_favor)
	var faded := roundi(profile.hype * (100.0 - _num(["season", "hype_decay_percent"], 30.0)) / 100.0)
	apply(profile, {"fan_favor": fan, "hype": (faded - profile.hype) + hype_gain})
	var tag_effects: Dictionary = rules().get("tag_effects", {})
	for tag in profile.tags:
		if tag_effects.has(tag):
			apply(profile, tag_effects[tag])
	var out := {}
	for key in KEYS:
		out[key] = int(profile.get(key)) - int(before[key])
	return out


## Sponsor offers scale with the public image: 1.0 at the starting image, between min and max in the data. Fans and hype both count.
static func sponsor_multiplier(profile: FcCareerProfile) -> float:
	var raw := 1.0 + (profile.fan_favor - 50) * _num(["sponsor", "fan_weight"], 0.006) + profile.hype * _num(["sponsor", "hype_weight"], 0.004)
	return clampf(raw, _num(["sponsor", "min"], 0.75), _num(["sponsor", "max"], 1.5))


## The words for a number: label("fan_favor", 72) = "Beloved".
static func label(kind: String, value: int) -> String:
	var rows: Array = (rules().get("labels", {}) as Dictionary).get(kind, [])
	var out := ""
	for row in rows:
		if value >= int(row[0]):
			out = str(row[1])
	return out


## A headline from the templates for `kind` ("notable_points", "triple_double", "title", "award"); the same facts always read the same.
static func headline(kind: String, year: int, facts: Dictionary) -> String:
	var options: Array = (rules().get("headlines", {}) as Dictionary).get(kind, [])
	if options.is_empty():
		return ""
	var text := str(options[absi(hash("%d:%s:%s:%s" % [year, kind, facts.get("name", ""), facts.get("points", 0)])) % options.size()])
	for key in facts:
		text = text.replace("{%s}" % key, str(facts[key]))
	return text


## Keeps a headline (newest last, at most `headline_limit`).
static func add_headline(profile: FcCareerProfile, year: int, text: String) -> void:
	if text == "":
		return
	for row in profile.headlines:
		if int(row["year"]) == year and str(row["text"]) == text:
			return
	profile.headlines.append({"year": year, "text": text})
	var limit := int(_num(["headline_limit"], 12))
	while profile.headlines.size() > limit:
		profile.headlines.pop_front()
