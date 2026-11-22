class_name FcDynastyMigrator
extends RefCounted
## Upgrades an older Dynasty profile file to the current layout one version at a time (same idea as FcSaveMigrator, but
## for the separate Dynasty file). When FcVersion.DYNASTY_DATA_VERSION goes from N to N+1, register a step for N.
## Steps must never be edited after release.
##
## Built-in steps: 1 -> 2 (play-by-play) gives the profile an empty `replays` list; 2 -> 3 (ranked ladder) gives it the starting ladder; 3 -> 4 (collection goals) gives it an empty claimed list. Tests may register their own steps, which
## replace a built-in step with the same number.

var _steps: Dictionary = {}


func _init() -> void:
	register(1, _v1_to_v2)
	register(2, _v2_to_v3)
	register(3, _v3_to_v4)


## Version 2 added the last few game replays to the profile. Older profiles never kept any, so they get an empty list.
func _v1_to_v2(payload: Dictionary) -> Dictionary:
	var out := payload.duplicate(true)
	if not out.has("replays"):
		out["replays"] = []
	return out


## Version 3 added the ranked ladder. Older profiles start at the ladder's starting rating (written inline: a released step never changes).
func _v2_to_v3(payload: Dictionary) -> Dictionary:
	var out := payload.duplicate(true)
	if not out.has("ladder"):
		out["ladder"] = {"rating": 1000, "peak": 1000, "games": 0, "wins": 0, "season_id": "", "reached": [], "history": []}
	return out


## Version 4 added claimed collection goals. Older profiles have claimed none.
func _v3_to_v4(payload: Dictionary) -> Dictionary:
	var out := payload.duplicate(true)
	if not out.has("goals"):
		out["goals"] = {"claimed": []}
	return out


## `step` takes the payload Dictionary and returns the upgraded Dictionary (or null if it cannot).
func register(from_version: int, step: Callable) -> void:
	_steps[from_version] = step


## Returns {"ok": bool, "payload": Dictionary, "message": String}.
func migrate(payload: Dictionary, from_version: int, to_version: int) -> Dictionary:
	var current := payload
	var v := from_version
	while v < to_version:
		if not _steps.has(v):
			return {"ok": false, "payload": payload, "message": "no migration from Dynasty save version %d to %d" % [v, v + 1]}
		var result = _steps[v].call(current)
		if not (result is Dictionary):
			return {"ok": false, "payload": payload, "message": "migration from Dynasty save version %d failed" % v}
		current = result
		v += 1
	return {"ok": true, "payload": current, "message": ""}
