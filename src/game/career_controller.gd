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


## Saves the career to a slot. Returns the FcSaveResult.
func save(manager: FcSaveManager, slot_id: String = "career_1") -> FcSaveResult:
	return manager.save(slot_id, state, "%s (Career)" % player().identity.full_name())
