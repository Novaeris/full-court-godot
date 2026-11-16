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
		var record_pick: int = record_order.find(pick[2]) + 1 + (pick[0] - 1) * team_count
		rows.append({"round": pick[0], "pick": pick[1], "team": pick[2], "player": pick[3], "record_pick": record_pick, "moved": record_pick - pick[1]})
	return {"year": latest.year, "lottery": rules.draft.lottery_teams > 0, "rows": rows}


# --- free agents -------------------------------------------------------------------------

## Free agents (best first by market value): [{"player", "age", "ask", "years"}, ...].
func free_agent_market(limit: int = 30) -> Array:
	var w := state.world
	var rules := w.rules_of_league(league_id)
	var market := FcPlayerMarket.new(FcPlayerRatings.load_default())
	var year := state.current_season
	var out: Array = []
	for p in w.players.all():
		if p.status == FcPlayer.Status.ACTIVE and w.team_of_player(p.id) == null:
			var age: int = p.age_on(FcDate.new(year, 7, 1))
			out.append({"player": p, "age": age, "value": market.value(p, age), "ask": market.asking_salary(p, age, rules.cap), "years": market.desired_years(age, rules.cap)})
	out.sort_custom(func(a, b): return a["value"] > b["value"] if a["value"] != b["value"] else a["player"].id < b["player"].id)
	return out.slice(0, limit)


## Signs a free agent for the user's team at his asking price. The cheapest legal
## route is used: cap space, then the minimum contract (only for players asking
## close to the minimum), then the mid-level exception (once a season).
## Returns {"signed": bool, "reason": String}.
func sign_free_agent(player_id: int) -> Dictionary:
	var w := state.world
	var team: FcTeam = w.teams.get_by_id(state.user_team_id)
	var p: FcPlayer = w.players.get_by_id(player_id)
	if p == null or p.status != FcPlayer.Status.ACTIVE or w.team_of_player(player_id) != null:
		return {"signed": false, "reason": "That player is not a free agent."}
	var rules := w.rules_of_league(league_id)
	if team.roster.size() >= rules.roster_max:
		return {"signed": false, "reason": "Your roster is full (%d players). Trade or release someone first." % rules.roster_max}
	var year := state.current_season
	var market := FcPlayerMarket.new(FcPlayerRatings.load_default())
	var age: int = p.age_on(FcDate.new(year, 7, 1))
	var ask := market.asking_salary(p, age, rules.cap)
	var payroll := w.payroll_of_team(team.id, year)
	var offer := ask
	var kind := -1
	var use_mle := false
	var last_reason := ""
	var check := rules.cap.check_signing(payroll, ask, FcCapRules.SigningKind.CAP_SPACE)
	if check.allowed:
		kind = FcCapRules.SigningKind.CAP_SPACE
	else:
		last_reason = check.reason
		if ask <= int(rules.cap.min_player_salary * 1.35):
			offer = rules.cap.min_player_salary
			var min_check := rules.cap.check_signing(payroll, offer, FcCapRules.SigningKind.MINIMUM)
			if min_check.allowed:
				kind = FcCapRules.SigningKind.MINIMUM
			else:
				last_reason = min_check.reason
		if kind < 0:
			var mle := rules.cap.check_signing(payroll, ask, FcCapRules.SigningKind.MID_LEVEL)
			if business().mid_level_used_season == year:
				last_reason = "your mid-level exception is already used this season"
			elif mle.allowed:
				kind = FcCapRules.SigningKind.MID_LEVEL
				use_mle = true
			else:
				last_reason = mle.reason
	if kind < 0:
		return {"signed": false, "reason": "%s asks %s a year, and you cannot sign him: %s." % [p.identity.full_name(), "$%.1fM" % (ask / 1e6), last_reason]}
	var today := state.current_date
	var c := FcPlayerMarket.make_contract(w.ids.next_id(FcWorld.KIND_CONTRACT), p.id, team.id, year, market.desired_years(age, rules.cap), offer, rules.cap, today)
	w.contracts.add(c)
	team.roster.add(p.id)
	if use_mle:
		business().mid_level_used_season = year
	w.add_news(today, "signing", "%s sign %s" % [w.team_display_name(team.id), p.identity.full_name()], team.id)
	return {"signed": true, "reason": "Signed %s for %s a year over %d years." % [p.identity.full_name(), "$%.1fM" % (offer / 1e6), c.length()]}


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
		cost = c.salary_for(state.current_season) / 2
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

## Chooses the sponsorship deal style: 0 balanced, 1 steady, 2 performance
## (see FcTeamBusiness.sponsor_plan). It applies when the season's books are settled.
func set_sponsor_plan(plan: int) -> bool:
	if plan < 0 or plan > 2:
		return false
	business().sponsor_plan = plan
	return true


## The most the owner may owe in total: a share of the franchise's value.
func loan_limit() -> int:
	return roundi(business().valuation * float(FcFinanceEngine.load_constants()["loan_limit_share"]))


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
