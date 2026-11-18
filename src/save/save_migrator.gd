class_name FcSaveMigrator
extends RefCounted
## Upgrades old save data to the current layout, one version step at a time.
##
## When DATA_VERSION (src/core/version.gd) goes from N to N+1, register a step
## for N here that converts a version-N payload Dictionary into version N+1.
## A save from version 1 loaded by version 4 passes through steps 1->2, 2->3
## and 3->4 in order. Steps must never be edited after release.
##
## Built-in steps: 1 -> 2 (Career Mode) adds the empty `career_profiles` list. Tests may register their own
## steps, which replace a built-in step with the same number.

var _steps: Dictionary = {}


func _init() -> void:
	register(1, _v1_to_v2)


## Version 2 added the Career Mode section. A version-1 save has no career, so it gets an empty list.
func _v1_to_v2(payload: Dictionary) -> Dictionary:
	var out := payload.duplicate(true)
	if not out.has("career_profiles"):
		out["career_profiles"] = []
	return out


## `step` is a Callable taking the payload Dictionary and returning the
## upgraded Dictionary (or null if it cannot be upgraded).
func register(from_version: int, step: Callable) -> void:
	_steps[from_version] = step


## Returns {"ok": bool, "payload": Dictionary, "message": String}.
func migrate(payload: Dictionary, from_version: int, to_version: int) -> Dictionary:
	var current := payload
	var v := from_version
	while v < to_version:
		if not _steps.has(v):
			return {"ok": false, "payload": payload,
				"message": "no migration from save version %d to %d" % [v, v + 1]}
		var result = _steps[v].call(current)
		if not (result is Dictionary):
			return {"ok": false, "payload": payload,
				"message": "migration from save version %d failed" % v}
		current = result
		v += 1
	return {"ok": true, "payload": current, "message": ""}
