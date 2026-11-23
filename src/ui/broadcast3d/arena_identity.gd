class_name FcArenaIdentity
extends RefCounted
## How the one 3D arena (FcCourtScene) is dressed for a game (Broadcast pass 2, M5, D-071): the home team's colours and mark, the LED board
## messages, the crowd's loyalties, the light tint, the bench colours. Pure data derived from the game's own team facts plus
## data/ui/arena_identity.json, so a different team or arena identity never means a different scene, and nothing here touches a game.
##
## make() takes {home: {abbr, name, color}, away: {abbr, name, color}} and returns a Dictionary:
##   key, home_color, away_color, accent (the floor trim), home_abbr, away_abbr, home_nickname, led_messages [String], led_seconds,
##   side_home_share [4 floats: near sideline, far sideline, left end, right end], away_block_share, away_block_from, away_neutral_share,
##   neutral_palette [Color], scale_min, scale_max, spot_count, spot_energy, light_tint, bench_seats, floor_roughness.

const PATH := "res://data/ui/arena_identity.json"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_data = parsed if parsed is Dictionary else {}
	return _data


## The identity for a home and away team (see the class comment). Missing parts fall back to a neutral arena, so it never fails.
static func make(teams: Dictionary) -> Dictionary:
	var d := data()
	var home: Dictionary = teams.get("home", {})
	var away: Dictionary = teams.get("away", {})
	var fallbacks: Dictionary = d.get("fallbacks", {})
	var home_color: Color = home.get("color", Color.html(str(fallbacks.get("home", "#2F6FED"))))
	var away_color: Color = away.get("color", Color.html(str(fallbacks.get("away", "#F28A2E"))))
	var home_abbr := str(home.get("abbr", ""))
	var away_abbr := str(away.get("abbr", ""))
	var nickname := nickname_of(str(home.get("name", "")))
	var crowd: Dictionary = d.get("crowd", {})
	var lights: Dictionary = d.get("lights", {})
	var palette: Array[Color] = []
	for hex in crowd.get("neutral_palette", ["#C94B4B", "#F0F0F0"]):
		palette.append(Color.html(str(hex)))
	var messages: Array[String] = []
	for template in d.get("led_templates", ["{abbr}"]):
		var text := str(template).replace("{abbr}", home_abbr).replace("{nickname}", nickname).replace("{away_abbr}", away_abbr).strip_edges()
		if text != "" and not messages.has(text):
			messages.append(text)
	if messages.is_empty():
		messages.append("FULL COURT")
	var mix := float((d.get("floor", {}) as Dictionary).get("accent_mix", 0.5))
	var bench: Dictionary = d.get("bench", {})
	var skins: Array[Color] = []
	for hex in bench.get("skins", ["#C68E63"]):
		skins.append(Color.html(str(hex)))
	return {"key": "arena:%s" % home_abbr, "home_color": home_color, "away_color": away_color, "accent": home_color.lerp(Color.WHITE, mix),
		"home_abbr": home_abbr, "away_abbr": away_abbr, "home_nickname": nickname, "led_messages": messages,
		"led_seconds": float(d.get("led_seconds_per_message", 4.0)),
		"side_home_share": _floats(crowd.get("side_home_share", [0.7, 0.7, 0.5, 0.3]), 4),
		"away_block_share": float(crowd.get("away_block_share", 0.12)), "away_block_from": float(crowd.get("away_block_from", 0.55)),
		"away_neutral_share": float(crowd.get("away_neutral_share", 0.18)), "neutral_palette": palette,
		"scale_min": float(crowd.get("scale_min", 0.9)), "scale_max": float(crowd.get("scale_max", 1.15)),
		"spot_count": int(lights.get("spot_count", 4)), "spot_energy": float(lights.get("spot_energy", 0.55)), "light_tint": Color.html(str(lights.get("tint", fallbacks.get("tint", "#FFE9C7")))), "bench_skins": skins, "bench_furniture": Color.html(str(bench.get("furniture", "#1D2638"))),
		"bench_seats": int((d.get("bench", {}) as Dictionary).get("seats", 6)), "floor_roughness": float((d.get("floor", {}) as Dictionary).get("roughness", 0.4))}


## The identity of a replay's home team, from its box score and the two team colours.
static func for_box(box: FcBoxScore, home_color: Color, away_color: Color) -> Dictionary:
	return make({"home": {"abbr": str(box.abbreviations[0]), "name": str(box.team_names[0]), "color": home_color},
		"away": {"abbr": str(box.abbreviations[1]), "name": str(box.team_names[1]), "color": away_color}})


## The team's nickname in capitals: the last word of its name ("Houston Sentinels" gives "SENTINELS").
static func nickname_of(team_name: String) -> String:
	var words := team_name.strip_edges().split(" ", false)
	return str(words[words.size() - 1]).to_upper() if words.size() > 1 else team_name.strip_edges().to_upper()


## Everything wrong with the data file (empty = valid).
static func problems() -> Array[String]:
	var out: Array[String] = []
	var d := data()
	if d.is_empty():
		out.append("the arena identity file is missing or not valid JSON")
		return out
	var shares: Array = (d.get("crowd", {}) as Dictionary).get("side_home_share", [])
	if shares.size() != 4:
		out.append("crowd.side_home_share needs four numbers (near, far, left end, right end)")
	for s in shares:
		if float(s) < 0.0 or float(s) > 1.0:
			out.append("crowd.side_home_share values must be between 0 and 1")
	if float((d.get("crowd", {}) as Dictionary).get("scale_min", 1.0)) > float((d.get("crowd", {}) as Dictionary).get("scale_max", 1.0)):
		out.append("crowd.scale_min must not exceed crowd.scale_max")
	if (d.get("led_templates", []) as Array).is_empty():
		out.append("led_templates must hold at least one message")
	return out


static func _floats(values: Array, count: int) -> Array[float]:
	var out: Array[float] = []
	for i in count:
		out.append(float(values[i]) if i < values.size() else 0.5)
	return out
