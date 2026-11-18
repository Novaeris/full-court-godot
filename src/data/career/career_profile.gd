class_name FcCareerProfile
extends RefCounted
## The career side of a Career Mode player. The player himself is an ordinary FcPlayer (identity, body, the shared
## 0-100 attributes, potential): there is no second player type. This record sits beside him keyed by player_id,
## exactly like contracts and statistics do (decision D-009), and holds what only a career has: archetype, look,
## jersey, XP and levels, points, reputation, currency, badges, stage, decisions and history.
##
## `profile_id` is the future online identity: a text id that is globally unique and never reused, separate from the
## world's integer player ids (which are only unique inside one save). Money-like values are ints (rule 6).
## `build_version` is the ruleset the build was created under; `ruleset_version` the one it was last validated under.
## Progression numbers change only through validated rules (src/career), never by direct assignment from a client.

const SCHEMA_VERSION := 1

## Career stages, in order (the brief's seven). Stored as integers; never renumber.
enum Stage { PROSPECT = 0, DEVELOPMENT = 1, LEAGUE_PREP = 2, PROFESSIONAL_ENTRY = 3, PROFESSIONAL = 4, VETERAN = 5, LEGACY = 6 }

var profile_id: String = ""
var player_id: int = 0
var archetype_key: String = "custom"
var appearance: Dictionary = {}
var jersey_number: int = 0
var stage: int = Stage.PROSPECT
var xp: int = 0
var level: int = 1
var development_points: int = 0
var skill_points: int = 0
var reputation: int = 0
var currency: int = 0
## Badge keys owned and equipped (definitions come with the progression phase).
var badges_owned: Array[String] = []
var badges_equipped: Array[String] = []
var build_version: int = 1
var ruleset_version: int = 1
## Career decisions: [{"year", "key", "choice"}] (filled by the career RPG phase).
var decisions: Array = []
## One row per season: {"year", "team_id", "games", "points", "rebounds", "assists", "awards": []}.
var history: Array = []
## The online account that owns this profile (empty until online exists).
var owner_account: String = ""


## A new globally unique profile id from a seeded stream: "fcp_" + 16 hex digits.
static func make_profile_id(rng: FcRng) -> String:
	return "fcp_%04x%04x%04x%04x" % [rng.range_int(0, 0xFFFF), rng.range_int(0, 0xFFFF), rng.range_int(0, 0xFFFF), rng.range_int(0, 0xFFFF)]


static func is_valid_profile_id(text: String) -> bool:
	if text.length() != 20 or not text.begins_with("fcp_"):
		return false
	for i in range(4, 20):
		if not "0123456789abcdef".contains(text[i]):
			return false
	return true


func validate() -> Array[String]:
	var errors: Array[String] = []
	if not is_valid_profile_id(profile_id):
		errors.append("career profile id '%s' is not valid" % profile_id)
	if player_id <= 0:
		errors.append("career profile needs a player")
	if FcArchetypes.get_archetype(archetype_key).is_empty():
		errors.append("career profile has an unknown archetype '%s'" % archetype_key)
	if stage < Stage.PROSPECT or stage > Stage.LEGACY:
		errors.append("career stage %d is not valid" % stage)
	if xp < 0 or level < 1 or development_points < 0 or skill_points < 0 or reputation < 0 or currency < 0:
		errors.append("xp, points, reputation and currency cannot be negative and the level starts at 1")
	var maximum := int(FcBuildRules.rules().get("max_badges_equipped", 5))
	if badges_equipped.size() > maximum:
		errors.append("at most %d badges can be equipped" % maximum)
	for key in badges_equipped:
		if not badges_owned.has(key):
			errors.append("badge %s is equipped but not owned" % key)
	return errors


func to_dict() -> Dictionary:
	return {
		"schema": SCHEMA_VERSION, "profile_id": profile_id, "player_id": player_id, "archetype": archetype_key,
		"appearance": appearance.duplicate(), "jersey_number": jersey_number, "stage": stage, "xp": xp, "level": level,
		"development_points": development_points, "skill_points": skill_points, "reputation": reputation, "currency": currency,
		"badges_owned": badges_owned.duplicate(), "badges_equipped": badges_equipped.duplicate(),
		"build_version": build_version, "ruleset_version": ruleset_version,
		"decisions": decisions.duplicate(true), "history": history.duplicate(true), "owner_account": owner_account,
	}


static func from_dict(d: Dictionary) -> FcCareerProfile:
	var p := FcCareerProfile.new()
	p.profile_id = str(d.get("profile_id", ""))
	p.player_id = int(d.get("player_id", 0))
	p.archetype_key = str(d.get("archetype", "custom"))
	var look = d.get("appearance", {})
	if look is Dictionary:
		for key in look:
			p.appearance[str(key)] = str(look[key])
	p.jersey_number = int(d.get("jersey_number", 0))
	p.stage = int(d.get("stage", Stage.PROSPECT))
	p.xp = int(d.get("xp", 0))
	p.level = int(d.get("level", 1))
	p.development_points = int(d.get("development_points", 0))
	p.skill_points = int(d.get("skill_points", 0))
	p.reputation = int(d.get("reputation", 0))
	p.currency = int(d.get("currency", 0))
	for key in d.get("badges_owned", []):
		p.badges_owned.append(str(key))
	for key in d.get("badges_equipped", []):
		p.badges_equipped.append(str(key))
	p.build_version = int(d.get("build_version", 1))
	p.ruleset_version = int(d.get("ruleset_version", 1))
	for row in d.get("decisions", []):
		if row is Dictionary:
			p.decisions.append({"year": int(row.get("year", 0)), "key": str(row.get("key", "")), "choice": str(row.get("choice", ""))})
	for row in d.get("history", []):
		if row is Dictionary:
			var clean: Dictionary = row.duplicate(true)
			for key in ["year", "team_id", "games", "wins", "losses"]:   # JSON turns whole numbers into floats
				if clean.has(key):
					clean[key] = int(clean[key])
			p.history.append(clean)
	p.owner_account = str(d.get("owner_account", ""))
	return p


## A fingerprint of the whole profile in canonical form (sorted keys), so two copies can be compared and a server can
## detect a tampered record. Not a security feature by itself.
func checksum() -> String:
	return JSON.stringify(to_dict(), "", true).sha256_text()
