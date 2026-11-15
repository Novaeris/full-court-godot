class_name FcArena
extends RefCounted
## A basketball arena. Separate from the team so renovations, replacement and
## shared arenas are possible. Facility upgrades and finances (Owner Mode)
## will build on this entity later.

const SCHEMA_VERSION := 1

var id: int
var name: String = ""
var city_id: int = 0
var capacity: int = 18000
var year_built: int = 2000


func _init(arena_id: int = 0) -> void:
	id = arena_id


func validate() -> Array[String]:
	var errors: Array[String] = []
	if id <= 0:
		errors.append("arena id must be positive")
	if FcChecks.is_blank(name):
		errors.append("arena name is required")
	if city_id <= 0:
		errors.append("arena needs a city")
	if capacity < 1000 or capacity > 60000:
		errors.append("arena capacity %d must be 1000-60000" % capacity)
	if year_built < 1800 or year_built > 2200:
		errors.append("arena year built %d is out of range" % year_built)
	return errors


func to_dict() -> Dictionary:
	return {
		"schema": SCHEMA_VERSION, "id": id, "name": name, "city_id": city_id,
		"capacity": capacity, "year_built": year_built,
	}


static func from_dict(data: Dictionary) -> FcArena:
	var a := FcArena.new(int(data.get("id", 0)))
	a.name = str(data.get("name", ""))
	a.city_id = int(data.get("city_id", 0))
	a.capacity = int(data.get("capacity", a.capacity))
	a.year_built = int(data.get("year_built", a.year_built))
	return a
