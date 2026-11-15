class_name FcIdGenerator
extends RefCounted
## Hands out stable integer IDs, one counter per kind of entity
## (e.g. "player", "team", "coach"). IDs are never reused, even after a
## player retires, so history and saves can always refer to them safely.
##
## The counters are part of the save file (see to_dict / from_dict).

var _counters: Dictionary = {}


## Returns the next unused ID for this kind. The first ID is 1; 0 means "none".
func next_id(kind: String) -> int:
	var value: int = int(_counters.get(kind, 0)) + 1
	_counters[kind] = value
	return value


## How many IDs have been issued for this kind so far.
func issued_count(kind: String) -> int:
	return int(_counters.get(kind, 0))


func to_dict() -> Dictionary:
	return _counters.duplicate()


func from_dict(data: Dictionary) -> void:
	_counters.clear()
	for kind in data:
		_counters[str(kind)] = int(data[kind])
