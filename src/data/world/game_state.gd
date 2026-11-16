class_name FcGameState
extends RefCounted
## The root of one playthrough: everything a save slot contains.
## The world (all entities), the random generator position, which mode is
## being played, which team the player controls, and the current date.
## Later systems (league calendar, finances, news...) attach here or to the
## world as they are built.

const SCHEMA_VERSION := 1
const MODE_OWNER := "owner"
const MODE_DYNASTY := "dynasty"
const MODES := [MODE_OWNER, MODE_DYNASTY]

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
		"rng": rng.get_state(),
		"world": world.to_dict(),
	}


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
	s.user_team_id = int(data.get("user_team_id", 0))
	s.current_season = int(data.get("current_season", 2026))
	for pid in data.get("agreed_extensions", []):
		s.agreed_extensions.append(int(pid))
	var d := FcDate.from_iso(str(data.get("current_date", "")))
	s.current_date = d if d != null else FcDate.new(0, 0, 0)
	return s
