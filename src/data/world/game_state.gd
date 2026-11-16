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
const MODES := [MODE_OWNER, MODE_SPECTATOR]

var world: FcWorld
var rng: FcRng
var mode: String = MODE_OWNER
## The franchise the player controls.
var user_team_id: int = 0
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
## 0 = normal; 2 = the owner's draft is under way; 1 = the draft and the rest of the first half are
## done and the owner's free-agency window is open (current_season is still the season that just ended).
var offseason_stage: int = 0
## The owner's career (Owner Mode): "reputation" 0-100 (starts at START_REPUTATION), "history"
## [[year, team id, approval, wins, title (0 or 1)], ...] one row per finished season, and
## "transfer_year" (the last season in which the owner changed teams, 0 = never).
var owner_career: Dictionary = {"reputation": 40, "history": [], "transfer_year": 0}
const START_REPUTATION := 40
## The draft while it is under way (stage 2), see FcOffseason.prepare_draft. Empty otherwise.
var draft_state: Dictionary = {}


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
	if user_team_id <= 0 or not world.teams.has_id(user_team_id):
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
		"current_season": current_season,
		"current_date": current_date.to_iso(),
		"agreed_extensions": agreed_extensions.duplicate(),
		"agreed_terms": _terms_for_json(),
		"agreed_staff_terms": _terms_for_json(agreed_staff_terms),
		"delegation": delegation.duplicate(),
		"direction": direction.duplicate(),
		"offseason_stage": offseason_stage,
		"owner_career": owner_career.duplicate(true),
		"draft_state": draft_state.duplicate(true),
		"rng": rng.get_state(),
		"world": world.to_dict(),
	}


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
	s.current_season = int(data.get("current_season", 2026))
	s.offseason_stage = int(data.get("offseason_stage", 0))
	var raw_career = data.get("owner_career", {})
	if raw_career is Dictionary and not raw_career.is_empty():
		var rows: Array = []
		for entry in raw_career.get("history", []):
			rows.append([int(entry[0]), int(entry[1]), int(entry[2]), int(entry[3]), int(entry[4])])
		s.owner_career = {"reputation": clampi(int(raw_career.get("reputation", START_REPUTATION)), 0, 100), "history": rows, "transfer_year": int(raw_career.get("transfer_year", 0))}
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
	var d := FcDate.from_iso(str(data.get("current_date", "")))
	s.current_date = d if d != null else FcDate.new(0, 0, 0)
	return s
