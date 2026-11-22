class_name FcCareerProfile
extends RefCounted
## The career side of a Career Mode player. The player himself is an ordinary FcPlayer (identity, body, the shared
## 0-100 attributes, potential): there is no second player type. This record sits beside him keyed by player_id,
## exactly like contracts and statistics do (decision D-009), and holds what only a career has: archetype, look,
## jersey, XP and levels, points, reputation, currency, badges, stage, decisions and history.
##
## `profile_id` is a text id ("fcp_" + 16 hex digits) drawn from the seeded FcRng, separate from the world's integer
## player ids. It is unique within one save (GameState checks that) and deterministic from the seed: two saves made
## from the same seed get the same id, so it is NOT globally unique. It deliberately does not use FcIdGenerator (a
## documented exception to the integer-id rule, see D-041). Money-like values are ints (rule 6).
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
## The rival: another team's player of a similar level, picked when the player accepts a rival's challenge (0 = none), and the
## head-to-head record of the games both played.
var rival_player_id: int = 0
var rival_wins: int = 0
var rival_losses: int = 0
## The sponsorship deal in force ({} = none): {"sponsor", "amount" a season in currency, "years_left", "edge"}, and the last season it was paid.
var sponsor_deal: Dictionary = {}
var sponsor_paid_year: int = 0
## The last season whose automatic growth was handed to the player as development points (a season is granted once, even across
## a save), and whether the "max potential reached" moment is waiting to be shown.
var growth_granted_year: int = 0
var potential_banner_pending: bool = false
## The decision waiting for an answer (an event key, "" = none) and the tags earlier choices left (what kind of person the
## player has become: "agent_loyal", "outspoken", ...).
var pending_event: String = ""
var tags: Array[String] = []
## Career decisions: [{"year", "key", "choice"}] (filled by the career RPG phase).
var decisions: Array = []
## One row per season: {"year", "team_id", "games", "points", "rebounds", "assists", "awards": []}.
var history: Array = []
## The public image, 0-100 each (data/career/media.json, FcCareerMedia): do supporters love the player, how the press sees him, and how loud
## the buzz is right now. `public_year` is the last season whose image changes were applied (a season is applied once, even across a save).
var fan_favor: int = 50
var media_image: int = 50
var hype: int = 0
var public_year: int = 0
## The latest headlines about the player [{"year", "text"}] (newest last) and the career timeline [{"year", "kind", "text"}] (oldest first):
## see FcCareerMedia and FcCareerTimeline. Display and legacy only: no rule reads them back.
var headlines: Array = []
var timeline: Array = []
## Reserved and unused: an account name for a possible future online feature (not planned for Career). Always empty today.
var owner_account: String = ""


## A new profile id from a seeded stream: "fcp_" + 16 hex digits. Unique within a save, not across saves.
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
	if fan_favor < 0 or fan_favor > 100 or media_image < 0 or media_image > 100 or hype < 0 or hype > 100:
		errors.append("the public image (fan favour, media image, hype) is 0-100")
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
		"badges_owned": badges_owned.duplicate(), "badges_equipped": badges_equipped.duplicate(), "role": role, "minutes_pref": minutes_pref, "usage_pref": usage_pref, "growth_granted_year": growth_granted_year, "potential_banner_pending": potential_banner_pending, "sponsor_deal": sponsor_deal.duplicate(), "sponsor_paid_year": sponsor_paid_year, "rival_player_id": rival_player_id, "rival_wins": rival_wins, "rival_losses": rival_losses, "coach_trust": coach_trust, "chemistry": chemistry, "relationships_year": relationships_year, "contract_pending": contract_pending, "contract_resolved_year": contract_resolved_year, "pending_event": pending_event, "tags": tags.duplicate(), "milestones": milestones.duplicate(), "training_used": training_used.duplicate(),
		"build_potential": build_potential, "build_version": build_version, "ruleset_version": ruleset_version,
		"decisions": decisions.duplicate(true), "history": history.duplicate(true), "owner_account": owner_account,
		"fan_favor": fan_favor, "media_image": media_image, "hype": hype, "public_year": public_year,
		"headlines": headlines.duplicate(true), "timeline": timeline.duplicate(true),
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
	p.growth_granted_year = int(d.get("growth_granted_year", 0))
	p.potential_banner_pending = bool(d.get("potential_banner_pending", false))
	var deal = d.get("sponsor_deal", {})
	if deal is Dictionary and not deal.is_empty():
		p.sponsor_deal = {"sponsor": str(deal.get("sponsor", "")), "amount": int(deal.get("amount", 0)), "years_left": int(deal.get("years_left", 0)), "edge": str(deal.get("edge", "safe"))}
	p.sponsor_paid_year = int(d.get("sponsor_paid_year", 0))
	p.rival_player_id = int(d.get("rival_player_id", 0))
	p.rival_wins = maxi(0, int(d.get("rival_wins", 0)))
	p.rival_losses = maxi(0, int(d.get("rival_losses", 0)))
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
			for key in ["year", "team_id", "games", "wins", "losses", "trust_change", "chemistry_change", "sponsor_paid", "fan_change", "media_change", "hype_change"]:   # JSON turns whole numbers into floats
				if clean.has(key):
					clean[key] = int(clean[key])
			p.history.append(clean)
	p.owner_account = str(d.get("owner_account", ""))
	p.fan_favor = clampi(int(d.get("fan_favor", 50)), 0, 100)
	p.media_image = clampi(int(d.get("media_image", 50)), 0, 100)
	p.hype = clampi(int(d.get("hype", 0)), 0, 100)
	p.public_year = int(d.get("public_year", 0))
	for row in d.get("headlines", []):
		if row is Dictionary:
			p.headlines.append({"year": int(row.get("year", 0)), "text": str(row.get("text", ""))})
	for row in d.get("timeline", []):
		if row is Dictionary:
			p.timeline.append({"year": int(row.get("year", 0)), "kind": str(row.get("kind", "")), "text": str(row.get("text", ""))})
	return p


## A fingerprint of the whole profile in canonical form (sorted keys), so two copies can be compared and a server can
## detect a tampered record. Not a security feature by itself.
func checksum() -> String:
	return JSON.stringify(to_dict(), "", true).sha256_text()
