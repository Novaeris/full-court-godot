class_name FcLegacy
extends RefCounted
## The legacy of a Career player (data/career/legacy.json): five pillars (production, honours, longevity, public image, character), each
## 0-100 with a weight, a total and a tier name, the key moments from the timeline, Hall of Fame status and a retired number if the
## club honoured one. Derived every time from the profile and what the world keeps forever, so it is never saved (same idea as
## FcRecords) and always agrees with the data. Works for a running career ("so far") and a finished one.

const PILLARS := ["production", "honours", "longevity", "public_image", "character"]

static var _cache: Dictionary = {}


static func rules() -> Dictionary:
	if _cache.is_empty():
		var file := FileAccess.open("res://data/career/legacy.json", FileAccess.READ)
		var parsed = FcChecks.parse_json(file.get_as_text()) if file != null else null
		_cache = parsed if parsed is Dictionary else {}
	return _cache


static func _num(path: Array, fallback: float) -> float:
	var node: Variant = rules()
	for key in path:
		if node is Dictionary and (node as Dictionary).has(key):
			node = (node as Dictionary)[key]
		else:
			return fallback
	return float(node)


static func _scaled(value: float, full_at: float) -> int:
	return clampi(roundi(value / maxf(0.0001, full_at) * 100.0), 0, 100)


## The words for a pillar at a score: one of the four lines, by quarter.
static func line_for(pillar: String, score: int) -> String:
	var lines: Array = (rules().get("lines", {}) as Dictionary).get(pillar, [])
	if lines.is_empty():
		return ""
	return str(lines[mini(lines.size() - 1, floori(score / 25.0))])


## The tier name for a total score.
static func tier_for(total_score: int) -> String:
	var out := ""
	for row in rules().get("tiers", []):
		if total_score >= int(row[0]):
			out = str(row[1])
	return out


## The pillar scores for one career (0-100 each). `records` is an FcRecords for the career's league.
static func pillars(profile: FcCareerProfile, records: FcRecords) -> Dictionary:
	var h := records.honours_of(profile.player_id)
	var honours := float(h["mvp"]) * _num(["honours", "mvp"], 25) + float(h["finals_mvp"]) * _num(["honours", "finals_mvp"], 15) \
		+ float(h["titles"]) * _num(["honours", "title"], 12) + float(h["all_league_first"]) * _num(["honours", "all_league_first"], 10) \
		+ float(h["scoring_titles"]) * _num(["honours", "scoring_title"], 8)
	var image := profile.fan_favor * _num(["public_image", "fan_weight"], 0.45) + profile.media_image * _num(["public_image", "media_weight"], 0.35) \
		+ profile.hype * _num(["public_image", "hype_weight"], 0.2)
	var good := 0
	var bad := 0
	var good_tags: Array = (rules().get("character", {}) as Dictionary).get("good_tags", [])
	var bad_tags: Array = (rules().get("character", {}) as Dictionary).get("bad_tags", [])
	for tag in profile.tags:
		if good_tags.has(tag):
			good += 1
		elif bad_tags.has(tag):
			bad += 1
	var character := float(good) * _num(["character", "per_tag"], 25) - float(bad) * _num(["character", "bad_cost"], 15)
	return {
		"production": _scaled(records.score_of(profile.player_id), _num(["production", "full_at"], 120)),
		"honours": _scaled(honours, _num(["honours", "full_at"], 60)),
		"longevity": _scaled(float(profile.history.size()), _num(["longevity", "full_at"], 18)),
		"public_image": clampi(roundi(image), 0, 100),
		"character": clampi(roundi(character), 0, 100)}


## The weighted total, 0-100.
static func total(scores: Dictionary) -> int:
	var sum := 0.0
	var weights: Dictionary = rules().get("weights", {})
	for key in weights:
		sum += float(scores.get(key, 0)) * float(weights[key])
	return clampi(roundi(sum), 0, 100)


## The whole picture:
## {"total", "tier", "pillars": [{"key", "label", "score", "line"}], "moments": [timeline rows], "seasons", "hall_of_fame": "inducted" |
## "eligible" | "no", "inducted_year", "retired_number": {"team_id", "number", "ceremony"} or {}, "narrative"}.
## `current_year` is the season now; `retired` says whether the career is over.
static func summary(profile: FcCareerProfile, world: FcWorld, league_id: int, current_year: int, retired: bool) -> Dictionary:
	var records := FcRecords.new(world, league_id)
	var scores := pillars(profile, records)
	var sum_total := total(scores)
	var rows: Array = []
	var labels: Dictionary = rules().get("labels", {})
	for key in PILLARS:
		rows.append({"key": key, "label": str(labels.get(key, key)), "score": int(scores[key]), "line": line_for(key, int(scores[key]))})
	var hof := "no"
	var inducted_year := 0
	for entry in records.hall_of_fame(current_year):
		if int(entry[1]) == profile.player_id:
			hof = "inducted"
			inducted_year = int(entry[2])
	if hof == "no" and not retired and records.score_of(profile.player_id) >= FcRecords.INDUCTION_SCORE:
		hof = "eligible"
	var number := {}
	var all := FcFranchiseHistory.new(world, league_id).retired_numbers_all(current_year)
	for team_id in all:
		for row in all[team_id]:
			if int(row["player_id"]) == profile.player_id:
				number = {"team_id": int(team_id), "number": int(row["number"]), "ceremony": int(row["ceremony"])}
	var best := ""
	var best_score := -1
	for row in rows:
		if int(row["score"]) > best_score:
			best_score = int(row["score"])
			best = str(row["label"]).to_lower()
	var seasons := profile.history.size()
	var narrative := "%s: %d season%s, remembered mostly for %s." % [tier_for(sum_total), seasons, "" if seasons == 1 else "s", best]
	if hof == "inducted":
		narrative += " Inducted into the Hall of Fame in %d." % inducted_year
	elif hof == "eligible":
		narrative += " Already has a Hall of Fame resume."
	if not number.is_empty():
		narrative += " Shirt number %d retired by %s." % [int(number["number"]), world.team_display_name(int(number["team_id"]))]
	return {"total": sum_total, "tier": tier_for(sum_total), "pillars": rows, "moments": FcCareerTimeline.key_moments(profile, 8), "seasons": seasons,
		"hall_of_fame": hof, "inducted_year": inducted_year, "retired_number": number, "narrative": narrative}
