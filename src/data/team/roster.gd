class_name FcRoster
extends RefCounted
## The players currently on a team, as a list of player IDs. This is the
## CHANGING part of a team (trades, signings, retirements). The roster is the
## single source of truth for "who is on this team".
## max_size will come from league rules later; the default is a typical limit.

const DEFAULT_MAX_SIZE := 15

var max_size: int = DEFAULT_MAX_SIZE
var player_ids: Array[int] = []


func size() -> int:
	return player_ids.size()


func contains(player_id: int) -> bool:
	return player_ids.has(player_id)


func is_full() -> bool:
	return player_ids.size() >= max_size


## OK, ERR_INVALID_PARAMETER (bad id), ERR_ALREADY_EXISTS, or
## ERR_PARAMETER_RANGE_ERROR (roster full).
func add(player_id: int) -> Error:
	if player_id <= 0:
		return ERR_INVALID_PARAMETER
	if contains(player_id):
		return ERR_ALREADY_EXISTS
	if is_full():
		return ERR_PARAMETER_RANGE_ERROR
	player_ids.append(player_id)
	return OK


## OK, or ERR_DOES_NOT_EXIST if the player is not on the roster.
func remove(player_id: int) -> Error:
	var index := player_ids.find(player_id)
	if index < 0:
		return ERR_DOES_NOT_EXIST
	player_ids.remove_at(index)
	return OK


func validate() -> Array[String]:
	var errors: Array[String] = []
	if max_size < 1:
		errors.append("roster max size must be at least 1")
	if player_ids.size() > max_size:
		errors.append("roster has %d players but max is %d" % [player_ids.size(), max_size])
	var seen := {}
	for pid in player_ids:
		if pid <= 0:
			errors.append("roster contains invalid player id %d" % pid)
		if seen.has(pid):
			errors.append("roster contains player %d twice" % pid)
		seen[pid] = true
	return errors


func to_dict() -> Dictionary:
	return {"max_size": max_size, "player_ids": player_ids.duplicate()}


static func from_dict(data: Dictionary) -> FcRoster:
	var r := FcRoster.new()
	r.max_size = int(data.get("max_size", DEFAULT_MAX_SIZE))
	for pid in data.get("player_ids", []):
		r.player_ids.append(int(pid))
	return r
