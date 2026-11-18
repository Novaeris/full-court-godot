class_name FcCareerController
extends RefCounted
## The API Career Mode screens call (like FcGameController does for Owner Mode). It never touches the UI. Phase 2: create a
## player, view the career card, save and resume. Later phases add progression, the calendar and games by composing the
## existing FcGameController (calendar, season and offseason flow) instead of duplicating it.
##
## Authority: everything that changes a career goes through rules in src/career (validation, later progression) so the
## same rules can run on a server. This class holds no rules of its own.

var state: FcGameState


## Creates a new career: a generated league (a small one by default so seasons are quick), the player from a validated build,
## and the career profile. Returns {"controller": FcCareerController} or {"errors": [plain-language problems]}.
static func new_career(spec: Dictionary, seed_value: int, team_count: int = 12) -> Dictionary:
	var data := FcGenerationData.load_default()
	var defs := FcDefinitionSet.load_default()
	var errors := FcPlayerBuild.validate(spec, defs)
	if not errors.is_empty():
		return {"errors": errors}
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = team_count
	cfg.conference_count = 2
	cfg.divisions_per_conference = 2 if team_count % 4 == 0 else 1
	var generator := FcWorldGenerator.new(data, defs, cfg)
	var problems := generator.validate()
	if not problems.is_empty():
		return {"errors": problems}
	var state := generator.new_game_state(seed_value, FcGameState.MODE_CAREER, 0)
	state.user_team_id = 0   # the player joins a team in a later phase
	var made := FcPlayerBuild.create(state.world, spec, state.current_season, state.rng.fork("career-profile"))
	if made.has("errors"):
		return {"errors": made["errors"]}
	state.career_profiles.append(made["profile"])
	var controller := FcCareerController.new()
	controller.state = state
	return {"controller": controller}


## A controller for a loaded career save, or null if the state is not a career.
static func resume(game_state: FcGameState) -> FcCareerController:
	if game_state.mode != FcGameState.MODE_CAREER or game_state.career_profiles.is_empty():
		return null
	var controller := FcCareerController.new()
	controller.state = game_state
	return controller


func profile() -> FcCareerProfile:
	return state.career_profiles[0]


func player() -> FcPlayer:
	return state.world.players.get_by_id(profile().player_id)


## What the Career Hub shows: {"name", "position", "secondary", "archetype", "age", "height_cm", "weight_kg", "wingspan_cm", "overall",
## "potential", "level", "xp", "jersey", "team", "profile_id", "groups": [{"name", "rows": [[label, value, ceiling]]}]}.
func card() -> Dictionary:
	var p := player()
	var profile := profile()
	var ratings := FcPlayerRatings.load_default()
	var spec := {"height_cm": p.physical.height_cm, "weight_kg": p.physical.weight_kg, "wingspan_cm": p.physical.wingspan_cm, "potential": p.development.potential}
	var groups := {}
	for key in state.world.definitions.attributes.keys():
		var def = state.world.definitions.attributes.get_def(key)
		var category: String = def.category
		if not groups.has(category):
			groups[category] = []
		groups[category].append([def.display_name, p.attributes.get_value(key), FcPlayerBuild.attribute_ceiling(key, spec)])
	var out_groups: Array = []
	for category in groups:
		out_groups.append({"name": category.capitalize(), "rows": groups[category]})
	var team_name := "Not signed yet"
	if state.user_team_id > 0:
		team_name = state.world.team_display_name(state.user_team_id)
	return {
		"name": p.identity.full_name(), "position": FcPosition.abbreviation(p.primary_position),
		"secondary": FcPosition.abbreviation(p.secondary_position) if p.secondary_position != 0 else "",
		"archetype": str(FcArchetypes.get_archetype(profile.archetype_key).get("name", profile.archetype_key)),
		"age": p.age_on(state.current_date), "height_cm": p.physical.height_cm, "weight_kg": p.physical.weight_kg,
		"wingspan_cm": p.physical.wingspan_cm, "overall": roundi(ratings.overall(p)), "potential": p.development.potential,
		"level": profile.level, "xp": profile.xp, "jersey": profile.jersey_number, "team": team_name,
		"profile_id": profile.profile_id, "groups": out_groups}


# --- progression (all rules live in FcCareerRules; these only apply them to this career) -----------------------

## Where the career stands: level, XP progress, points, training left this season, owned and equipped badges.
func progress() -> Dictionary:
	var profile := profile()
	var level := FcCareerRules.level_progress(profile.xp)
	var used := int(profile.training_used.get(str(state.current_season), 0))
	return {"level": profile.level, "xp": profile.xp, "into_level": level["into_level"], "needed": level["needed"], "fraction": level["fraction"],
		"development_points": profile.development_points, "skill_points": profile.skill_points, "currency": profile.currency,
		"training_left": int(FcCareerRules.rules()["training"]["sessions_per_season"]) - used,
		"badges_owned": profile.badges_owned.duplicate(), "badges_equipped": profile.badges_equipped.duplicate(),
		"milestones": profile.milestones.duplicate()}


## Applies a played game line (from a simulation box score) to the career: XP, milestones, levels. Returns what was granted.
func award_game(line: Dictionary) -> Dictionary:
	return FcCareerRules.apply_game(profile(), line)


func train() -> Dictionary:
	return FcCareerRules.train(profile(), state.current_season)


## Spends development points to raise one attribute by 1 (cost grows with the value; the body's ceiling is a hard limit).
func raise_attribute(key: String) -> Dictionary:
	return FcCareerRules.raise_attribute(profile(), player(), key)


## Every badge with whether it is owned/equipped and why it cannot be unlocked yet ("" = it can).
func badge_list() -> Array:
	var out: Array = []
	for badge in FcBadges.all():
		out.append({"key": badge["key"], "name": badge["name"], "tree": badge["tree"], "description": badge["description"], "cost": badge["cost"],
			"owned": profile().badges_owned.has(badge["key"]), "equipped": profile().badges_equipped.has(badge["key"]),
			"problem": FcCareerRules.badge_problem(profile(), player(), badge["key"])})
	return out


func unlock_badge(key: String) -> Dictionary:
	return FcCareerRules.unlock_badge(profile(), player(), key)


func equip_badge(key: String, equipped: bool) -> Dictionary:
	return FcCareerRules.set_badge_equipped(profile(), key, equipped)


## Composite rating bonuses of the equipped badges (used by the simulation integration in a later phase).
func badge_bonus() -> Dictionary:
	return FcCareerRules.composite_bonus(profile().badges_equipped)


## Saves the career to a slot. Returns the FcSaveResult.
func save(manager: FcSaveManager, slot_id: String = "career_1") -> FcSaveResult:
	return manager.save(slot_id, state, "%s (Career)" % player().identity.full_name())
