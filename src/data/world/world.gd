class_name FcWorld
extends RefCounted
## The whole basketball universe's data in one place: attribute definitions,
## the ID generator, and one repository per entity type. It also checks that
## entities agree with each other (no contract pointing at a missing player,
## no player on two rosters...). It holds data only: no simulation, no UI.
##
## to_dict()/from_dict() produce the snapshot the future save system will wrap
## with slots, metadata, versioning and atomic file writing.

const SCHEMA_VERSION := 1

const KIND_PLAYER := "player"
const KIND_TEAM := "team"
const KIND_CONTRACT := "contract"
const KIND_CITY := "city"
const KIND_ARENA := "arena"

var definitions: FcDefinitionSet
var ids := FcIdGenerator.new()
var players: FcRepository = FcMemoryRepository.new()
var teams: FcRepository = FcMemoryRepository.new()
var contracts: FcRepository = FcMemoryRepository.new()
var cities: FcRepository = FcMemoryRepository.new()
var arenas: FcRepository = FcMemoryRepository.new()


func _init(defs: FcDefinitionSet) -> void:
	definitions = defs


## The team whose roster contains this player, or null (free agent).
func team_of_player(player_id: int) -> FcTeam:
	for t in teams.all():
		if t.roster.contains(player_id):
			return t
	return null


## The player's ACTIVE contract, or null.
func active_contract_of(player_id: int) -> FcContract:
	for c in contracts.all():
		if c.player_id == player_id and c.status == FcContract.Status.ACTIVE:
			return c
	return null


## Full integrity check. Returns problems as readable text; empty = healthy.
func validate() -> Array[String]:
	var errors: Array[String] = []

	for c in cities.all():
		for e in c.validate():
			errors.append("city %d: %s" % [c.id, e])
	for a in arenas.all():
		for e in a.validate():
			errors.append("arena %d: %s" % [a.id, e])
		if a.city_id > 0 and not cities.has_id(a.city_id):
			errors.append("arena %d: city %d does not exist" % [a.id, a.city_id])
	for p in players.all():
		for e in p.validate():
			errors.append("player %d: %s" % [p.id, e])
	for t in teams.all():
		for e in t.validate():
			errors.append("team %d: %s" % [t.id, e])
		if t.city_id > 0 and not cities.has_id(t.city_id):
			errors.append("team %d: city %d does not exist" % [t.id, t.city_id])
		if t.arena_id > 0 and not arenas.has_id(t.arena_id):
			errors.append("team %d: arena %d does not exist" % [t.id, t.arena_id])

	var active_by_player := {}
	for c in contracts.all():
		for e in c.validate():
			errors.append("contract %d: %s" % [c.id, e])
		if c.player_id > 0 and not players.has_id(c.player_id):
			errors.append("contract %d: player %d does not exist" % [c.id, c.player_id])
		if c.team_id > 0 and not teams.has_id(c.team_id):
			errors.append("contract %d: team %d does not exist" % [c.id, c.team_id])
		if c.status == FcContract.Status.ACTIVE:
			if active_by_player.has(c.player_id):
				errors.append("player %d has more than one active contract" % c.player_id)
			active_by_player[c.player_id] = c

	var rostered := {}
	for t in teams.all():
		for pid in t.roster.player_ids:
			var p: FcPlayer = players.get_by_id(pid)
			if p == null:
				errors.append("team %d: roster player %d does not exist" % [t.id, pid])
				continue
			if rostered.has(pid):
				errors.append("player %d is on rosters of teams %d and %d" % [pid, rostered[pid], t.id])
			rostered[pid] = t.id
			if p.status == FcPlayer.Status.RETIRED:
				errors.append("team %d: roster player %d is retired" % [t.id, pid])
			var contract: FcContract = active_by_player.get(pid, null)
			if contract == null or contract.team_id != t.id:
				errors.append("team %d: roster player %d has no active contract with this team" % [t.id, pid])
	return errors


func to_dict() -> Dictionary:
	return {
		"schema": SCHEMA_VERSION,
		"ids": ids.to_dict(),
		"cities": _dicts_of(cities),
		"arenas": _dicts_of(arenas),
		"teams": _dicts_of(teams),
		"players": _dicts_of(players),
		"contracts": _dicts_of(contracts),
	}


## Rebuilds a world from a snapshot. Entities that cannot be added (duplicate
## or invalid id) are reported in the returned `errors` array.
static func from_dict(data: Dictionary, defs: FcDefinitionSet, errors: Array[String] = []) -> FcWorld:
	var w := FcWorld.new(defs)
	w.ids.from_dict(data.get("ids", {}))
	for d in data.get("cities", []):
		_report(w.cities.add(FcCity.from_dict(d)), "city", errors)
	for d in data.get("arenas", []):
		_report(w.arenas.add(FcArena.from_dict(d)), "arena", errors)
	for d in data.get("teams", []):
		_report(w.teams.add(FcTeam.from_dict(d)), "team", errors)
	for d in data.get("players", []):
		_report(w.players.add(FcPlayer.from_dict(d, defs)), "player", errors)
	for d in data.get("contracts", []):
		_report(w.contracts.add(FcContract.from_dict(d)), "contract", errors)
	return w


static func _report(err: Error, label: String, errors: Array[String]) -> void:
	if err != OK:
		errors.append("could not load %s (error %d)" % [label, err])


static func _dicts_of(repo: FcRepository) -> Array:
	var out: Array = []
	for e in repo.all():
		out.append(e.to_dict())
	return out
