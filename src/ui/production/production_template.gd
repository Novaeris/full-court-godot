class_name FcProductionTemplate
extends RefCounted
## A broadcast production template (Broadcast pass 2, M7, D-071): an ordered list of SEGMENTS, as data in data/broadcast/templates/<id>.json, so the
## pregame show, the halftime report, the postgame report, the championship presentation and the weekly show "Full Court Tonight" are all the
## same machinery with different lists. Adding or reordering a segment is a data edit, never code. A template names segment TYPES; what a type
## shows is built by FcProductionPlan (for one game) or FcWeeklyRecap (for a week of the league), only from recorded or saved data.
##
## Template: {id, title, scope ("game" or "week"), segments: [{type, seconds}]}.

const DIR := "res://data/broadcast/templates/"
const SCOPE_GAME := "game"
const SCOPE_WEEK := "week"

## The segment types each scope can build.
const GAME_TYPES := ["matchup", "lineups", "halftime_score", "final_score", "line_score", "storyline", "player_of_game", "team_comparison", "leaders", "milestones", "highlights", "trophy"]
const WEEK_TYPES := ["headlines", "game_of_the_week", "player_of_the_week", "best_performances", "upsets", "streaks", "standings_race", "marquee_matchups"]
const IDS := ["pregame", "halftime", "postgame", "championship", "full_court_tonight"]


## The template with this id ({} when the file is missing or damaged; callers then show nothing, never fail).
static func load_template(id: String) -> Dictionary:
	var path := DIR + id + ".json"
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## Everything wrong with a template, as readable sentences (empty = valid). Tests run it over every shipped template.
static func problems(template: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if template.is_empty():
		out.append("the template is missing or not valid JSON")
		return out
	for key in ["id", "title", "scope", "segments"]:
		if not template.has(key):
			out.append("missing %s" % key)
	if not out.is_empty():
		return out
	var scope := str(template["scope"])
	if scope != SCOPE_GAME and scope != SCOPE_WEEK:
		out.append("scope must be game or week")
	var allowed: Array = GAME_TYPES if scope == SCOPE_GAME else WEEK_TYPES
	if (template["segments"] as Array).is_empty():
		out.append("a template needs at least one segment")
	var seen := {}
	for seg in template["segments"]:
		if not (seg is Dictionary) or not (seg as Dictionary).has("type") or not (seg as Dictionary).has("seconds"):
			out.append("every segment needs a type and seconds")
			continue
		var type := str(seg["type"])
		if not (type in allowed):
			out.append("%s is not a %s segment type" % [type, scope])
		if float(seg["seconds"]) <= 0.0:
			out.append("%s needs seconds above 0" % type)
		if seen.has(type):
			out.append("%s appears twice" % type)
		seen[type] = true
	return out


## The segment list of a template: [{type, seconds}].
static func segments(template: Dictionary) -> Array:
	return (template.get("segments", []) as Array).duplicate(true)
