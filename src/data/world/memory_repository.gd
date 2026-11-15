class_name FcMemoryRepository
extends FcRepository
## In-memory FcRepository backed by a Dictionary (id -> entity). O(1) lookup.

var _items: Dictionary = {}


func get_by_id(id: int):
	return _items.get(id, null)


func has_id(id: int) -> bool:
	return _items.has(id)


func add(entity) -> Error:
	if entity.id <= 0:
		return ERR_INVALID_PARAMETER
	if _items.has(entity.id):
		return ERR_ALREADY_EXISTS
	_items[entity.id] = entity
	return OK


func update(entity) -> Error:
	if not _items.has(entity.id):
		return ERR_DOES_NOT_EXIST
	_items[entity.id] = entity
	return OK


func remove(id: int) -> Error:
	if not _items.has(id):
		return ERR_DOES_NOT_EXIST
	_items.erase(id)
	return OK


func ids() -> Array[int]:
	var out: Array[int] = []
	for k in _items:
		out.append(int(k))
	out.sort()
	return out


func count() -> int:
	return _items.size()
