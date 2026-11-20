class_name FcPlayerVisual
extends RefCounted
## THE ONE place a player's look is decided. Every screen that shows a player (a roster row, a profile, a card, the post-game screen, a
## trade proposal, a comparison, the showcase stage) gets the player's visual through resolve(), so the same player looks the same
## everywhere. Rules (docs/UI_POLISH_PLAN.md, Phase 7, D-050):
##   - PURE and DETERMINISTIC: the result depends only on the subject passed in (a stable key, optional stored appearance, optional art,
##     team colours). Randomness is never used: choices come from a hash (FNV-1a over the key, stable across Godot versions).
##   - It NEVER touches game RNG or player data: it reads a dictionary and returns a new one.
##   - The IDENTITY (skin, hair, face, facial hair, build) depends on the key (and stored appearance) only; the UNIFORM (team colours,
##     number) is the context and may change when a player changes team.
## Tiers (a provider chain; each falls back to the one before):
##   0 monogram (initials)     1 portrait art (a readable image)     2 stylised procedural figure (built; the default look)
##   3 full-body pose sprites  4 richer or 3D rendering              (3 and 4 are RESERVED: designed for, not built; resolve never returns them)
## Poses: only "idle" exists until tier 3 does; set_pose on the showcase stage uses the best available.

const TIER_MONOGRAM := 0
const TIER_PORTRAIT := 1
const TIER_PROCEDURAL := 2
const TIER_POSE := 3
const TIER_RENDER := 4
const IMPLEMENTED_TIERS := [0, 1, 2]

const SKIN_TONES := {"tone_1": "F6D7BD", "tone_2": "E9B98F", "tone_3": "CF9468", "tone_4": "A9703F", "tone_5": "7B4A27", "tone_6": "4E2D18"}
const HAIR_COLORS := ["15110D", "2B1B12", "4A2E1B", "6B3F22", "8C8C8C"]
const FALLBACK_OPTIONS := {
	"skin": ["tone_1", "tone_2", "tone_3", "tone_4", "tone_5", "tone_6"],
	"hair": ["bald", "short", "fade", "afro", "braids", "locs", "curly", "long"],
	"face": ["face_1", "face_2", "face_3", "face_4", "face_5", "face_6"],
	"facial_hair": ["none", "stubble", "goatee", "beard"],
}
## Team-colour palette for subjects with no branding (Dynasty cards have a team name only).
const TEAM_PALETTE := ["1F3A5F", "7A1F2B", "1F5F3A", "5F3A1F", "3A1F5F", "1F5F5F", "5F5F1F", "5F1F4A"]


## 32-bit FNV-1a hash of a string (stable across runs, machines and Godot versions, unlike String.hash()).
static func fnv1a(text: String) -> int:
	var h := 2166136261
	for byte in text.to_utf8_buffer():
		h = ((h ^ byte) * 16777619) & 0xFFFFFFFF
	return h


## The visual description of `subject`: {key, tier, monogram, art_path, identity, uniform, poses}.
## subject: {"key": String (required: the entity's stable key), "name": String, "appearance": Dictionary, "art_path": String,
##           "team": {"primary": "#RRGGBB", "secondary": "#RRGGBB", "abbreviation": String, "name": String}, "jersey": int}
static func resolve(subject: Dictionary) -> Dictionary:
	var key := str(subject.get("key", ""))
	var options := _options()
	var appearance: Dictionary = subject.get("appearance", {})
	var identity := {}
	for field in ["skin", "hair", "face", "facial_hair"]:
		var stored := str(appearance.get(field, ""))
		identity[field] = stored if options[field].has(stored) else options[field][fnv1a("%s|%s" % [key, field]) % options[field].size()]
	identity["build"] = fnv1a(key + "|build") % 3
	identity["skin_color"] = Color(str(SKIN_TONES.get(identity["skin"], "CF9468")))
	identity["hair_color"] = Color(HAIR_COLORS[fnv1a(key + "|haircolor") % HAIR_COLORS.size()])
	var art := str(subject.get("art_path", ""))
	var tier := TIER_PROCEDURAL
	if art != "" and FcDynastyStyle.art_texture(art) != null:
		tier = TIER_PORTRAIT
	else:
		art = ""
	return {
		"key": key, "tier": tier, "monogram": _monogram(str(subject.get("name", key))), "art_path": art,
		"identity": identity, "uniform": _uniform(subject, key), "poses": ["idle"],
	}


## The same subject drawn as the monogram only (the tier-0 fallback), for places with no room for a figure.
static func monogram_only(subject: Dictionary) -> Dictionary:
	var out := resolve(subject)
	out["tier"] = TIER_MONOGRAM
	out["art_path"] = ""
	return out


static func _uniform(subject: Dictionary, key: String) -> Dictionary:
	var team: Dictionary = subject.get("team", {})
	var primary := str(team.get("primary", ""))
	var secondary := str(team.get("secondary", ""))
	if not FcChecks.is_hex_color(primary):
		var seed_name := str(team.get("name", team.get("abbreviation", key)))
		primary = "#" + TEAM_PALETTE[fnv1a(seed_name + "|team") % TEAM_PALETTE.size()]
		secondary = "#EAF0FA"
	if not FcChecks.is_hex_color(secondary):
		secondary = "#FFFFFF"
	return {"primary": Color(primary), "secondary": Color(secondary), "number": int(subject.get("jersey", 0)), "abbreviation": str(team.get("abbreviation", ""))}


static func _monogram(name: String) -> String:
	var out := ""
	for part in name.split(" ", false):
		if part.length() > 0 and out.length() < 2:
			out += part.substr(0, 1).to_upper()
	return out if out != "" else "?"


static func _options() -> Dictionary:
	var rules := FcBuildRules.rules()
	var appearance: Dictionary = rules.get("appearance", {})
	var out := {}
	for field in FALLBACK_OPTIONS:
		var listed: Array = appearance.get(field, [])
		out[field] = listed if not listed.is_empty() else FALLBACK_OPTIONS[field]
	return out
