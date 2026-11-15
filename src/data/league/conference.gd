class_name FcConference
extends RefCounted
## A conference: a named group of divisions. Has its own stable ID.

var id: int
var name: String = ""
var divisions: Array[FcDivision] = []


func _init(conference_id: int = 0, conference_name: String = "") -> void:
	id = conference_id
	name = conference_name


func validate() -> Array[String]:
	var errors: Array[String] = []
	if id <= 0:
		errors.append("conference id must be positive")
	if FcChecks.is_blank(name):
		errors.append("conference %d needs a name" % id)
	if divisions.is_empty():
		errors.append("conference '%s' needs at least one division" % name)
	for d in divisions:
		errors.append_array(d.validate())
	return errors


func to_dict() -> Dictionary:
	var div_dicts: Array = []
	for d in divisions:
		div_dicts.append(d.to_dict())
	return {"id": id, "name": name, "divisions": div_dicts}


static func from_dict(data: Dictionary) -> FcConference:
	var c := FcConference.new(int(data.get("id", 0)), str(data.get("name", "")))
	for d in data.get("divisions", []):
		c.divisions.append(FcDivision.from_dict(d))
	return c
