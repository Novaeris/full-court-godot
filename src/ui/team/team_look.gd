class_name FcTeamLook
extends RefCounted
## THE ONE place a team's visual identity is decided (the team counterpart of FcPlayerVisual, D-057). Every screen that shows a team
## (a crest in a table, the Owner header, a score bug, a save card, a bracket) gets it through resolve(), so one team is one crest,
## one wordmark and one set of uniforms everywhere. Rules:
##   - PURE and DETERMINISTIC: the result depends only on the subject passed in. Choices come from a hash (FNV-1a, the same one the
##     player visuals use), never from game RNG, and nothing is stored: the team data model is unchanged.
##   - The crest SHAPE comes from the hash of the team key. The EMBLEM comes from the words of the team's own nickname when a rule in
##     data/ui/team_identity.json matches (Falconers get a swooping bird), otherwise from the hash.
##   - Colours are the team's branding; ink, trim and the uniforms are chosen so the crest and the jersey numbers are always readable.
## subject: {"key": String (stable, e.g. "team:12"), "name": String, "city": String, "nickname": String, "abbreviation": String,
##           "primary": "#RRGGBB", "secondary": "#RRGGBB", "accent": "#RRGGBB", "logo_key": String}

const SHAPES := ["shield", "roundel", "hexagon", "diamond", "pennant", "banner", "octagon", "badge"]
const EMBLEMS := ["star", "spark", "bolt", "crown", "peak", "wave", "flame", "wing", "chevrons", "sun", "crescent", "gem", "target", "pine", "arrow",
	"swoop", "hoop", "ball", "paw", "claw", "tower", "bridge", "anchor"]
const DATA_PATH := "res://data/ui/team_identity.json"
const FALLBACK_PRIMARIES := ["#1F3A5F", "#8B1E2D", "#0B6E4F", "#3B2F8F", "#111827", "#0E7490", "#7C2D12", "#4C1D95"]
## Neutral light base for an away jersey when the team's secondary colour is not light.
const AWAY_BASE := "#EAF0FA"

static var _rules: Array = []


## A subject from plain values (the pieces every caller already has).
static func subject(key: String, display_name: String, abbreviation: String, primary: String, secondary: String, accent: String = "", nickname: String = "", logo_key: String = "") -> Dictionary:
	var nick := nickname
	var city := display_name
	if nick == "":
		var words := display_name.strip_edges().split(" ", false)
		if words.size() > 1:
			nick = words[words.size() - 1]
			city = " ".join(words.slice(0, words.size() - 1))
	elif display_name.ends_with(nick):
		city = display_name.trim_suffix(nick).strip_edges()
	return {"key": key, "name": display_name, "city": city, "nickname": nick, "abbreviation": abbreviation, "primary": primary, "secondary": secondary, "accent": accent, "logo_key": logo_key}


## A subject for an Owner/Career world team.
static func subject_for_team(world: FcWorld, team: FcTeam) -> Dictionary:
	return subject("team:%d" % team.id, world.team_display_name(team.id), team.identity.abbreviation, team.branding.primary_color, team.branding.secondary_color,
		team.branding.accent_color, team.identity.nickname, team.branding.logo_key)


## The resolved look: {key, shape, emblem, fill, ink, trim, abbreviation, city, nickname, uniforms, signature}.
static func resolve(subject_data: Dictionary) -> Dictionary:
	var key := str(subject_data.get("key", subject_data.get("name", "")))
	var shape: String = SHAPES[FcPlayerVisual.fnv1a(key + "|shape") % SHAPES.size()]
	var nickname := str(subject_data.get("nickname", ""))
	var emblem := _emblem_for(nickname)
	if emblem == "":
		emblem = EMBLEMS[FcPlayerVisual.fnv1a(key + "|emblem") % EMBLEMS.size()]
	var logo_key := str(subject_data.get("logo_key", ""))
	if logo_key.contains("/"):   # a chosen crest "shape/emblem" (reserved for a future branding editor; ignored when invalid)
		var parts := logo_key.split("/")
		if SHAPES.has(parts[0]) and EMBLEMS.has(parts[1]):
			shape = parts[0]
			emblem = parts[1]
	var fallback := Color(FALLBACK_PRIMARIES[FcPlayerVisual.fnv1a(key + "|color") % FALLBACK_PRIMARIES.size()])
	var primary := _color(str(subject_data.get("primary", "")), fallback)
	var secondary := _color(str(subject_data.get("secondary", "")), FcUiTokens.TEXT)
	var accent := _color(str(subject_data.get("accent", "")), secondary)
	var ink := _ink_for(primary, [secondary, accent])
	var trim := accent if FcUiContrast.ratio(accent, primary) >= 1.8 else ink
	return {"key": key, "shape": shape, "emblem": emblem, "fill": primary, "ink": ink, "trim": trim, "abbreviation": str(subject_data.get("abbreviation", "")).substr(0, 3).to_upper(),
		"city": str(subject_data.get("city", "")), "nickname": nickname, "uniforms": _uniforms(primary, secondary, accent),
		"signature": "%s|%s|%s|%s" % [shape, emblem, primary.to_html(false), secondary.to_html(false)]}


## The first of `candidates` readable (at least 3:1) on `fill`, else the better of the text and background colours.
static func _ink_for(fill: Color, candidates: Array) -> Color:
	for c in candidates:
		if FcUiContrast.ratio(c, fill) >= 3.0:
			return c
	return FcUiContrast.readable_on(fill)


static func _color(hex: String, fallback: Color) -> Color:
	return Color(hex) if FcChecks.is_hex_color(hex) else fallback


## Home, away and alternate uniforms from the same colours: {kind: {"primary", "secondary" (numbers), "trim"}} (Colors).
## Home is the team colours; away is a light neutral (or the team's own secondary when that is light) with the primary as trim; alternate
## is built on the accent colour. The number colour is always at least 3:1 against its jersey.
static func _uniforms(primary: Color, secondary: Color, accent: Color) -> Dictionary:
	var home := {"primary": primary, "secondary": _ink_for(primary, [secondary, accent]), "trim": accent}
	var away_base := secondary if FcUiContrast.luminance(secondary) > 0.5 else Color(AWAY_BASE)
	var away := {"primary": away_base, "secondary": _ink_for(away_base, [primary, accent]), "trim": primary}
	var alt_base := accent
	if FcUiContrast.ratio(alt_base, primary) < 1.6 or FcUiContrast.ratio(alt_base, away_base) < 1.3:
		alt_base = primary.darkened(0.45) if FcUiContrast.luminance(primary) > 0.2 else primary.lightened(0.45)
	var alt := {"primary": alt_base, "secondary": _ink_for(alt_base, [secondary, primary]), "trim": secondary}
	return {"home": home, "away": away, "alt": alt}


static func _emblem_for(nickname: String) -> String:
	if nickname == "":
		return ""
	if _rules.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if parsed is Dictionary:
			_rules = (parsed as Dictionary).get("emblem_rules", [])
	var lower := nickname.to_lower()
	for rule in _rules:
		for word in rule["words"]:
			if lower.contains(str(word)):
				return str(rule["emblem"]) if EMBLEMS.has(str(rule["emblem"])) else ""
	return ""
