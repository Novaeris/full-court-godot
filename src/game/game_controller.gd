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
	sim_playoffs()
	var finished := season()
	var report := FcOffseason.new(state.world).run(league_id, finished, state.rng)
	state.current_season = finished.year + 1
	state.current_date = FcDate.new(state.current_season, 7, 1)
	_prepare_engine()
	_start_season(state.current_season)
	_update_date()
	return report


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


## Proposes a trade from the user's team. `preview` true only checks it.
## Returns {"accepted": bool, "reason": String}.
func propose_trade(ai_team_id: int, give_ids: Array, get_ids: Array, preview: bool = false) -> Dictionary:
	var desk := FcTradeDesk.new(state.world)
	return desk.propose(league_id, state.current_season, state.user_team_id, ai_team_id, give_ids, get_ids, is_contending(ai_team_id), not preview)


# --- owner decisions --------------------------------------------------------------------

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
