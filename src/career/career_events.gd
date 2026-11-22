class_name FcCareerEvents
extends RefCounted
## Career decisions (data/career/events.json): which event is offered, and what a choice does. Pure and seeded, like the other
## career rules. Every choice changes the career for real (XP, points, reputation, currency, tags); none is cosmetic.

static var _cache: Dictionary = {}


static func _load() -> Dictionary:
	if _cache.is_empty():
		var file := FileAccess.open("res://data/career/events.json", FileAccess.READ)
		var parsed = FcChecks.parse_json(file.get_as_text()) if file != null else null
		_cache = parsed if parsed is Dictionary else {"events": []}
	return _cache


static func all() -> Array:
	return _load().get("events", [])


static func get_event(key: String) -> Dictionary:
	for e in all():
		if e["key"] == key:
			return e
	return {}


## Events the profile can be offered now: its level is high enough and it has not answered this event in the last
## `repeat_after_seasons` years (decisions are not repeated every season).
static func eligible(profile: FcCareerProfile, year: int) -> Array:
	var out: Array = []
	for e in all():
		if profile.level < int(e["when"].get("min_level", 1)):
			continue
		var last := 0
		for d in profile.decisions:
			if d["key"] == e["key"]:
				last = maxi(last, int(d["year"]))
		if last > 0 and year - last < 4:
			continue
		out.append(e)
	return out


## Chooses one eligible event for `year` with a seeded draw (the same profile and year always get the same event), or "" if none.
static func pick(profile: FcCareerProfile, year: int, rng: FcRng) -> String:
	var options := eligible(profile, year)
	if options.is_empty():
		return ""
	return str(options[rng.range_int(0, options.size() - 1)]["key"])


## Applies a choice to the profile: effects, tag and the decision log. Returns {"ok", "reason", "effects"}.
static func apply_choice(profile: FcCareerProfile, event_key: String, choice_key: String, year: int) -> Dictionary:
	var event := get_event(event_key)
	if event.is_empty():
		return {"ok": false, "reason": "Unknown event."}
	var choice := {}
	for c in event["choices"]:
		if c["key"] == choice_key:
			choice = c
	if choice.is_empty():
		return {"ok": false, "reason": "That is not one of the choices."}
	for d in profile.decisions:
		if d["key"] == event_key and int(d["year"]) == year:
			return {"ok": false, "reason": "You already decided this."}
	var effects: Dictionary = choice["effects"]
	if effects.has("xp"):
		FcCareerRules.award_xp(profile, int(effects["xp"]))
	profile.development_points += int(effects.get("development_points", 0))
	profile.skill_points += int(effects.get("skill_points", 0))
	profile.reputation = maxi(0, profile.reputation + int(effects.get("reputation", 0)))
	profile.currency = maxi(0, profile.currency + int(effects.get("currency", 0)))
	var tag := str(choice.get("tag", ""))
	if tag != "" and not profile.tags.has(tag):
		profile.tags.append(tag)
	profile.decisions.append({"year": year, "key": event_key, "choice": choice_key})
	FcCareerTimeline.add(profile, year, "decision", "%s: %s" % [str(event["title"]), str(choice["label"])])
	if profile.pending_event == event_key:
		profile.pending_event = ""
	return {"ok": true, "reason": "%s: %s" % [choice["label"], choice.get("note", "")], "effects": effects.duplicate()}
