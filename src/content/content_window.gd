class_name FcContentWindow
extends RefCounted
## The shared "is this published thing available right now" rule (D-067) for sets and tournaments: an optional start and end given as
## whole unix seconds (UTC). Nothing here knows about sets or tournaments, so both use one rule. A definition with neither field is
## ALWAYS available. A window never removes what a player already owns: callers use it only to decide what can be bought or entered.

const ALWAYS := "always"
const UPCOMING := "upcoming"
const ACTIVE := "active"
const ENDED := "ended"


## The status of a definition at `now`: always | upcoming | active | ended. The end moment itself is already ended.
static func status(def: Dictionary, now: int) -> String:
	if not def.has("starts_at") and not def.has("ends_at"):
		return ALWAYS
	if def.has("starts_at") and now < _int(def["starts_at"]):
		return UPCOMING
	if def.has("ends_at") and now >= _int(def["ends_at"]):
		return ENDED
	return ACTIVE


## Whether the definition can be bought or entered at `now`.
static func is_open(def: Dictionary, now: int) -> bool:
	var s := status(def, now)
	return s == ALWAYS or s == ACTIVE


## Seconds left until the end (0 when there is no end or it has passed).
static func seconds_left(def: Dictionary, now: int) -> int:
	if not def.has("ends_at"):
		return 0
	return maxi(0, _int(def["ends_at"]) - now)


## Short plain text for a screen: "Ends in 3 days", "Starts in 5 hours", "Ended", or "" for an always-open definition.
static func describe(def: Dictionary, now: int) -> String:
	match status(def, now):
		UPCOMING:
			return "Starts in %s" % _span(_int(def["starts_at"]) - now)
		ACTIVE:
			return "Ends in %s" % _span(seconds_left(def, now)) if def.has("ends_at") else ""
		ENDED:
			return "Ended"
	return ""


## Publish-time problems with the window fields of one definition (empty = fine).
static func problems(path: String, def: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for key in ["starts_at", "ends_at"]:
		if def.has(key) and _int(def[key]) < 1:
			errors.append("%s: %s must be a whole number of unix seconds (UTC), 1 or more" % [path, key])
	if errors.is_empty() and def.has("starts_at") and def.has("ends_at") and _int(def["ends_at"]) <= _int(def["starts_at"]):
		errors.append("%s: ends_at must be later than starts_at" % path)
	return errors


static func _span(seconds: int) -> String:
	if seconds >= 172800:
		return "%d days" % floori(float(seconds) / 86400.0)
	if seconds >= 3600:
		var hours := floori(float(seconds) / 3600.0)
		return "%d hour%s" % [hours, "" if hours == 1 else "s"]
	var minutes := maxi(1, floori(float(seconds) / 60.0))
	return "%d minute%s" % [minutes, "" if minutes == 1 else "s"]


static func _int(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, floorf(value)):
		return int(value)
	return -1
