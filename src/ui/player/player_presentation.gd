class_name FcPlayerPresentation
extends RefCounted
## One READ-ONLY view-model of a player, whatever the mode: an Owner Mode player, the Career player, or a Dynasty card all become the
## same dictionary, so the profile (and every list, comparison and result line) is built once. Nothing here writes to game data.
## Fields: mode, subject (for FcPlayerVisual), name, jersey, position, secondary, archetype, playstyle {label, text}, team {name, abbreviation,
## primary, secondary}, physical {height_cm, weight_kg, wingspan_cm, hand}, overall, potential, age, attributes [{key, name, category, value}],
## badges [{key, name, description}], stats {columns, rows}, history {columns, rows}, awards [text], progression {kind, ...}.
## Sections a mode has no data for are left empty and the profile hides them; nothing is invented.
##
## Keys (the visual identity): Owner "owner_player:<id>", Career "career_player:<id>", Dynasty "dynasty_player:<player_id>" (so every edition
## of one real player looks the same).

const HAND_NAMES := ["Right", "Left", "Both"]


## The subject FcPlayerVisual.resolve needs, built the same way by every screen.
static func subject(key: String, name: String, team: Dictionary = {}, jersey: int = 0, appearance: Dictionary = {}, art_path: String = "", extra: Dictionary = {}) -> Dictionary:
	var out := {"key": key, "name": name, "team": team, "jersey": jersey, "appearance": appearance, "art_path": art_path}
	out.merge(extra, true)   # optional presentation inputs: age, physical {height_cm, weight_kg}, position
	return out


## The date ages are counted from on screen (UI only, set by FcApp whenever a screen is built from a running game). null: no age is passed and
## the figure uses a stable age derived from the player's key.
static var reference_date: FcDate = null


## A Dynasty card row (FcCollectionQuery) as a subject: the real player's id is the key, so editions share a face.
static func subject_for_card(row: Dictionary) -> Dictionary:
	return subject("dynasty_player:%s" % str(row.get("player_id", row.get("card_id", ""))), str(row.get("name", "?")), {"name": str(row.get("team", ""))}, 0, {}, str(row.get("art_path", "")))


## An Owner Mode (or Career) world player as a subject.
static func subject_for_player(world: FcWorld, player_id: int, prefix: String = "owner_player") -> Dictionary:
	var p: FcPlayer = world.players.get_by_id(player_id)
	var team: FcTeam = world.team_of_player(player_id)
	var extra := {}
	if p != null:
		extra["physical"] = {"height_cm": p.physical.height_cm, "weight_kg": p.physical.weight_kg}
		extra["position"] = FcPosition.abbreviation(p.primary_position)
		if reference_date != null:
			extra["age"] = p.age_on(reference_date)
	return subject("%s:%d" % [prefix, player_id], p.identity.full_name() if p != null else "?", _team_dict(world, team), 0, {}, "", extra)


static func _team_dict(world: FcWorld, team: FcTeam) -> Dictionary:
	if team == null:
		return {}
	return {"name": world.team_display_name(team.id), "abbreviation": team.identity.abbreviation, "primary": team.branding.primary_color, "secondary": team.branding.secondary_color}


# --- Dynasty card ---------------------------------------------------------------------------------------------------------

static func from_card(row: Dictionary, ctl: FcDynastyController) -> Dictionary:
	var card_id := str(row["card_id"])
	var attrs: Dictionary = row.get("attributes", {})
	var composites := {}
	if bool(row.get("available", true)) and ctl.catalog.has_card(card_id):
		composites = ctl.catalog.ratings.compute(ctl.catalog.make_player(card_id, 1))
	var badges: Array = []
	for b in row.get("badges", []):
		var def := FcBadges.get_badge(str(b))
		badges.append({"key": str(b), "name": str(def.get("name", b)), "description": str(def.get("description", ""))})
	var stats: Dictionary = ctl.profile().card_stats.get(card_id, {}) if ctl.has_profile_open() else {}
	var stat_rows: Array = []
	if not stats.is_empty() and int(stats["games"]) > 0:
		var g := float(stats["games"])
		stat_rows.append(["With your team", stats["games"], "%.1f" % (float(stats["points"]) / g), "%.1f" % (float(stats["rebounds"]) / g), "%.1f" % (float(stats["assists"]) / g)])
	var mastery := int(row.get("mastery", 0))
	return {
		"mode": "dynasty", "subject": subject_for_card(row), "name": str(row["name"]), "jersey": 0, "position": str(row.get("position", "")),
		"secondary": str(row.get("secondary", "")), "archetype": FcRarityStyle.label(str(row.get("rarity", "common"))) + " card", "playstyle": FcPlaystyle.summary(composites),
		"team": {"name": str(row.get("team", ""))}, "physical": {}, "overall": int(row.get("overall", 0)), "potential": 0, "age": 0,
		"attributes": _attributes(ctl.defs, attrs), "badges": badges,
		"stats": {"columns": ["", "Games", "PPG", "RPG", "APG"], "rows": stat_rows}, "history": {"columns": [], "rows": []}, "awards": [],
		"progression": {"kind": "static", "mastery": mastery, "frame": ctl.catalog.config.mastery_frame(mastery), "note": "Card ratings never change; mastery is cosmetic."},
	}


# --- Owner / Career world player ------------------------------------------------------------------------------------------------

## `league_id` lets the Owner profile list the player's honours (FcRecords). `mode` is "owner" or "career".
static func from_player(world: FcWorld, player_id: int, current_year: int, league_id: int = 0, mode: String = "owner") -> Dictionary:
	var p: FcPlayer = world.players.get_by_id(player_id)
	if p == null:
		return {}
	var team: FcTeam = world.team_of_player(player_id)
	var composites := FcPlayerRatings.load_default().compute(p)
	var rows: Array = []
	var history: Array = []
	for r in world.careers.get(player_id, []):
		var gp: int = maxi(1, r[2])
		var t: FcTeam = world.teams.get_by_id(r[1])
		var season := "%d-%02d" % [r[0], (r[0] + 1) % 100]
		var abbr := t.identity.abbreviation if t != null else "?"
		rows.append([season, abbr, r[2], "%.1f" % (r[3] / 60.0 / gp), "%.1f" % (float(r[4]) / gp), "%.1f" % (float(r[11] + r[12]) / gp), "%.1f" % (float(r[13]) / gp)])
		history.append([season, abbr, r[2], r[4], r[11] + r[12], r[13]])
	var awards: Array[String] = []
	if league_id > 0:
		var h := FcRecords.new(world, league_id).honours_of(player_id)
		for pair in [["mvp", "Most Valuable Player"], ["finals_mvp", "Finals MVP"], ["scoring_titles", "Scoring title"], ["all_league_first", "All-League First Team"], ["titles", "Championship"]]:
			if int(h[pair[0]]) > 0:
				awards.append("%dx %s" % [h[pair[0]], pair[1]] if int(h[pair[0]]) > 1 else str(pair[1]))
	var branding_team := _team_dict(world, team)
	return {
		"mode": mode, "subject": subject_for_player(world, player_id, "career_player" if mode == "career" else "owner_player"), "name": p.identity.full_name(), "jersey": 0,
		"position": FcPosition.abbreviation(p.primary_position), "secondary": FcPosition.abbreviation(p.secondary_position) if p.secondary_position != 0 else "",
		"archetype": "", "playstyle": FcPlaystyle.summary(composites), "team": branding_team if not branding_team.is_empty() else {"name": "Free agent"},
		"physical": {"height_cm": p.physical.height_cm, "weight_kg": p.physical.weight_kg, "wingspan_cm": p.physical.wingspan_cm, "hand": HAND_NAMES[clampi(p.physical.handedness, 0, 2)]},
		"overall": roundi(composites["overall"]), "potential": p.development.potential, "age": p.age_on(FcDate.new(current_year, 7, 1)),
		"attributes": _attributes(world.definitions, _values(world.definitions, p)), "badges": [],
		"stats": {"columns": ["Season", "Team", "GP", "MPG", "PPG", "RPG", "APG"], "rows": rows},
		"history": {"columns": ["Season", "Team", "GP", "Points", "Rebounds", "Assists"], "rows": history}, "awards": awards,
		"progression": {"kind": "outlook", "overall": roundi(composites["overall"]), "potential": p.development.potential, "peak_age": p.development.peak_age, "age": p.age_on(FcDate.new(current_year, 7, 1))},
	}


## The Career player: the world player plus the career record (archetype, level, XP, seasons, awards, milestones, appearance, jersey).
static func from_career(career: FcCareerController) -> Dictionary:
	var state := career.state
	var vm := from_player(state.world, career.player().id, state.current_season, 0, "career")
	var profile := career.profile()
	var card := career.card()
	vm["jersey"] = profile.jersey_number
	vm["archetype"] = str(card["archetype"])
	var career_extra: Dictionary = {"physical": vm["physical"], "position": vm["position"]}
	if int(vm["age"]) > 0:
		career_extra["age"] = int(vm["age"])
	vm["subject"] = subject("career_player:%d" % career.player().id, str(card["name"]), vm["team"], profile.jersey_number, profile.appearance, "", career_extra)
	var progress := career.progress()
	vm["progression"] = {"kind": "career", "level": progress["level"], "xp": progress["xp"], "into_level": progress["into_level"], "needed": progress["needed"],
		"development_points": progress["development_points"], "skill_points": progress["skill_points"], "overall": card["overall"], "potential": card["potential"]}
	var badges: Array = []
	for key in progress["badges_owned"]:
		var def := FcBadges.get_badge(str(key))
		badges.append({"key": str(key), "name": str(def.get("name", key)), "description": str(def.get("description", ""))})
	vm["badges"] = badges
	var history: Array = []
	var awards: Array[String] = []
	for row in profile.history:
		history.append(["%d-%02d" % [row["year"], (int(row["year"]) + 1) % 100], row.get("games", 0), row.get("points", 0), row.get("rebounds", 0), row.get("assists", 0)])
		for award in row.get("awards", []):
			awards.append("%s (%d-%02d)" % [str(award), row["year"], (int(row["year"]) + 1) % 100])
	vm["history"] = {"columns": ["Season", "GP", "Points", "Rebounds", "Assists"], "rows": history}
	for milestone in progress["milestones"]:
		awards.append(str(milestone).replace("_", " ").capitalize())
	vm["awards"] = awards
	return vm


# --- helpers ----------------------------------------------------------------------------------------------------------------

static func _values(defs: FcDefinitionSet, p: FcPlayer) -> Dictionary:
	var out := {}
	for key in defs.attributes.keys():
		out[key] = p.attributes.get_value(key)
	return out


static func _attributes(defs: FcDefinitionSet, values: Dictionary) -> Array:
	var out: Array = []
	for key in defs.attributes.keys():
		var def := defs.attributes.get_def(key)
		out.append({"key": key, "name": def.display_name, "category": def.category, "value": int(values.get(key, 0))})
	return out
