class_name FcDivision
extends RefCounted
## A group of teams inside a conference. Holds team IDs (membership lives
## here, not on the team, like a roster). Has its own stable ID.

var id: int
var name: String = ""
var team_ids: Array[int] = []


func _init(division_id: int = 0, division_name: String = "") -> void:
	id = division_id
	name = division_name


func validate() -> Array[String]:
	var errors: Array[String] = []
	if id <= 0:
		errors.append("division id must be positive")
	if FcChecks.is_blank(name):
		errors.append("division %d needs a name" % id)
	return errors


func to_dict() -> Dictionary:
	return {"id": id, "name": name, "team_ids": team_ids.duplicate()}


static func from_dict(data: Dictionary) -> FcDivision:
	var d := FcDivision.new(int(data.get("id", 0)), str(data.get("name", "")))
	for t in data.get("team_ids", []):
		d.team_ids.append(int(t))
	return d
