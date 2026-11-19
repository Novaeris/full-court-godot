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
## The potential the player was created with. Ceilings come from this, not from the player's current `potential`, which the
## league's yearly aging may lower: a career's limits must not shrink behind the player's back.
var build_potential: int = 0
var build_version: int = 1
var ruleset_version: int = 1
## Milestone keys already claimed (each pays once) and training sessions used per season ({"2026": 3}).
var milestones: Array[String] = []
var training_used: Dictionary = {}
## What the player asks of his coach: "auto" (the coach decides), "starter" or "bench"; minutes and usage preferences from -1 to +1.
## The coach can refuse a request the player has not earned (see FcCareerRules.role_problem).
var role: String = "auto"
var minutes_pref: int = 0
var usage_pref: int = 0
## Contract talks: true while the player's contract ends this season and he has not decided; the season of the last talks.
var contract_pending: bool = false
var contract_resolved_year: int = 0
## Relationships, 0-100 (50 = neutral): how much the coach trusts the player and how well he fits with his teammates.
## They change each season (FcCareerRules.relationships_after_season) and feed back into role requests, contract talks and growth.
var coach_trust: int = 50
var chemistry: int = 50
## The last season whose relationship changes were applied (a season is scored once, even across a save).
var relationships_year: int = 0
## The decision waiting for an answer (an event key, "" = none) and the tags earlier choices left (what kind of person the
## player has become: "agent_loyal", "outspoken", ...).
var pending_event: String = ""
var tags: Array[String] = []
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
	if coach_trust < 0 or coach_trust > 100 or chemistry < 0 or chemistry > 100:
		errors.append("relationships are 0-100")
	if not ["auto", "starter", "bench"].has(role):
		errors.append("role must be auto, starter or bench")
	if absi(minutes_pref) > 1 or absi(usage_pref) > 1:
		errors.append("minutes and usage preferences are -1, 0 or +1")
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
		"badges_owned": badges_owned.duplicate(), "badges_equipped": badges_equipped.duplicate(), "role": role, "minutes_pref": minutes_pref, "usage_pref": usage_pref, "coach_trust": coach_trust, "chemistry": chemistry, "relationships_year": relationships_year, "contract_pending": contract_pending, "contract_resolved_year": contract_resolved_year, "pending_event": pending_event, "tags": tags.duplicate(), "milestones": milestones.duplicate(), "training_used": training_used.duplicate(),
		"build_potential": build_potential, "build_version": build_version, "ruleset_version": ruleset_version,
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
	p.role = str(d.get("role", "auto"))
	p.minutes_pref = clampi(int(d.get("minutes_pref", 0)), -1, 1)
	p.usage_pref = clampi(int(d.get("usage_pref", 0)), -1, 1)
	p.coach_trust = clampi(int(d.get("coach_trust", 50)), 0, 100)
	p.chemistry = clampi(int(d.get("chemistry", 50)), 0, 100)
	p.relationships_year = int(d.get("relationships_year", 0))
	p.contract_pending = bool(d.get("contract_pending", false))
	p.contract_resolved_year = int(d.get("contract_resolved_year", 0))
	p.pending_event = str(d.get("pending_event", ""))
	for key in d.get("tags", []):
		p.tags.append(str(key))
	for key in d.get("milestones", []):
		p.milestones.append(str(key))
	var used = d.get("training_used", {})
	if used is Dictionary:
		for year in used:
			p.training_used[str(year)] = int(used[year])
	p.build_potential = int(d.get("build_potential", 0))
	p.build_version = int(d.get("build_version", 1))
	p.ruleset_version = int(d.get("ruleset_version", 1))
	for row in d.get("decisions", []):
		if row is Dictionary:
			p.decisions.append({"year": int(row.get("year", 0)), "key": str(row.get("key", "")), "choice": str(row.get("choice", ""))})
	for row in d.get("history", []):
		if row is Dictionary:
			var clean: Dictionary = row.duplicate(true)
			for key in ["year", "team_id", "games", "wins", "losses", "trust_change", "chemistry_change"]:   # JSON turns whole numbers into floats
				if clean.has(key):
					clean[key] = int(clean[key])
			p.history.append(clean)
	p.owner_account = str(d.get("owner_account", ""))
	return p


## A fingerprint of the whole profile in canonical form (sorted keys), so two copies can be compared and a server can
## detect a tampered record. Not a security feature by itself.
func checksum() -> String:
	return JSON.stringify(to_dict(), "", true).sha256_text()
