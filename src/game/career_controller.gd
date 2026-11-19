class_name FcCareerController
extends RefCounted
## The API Career Mode screens call (like FcGameController does for Owner Mode). It never touches the UI. Phase 2: create a
## player, view the career card, save and resume. Later phases add progression, the calendar and games by composing the
## existing FcGameController (calendar, season and offseason flow) instead of duplicating it.
##
## Authority: everything that changes a career goes through rules in src/career (validation, later progression) so the
## same rules can run on a server. This class holds no rules of its own.

var state: FcGameState
## The league's calendar and season flow (FcGameController), created once the player is on a team.
var _game: FcGameController
## Box scores already turned into career rewards: {key: true}, so a reloaded or repeated look never pays a game twice.
var _seen: Dictionary = {}


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
	var spec := FcPlayerBuild.spec_of(p, profile.build_potential)
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


# --- joining a team and playing seasons (Phase 4) ---------------------------------------------------------------

## The league game flow, or null while the player has no team.
func game() -> FcGameController:
	if _game == null and state.user_team_id > 0:
		_game = FcGameController.resume(state)
		_game.career_player_id = profile().player_id
		for entry in _game.season().recent_boxes:
			_seen[_box_key(entry)] = true   # games played before this look were already rewarded
		_sync_badges()
	return _game


func is_signed() -> bool:
	return state.user_team_id > 0 and state.world.team_of_player(profile().player_id) != null


## True once the player has retired: the career is over (stage Legacy) and no more games are played.
func is_retired() -> bool:
	return player().status == FcPlayer.Status.RETIRED


## A team chosen by a seeded "draft" (the same for the same career and season): the player may also pick a team himself.
func draft_team() -> int:
	var ids := state.world.teams.ids()
	var rng := state.rng.fork("career-draft:%d" % state.current_season)
	return ids[rng.range_int(0, ids.size() - 1)]


## Signs the player to a team with a rookie contract (a full roster releases its weakest player). Returns {"ok", "reason"}.
func join_team(team_id: int) -> Dictionary:
	if is_signed():
		return {"ok": false, "reason": "You already have a team."}
	var team: FcTeam = state.world.teams.get_by_id(team_id)
	if team == null:
		return {"ok": false, "reason": "That team does not exist."}
	var league := state.world.league_of_team(team_id)
	var rules := state.world.rules_of_league(league.id)
	var year := state.current_season
	if team.roster.size() >= rules.roster_max:
		FcOffseason.new(state.world).make_room(team, year)
	var salary := rules.cap.rookie_salary(15, 30)
	var contract := FcPlayerMarket.make_contract(state.world.ids.next_id(FcWorld.KIND_CONTRACT), profile().player_id, team_id, year,
		rules.cap.rookie_contract_years, salary, rules.cap, FcDate.new(year, 7, 1))
	state.world.contracts.add(contract)
	team.roster.add(profile().player_id)
	state.user_team_id = team_id
	if profile().stage < FcCareerProfile.Stage.PROFESSIONAL_ENTRY:
		profile().stage = FcCareerProfile.Stage.PROFESSIONAL_ENTRY
	_game = null
	game()
	_game.career_player_id = profile().player_id
	_roll_event()
	state.world.add_news(state.current_date, "signing", "%s signed with %s." % [player().identity.full_name(), state.world.team_display_name(team_id)], team_id)
	return {"ok": true, "reason": "You signed with %s on a %d-year rookie contract." % [state.world.team_display_name(team_id), rules.cap.rookie_contract_years]}


## The next game of the player's team: {"date", "opponent", "home"} or {} (season over or no team).
func next_game() -> Dictionary:
	var g := game()
	if g == null:
		return {}
	var next := g.next_user_game()
	if next == null:
		return {}
	var home := next.home_id == state.user_team_id
	return {"date": g.season().date_of_day(next.day).to_iso(), "opponent": state.world.team_display_name(next.away_id if home else next.home_id), "home": home}


## Plays one day of the league. Returns {"ok", "games": [what the player did], "phase"}; each entry has the box score line, the
## result and the career rewards it paid.
func advance_day() -> Dictionary:
	if is_retired():
		return {"ok": false, "reason": "Your career is over.", "games": []}
	var g := game()
	if g == null:
		return {"ok": false, "reason": "Join a team first.", "games": []}
	if profile().pending_event != "":
		return {"ok": false, "reason": "You have a decision to make before you play on.", "games": []}
	g.advance_day()
	return {"ok": true, "games": _collect_games(), "phase": g.phase()}


## Plays up to `count` days (stops when the season is over).
func advance_days(count: int) -> Dictionary:
	if is_retired():
		return {"ok": false, "reason": "Your career is over.", "games": []}
	var g := game()
	if g == null:
		return {"ok": false, "reason": "Join a team first.", "games": []}
	if profile().pending_event != "":
		return {"ok": false, "reason": "You have a decision to make before you play on.", "games": []}
	var games: Array = []
	for i in count:
		if g.phase() == FcGameController.PHASE_COMPLETE:
			break
		g.advance_day()
		games.append_array(_collect_games())
	return {"ok": true, "games": games, "phase": g.phase()}


## Plays everything left of the season, playoffs included, then records the season: history row, the season milestone, and
## the automatic league offseason into the next season (contracts, draft, free agency). If the player's contract ends this
## season the offseason waits for his decision: the result then has "contract_pending": true until `answer_contract` is called
## and `finish_season` is called again. Returns {"ok", "summary", "games"}.
func finish_season() -> Dictionary:
	if is_retired():
		return {"ok": false, "reason": "Your career is over.", "games": []}
	var g := game()
	if g == null:
		return {"ok": false, "reason": "Join a team first.", "games": []}
	if profile().pending_event != "":
		return {"ok": false, "reason": "You have a decision to make before you play on.", "games": []}
	if profile().contract_pending:
		return {"ok": false, "reason": "Settle your contract talks first.", "games": []}
	var games: Array = []
	while g.phase() != FcGameController.PHASE_COMPLETE:
		g.advance_day()
		games.append_array(_collect_games())
	var year := state.current_season
	var row := _record_season(year)
	var milestone := FcCareerRules.claim_milestone(profile(), "season_complete")
	if profile().contract_resolved_year != year:
		var contract := state.world.active_contract_of(profile().player_id)
		if contract != null and contract.end_season() <= year:
			profile().contract_pending = true
			return {"ok": true, "summary": row, "milestone": milestone.get("reason", ""), "games": games, "contract_pending": true}
	g.career_player_id = profile().player_id
	g.start_next_season()
	state.agreed_extensions.clear()
	state.agreed_terms.clear()
	_after_offseason()
	return {"ok": true, "summary": row, "milestone": milestone.get("reason", ""), "games": games, "contract_pending": false}


## The contract talks waiting for an answer, or {} : {"team", "salary", "max_salary", "years", "market_ask", "agent", "season"}.
## The offer is what the team will pay; with the agent and reputation the player may push up to `max_salary`.
func contract_offer() -> Dictionary:
	if not profile().contract_pending:
		return {}
	var team := state.world.team_of_player(profile().player_id)
	var rules := state.world.rules_of_league(state.world.league_of_team(state.user_team_id).id)
	var market := FcPlayerMarket.new(FcPlayerRatings.load_default())
	var age := player().age_on(FcDate.new(state.current_season + 1, 7, 1))
	var overalls: Array = []
	var ratings := FcPlayerRatings.load_default()
	for pid in state.world.teams.get_by_id(state.user_team_id).roster.player_ids:
		overalls.append(ratings.overall(state.world.players.get_by_id(pid)))
	var ask := market.asking_salary(player(), age, rules.cap)
	var terms := FcCareerRules.contract_terms(profile(), ask, ratings.overall(player()), overalls, market.desired_years(age, rules.cap), rules.cap)
	var agent := "none"
	if profile().tags.has("agent_flashy"):
		agent = "flashy"
	elif profile().tags.has("agent_loyal"):
		agent = "loyal"
	return {"team": state.world.team_display_name(state.user_team_id) if team != null else "", "salary": terms["salary"], "max_salary": terms["max_salary"],
		"years": terms["years"], "market_ask": ask, "agent": agent, "season": state.current_season}


## Answers the contract talks: "accept" (the team's offer), "counter" (ask for `salary`, up to the ceiling) or "expire" (let the
## contract run out and go to free agency, where the league's teams decide). Returns {"ok", "reason"}. A refused counter leaves
## the talks open.
func answer_contract(action: String, salary: int = 0) -> Dictionary:
	var offer := contract_offer()
	if offer.is_empty():
		return {"ok": false, "reason": "There are no contract talks right now."}
	var pid := profile().player_id
	var signed := 0
	var message := ""
	match action:
		"accept":
			signed = int(offer["salary"])
			message = "You accepted %s's offer: $%.2fM a year for %d years." % [offer["team"], signed / 1e6, int(offer["years"])]
		"counter":
			if salary <= int(offer["salary"]):
				signed = int(offer["salary"])
				message = "%s agreed at its own offer, $%.2fM." % [offer["team"], signed / 1e6]
			elif salary > int(offer["max_salary"]):
				return {"ok": false, "reason": "%s will not pay that: the most it would go to is $%.2fM." % [offer["team"], int(offer["max_salary"]) / 1e6]}
			else:
				signed = salary
				message = "You pushed %s up to $%.2fM a year for %d years." % [offer["team"], signed / 1e6, int(offer["years"])]
				if salary > int(offer["salary"]) * 1.05:
					profile().reputation = maxi(0, profile().reputation - 1)
					if not profile().tags.has("hardball"):
						profile().tags.append("hardball")
					message += " Hard bargaining costs 1 reputation."
		"expire":
			message = "You let your contract run out and head into free agency."
		_:
			return {"ok": false, "reason": "Choose accept, counter or expire."}
	if signed > 0:
		state.agreed_extensions.append(pid)
		state.agreed_terms[pid] = [signed, int(offer["years"])]
	profile().decisions.append({"year": state.current_season, "key": "contract", "choice": "%s %d" % [action, signed]})
	profile().contract_pending = false
	profile().contract_resolved_year = state.current_season
	return {"ok": true, "reason": message}


## The player's totals for a season from the league's own statistics: {"games", "points", "rebounds", "assists", ...} per game.
func season_line(year: int = 0) -> Dictionary:
	var g := game()
	if g == null:
		return {}
	var season := g.season() if year == 0 else null
	if season == null:
		for s in state.world.seasons.all():
			if s.year == year:
				season = s
	if season == null or not season.stats.lines.has(profile().player_id):
		return {"games": 0}
	var s: FcSeasonStats = season.stats
	var pid := profile().player_id
	return {"games": s.games_played(pid), "points": s.per_game(pid, "points"), "rebounds": s.per_game(pid, "rebounds"),
		"assists": s.per_game(pid, "ast"), "steals": s.per_game(pid, "stl"), "blocks": s.per_game(pid, "blk"), "minutes": s.per_game(pid, "seconds") / 60.0}


func _record_season(year: int) -> Dictionary:
	var line := season_line(year)
	var wins := 0
	var losses := 0
	var standings := game().standings()
	if standings != null and standings.records.has(state.user_team_id):
		wins = int(standings.records[state.user_team_id]["w"])
		losses = int(standings.records[state.user_team_id]["l"])
	var row := {"year": year, "team_id": state.user_team_id, "games": int(line.get("games", 0)), "points": snappedf(float(line.get("points", 0.0)), 0.1),
		"rebounds": snappedf(float(line.get("rebounds", 0.0)), 0.1), "assists": snappedf(float(line.get("assists", 0.0)), 0.1), "wins": wins, "losses": losses, "awards": []}
	for existing in profile().history:
		if int(existing.get("year", 0)) == year:
			return existing
	profile().history.append(row)
	return row


## After the league's offseason: follow the player to the team he is on now, and if no team kept him he signs with the draft's team
## (agents and negotiations come with the career RPG phase).
func _after_offseason() -> void:
	_clamp_to_ceilings()
	if is_retired():
		profile().stage = FcCareerProfile.Stage.LEGACY   # the league retired him in the offseason: the career ends here
		state.world.add_news(state.current_date, "retirement", "%s has retired after %d seasons." % [player().identity.full_name(), profile().history.size()], state.user_team_id)
		return
	var team := state.world.team_of_player(profile().player_id)
	if team == null:
		state.user_team_id = 0
		_game = null
		var picked := draft_team()
		join_team(picked)
		return
	if team.id != state.user_team_id:
		_game.follow_team(team.id)
	_seen.clear()
	for entry in _game.season().recent_boxes:
		_seen[_box_key(entry)] = true
	_roll_event()


## The decision waiting for an answer, as {"key", "title", "text", "choices": [{"key", "label", "note"}]} or {} if none.
func pending_event() -> Dictionary:
	var key := profile().pending_event
	if key == "":
		return {}
	var event := FcCareerEvents.get_event(key)
	if event.is_empty():
		return {}
	return {"key": key, "title": event["title"], "text": event["text"],
		"choices": event["choices"].map(func(c): return {"key": c["key"], "label": c["label"], "note": c.get("note", "")})}


## Answers the waiting decision. The choice's effects apply to the career immediately. Returns {"ok", "reason"}.
func answer_event(choice_key: String) -> Dictionary:
	if profile().pending_event == "":
		return {"ok": false, "reason": "There is nothing to decide right now."}
	return FcCareerEvents.apply_choice(profile(), profile().pending_event, choice_key, state.current_season)


## Offers a new decision for the season that is starting (a seeded pick among the events the career qualifies for).
func _roll_event() -> void:
	if profile().pending_event != "":
		return
	var rng := state.rng.fork("career-event:%s:%d" % [profile().profile_id, state.current_season])
	profile().pending_event = FcCareerEvents.pick(profile(), state.current_season, rng)


## The league's yearly aging may raise an attribute past what the player's body and potential allow; the ceiling is a hard limit,
## so anything above it is brought back to it (decline from age is left alone).
func _clamp_to_ceilings() -> void:
	var spec := FcPlayerBuild.spec_of(player(), profile().build_potential)
	for key in state.world.definitions.attributes.keys():
		var ceiling := FcPlayerBuild.attribute_ceiling(key, spec)
		if player().attributes.get_value(key) > ceiling:
			player().attributes.set_value(key, ceiling)
	if _game != null:
		_game.engine.refresh_teams()


func _box_key(entry: Dictionary) -> String:
	var box: Dictionary = entry["box"]
	return "%d:%d:%d:%d:%d" % [state.current_season, int(entry["day"]), int(entry["series"]), int(box["team_ids"][0]), int(box["team_ids"][1])]


func _collect_games() -> Array:
	var out: Array = []
	var pid := profile().player_id
	for entry in _game.season().recent_boxes:
		var key := _box_key(entry)
		if _seen.has(key):
			continue
		_seen[key] = true
		var box: Dictionary = entry["box"]
		for row in box["players"]:
			if int(row["player_id"]) != pid or int(row["seconds"]) <= 0:
				continue
			var side := 0 if int(box["team_ids"][0]) == state.user_team_id else 1
			var won: bool = int(box["scores"][side]) > int(box["scores"][1 - side])
			var line := {"minutes": float(row["seconds"]) / 60.0, "points": int(row["points"]), "rebounds": int(row["oreb"]) + int(row["dreb"]),
				"assists": int(row["ast"]), "steals": int(row["stl"]), "blocks": int(row["blk"]), "turnovers": int(row["tov"]), "won": won}
			var reward := FcCareerRules.apply_game(profile(), line)
			out.append({"day": int(entry["day"]), "opponent": str(box["team_names"][1 - side]), "score": "%d-%d" % [int(box["scores"][side]), int(box["scores"][1 - side])],
				"won": won, "line": line, "xp": int(reward["xp"]), "levels_gained": int(reward["levels_gained"]), "milestones": reward["milestones"]})
	return out


## Asks the coach for a role. Returns {"ok", "reason"}; a refused request changes nothing. `role` is "auto", "starter" or "bench";
## `minutes_pref` and `usage_pref` are -1, 0 or +1.
func set_role(role: String, minutes_pref: int, usage_pref: int) -> Dictionary:
	var g := game()
	var overalls: Array = []
	var ratings := FcPlayerRatings.load_default()
	var me := ratings.overall(player())
	if g != null and state.user_team_id > 0:
		for pid in state.world.teams.get_by_id(state.user_team_id).roster.player_ids:
			overalls.append(ratings.overall(state.world.players.get_by_id(pid)))
	var problem := FcCareerRules.role_problem(profile(), me, overalls, role, minutes_pref, usage_pref)
	if problem != "":
		return {"ok": false, "reason": problem}
	profile().role = role
	profile().minutes_pref = minutes_pref
	profile().usage_pref = usage_pref
	_sync_badges()
	return {"ok": true, "reason": "The coach agrees: %s, minutes %+d, usage %+d." % [role, minutes_pref, usage_pref]}


## Gives the equipped badges' capped bonuses to the career player's simulated ratings (and only his).
func _sync_badges() -> void:
	if _game == null:
		return
	var bonus := badge_bonus()
	_game.engine.composite_bonuses = {profile().player_id: bonus} if not bonus.is_empty() else {}
	var inputs := FcCareerRules.role_inputs(profile())
	var any_role: bool = inputs["role_bonus"] != 0.0 or inputs["minutes_pref"] != 0.0 or inputs["usage_pref"] != 0.0
	_game.engine.role_inputs = {profile().player_id: inputs} if any_role else {}
	_game.engine.refresh_teams()


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
	var result := FcCareerRules.raise_attribute(profile(), player(), key)
	if result["ok"] and _game != null:
		_game.engine.refresh_teams()   # the simulation reads the player's attributes when it builds a team
	return result


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
	var result := FcCareerRules.set_badge_equipped(profile(), key, equipped)
	if result["ok"]:
		_sync_badges()
	return result


## Composite rating bonuses of the equipped badges (used by the simulation integration in a later phase).
func badge_bonus() -> Dictionary:
	return FcCareerRules.composite_bonus(profile().badges_equipped)


## Saves the career to a slot. Returns the FcSaveResult.
func save(manager: FcSaveManager, slot_id: String = "career_1") -> FcSaveResult:
	return manager.save(slot_id, state, "%s (Career)" % player().identity.full_name())
