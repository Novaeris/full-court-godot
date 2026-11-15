class_name FcRepository
extends RefCounted
## The persistence abstraction: how game systems store and find entities by ID.
## Game code talks ONLY to this interface, never to a specific storage engine.
## FcMemoryRepository is the current implementation; a SQLite-backed one can
## be added later without changing any game system.
##
## Entities must have an integer `id` property (> 0).
## Methods below are abstract: implementations override them.


## The entity with this id, or null.
func get_by_id(_id: int):
	push_error("FcRepository.get_by_id not implemented")
	return null


func has_id(_id: int) -> bool:
	push_error("FcRepository.has_id not implemented")
	return false


## Inserts a new entity. OK, ERR_INVALID_PARAMETER (id <= 0) or ERR_ALREADY_EXISTS.
func add(_entity) -> Error:
	push_error("FcRepository.add not implemented")
	return ERR_UNAVAILABLE


## Replaces an existing entity. OK or ERR_DOES_NOT_EXIST.
func update(_entity) -> Error:
	push_error("FcRepository.update not implemented")
	return ERR_UNAVAILABLE


## OK or ERR_DOES_NOT_EXIST.
func remove(_id: int) -> Error:
	push_error("FcRepository.remove not implemented")
	return ERR_UNAVAILABLE


## All ids in ascending order.
func ids() -> Array[int]:
	push_error("FcRepository.ids not implemented")
	return []


func count() -> int:
	push_error("FcRepository.count not implemented")
	return 0


## All entities in ascending id order.
func all() -> Array:
	var out: Array = []
	for i in ids():
		out.append(get_by_id(i))
	return out
