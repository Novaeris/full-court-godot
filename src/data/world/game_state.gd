class_name FcGameState
extends RefCounted
## The root of one playthrough: everything a save slot contains.
## The world (all entities), the random generator position, which mode is
## being played, which team the player controls, and the current date.
## Later systems (league calendar, finances, news...) attach here or to the
## world as they are built.

const SCHEMA_VERSION := 1
const MODE_OWNER := "owner"
## Watch-only mode: the AI runs every team, including yours (no owner controls). It is NOT the
## planned Dynasty Mode (a card-collecting game, see D-029); it used to be called "dynasty".
const MODE_SPECTATOR := "spectator"
## Career Mode: one created player lives a career in the league (docs/CAREER_MODE_PLAN.md). The career record is in
## `career_profiles`; `user_team_id` stays 0 until the player joins a team.
const MODE_CAREER := "career"
const MODES := [MODE_OWNER, MODE_SPECTATOR, MODE_CAREER]

var world: FcWorld
var rng: FcRng
var mode: String = MODE_OWNER
## The franchise the player controls.
var user_team_id: int = 0
## Career Mode profiles (FcCareerProfile), one per created player; empty in the other modes. Saved from data version 2.
var career_profiles: Array[FcCareerProfile] = []
## Season identified by the year it starts in (2026 = 2026-27).
var current_season: int = 2026
var current_date: FcDate = FcDate.new(2026, 7, 1)
## Players the owner has agreed to keep when their contracts end this season. Applied by the
## offseason as new contracts, then cleared. (Missing in older saves = nobody.)
var agreed_extensions: Array[int] = []
## Terms agreed with those players: player id -> [first-year salary, years].
var agreed_terms: Dictionary = {}
## Staff the owner agreed to keep when their contracts end: staff id -> [first-year salary, years].
var agreed_staff_terms: Dictionary = {}
## What the owner lets the general manager handle (Owner Mode): "contracts" (re-signing),
## "draft", "free_agency", "trades", "injuries" (in-season replacements). Off = the owner decides. Missing in older saves = all off.
var delegation: Dictionary = {"contracts": false, "draft": false, "free_agency": false, "trades": false, "injuries": false}
const DELEGATION_KEYS := ["contracts", "draft", "free_agency", "trades", "injuries"]
## The owner's direction for the general manager (Owner Mode): "philosophy" is one of
## PHILOSOPHIES (win now = value ability today, rebuild = value youth and potential and
## sell veterans), "budget" one of BUDGETS (how much payroll the GM may commit).
var direction: Dictionary = {"philosophy": "balanced", "budget": "normal"}
const PHILOSOPHIES := ["win_now", "balanced", "rebuild"]
const BUDGETS := ["frugal", "normal", "aggressive"]
## 0 = normal; 4 = an approved expansion's draft is waiting for the owner's protected list; 3 = the owners' meeting is under way; 2 = the owner's draft is under way; 1 = the draft and the rest of the first half are
## done and the owner's free-agency window is open (current_season is still the season that just ended).
var offseason_stage: int = 0
## The owners' meeting while it is under way (stage 3): {"year", "items": [item dictionaries from
## FcOwnersMeeting], "votes": {item id: bool}, "lobbied": {item id: [team ids]}, "influence": points left,
## "proposed": whether the owner has added an item}. Empty otherwise.
var meeting: Dictionary = {}
## The last season in which the meeting was held (so it is held once a year).
var meeting_year: int = 0
## The year the league last expanded (0 = never): expansions are not proposed twice within a few years.
var last_expansion_year: int = 0
## Franchise moves: [[year, team id, old city, new city], ...].
var relocation_log: Array = []
## While the expansion draft is pending (stage 4): {"year", "protected": [player ids of the owner's team]}.
var expansion: Dictionary = {}
## The last expansion draft: [[year, pick number, new team id, player id, team he came from], ...].
var expansion_log: Array = []
## How AI clubs feel about the owner (Owner Mode): {team id: {"wary": 0-6, "rapport": -6..6}}. "wary" rises
## by 2 with every trade the owner makes with that club and makes it ask for more next time (it fades by 1 each
## season); "rapport" moves with the owners' meetings (owners who voted with the owner like them more, those
## who were lobbied or voted against like them less) and nudges those owners' later votes.
var ai_relations: Dictionary = {}
## What past meetings decided: [[year, title, passed (0/1), yes, no], ...].
var meeting_log: Array = []
## The owner's career (Owner Mode): "reputation" 0-100 (starts at START_REPUTATION), "history"
## [[year, team id, approval, wins, title (0 or 1)], ...] one row per finished season, and
## "transfer_year" (the last season in which the owner changed teams, 0 = never).
var owner_career: Dictionary = {"reputation": 40, "history": [], "transfer_year": 0, "restructurings": []}
const START_REPUTATION := 40
## The draft while it is under way (stage 2), see FcOffseason.prepare_draft. Empty otherwise.
var draft_state: Dictionary = {}
## Owner objectives by season (D-077 C3): {year: [objective dictionaries]} (FcOwnerObjectives). Set once when a season starts, judged once at its end.
var owner_objectives: Dictionary = {}
## How the season clock runs (D-077 H): speed and pause rules. Missing keys take DEFAULT_SIM_PREFS.
var sim_prefs: Dictionary = {}
const DEFAULT_SIM_PREFS := {"speed": "normal", "pause_user_games": true, "pause_playoff_games": true, "pause_injuries": true, "pause_trade_offers": true,
	"pause_contract_offers": true, "pause_transactions": false, "pause_deadline": true, "pause_draft": true, "pause_all_star": true,
	"pause_season_transitions": true, "auto_sim_other_games": true, "autosave_days": 7}
## The ledger of processed things (D-077 B): {key: ISO date processed}. Keys: "event:<season>:<kind>", "report:<season>:<day>",
## "award:<season>:<period>:<n>" ... A key present means "done; never do it again".
var ledger: Dictionary = {}


func _init(game_world: FcWorld, random: FcRng) -> void:
	world = game_world
	rng = random


## "City Nickname" of the user's team, or "" if not set up yet.
func user_team_name() -> String:
	var t: FcTeam = world.teams.get_by_id(user_team_id)
	if t == null:
		return ""
	var c: FcCity = world.cities.get_by_id(t.city_id)
	return t.identity.display_name(c.name if c != null else "")


func validate() -> Array[String]:
	var errors: Array[String] = []
	if not MODES.has(mode):
		errors.append("unknown game mode '%s'" % mode)
	if mode == MODE_CAREER:
		var seen := {}
		for profile in career_profiles:
			for e in profile.validate():
				errors.append("career profile: %s" % e)
			if profile.player_id > 0 and world.players.get_by_id(profile.player_id) == null:
				errors.append("career profile %s refers to player %d who does not exist" % [profile.profile_id, profile.player_id])
			if seen.has(profile.profile_id):
				errors.append("career profile id %s is used twice" % profile.profile_id)
			seen[profile.profile_id] = true
		if user_team_id != 0 and not world.teams.has_id(user_team_id):
			errors.append("career team %d does not exist" % user_team_id)
	elif user_team_id <= 0 or not world.teams.has_id(user_team_id):
		errors.append("user team %d does not exist" % user_team_id)
	if not current_date.is_valid():
		errors.append("current date is not valid")
	errors.append_array(world.validate(current_season))
	return errors


func to_dict() -> Dictionary:
	return {
		"schema": SCHEMA_VERSION,
		"mode": mode,
		"user_team_id": user_team_id,
		"career_profiles": career_profiles.map(func(c): return c.to_dict()),
		"current_season": current_season,
		"current_date": current_date.to_iso(),
		"agreed_extensions": agreed_extensions.duplicate(),
		"agreed_terms": _terms_for_json(),
		"agreed_staff_terms": _terms_for_json(agreed_staff_terms),
		"delegation": delegation.duplicate(),
		"direction": direction.duplicate(),
		"offseason_stage": offseason_stage,
		"meeting": meeting.duplicate(true),
		"meeting_year": meeting_year,
		"last_expansion_year": last_expansion_year,
		"relocation_log": relocation_log.duplicate(true),
		"expansion": expansion.duplicate(true),
		"expansion_log": expansion_log.duplicate(true),
		"meeting_log": meeting_log.duplicate(true),
		"ai_relations": ai_relations.duplicate(true),
		"owner_career": owner_career.duplicate(true),
		"draft_state": draft_state.duplicate(true),
		"owner_objectives": _objectives_for_json(),
		"sim_prefs": sim_prefs.duplicate(),
		"ledger": ledger.duplicate(),
		"rng": rng.get_state(),
		"world": world.to_dict(),
	}


func _objectives_for_json() -> Dictionary:
	var out := {}
	for year in owner_objectives:
		out[str(year)] = (owner_objectives[year] as Array).duplicate(true)
	return out


## A sim preference, with its default when it was never set.
func sim_pref(key: String) -> Variant:
	return sim_prefs.get(key, DEFAULT_SIM_PREFS.get(key))


func ledger_has(key: String) -> bool:
	return ledger.has(key)


## Marks a key as processed (the first date wins). Returns false when it was already there (the caller must not process it again).
func ledger_mark(key: String, iso: String) -> bool:
	if ledger.has(key):
		return false
	ledger[key] = iso
	return true


static func _restructuring_rows(raw) -> Array:
	var rows: Array = []
	if raw is Array:
		for entry in raw:
			if entry is Array and entry.size() >= 3:
				rows.append([int(entry[0]), int(entry[1]), int(entry[2])])
	return rows


func _terms_for_json(source: Dictionary = {}) -> Dictionary:
	var terms := agreed_terms if source.is_empty() else source
	var out := {}
	for pid in terms:
		out[str(pid)] = terms[pid].duplicate()
	return out


## JSON turns whole numbers into floats; put the draft state's integers back.
static func _clean_draft_state(raw: Dictionary) -> Dictionary:
	var order: Array = []
	for t in raw.get("order", []):
		order.append(int(t))
	var available: Array = []
	for p in raw.get("available", []):
		available.append(int(p))
	var workouts: Array = []
	for w in raw.get("workouts", []):
		workouts.append(int(w))
	var results: Array = []
	for r in raw.get("results", []):
		results.append([int(r[0]), int(r[1]), int(r[2]), int(r[3]), int(r[4]) if r.size() > 4 else int(r[2])])
	return {"year": int(raw.get("year", 0)), "order": order, "total": int(raw.get("total", 0)),
		"next": int(raw.get("next", 1)), "available": available, "results": results, "workouts": workouts}


## Problems found while loading are appended to `errors`.
static func from_dict(data: Dictionary, defs: FcDefinitionSet, errors: Array[String] = []) -> FcGameState:
	var w := FcWorld.from_dict(data.get("world", {}), defs, errors)
	var r := FcRng.new()
	var rng_data = data.get("rng", null)
	if rng_data is Dictionary and rng_data.has("seed") and rng_data.has("state"):
		r.set_state(rng_data)
	else:
		errors.append("saved random generator state missing; using a fresh one")
	var s := FcGameState.new(w, r)
	s.mode = str(data.get("mode", MODE_OWNER))
	if s.mode == "dynasty":
		s.mode = MODE_SPECTATOR   # saves made before the rename
	s.user_team_id = int(data.get("user_team_id", 0))
	for row in data.get("career_profiles", []):
		if row is Dictionary:
			s.career_profiles.append(FcCareerProfile.from_dict(row))
	s.current_season = int(data.get("current_season", 2026))
	s.offseason_stage = int(data.get("offseason_stage", 0))
	s.meeting_year = int(data.get("meeting_year", 0))
	s.last_expansion_year = int(data.get("last_expansion_year", 0))
	for row in data.get("relocation_log", []):
		s.relocation_log.append([int(row[0]), int(row[1]), str(row[2]), str(row[3])])
	for row in data.get("expansion_log", []):
		s.expansion_log.append([int(row[0]), int(row[1]), int(row[2]), int(row[3]), int(row[4])])
	var raw_expansion = data.get("expansion", {})
	if raw_expansion is Dictionary and not raw_expansion.is_empty():
		var kept: Array[int] = []
		for pid in raw_expansion.get("protected", []):
			kept.append(int(pid))
		s.expansion = {"year": int(raw_expansion.get("year", 0)), "protected": kept}
	var raw_relations = data.get("ai_relations", {})
	if raw_relations is Dictionary:
		for key in raw_relations:
			var entry: Dictionary = raw_relations[key]
			s.ai_relations[int(key)] = {"wary": clampi(int(entry.get("wary", 0)), 0, 6), "rapport": clampi(int(entry.get("rapport", 0)), -6, 6)}
	for row in data.get("meeting_log", []):
		s.meeting_log.append([int(row[0]), str(row[1]), int(row[2]), int(row[3]), int(row[4])])
	var raw_meeting = data.get("meeting", {})
	if raw_meeting is Dictionary and not raw_meeting.is_empty():
		var votes := {}
		for key in raw_meeting.get("votes", {}):
			votes[str(key)] = bool(raw_meeting["votes"][key])
		var items: Array = []
		for item in raw_meeting.get("items", []):
			var restored := {"id": str(item["id"]), "family": str(item["family"]), "title": str(item["title"]), "detail": str(item["detail"]), "supermajority": bool(item["supermajority"])}
			if bool(item.get("proposed", false)):
				restored["proposed"] = true
			if item.has("mover"):
				restored["mover"] = int(item["mover"])
				restored["region"] = str(item.get("region", ""))
			items.append(restored)
		var lobbied := {}
		for key in raw_meeting.get("lobbied", {}):
			var teams: Array = []
			for t in raw_meeting["lobbied"][key]:
				teams.append(int(t))
			lobbied[str(key)] = teams
		s.meeting = {"year": int(raw_meeting.get("year", 0)), "items": items, "votes": votes, "lobbied": lobbied,
			"influence": int(raw_meeting.get("influence", 0)), "proposed": bool(raw_meeting.get("proposed", false))}
	var raw_career = data.get("owner_career", {})
	if raw_career is Dictionary and not raw_career.is_empty():
		var rows: Array = []
		for entry in raw_career.get("history", []):
			rows.append([int(entry[0]), int(entry[1]), int(entry[2]), int(entry[3]), int(entry[4])])
		s.owner_career = {"reputation": clampi(int(raw_career.get("reputation", START_REPUTATION)), 0, 100), "history": rows, "transfer_year": int(raw_career.get("transfer_year", 0)), "restructurings": _restructuring_rows(raw_career.get("restructurings", []))}
	var raw_draft = data.get("draft_state", {})
	if raw_draft is Dictionary and not raw_draft.is_empty():
		s.draft_state = _clean_draft_state(raw_draft)
	var raw_delegation = data.get("delegation", {})
	if raw_delegation is Dictionary:
		for key in DELEGATION_KEYS:
			s.delegation[key] = bool(raw_delegation.get(key, false))
	var raw_direction = data.get("direction", {})
	if raw_direction is Dictionary:
		var philosophy := str(raw_direction.get("philosophy", "balanced"))
		var budget := str(raw_direction.get("budget", "normal"))
		s.direction["philosophy"] = philosophy if PHILOSOPHIES.has(philosophy) else "balanced"
		s.direction["budget"] = budget if BUDGETS.has(budget) else "normal"
	var raw_staff_terms = data.get("agreed_staff_terms", {})
	if raw_staff_terms is Dictionary:
		for key in raw_staff_terms:
			s.agreed_staff_terms[int(key)] = [int(raw_staff_terms[key][0]), int(raw_staff_terms[key][1])]
	var raw_terms = data.get("agreed_terms", {})
	if raw_terms is Dictionary:
		for key in raw_terms:
			s.agreed_terms[int(key)] = [int(raw_terms[key][0]), int(raw_terms[key][1])]
	for pid in data.get("agreed_extensions", []):
		s.agreed_extensions.append(int(pid))
	var raw_objectives = data.get("owner_objectives", {})   # data version 5: missing = none
	if raw_objectives is Dictionary:
		for key in raw_objectives:
			var rows: Array = []
			for o in raw_objectives[key]:
				if o is Dictionary:
					rows.append({"kind": str(o.get("kind", "")), "text": str(o.get("text", "")), "target": int(o.get("target", 0)), "actual": int(o.get("actual", 0)),
						"met": bool(o.get("met", false)), "status": str(o.get("status", FcOwnerObjectives.STATUS_OPEN))})
			s.owner_objectives[int(key)] = rows
	var raw_prefs = data.get("sim_prefs", {})
	if raw_prefs is Dictionary:
		for key in raw_prefs:
			if DEFAULT_SIM_PREFS.has(key):
				var default_value = DEFAULT_SIM_PREFS[key]
				s.sim_prefs[str(key)] = int(raw_prefs[key]) if default_value is int else (bool(raw_prefs[key]) if default_value is bool else str(raw_prefs[key]))
	var raw_ledger = data.get("ledger", {})
	if raw_ledger is Dictionary:
		for key in raw_ledger:
			s.ledger[str(key)] = str(raw_ledger[key])
	var d := FcDate.from_iso(str(data.get("current_date", "")))
	s.current_date = d if d != null else FcDate.new(0, 0, 0)
	return s
