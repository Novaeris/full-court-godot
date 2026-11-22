class_name FcCareerTimeline
extends RefCounted
## The career timeline: the moments of a career in order, kept in the profile as plain rows {"year", "kind", "text"} (whole numbers and text
## only, so it saves without precision problems). The controller adds a row whenever something worth remembering happens (signing, a season,
## an award or title, a milestone or level, an injury, a decision, a contract, a rival, a sponsor, retirement); the screens read it; the
## legacy summary picks its key moments from it. Pure: it only edits the profile it is given.

## Newest rows win: the oldest are dropped beyond this, so a 20-year career cannot grow a save without bound.
const LIMIT := 300

const KINDS := ["team", "season", "award", "title", "milestone", "level", "injury", "decision", "contract", "rival", "sponsor", "game", "retired"]

## How memorable each kind is, for the legacy summary's "key moments" (bigger first).
const WEIGHT := {"title": 100, "award": 90, "retired": 80, "rival": 50, "injury": 45, "contract": 40, "team": 35, "milestone": 30, "game": 28,
	"decision": 25, "sponsor": 20, "level": 15, "season": 10}


## Adds a row. An identical row (same year, kind and text) is not added twice, so a retried step never doubles a moment. Returns whether it was added.
static func add(profile: FcCareerProfile, year: int, kind: String, text: String) -> bool:
	if not KINDS.has(kind) or text.strip_edges() == "":
		return false
	for row in profile.timeline:
		if int(row["year"]) == year and str(row["kind"]) == kind and str(row["text"]) == text:
			return false
	profile.timeline.append({"year": year, "kind": kind, "text": text})
	while profile.timeline.size() > LIMIT:
		profile.timeline.pop_front()
	return true


## The rows, oldest first (the order they were added, which is the order they happened).
static func entries(profile: FcCareerProfile) -> Array:
	return profile.timeline


## Rows grouped by year: {year: [rows]}.
static func by_year(profile: FcCareerProfile) -> Dictionary:
	var out := {}
	for row in profile.timeline:
		var year := int(row["year"])
		if not out.has(year):
			out[year] = []
		(out[year] as Array).append(row)
	return out


## The years that have rows, oldest first.
static func years(profile: FcCareerProfile) -> Array:
	var list: Array = by_year(profile).keys()
	list.sort()
	return list


## The `count` most memorable rows (by kind weight, then the more recent), returned in the order they happened.
static func key_moments(profile: FcCareerProfile, count: int = 6) -> Array:
	var ranked: Array = []
	for i in profile.timeline.size():
		ranked.append([int(WEIGHT.get(str(profile.timeline[i]["kind"]), 5)), i])
	ranked.sort_custom(func(a, b) -> bool: return a[0] > b[0] if a[0] != b[0] else a[1] > b[1])
	var chosen: Array = []
	for pair in ranked.slice(0, count):
		chosen.append(pair[1])
	chosen.sort()
	var out: Array = []
	for index in chosen:
		out.append(profile.timeline[index])
	return out
