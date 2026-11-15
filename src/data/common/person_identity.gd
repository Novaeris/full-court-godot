class_name FcPersonIdentity
extends RefCounted
## Who a person is: name and biography. Shared by players and staff. Does not change during
## a career (except nickname).

var first_name: String = ""
var last_name: String = ""
var nickname: String = ""
var birth_date: FcDate = FcDate.new(2000, 1, 1)
var birthplace: String = ""
var country: String = ""


func full_name() -> String:
	return ("%s %s" % [first_name, last_name]).strip_edges()


func validate() -> Array[String]:
	var errors: Array[String] = []
	if FcChecks.is_blank(first_name):
		errors.append("first name is required")
	if FcChecks.is_blank(last_name):
		errors.append("last name is required")
	if FcChecks.is_blank(country):
		errors.append("country is required")
	if not birth_date.is_valid():
		errors.append("birth date is not a valid date")
	elif birth_date.year < 1900 or birth_date.year > 2100:
		errors.append("birth year %d is out of range" % birth_date.year)
	return errors


func to_dict() -> Dictionary:
	return {
		"first_name": first_name, "last_name": last_name, "nickname": nickname,
		"birth_date": birth_date.to_iso(), "birthplace": birthplace, "country": country,
	}


static func from_dict(data: Dictionary) -> FcPersonIdentity:
	var i := FcPersonIdentity.new()
	i.first_name = str(data.get("first_name", ""))
	i.last_name = str(data.get("last_name", ""))
	i.nickname = str(data.get("nickname", ""))
	var bd := FcDate.from_iso(str(data.get("birth_date", "")))
	if bd != null:
		i.birth_date = bd
	else:
		i.birth_date = FcDate.new(0, 0, 0) # invalid on purpose so validate() reports it
	i.birthplace = str(data.get("birthplace", ""))
	i.country = str(data.get("country", ""))
	return i
