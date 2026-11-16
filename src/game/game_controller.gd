class_name FcGameController
extends RefCounted
## The one object a screen (or a script) talks to in order to play the game.
## It owns an FcGameState and drives the season engine: advance days, finish
## the regular season, play the playoffs, roll into the next season (the
## offseason), and make the owner's decisions. It contains no UI code.
##
## Phases of a season: "regular_season" -> "playoffs" -> "season_complete"
## (call start_next_season() to run the offseason and begin the next year).
## All randomness comes from state.rng, which is part of every save, so a game
## continues identically after saving and loading.

const PHASE_REGULAR := "regular_season"
const PHASE_PLAYOFFS := "playoffs"
const PHASE_COMPLETE := "season_complete"
## Owner Mode only: the draft and re-signing are done and the owner may sign free agents
## before the AI teams do (see begin_offseason / start_next_season).
const PHASE_OFFSEASON := "offseason"
## Owner Mode only: the draft is under way and the owner picks for their team.
const PHASE_DRAFT := "draft"
const SEASON_START_MONTH := 10
const SEASON_START_DAY := 20

var state: FcGameState
var league_id: int = 0
var engine: FcSeasonEngine


## A brand-new game from a generator: the user controls `user_team_index`.
static func new_game(generator: FcWorldGenerator, seed_value: int, mode: String = FcGameState.MODE_OWNER, user_team_index: int = 0) -> FcGameController:
	return FcGameController.resume(generator.new_game_state(seed_value, mode, user_team_index))


## Wraps an existing state (a new game or a loaded save). Starts the season for
## the state's current year if it does not exist yet.
static func resume(game_state: FcGameState) -> FcGameController:
	var c := FcGameController.new()
	c.state = game_state
	c.league_id = game_state.world.league_of_team(game_state.user_team_id).id
	c._prepare_engine()
	if c.season() == null:
		c._start_season(game_state.current_season)
	c._update_date()
	return c


func _prepare_engine() -> void:
	engine = FcSeasonEngine.for_league(state.world, league_id)
	engine.human_teams = [state.user_team_id] as Array[int] if state.mode == FcGameState.MODE_OWNER else ([] as Array[int])
	engine.watched_teams = [state.user_team_id] as Array[int]


func _start_season(year: int) -> FcSeason:
	return engine.start_season(league_id, year, FcDate.new(year, SEASON_START_MONTH, SEASON_START_DAY), state.rng)


func season() -> FcSeason:
	return state.world.season_of(league_id, state.current_season)


func phase() -> String:
	var s := season()
	match s.status:
		FcSeason.Status.PLAYOFFS:
			return PHASE_PLAYOFFS
		FcSeason.Status.COMPLETE:
			match state.offseason_stage:
				1: return PHASE_OFFSEASON
				2: return PHASE_DRAFT
			return PHASE_COMPLETE
	return PHASE_REGULAR


# --- advancing time ------------------------------------------------------------------

## Plays the next day (regular season or playoffs). Returns the number of games played.
func advance_day() -> int:
	var s := season()
	var played := 0
	match phase():
		PHASE_REGULAR:
			played = engine.play_day(s, state.rng)
			if s.regular_season_complete():
				engine.start_playoffs(s)
		PHASE_PLAYOFFS:
			played = engine.play_playoff_day(s, state.rng)
	_update_date()
	return played


func advance_days(count: int) -> int:
	var total := 0
	for i in count:
		if phase() == PHASE_COMPLETE:
			break
		total += advance_day()
	return total


func sim_regular_season() -> void:
	while phase() == PHASE_REGULAR:
		advance_day()


func sim_playoffs() -> void:
	sim_regular_season()
	while phase() == PHASE_PLAYOFFS:
		advance_day()


## Finishes the current season (if needed), runs the offseason (aging, retirement,
## contracts, draft, free agency, staff) and starts the next season.
## Returns the offseason report.
func start_next_season() -> Dictionary:
	if state.offseason_stage == 0:
		begin_offseason()
	if state.offseason_stage == 2:
		draft_auto_rest()   # the owner did not finish the draft: the staff picks for them
	var report := _report_so_far.duplicate()
	_report_so_far = {}
	var finished := season()
	var offseason := _new_offseason()
	report.merge(offseason.run_second_half(league_id, finished, state.rng))
	state.offseason_stage = 0
	state.current_season = finished.year + 1
	state.current_date = FcDate.new(state.current_season, 7, 1)
	_prepare_engine()
	_start_season(state.current_season)
	_update_date()
	return report


func _new_offseason() -> FcOffseason:
	var offseason := FcOffseason.new(state.world)
	offseason.human_team_ids = [state.user_team_id] as Array[int] if state.mode == FcGameState.MODE_OWNER else ([] as Array[int])
	offseason.agreed_re_signs = state.agreed_extensions.duplicate()
	offseason.agreed_terms = state.agreed_terms.duplicate(true)
	if state.mode == FcGameState.MODE_OWNER and not state.delegation["free_agency"]:
		offseason.manual_free_agency_team_ids = [state.user_team_id] as Array[int]
	return offseason


## First half of the offseason: finishes the season if needed, then aging and retirement,
## contracts ending, re-signing the agreed players, the draft and AI trades. Afterwards,
## in Owner Mode, the phase is PHASE_OFFSEASON and the owner can sign free agents and
## release players before start_next_season() lets the AI teams sign players.
## Returns the report so far.
func begin_offseason() -> Dictionary:
	sim_playoffs()
	var finished := season()
	_gm_log = []
	if state.mode == FcGameState.MODE_OWNER and state.delegation["contracts"]:
		_gm_re_sign_players()
	var offseason := _new_offseason()
	if state.mode != FcGameState.MODE_OWNER:
		var all := offseason.run_first_half(league_id, finished, state.rng)
		state.agreed_extensions.clear()
		state.agreed_terms.clear()
		_report_so_far = all.duplicate()
		return all
	var report := offseason.run_before_draft(league_id, finished, state.rng)
	_report_so_far = report.duplicate()
	state.agreed_extensions.clear()
	state.agreed_terms.clear()
	state.draft_state = offseason.prepare_draft(league_id, finished, finished.year + 1, state.rng.fork("draft"))
	state.offseason_stage = 2
	_draft_advance_to_user()
	if state.delegation["draft"] and state.offseason_stage == 2:
		_gm_log.append("Your general manager ran the draft.")
		draft_auto_rest()
	return report


## The season whose contracts and ages count right now: the next season during the
## owner's offseason window, otherwise the current one.
func contract_year() -> int:
	return state.current_season + (1 if state.offseason_stage >= 1 else 0)


func _update_date() -> void:
	var s := season()
	if s == null:
		return
	match s.status:
		FcSeason.Status.REGULAR, FcSeason.Status.PENDING:
			state.current_date = s.date_of_day(s.next_day)
		FcSeason.Status.PLAYOFFS:
			state.current_date = s.date_of_day(s.total_days() + FcSeasonEngine.PLAYOFF_GAP_DAYS + (s.playoffs.day if s.playoffs != null else 0))
		FcSeason.Status.COMPLETE:
			state.current_date = s.date_of_day(s.total_days() + FcSeasonEngine.PLAYOFF_GAP_DAYS + (s.playoffs.day if s.playoffs != null else 0))


# --- information for screens ----------------------------------------------------------

func standings() -> FcStandings:
	return engine.standings_of(season())


## The user's team record: {"wins", "losses", "rank", "games_left", "streak"}.
func user_record() -> Dictionary:
	var st := standings()
	var tid := state.user_team_id
	return {
		"wins": st.records[tid]["w"], "losses": st.records[tid]["l"],
		"rank": st.league_ranking().find(tid) + 1,
		"games_left": state.world.rules_of_league(league_id).season.games_for_team(state.world.leagues.get_by_id(league_id), tid) - st.games_played(tid),
		"streak": st.streak_text(tid),
	}


func next_user_game() -> FcScheduledGame:
	var s := season()
	for g in s.games:
		if not g.played and g.series == 0 and g.involves(state.user_team_id):
			return g
	return null


# --- trades ---------------------------------------------------------------------------------

## Is this AI team in a "win now" mood? The top third of the current standings are.
func is_contending(team_id: int) -> bool:
	var ranking := standings().league_ranking()
	return ranking.find(team_id) < maxi(1, floori(ranking.size() / 3.0))


## The first draft year whose picks can still be traded: the next draft, or the one after
## it once this offseason's draft has been held. Three drafts are tradable.
func first_tradable_pick_year() -> int:
	return state.current_season + (2 if state.offseason_stage >= 1 else 1)


## Draft picks a team owns that can be traded: [{"year", "round", "original" (team id), "label"}].
func tradable_picks(team_id: int) -> Array:
	var w := state.world
	var out: Array = []
	var first := first_tradable_pick_year()
	for year in range(first, first + FcTradeDesk.PICK_YEARS):
		for round_number in range(1, FcOffseason.DRAFT_ROUNDS + 1):
			for tid in w.leagues.get_by_id(league_id).all_team_ids():
				if w.pick_owner(year, round_number, tid) == team_id:
					out.append({"year": year, "round": round_number, "original": tid,
						"label": "%d round %d%s" % [year, round_number, "" if tid == team_id else " (from %s)" % w.team_display_name(tid)]})
	return out


## Proposes a trade from the user's team. `preview` true only checks it.
## Returns {"accepted": bool, "reason": String}.
func propose_trade(ai_team_id: int, give_ids: Array, get_ids: Array, preview: bool = false, give_picks: Array = [], get_picks: Array = []) -> Dictionary:
	if state.offseason_stage == 2:
		return {"accepted": false, "reason": "Finish the draft first."}
	var desk := FcTradeDesk.new(state.world)
	return desk.propose(league_id, contract_year(), state.user_team_id, ai_team_id, give_ids, get_ids, is_contending(ai_team_id), not preview, give_picks, get_picks, first_tradable_pick_year())


# --- the draft (Owner Mode) -----------------------------------------------------------------

## What the general manager did for the owner this offseason (shown in the UI).
var _gm_log: Array[String] = []


## The general manager's talent evaluation (0-100) and name, or {} if there is no GM.
func gm_summary() -> Dictionary:
	var gm := state.world.staff_in_role(state.user_team_id, FcStaffRole.Id.GENERAL_MANAGER)
	if gm == null:
		return {}
	return {"name": gm.identity.full_name(), "talent_evaluation": gm.skills.get_value("talent_evaluation"), "negotiation": gm.skills.get_value("negotiation")}


func gm_log() -> Array[String]:
	return _gm_log


func delegation_on(key: String) -> bool:
	return bool(state.delegation.get(key, false))


## Lets the general manager handle one area ("contracts", "draft" or "free_agency") or takes it back.
func set_delegation(key: String, on: bool) -> bool:
	if not FcGameState.DELEGATION_KEYS.has(key) or state.mode != FcGameState.MODE_OWNER:
		return false
	state.delegation[key] = on
	return true


## How the GM sees a player's worth: the market value plus an error that shrinks with the
## GM's (and scouts') talent evaluation, the same for the same player every time.
func _gm_value(p: FcPlayer, age: int, market: FcPlayerMarket) -> float:
	var noise := FcRng.new(hash("gm:%d:%d" % [state.user_team_id, p.id])).gaussian(0.0, maxf(0.5, _off().draft_noise(state.user_team_id)))
	return market.value(p, age) + noise


## Re-signing by the GM: he keeps players he believes are worth at least the keep line
## (value points), at their asking price, as far as the cap allows.
const GM_KEEP_VALUE := 50.0
const GM_FREE_AGENT_VALUE := 52.0
const GM_MAX_SIGNINGS := 3


func _gm_re_sign_players() -> void:
	var market := FcPlayerMarket.new(FcPlayerRatings.load_default())
	for entry in expiring_players():
		if entry["agreed"]:
			continue
		var p: FcPlayer = entry["player"]
		if _gm_value(p, entry["age"], market) < GM_KEEP_VALUE:
			continue
		var r := extend_contract(p.id)
		if r["ok"]:
			_gm_log.append("Your general manager agreed new terms with %s." % p.identity.full_name())


## Free agency by the GM: signs up to GM_MAX_SIGNINGS free agents he rates as real
## improvements (at their asking price), while there is roster space and cap room.
func _gm_sign_free_agents() -> void:
	var market := FcPlayerMarket.new(FcPlayerRatings.load_default())
	var team: FcTeam = state.world.teams.get_by_id(state.user_team_id)
	var rules := state.world.rules_of_league(league_id)
	var signed := 0
	var ranked: Array = []
	for entry in free_agent_market(40):
		ranked.append([_gm_value(entry["player"], entry["age"], market), entry["player"]])
	ranked.sort_custom(func(a, b): return a[0] > b[0])
	for pair in ranked:
		if signed >= GM_MAX_SIGNINGS or team.roster.size() >= rules.roster_max - 1:
			break
		if pair[0] < GM_FREE_AGENT_VALUE:
			break
		var r := sign_free_agent(pair[1].id)
		if r["signed"]:
			signed += 1
			_gm_log.append("Your general manager signed %s." % pair[1].identity.full_name())


## What the first half of this offseason did (counts), reported when the season starts.
var _report_so_far: Dictionary = {}


func _draft_rng() -> FcRng:
	return state.rng.fork("draft")


func _off() -> FcOffseason:
	return _new_offseason()


## Where the draft stands: {"pick", "round", "team", "user_on_clock", "complete", "total"}.
func draft_status() -> Dictionary:
	var ds := state.draft_state
	if ds.is_empty():
		return {}
	var off := _off()
	var complete := off.draft_complete(ds)
	var team := 0 if complete else off.draft_team_on_clock(ds)
	return {"pick": mini(int(ds["next"]), int(ds["total"])), "round": 0 if complete else off.draft_round_on_clock(ds), "team": team,
		"user_on_clock": team == state.user_team_id, "complete": complete, "total": int(ds["total"])}


## The draft board as the user's scouts see it, best first:
## [{"player", "age", "report" (see FcOffseason.scouting_report)}].
func draft_board() -> Array:
	var ds := state.draft_state
	var off := _off()
	var out: Array = []
	for pid in ds.get("available", []):
		var p: FcPlayer = state.world.players.get_by_id(int(pid))
		var worked_out: bool = (ds.get("workouts", []) as Array).has(p.id)
		out.append({"player": p, "age": p.age_on(FcDate.new(int(ds["year"]), 7, 1)), "report": off.scouting_report(state.user_team_id, p, int(ds["year"]), worked_out)})
	out.sort_custom(func(a, b): return a["report"]["value"] > b["report"]["value"] if a["report"]["value"] != b["report"]["value"] else a["player"].id < b["player"].id)
	return out


## How many private workouts the owner can still hold.
func draft_workouts_left() -> int:
	return FcOffseason.WORKOUT_SLOTS - (state.draft_state.get("workouts", []) as Array).size()


## Invites a prospect for a private workout: his report becomes much sharper and shows a
## note on his character. A few slots only (FcOffseason.WORKOUT_SLOTS) for the whole draft.
## Returns {"ok": bool, "reason": String}.
func invite_to_workout(prospect_id: int) -> Dictionary:
	var ds := state.draft_state
	if ds.is_empty():
		return {"ok": false, "reason": "There is no draft going on."}
	if not (ds["available"] as Array).has(prospect_id):
		return {"ok": false, "reason": "That prospect is not available."}
	if (ds["workouts"] as Array).has(prospect_id):
		return {"ok": false, "reason": "He has already worked out for you."}
	if draft_workouts_left() <= 0:
		return {"ok": false, "reason": "You have used all %d workouts." % FcOffseason.WORKOUT_SLOTS}
	(ds["workouts"] as Array).append(prospect_id)
	return {"ok": true, "reason": "%s worked out for you. Check the board." % state.world.players.get_by_id(prospect_id).identity.full_name()}


## Picks so far: [[round, pick, team id, player id], ...].
func draft_results() -> Array:
	return state.draft_state.get("results", [])


## The user's team drafts `prospect_id` (it must be the user's turn). Afterwards the AI teams
## pick until it is the user's turn again (or the draft ends).
## Returns {"ok": bool, "reason": String}.
func user_draft_pick(prospect_id: int) -> Dictionary:
	var status := draft_status()
	if status.is_empty() or status["complete"]:
		return {"ok": false, "reason": "There is no draft going on."}
	if not status["user_on_clock"]:
		return {"ok": false, "reason": "It is not your turn to pick."}
	var p: FcPlayer = state.world.players.get_by_id(prospect_id)
	if not _off().make_pick(state.draft_state, league_id, prospect_id):
		return {"ok": false, "reason": "That prospect is not available."}
	_draft_advance_to_user()
	return {"ok": true, "reason": "You drafted %s." % p.identity.full_name()}


## Lets the user's staff choose for the team (the same choice an AI team would make).
func draft_staff_pick() -> Dictionary:
	var status := draft_status()
	if status.is_empty() or status["complete"] or not status["user_on_clock"]:
		return {"ok": false, "reason": "It is not your turn to pick."}
	var choice := _off().ai_draft_choice(state.draft_state, state.user_team_id, _draft_rng())
	return user_draft_pick(choice)


## The staff picks for the user from now on and the draft finishes.
func draft_auto_rest() -> void:
	var off := _off()
	while not off.draft_complete(state.draft_state):
		var team := off.draft_team_on_clock(state.draft_state)
		off.make_pick(state.draft_state, league_id, off.ai_draft_choice(state.draft_state, team, _draft_rng()))
	_draft_finish()


func _draft_advance_to_user() -> void:
	var off := _off()
	while not off.draft_complete(state.draft_state) and off.draft_team_on_clock(state.draft_state) != state.user_team_id:
		var team := off.draft_team_on_clock(state.draft_state)
		off.make_pick(state.draft_state, league_id, off.ai_draft_choice(state.draft_state, team, _draft_rng()))
	if off.draft_complete(state.draft_state):
		_draft_finish()


## Ends the draft (undrafted players become free agents), runs the AI trades and opens
## the free-agency window.
func _draft_finish() -> void:
	if state.draft_state.is_empty():
		return
	var finished := season()
	var off := _off()
	_report_so_far["drafted"] = off.finish_draft(state.draft_state, finished)
	_report_so_far.merge(off.run_after_draft(league_id, finished, state.rng))
	state.draft_state = {}
	state.offseason_stage = 1
	if state.mode == FcGameState.MODE_OWNER and state.delegation["free_agency"]:
		_gm_sign_free_agents()


# --- contracts ending -----------------------------------------------------------------------

## The user's players whose contract ends with this season:
## [{"player", "age", "ask", "years", "agreed" (bool)}].
## In Owner Mode they leave as free agents unless agreed with extend_contract().
func expiring_players() -> Array:
	var w := state.world
	var team: FcTeam = w.teams.get_by_id(state.user_team_id)
	var rules := w.rules_of_league(league_id)
	var market := FcPlayerMarket.new(FcPlayerRatings.load_default())
	var out: Array = []
	for pid in team.roster.player_ids:
		var c := w.active_contract_of(pid)
		if c == null or c.end_season() > state.current_season:
			continue
		var p: FcPlayer = w.players.get_by_id(pid)
		var age: int = p.age_on(FcDate.new(state.current_season + 1, 7, 1))
		out.append({"player": p, "age": age, "ask": market.asking_salary(p, age, rules.cap), "years": market.desired_years(age, rules.cap), "agreed": state.agreed_extensions.has(pid)})
	return out


## Agrees to keep a player whose deal ends this season. When the season ends he is
## re-signed on a new contract at the agreed terms (own-player exception). With no
## terms given the contract is his asking price for the length he wants; a lower
## offer is accepted only if he is flexible enough (see FcPlayerMarket.minimum_acceptable).
## Returns {"ok": bool, "reason": String, "required": int (the least he accepts, if refused)}.
func extend_contract(player_id: int, salary_offered: int = -1, years_offered: int = -1) -> Dictionary:
	var w := state.world
	var team: FcTeam = w.teams.get_by_id(state.user_team_id)
	var rules := w.rules_of_league(league_id)
	if not team.roster.contains(player_id):
		return {"ok": false, "reason": "That player is not on your roster."}
	var c := w.active_contract_of(player_id)
	if c == null or c.end_season() > state.current_season:
		return {"ok": false, "reason": "Only players in the last year of their contract can be extended."}
	var p: FcPlayer = w.players.get_by_id(player_id)
	var market := FcPlayerMarket.new(FcPlayerRatings.load_default())
	var next_year := state.current_season + 1
	var age: int = p.age_on(FcDate.new(next_year, 7, 1))
	var ask := market.asking_salary(p, age, rules.cap)
	var years := clampi(years_offered if years_offered > 0 else market.desired_years(age, rules.cap), 1, rules.cap.max_contract_years)
	var wanted := clampi(salary_offered if salary_offered > 0 else ask, rules.cap.min_player_salary, rules.cap.max_player_salary)
	if state.agreed_extensions.has(player_id):
		return {"ok": false, "reason": "%s has already agreed to stay." % p.identity.full_name()}
	var verdict := market.evaluate_offer(p, age, rules.cap, wanted, years, true)
	if not verdict["accepted"]:
		return {"ok": false, "required": verdict["required"], "reason": "%s will not accept that: he wants at least %s a year for %d years." % [p.identity.full_name(), "$%.2fM" % (verdict["required"] / 1e6), years]}
	var check := rules.cap.check_signing(w.payroll_of_team(team.id, next_year), wanted, FcCapRules.SigningKind.OWN_PLAYER)
	if not check.allowed:
		return {"ok": false, "reason": "%s would get %s a year, but %s." % [p.identity.full_name(), "$%.1fM" % (wanted / 1e6), check.reason]}
	state.agreed_extensions.append(player_id)
	state.agreed_terms[player_id] = [wanted, years]
	return {"ok": true, "reason": "%s agreed to a new %d-year deal at %s a year, starting next season." % [p.identity.full_name(), years, "$%.2fM" % (wanted / 1e6)]}


# --- the draft ------------------------------------------------------------------------------

## The most recent draft of the league, for screens:
## {"year", "lottery" (bool), "rows": [{"round", "pick", "team", "player", "record_pick", "moved"}]}
## `record_pick` is where the team would have picked without a lottery and `moved`
## is record_pick - pick (positive = the lottery moved it up). Empty dictionary if no draft happened yet.
func latest_draft_report() -> Dictionary:
	var latest: FcSeason = null
	for s in state.world.seasons.all():
		if s.league_id == league_id and s.draft.size() > 0 and (latest == null or s.year > latest.year):
			latest = s
	if latest == null:
		return {}
	var qualified: Array[int] = []
	var missed: Array[int] = []
	for row in latest.final_standings:   # best record first
		if latest.playoffs != null and latest.playoffs.qualified(row[0]):
			qualified.append(row[0])
		else:
			missed.append(row[0])
	missed.reverse()
	qualified.reverse()
	var record_order: Array[int] = []
	record_order.append_array(missed)
	record_order.append_array(qualified)
	var team_count := record_order.size()
	var rules := state.world.rules_of_league(league_id)
	var rows: Array = []
	for pick in latest.draft:
		var original: int = pick[4] if pick.size() > 4 else pick[2]
		var record_pick: int = record_order.find(original) + 1 + (pick[0] - 1) * team_count
		rows.append({"round": pick[0], "pick": pick[1], "team": pick[2], "player": pick[3], "record_pick": record_pick, "moved": record_pick - pick[1]})
	return {"year": latest.year, "lottery": rules.draft.lottery_teams > 0, "rows": rows}


# --- free agents -------------------------------------------------------------------------

## Free agents (best first by market value): [{"player", "age", "ask", "years"}, ...].
func free_agent_market(limit: int = 30) -> Array:
	var w := state.world
	var rules := w.rules_of_league(league_id)
	var market := FcPlayerMarket.new(FcPlayerRatings.load_default())
	var year := contract_year()
	var out: Array = []
	for p in w.players.all():
		if p.status == FcPlayer.Status.ACTIVE and w.team_of_player(p.id) == null:
			var age: int = p.age_on(FcDate.new(year, 7, 1))
			out.append({"player": p, "age": age, "value": market.value(p, age), "ask": market.asking_salary(p, age, rules.cap), "years": market.desired_years(age, rules.cap)})
	out.sort_custom(func(a, b): return a["value"] > b["value"] if a["value"] != b["value"] else a["player"].id < b["player"].id)
	return out.slice(0, limit)


## Signs a free agent for the user's team. With no terms given: his asking price for the
## length he wants. A lower offer works only if he is flexible enough (see
## FcPlayerMarket.minimum_acceptable); a refusal says what he would accept. The legal route
## is the cheapest available: cap space, then the minimum contract (near-minimum players
## accept it), then the mid-level exception (once a season).
## Returns {"signed": bool, "reason": String, "required": int (the least he accepts, if refused)}.
func sign_free_agent(player_id: int, salary_offered: int = -1, years_offered: int = -1) -> Dictionary:
	if state.offseason_stage == 2:
		return {"signed": false, "reason": "Finish the draft first."}
	var w := state.world
	var team: FcTeam = w.teams.get_by_id(state.user_team_id)
	var p: FcPlayer = w.players.get_by_id(player_id)
	if p == null or p.status != FcPlayer.Status.ACTIVE or w.team_of_player(player_id) != null:
		return {"signed": false, "reason": "That player is not a free agent."}
	var rules := w.rules_of_league(league_id)
	if team.roster.size() >= rules.roster_max:
		return {"signed": false, "reason": "Your roster is full (%d players). Trade or release someone first." % rules.roster_max}
	var year := contract_year()
	var market := FcPlayerMarket.new(FcPlayerRatings.load_default())
	var age: int = p.age_on(FcDate.new(year, 7, 1))
	var ask := market.asking_salary(p, age, rules.cap)
	var years := clampi(years_offered if years_offered > 0 else market.desired_years(age, rules.cap), 1, rules.cap.max_contract_years)
	var offer := clampi(salary_offered if salary_offered > 0 else ask, rules.cap.min_player_salary, rules.cap.max_player_salary)
	var verdict := market.evaluate_offer(p, age, rules.cap, offer, years, false)
	if not verdict["accepted"]:
		return {"signed": false, "required": verdict["required"], "reason": "%s will not accept that: he wants at least %s a year for %d years." % [p.identity.full_name(), "$%.2fM" % (verdict["required"] / 1e6), years]}
	var payroll := w.payroll_of_team(team.id, year)
	var kind := -1
	var use_mle := false
	var last_reason := ""
	var check := rules.cap.check_signing(payroll, offer, FcCapRules.SigningKind.CAP_SPACE)
	if check.allowed:
		kind = FcCapRules.SigningKind.CAP_SPACE
	else:
		last_reason = check.reason
		var minimum_try := offer
		if salary_offered <= 0 and ask <= int(rules.cap.min_player_salary * 1.35):
			minimum_try = rules.cap.min_player_salary   # a default offer to a near-minimum player uses the minimum contract
		if minimum_try == rules.cap.min_player_salary:
			var min_check := rules.cap.check_signing(payroll, minimum_try, FcCapRules.SigningKind.MINIMUM)
			if min_check.allowed:
				offer = minimum_try
				kind = FcCapRules.SigningKind.MINIMUM
			else:
				last_reason = min_check.reason
		if kind < 0:
			var mle := rules.cap.check_signing(payroll, offer, FcCapRules.SigningKind.MID_LEVEL)
			if business().mid_level_used_season == year:
				last_reason = "your mid-level exception is already used this season"
			elif mle.allowed:
				kind = FcCapRules.SigningKind.MID_LEVEL
				use_mle = true
			else:
				last_reason = mle.reason
	if kind < 0:
		return {"signed": false, "reason": "%s would accept %s a year, but you cannot sign him: %s." % [p.identity.full_name(), "$%.2fM" % (offer / 1e6), last_reason]}
	var today := state.current_date
	var c := FcPlayerMarket.make_contract(w.ids.next_id(FcWorld.KIND_CONTRACT), p.id, team.id, year, years, offer, rules.cap, today)
	w.contracts.add(c)
	team.roster.add(p.id)
	if use_mle:
		business().mid_level_used_season = year
	w.add_news(today, "signing", "%s sign %s" % [w.team_display_name(team.id), p.identity.full_name()], team.id)
	return {"signed": true, "reason": "Signed %s for %s a year over %d years." % [p.identity.full_name(), "$%.2fM" % (offer / 1e6), c.length()]}


## Releases a player from the user's team. The team pays half of his current
## salary as a one-time buyout (from cash, any shortfall becomes debt), so dumping a
## bad contract is not free. The player becomes a free agent.
## Returns {"released": bool, "reason": String}.
func release_player(player_id: int) -> Dictionary:
	var w := state.world
	var team: FcTeam = w.teams.get_by_id(state.user_team_id)
	var rules := w.rules_of_league(league_id)
	if not team.roster.contains(player_id):
		return {"released": false, "reason": "That player is not on your roster."}
	if team.roster.size() <= rules.roster_min:
		return {"released": false, "reason": "You must keep at least %d players." % rules.roster_min}
	var c := w.active_contract_of(player_id)
	var cost := 0
	if c != null:
		cost = c.salary_for(contract_year()) / 2
		c.status = FcContract.Status.TERMINATED
	team.roster.remove(player_id)
	var b := business()
	var paid := mini(b.cash, cost)
	b.cash -= paid
	b.debt += cost - paid
	var name := w.player_name(player_id)
	w.add_news(state.current_date, "signing", "%s release %s" % [w.team_display_name(team.id), name], team.id)
	return {"released": true, "reason": "Released %s. Buyout cost: $%.1fM." % [name, cost / 1e6]}


# --- owner decisions --------------------------------------------------------------------

## Arena projects: [{"key", "name", "description", "cost", "seasons", "running" (bool)}].
func arena_project_options() -> Array:
	var scale := FcFinanceEngine.new(state.world).scale_for(state.world.rules_of_league(league_id))
	var out: Array = []
	for def in FcFinanceEngine.load_arena_projects()["projects"]:
		var running := false
		for p in business().projects:
			if p["key"] == def["key"]:
				running = true
		out.append({"key": def["key"], "name": def["name"], "description": def["description"], "cost": roundi(float(def["cost"]) * scale), "seasons": int(def["seasons"]), "running": running})
	return out


## Starts an arena project. Returns {"ok": bool, "reason": String}.
func start_arena_project(key: String) -> Dictionary:
	var w := state.world
	var team: FcTeam = w.teams.get_by_id(state.user_team_id)
	var finance := FcFinanceEngine.new(w)
	var problem := finance.start_project(business(), w.arenas.get_by_id(team.arena_id), key, finance.scale_for(w.rules_of_league(league_id)))
	if problem != "":
		return {"ok": false, "reason": problem}
	return {"ok": true, "reason": "Project started: %s." % FcFinanceEngine.project_def(key)["name"]}


## Chooses the sponsorship deal style: 0 balanced, 1 steady, 2 performance
## (see FcTeamBusiness.sponsor_plan). It applies when the season's books are settled.
func set_sponsor_plan(plan: int) -> bool:
	if plan < 0 or plan > 2:
		return false
	business().sponsor_plan = plan
	return true


## The most the owner may owe in total: a share of the franchise's value.
func loan_limit() -> int:
	var b := business()
	var value := b.valuation
	if value <= 0:   # saves made before valuations were set at the start
		var finance := FcFinanceEngine.new(state.world)
		value = finance.estimated_valuation(b, finance.scale_for(state.world.rules_of_league(league_id)))
	return roundi(value * float(FcFinanceEngine.load_constants()["loan_limit_share"]))


## Borrows money (it becomes debt, which costs interest every season).
## Returns {"ok": bool, "reason": String}.
func borrow(amount: int) -> Dictionary:
	var b := business()
	if amount <= 0:
		return {"ok": false, "reason": "Enter an amount above zero."}
	if b.debt + amount > loan_limit():
		return {"ok": false, "reason": "Lenders will not let you owe more than $%.1fM (you owe $%.1fM)." % [loan_limit() / 1e6, b.debt / 1e6]}
	b.cash += amount
	b.debt += amount
	return {"ok": true, "reason": "Borrowed $%.1fM." % (amount / 1e6)}


## Repays debt from cash. Returns {"ok": bool, "reason": String}.
func repay_debt(amount: int) -> Dictionary:
	var b := business()
	var paid := mini(mini(amount, b.debt), b.cash)
	if paid <= 0:
		return {"ok": false, "reason": "Nothing to repay (no debt, no cash, or no amount)."}
	b.cash -= paid
	b.debt -= paid
	return {"ok": true, "reason": "Repaid $%.1fM." % (paid / 1e6)}


func business() -> FcTeamBusiness:
	return state.world.businesses.get_by_id(state.user_team_id)


func set_ticket_price(price: int) -> bool:
	var scale := FcFinanceEngine.new(state.world).price_scale_for(state.world.rules_of_league(league_id), state.world.leagues.get_by_id(league_id))
	var lo := roundi(float(FcFinanceEngine.load_constants()["price_min"]) * scale)
	var hi := roundi(float(FcFinanceEngine.load_constants()["price_max"]) * scale)
	if price < lo or price > hi:
		return false
	business().ticket_price = price
	return true


func set_marketing_budget(amount: int) -> bool:
	if amount < 0 or amount > 400000000:
		return false
	business().marketing_budget = amount
	return true


func invest_in_facilities(points: int) -> bool:
	var finance := FcFinanceEngine.new(state.world)
	return finance.invest_in_facilities(business(), points, finance.scale_for(state.world.rules_of_league(league_id)))


## Staff without a job in a role, best reputation first, with their asking salary.
func staff_pool(role: int) -> Array[FcStaffMember]:
	var out: Array[FcStaffMember] = []
	for m in state.world.staff.all():
		if m.status == FcStaffMember.Status.ACTIVE and m.primary_role == role and state.world.active_staff_contract_of(m.id) == null:
			out.append(m)
	out.sort_custom(func(a: FcStaffMember, b: FcStaffMember): return a.reputation > b.reputation)
	return out


func asking_salary(staff_id: int) -> int:
	var m: FcStaffMember = state.world.staff.get_by_id(staff_id)
	var gen := FcStaffGenerator.new(FcGenerationData.load_default(), state.world.definitions)
	return gen.salary_for(m.primary_role, m.reputation)


## Ends the contract of the user's staff member in a unique role (GM or head coach)
## or a specific staff id. Returns false if nobody holds it.
func fire_staff(staff_id: int) -> bool:
	var c := state.world.active_staff_contract_of(staff_id)
	if c == null or c.team_id != state.user_team_id:
		return false
	c.status = FcContract.Status.TERMINATED
	engine.refresh_teams()
	return true


## Hires an unemployed staff member for the user's team. Unique roles (general
## manager, head coach) must be vacant. Returns an empty string on success or the reason.
func hire_staff(staff_id: int, role: int, years: int) -> String:
	var w := state.world
	var m: FcStaffMember = w.staff.get_by_id(staff_id)
	if m == null or m.status != FcStaffMember.Status.ACTIVE:
		return "that person is not available"
	if w.active_staff_contract_of(staff_id) != null:
		return "that person already has a job"
	if FcStaffRole.is_unique_per_team(role) and w.staff_in_role(state.user_team_id, role) != null:
		return "the team already has a %s; fire him first" % FcStaffRole.display_name(role)
	var salary := asking_salary(staff_id)
	var c := FcStaffContract.new(w.ids.next_id(FcWorld.KIND_STAFF_CONTRACT))
	c.staff_id = staff_id
	c.team_id = state.user_team_id
	c.role = role
	c.signed_on = state.current_date
	for i in clampi(years, 1, 5):
		c.years.append(FcContractYear.new(state.current_season + i, roundi(salary * pow(1.04, i) / 10000.0) * 10000))
	w.staff_contracts.add(c)
	engine.refresh_teams()
	return ""


## How the owner is doing: {"profit", "valuation", "valuation_change", "cash", "debt",
## "expected_wins", "wins", "approval"}. Approval (0-100) blends winning against
## expectations, profit and growth in the franchise's value for the last finished season.
func owner_report() -> Dictionary:
	var w := state.world
	var finance := FcFinanceEngine.new(w)
	var year := state.current_season if season().status == FcSeason.Status.COMPLETE else state.current_season - 1
	var rec := finance.record_of(state.user_team_id, year)
	var prev := finance.record_of(state.user_team_id, year - 1)
	if rec == null:
		return {}
	var cap: int = w.rules_of_league(league_id).cap.salary_cap
	var league_ranks := {}
	for t in w.teams.all():
		league_ranks[t.id] = w.payroll_of_team(t.id, year)
	var payroll_rank := 1
	for t in league_ranks:
		if league_ranks[t] > league_ranks[state.user_team_id]:
			payroll_rank += 1
	var games := rec.wins + rec.losses
	var expected := games * clampf(0.62 - 0.012 * (payroll_rank - 1) * 30.0 / maxf(1.0, w.teams.count()) * 1.0, 0.30, 0.65)
	var valuation_change := rec.valuation_end - (prev.valuation_end if prev != null else rec.valuation_end)
	var approval := 50.0 + (rec.wins - expected) * 1.5 + 25.0 * clampf(float(rec.profit()) / maxf(1.0, float(cap)), -0.4, 0.4) \
		+ 25.0 * clampf(float(valuation_change) / maxf(1.0, float(rec.valuation_end)), -0.2, 0.2)
	return {
		"year": year, "profit": rec.profit(), "revenue": rec.total_revenue(), "valuation": rec.valuation_end,
		"valuation_change": valuation_change, "cash": rec.cash_end, "debt": rec.debt_end,
		"wins": rec.wins, "expected_wins": roundi(expected), "playoff_rounds_won": rec.playoff_rounds_won,
		"approval": clampi(roundi(approval), 0, 100),
	}


# --- saving ---------------------------------------------------------------------------------

func autosave(manager: FcSaveManager) -> FcSaveResult:
	return manager.autosave(state)
