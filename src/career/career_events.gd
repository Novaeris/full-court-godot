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


const EFFECT_KEYS := ["xp", "development_points", "skill_points", "reputation", "currency", "fan_favor", "media_image", "hype", "coach_trust", "chemistry"]
const WHEN_KEYS := ["min_level", "max_level", "min_seasons", "min_reputation", "requires_tags", "excludes_tags", "min_fan_favor", "max_fan_favor",
	"min_media_image", "max_media_image", "min_hype", "max_hype", "min_coach_trust", "max_coach_trust", "has_rival", "repeat_after"]


## Whether the profile's situation fits an event's `when` block (all the conditions in it must hold). Every key is optional.
static func meets(profile: FcCareerProfile, when: Dictionary) -> bool:
	if profile.level < int(when.get("min_level", 1)) or profile.level > int(when.get("max_level", 999)):
		return false
	if profile.history.size() < int(when.get("min_seasons", 0)) or profile.reputation < int(when.get("min_reputation", 0)):
		return false
	for tag in when.get("requires_tags", []):
		if not profile.tags.has(str(tag)):
			return false
	for tag in when.get("excludes_tags", []):
		if profile.tags.has(str(tag)):
			return false
	for pair in [["fan_favor", profile.fan_favor], ["media_image", profile.media_image], ["hype", profile.hype], ["coach_trust", profile.coach_trust]]:
		if int(pair[1]) < int(when.get("min_" + str(pair[0]), 0)) or int(pair[1]) > int(when.get("max_" + str(pair[0]), 100)):
			return false
	if when.has("has_rival") and (profile.rival_player_id > 0) != bool(when["has_rival"]):
		return false
	return true


## Events the profile can be offered now: its situation fits the event's `when` block and it has not answered this event in the last
## `repeat_after` years (default 4; decisions are not repeated every season).
static func eligible(profile: FcCareerProfile, year: int) -> Array:
	var out: Array = []
	for e in all():
		if not meets(profile, e["when"]):
			continue
		var last := 0
		for d in profile.decisions:
			if d["key"] == e["key"]:
				last = maxi(last, int(d["year"]))
		if last > 0 and year - last < int(e["when"].get("repeat_after", 4)):
			continue
		out.append(e)
	return out


## Problems in the event data (empty when it is sound): unique keys, 2+ choices each, only known effect and condition keys, and no choice that
## changes nothing unless it says so in its note.
static func validate() -> Array:
	var problems: Array = []
	var keys := {}
	for e in all():
		var k := str(e.get("key", ""))
		if k == "" or keys.has(k):
			problems.append("event key %s is missing or repeated" % k)
		keys[k] = true
		for w in e.get("when", {}):
			if not WHEN_KEYS.has(w):
				problems.append("%s: unknown condition %s" % [k, w])
		var choices: Array = e.get("choices", [])
		if choices.size() < 2:
			problems.append("%s offers no real choice" % k)
		var seen := {}
		for c in choices:
			if seen.has(c.get("key", "")):
				problems.append("%s: repeated choice key" % k)
			seen[c.get("key", "")] = true
			for f in c.get("effects", {}):
				if not EFFECT_KEYS.has(f):
					problems.append("%s: unknown effect %s" % [k, f])
			if (c.get("effects", {}) as Dictionary).is_empty() and str(c.get("note", "")) == "":
				problems.append("%s/%s changes nothing and does not say so" % [k, c.get("key", "")])
	return problems


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
	FcCareerMedia.apply(profile, effects)
	profile.coach_trust = clampi(profile.coach_trust + int(effects.get("coach_trust", 0)), 0, 100)
	profile.chemistry = clampi(profile.chemistry + int(effects.get("chemistry", 0)), 0, 100)
	var tag := str(choice.get("tag", ""))
	if tag != "" and not profile.tags.has(tag):
		profile.tags.append(tag)
	profile.decisions.append({"year": year, "key": event_key, "choice": choice_key})
	FcCareerTimeline.add(profile, year, "decision", "%s: %s" % [str(event["title"]), str(choice["label"])])
	if profile.pending_event == event_key:
		profile.pending_event = ""
	return {"ok": true, "reason": "%s: %s" % [choice["label"], choice.get("note", "")], "effects": effects.duplicate()}
