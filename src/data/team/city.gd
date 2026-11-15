class_name FcCity
extends RefCounted
## A fictional city. Provides the "market" a team operates in. A separate
## entity (not part of the team) so teams can relocate and so several things
## (arenas, players' birthplaces later) can refer to the same city.

const SCHEMA_VERSION := 1

var id: int
var name: String = ""
var region: String = ""
var country: String = ""
## Metro population. Drives market size.
var population: int = 1000000
## Local wealth, 0-100. Drives ticket/sponsor spending power.
var economy_index: int = 50


func _init(city_id: int = 0) -> void:
	id = city_id


func validate() -> Array[String]:
	var errors: Array[String] = []
	if id <= 0:
		errors.append("city id must be positive")
	if FcChecks.is_blank(name):
		errors.append("city name is required")
	if FcChecks.is_blank(country):
		errors.append("city country is required")
	if population < 1000:
		errors.append("city population must be at least 1000")
	if economy_index < 0 or economy_index > 100:
		errors.append("economy index must be 0-100")
	return errors


func to_dict() -> Dictionary:
	return {
		"schema": SCHEMA_VERSION, "id": id, "name": name, "region": region,
		"country": country, "population": population, "economy_index": economy_index,
	}


static func from_dict(data: Dictionary) -> FcCity:
	var c := FcCity.new(int(data.get("id", 0)))
	c.name = str(data.get("name", ""))
	c.region = str(data.get("region", ""))
	c.country = str(data.get("country", ""))
	c.population = int(data.get("population", c.population))
	c.economy_index = int(data.get("economy_index", c.economy_index))
	return c
