class_name FcTeamBranding
extends RefCounted
## Visual identity. Kept separate from FcTeamIdentity because a franchise can
## rebrand (new colors/logo) without changing who it is. Colors are "#RRGGBB".
## `logo_key` names a logo asset; no art exists yet, so it is just a key.

var primary_color: String = "#1F3A5F"
var secondary_color: String = "#FFFFFF"
var accent_color: String = "#C8A951"
var logo_key: String = ""


func validate() -> Array[String]:
	var errors: Array[String] = []
	for entry in [["primary", primary_color], ["secondary", secondary_color], ["accent", accent_color]]:
		if not FcChecks.is_hex_color(entry[1]):
			errors.append("%s color '%s' must be #RRGGBB" % [entry[0], entry[1]])
	return errors


func to_dict() -> Dictionary:
	return {
		"primary_color": primary_color, "secondary_color": secondary_color,
		"accent_color": accent_color, "logo_key": logo_key,
	}


static func from_dict(data: Dictionary) -> FcTeamBranding:
	var b := FcTeamBranding.new()
	b.primary_color = str(data.get("primary_color", b.primary_color))
	b.secondary_color = str(data.get("secondary_color", b.secondary_color))
	b.accent_color = str(data.get("accent_color", b.accent_color))
	b.logo_key = str(data.get("logo_key", ""))
	return b
