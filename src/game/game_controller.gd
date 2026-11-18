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
## Owner Mode only: the league owners are meeting after the season to vote on rule changes.
const PHASE_MEETING := "meeting"
## Owner Mode only: the league has approved an expansion and the owner chooses whom to protect.
const PHASE_EXPANSION := "expansion"
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


## Career Mode: the team being followed changes (the career player was signed or moved).
func follow_team(team_id: int) -> void:
	state.user_team_id = team_id
	league_id = state.world.league_of_team(team_id).id
	engine.watched_teams = [team_id] as Array[int]


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
				3: return PHASE_MEETING
				4: return PHASE_EXPANSION
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
			if state.mode == FcGameState.MODE_OWNER and state.delegation["injuries"]:
				_gm_cover_injuries(s)
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
	if state.offseason_stage == 3:
		close_meeting()
	if state.offseason_stage == 4:
		run_expansion_draft()
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
	state.agreed_staff_terms.clear()
	for tid in state.ai_relations:   # the clubs forget a little of the past trades each season
		state.ai_relations[tid]["wary"] = maxi(0, int(state.ai_relations[tid]["wary"]) - 1)
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
	offseason.agreed_staff_terms = state.agreed_staff_terms.duplicate(true)
	if state.mode == FcGameState.MODE_OWNER and not state.delegation["free_agency"]:
		offseason.manual_free_agency_team_ids = [state.user_team_id] as Array[int]
	return offseason


## First half of the offseason: finishes the season if needed, then aging and retirement,
## contracts ending, re-signing the agreed players, the draft and AI trades. Afterwards,
## in Owner Mode, the phase is PHASE_OFFSEASON and the owner can sign free agents and
## release players before start_next_season() lets the AI teams sign players.
## Returns the report so far.
func begin_offseason() -> Dictionary:
	if state.offseason_stage == 3:
		close_meeting()
	if state.offseason_stage == 4:
		run_expansion_draft()   # the owner skipped the meeting: nothing was voted for, the AI owners decide alone
	sim_playoffs()
	var finished := season()
	_gm_log = []
	if state.mode == FcGameState.MODE_OWNER:
		_record_owner_season()
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
	_apply_restructuring(report.get("economy", {}), finished.year)
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


## Offers other teams make to the owner (see FcTradeOffers): during the regular season (new ones
## every two weeks) and in the free-agency window. [{"team", "name", "give", "get"}] where
## give is the owner's player and get is the AI team's player. Declined offers stay hidden until the next batch.
func trade_offers() -> Array:
	if state.mode != FcGameState.MODE_OWNER or state.offseason_stage == 2:
		return []
	var bucket := 0
	match phase():
		PHASE_REGULAR:
			bucket = season().next_day / 14
		PHASE_OFFSEASON:
			bucket = 1000
		_:
			return []
	var offers := FcTradeOffers.new(state.world).generate(league_id, contract_year(), state.user_team_id, is_contending, bucket, first_tradable_pick_year())
	var visible: Array = []
	for o in offers:
		if not _declined_offers.has("%d:%d:%d:%d" % [bucket, o["team"], o["give"], o["get"]]):
			o["bucket"] = bucket
			visible.append(o)
	return visible


var _declined_offers: Dictionary = {}


func decline_trade_offer(offer: Dictionary) -> void:
	_declined_offers["%d:%d:%d:%d" % [offer["bucket"], offer["team"], offer["give"], offer["get"]]] = true


## Accepts one of the current offers (it is checked again against the rules). Returns the
## same {"accepted", "reason"} as propose_trade.
func accept_trade_offer(offer: Dictionary) -> Dictionary:
	for o in trade_offers():
		if o["team"] == offer["team"] and o["give"] == offer["give"] and o["get"] == offer["get"]:
			return propose_trade(o["team"], [o["give"]], [o["get"]])
	return {"accepted": false, "reason": "That offer is no longer available."}


## Proposes a trade from the user's team. `preview` true only checks it.
## Returns {"accepted": bool, "reason": String}.
func propose_trade(ai_team_id: int, give_ids: Array, get_ids: Array, preview: bool = false, give_picks: Array = [], get_picks: Array = []) -> Dictionary:
	if state.offseason_stage == 2:
		return {"accepted": false, "reason": "Finish the draft first."}
	var desk := FcTradeDesk.new(state.world)
	var result := desk.propose(league_id, contract_year(), state.user_team_id, ai_team_id, give_ids, get_ids, is_contending(ai_team_id), not preview, give_picks, get_picks, first_tradable_pick_year(), gm_negotiation(), ai_wariness(ai_team_id))
	if result["accepted"] and not preview:
		_relation(ai_team_id)["wary"] = mini(6, ai_wariness(ai_team_id) + 2)   # that club remembers the deal
	return result


## How wary an AI club is of the owner's offers (0-6, see FcGameState.ai_relations).
func ai_wariness(team_id: int) -> int:
	return int(state.ai_relations.get(team_id, {}).get("wary", 0))


## An AI owner's rapport with the player (-6 to 6), built at the owners' meetings.
func ai_rapport(team_id: int) -> int:
	return int(state.ai_relations.get(team_id, {}).get("rapport", 0))


func _relation(team_id: int) -> Dictionary:
	if not state.ai_relations.has(team_id):
		state.ai_relations[team_id] = {"wary": 0, "rapport": 0}
	return state.ai_relations[team_id]


func _rapport_map() -> Dictionary:
	var out := {}
	for tid in state.ai_relations:
		out[tid] = int(state.ai_relations[tid].get("rapport", 0))
	return out


## After a meeting: old feelings fade by one point; owners who voted the way the player stood (or the player's
## own proposal) like the player more; owners who voted against, and owners the player had to lobby, like them less.
func _update_rapport(items: Array) -> void:
	for tid in state.ai_relations:
		var r: Dictionary = state.ai_relations[tid]
		r["rapport"] = int(r["rapport"]) - signi(int(r["rapport"]))
	for entry in items:
		var item: Dictionary = entry["item"]
		var stand = entry["user_vote"]
		if stand == null and item.get("proposed", false):
			stand = true
		if stand == null:
			continue
		var lobbied: Array = state.meeting.get("lobbied", {}).get(item["id"], [])
		for v in entry["tally"]["votes"]:
			var r := _relation(v["team"])
			if lobbied.has(v["team"]):
				r["rapport"] = clampi(int(r["rapport"]) - 1, -6, 6)
			elif v["yes"] == stand:
				r["rapport"] = clampi(int(r["rapport"]) + 1, -6, 6)
			else:
				r["rapport"] = clampi(int(r["rapport"]) - 1, -6, 6)


# --- the owner's career: reputation and changing jobs -----------------------------------------

## When lenders restructured the owner's debt in the offseason: the owner keeps the club (D-029) but loses reputation
## and the restructuring is logged ([year, team id, dollars written off]).
func _apply_restructuring(economy_report: Dictionary, year: int) -> void:
	for entry in economy_report.get("restructured", []):
		if int(entry["team"]) != state.user_team_id:
			continue
		var penalty := int(FcEconomy.load_constants()["restructure_reputation_penalty"])
		state.owner_career["reputation"] = maxi(0, int(state.owner_career["reputation"]) - penalty)
		state.owner_career["restructurings"].append([year, state.user_team_id, int(entry["written_off"])])
		_gm_log.append("Lenders restructured your debt ($%.1fM written off). Your reputation fell by %d and new loans are frozen for %d seasons." % [int(entry["written_off"]) / 1e6, penalty, int(FcEconomy.load_constants()["restructure_lockout_seasons"])])


## A plain-language warning about the owner's finances ("" when all is well): loans frozen, debt close to a
## restructuring, or a loss-making club with debt. Shown on the Overview and Finances tabs.
func distress_warning() -> String:
	if state.mode != FcGameState.MODE_OWNER:
		return ""
	var b := business()
	var cap := state.world.rules_of_league(league_id).cap.salary_cap
	var k := FcEconomy.load_constants()
	if loans_frozen():
		return "Lenders restructured your debt and froze new loans for %d more seasons. Your reputation took a hit. Raise income or lower payroll." % (int(k["restructure_lockout_seasons"]) - (state.current_season - b.restructured_year))
	var base := maxi(b.valuation, roundi(float(k["restructure_floor_cap_share"]) * cap))
	if b.debt > 0 and float(b.debt) > 0.7 * float(k["restructure_trigger_share"]) * base:
		return "Your debt ($%.0fM) is close to your club's value. Past 100%% lenders will restructure it: part is written off, your reputation falls and loans freeze. Cut payroll, reprice tickets or sell assets." % (b.debt / 1e6)
	var rec := FcFinanceEngine.new(state.world).record_of(state.user_team_id, state.current_season if season().status == FcSeason.Status.COMPLETE else state.current_season - 1)
	if b.debt > 0 and rec != null and rec.profit() < 0:
		return "You lost $%.0fM last season and carry $%.0fM of debt. Your general manager now limits payroll to 65%% of revenue (unless the budget is aggressive)." % [-rec.profit() / 1e6, b.debt / 1e6]
	return ""


## True while new loans are frozen after a restructuring.
func loans_frozen() -> bool:
	var b := business()
	return b.restructured_year > 0 and state.current_season - b.restructured_year < int(FcEconomy.load_constants()["restructure_lockout_seasons"])


## The owner's reputation (0-100): built from how owners of the franchise did each season.
func owner_reputation() -> int:
	if state.mode == FcGameState.MODE_OWNER and season().status == FcSeason.Status.COMPLETE:
		_record_owner_season()   # the finished season counts as soon as it is over
	return int(state.owner_career["reputation"])


## One row per finished season as owner: [[year, team id, approval, wins, title], ...].
func owner_history() -> Array:
	return state.owner_career["history"]


## At the end of a season: reputation moves toward the owner's approval (70% old, 30% new) and
## a title adds 5. Recorded once per season.
func _record_owner_season() -> void:
	var year := state.current_season
	var history: Array = state.owner_career["history"]
	for row in history:
		if row[0] == year:
			return
	var report := owner_report()
	if report.is_empty():
		return
	var title := 1 if season().champion_id == state.user_team_id else 0
	history.append([year, state.user_team_id, report["approval"], report["wins"], title])
	state.owner_career["reputation"] = clampi(roundi(0.7 * owner_reputation() + 0.3 * report["approval"]) + 5 * title, 0, 100)


## Franchises ranked by value, as a fraction: 0 = the least valuable team, 1 = the most.
func _prestige() -> Dictionary:
	var ranked: Array = []
	var w := state.world
	for tid in w.leagues.get_by_id(league_id).all_team_ids():
		var b: FcTeamBusiness = w.businesses.get_by_id(tid)
		ranked.append([b.valuation if b != null else 0, tid])
	ranked.sort()
	var out := {}
	for i in ranked.size():
		out[ranked[i][1]] = float(i) / maxf(1.0, ranked.size() - 1.0)
	return out


## Teams the owner could move to when the season is over: a better reputation opens the more
## valuable franchises (a team is on offer if its prestige is at most reputation/100 + 0.25),
## and a weaker team is always among them. Up to 3 offers, the same every time you look.
## [{"team", "name", "valuation", "wins", "payroll", "fan_interest", "cash", "debt", "seats"}].
func job_offers() -> Array:
	if state.mode != FcGameState.MODE_OWNER or phase() != PHASE_COMPLETE:
		return []
	var w := state.world
	var prestige := _prestige()
	var allowed: Array = []
	for tid in prestige:
		if tid != state.user_team_id and prestige[tid] <= owner_reputation() / 100.0 + 0.25:
			allowed.append(tid)
	allowed.sort()
	var rng := FcRng.new(hash("jobs:%d:%d" % [state.user_team_id, state.current_season]))
	var picks: Array[int] = []
	var pool := allowed.duplicate()
	while picks.size() < 3 and not pool.is_empty():
		var index := rng.range_int(0, pool.size() - 1)
		picks.append(pool[index])
		pool.remove_at(index)
	var finance := FcFinanceEngine.new(w)
	var st := standings()
	var out: Array = []
	for tid in picks:
		var team: FcTeam = w.teams.get_by_id(tid)
		var b: FcTeamBusiness = w.businesses.get_by_id(tid)
		out.append({"team": tid, "name": w.team_display_name(tid), "valuation": b.valuation, "wins": st.records[tid]["w"],
			"payroll": w.payroll_of_team(tid, state.current_season), "fan_interest": b.fan_interest, "cash": b.cash, "debt": b.debt,
			"seats": w.arenas.get_by_id(team.arena_id).capacity})
	out.sort_custom(func(a, b): return a["valuation"] > b["valuation"])
	return out


## Takes over another franchise (one of the current job offers), once per season, before the
## offseason begins. The old team goes back to the AI. Everything you decided for the old team
## that is still pending (agreed extensions) is dropped. Returns {"ok": bool, "reason": String}.
func transfer_to(team_id: int) -> Dictionary:
	var offered := false
	for offer in job_offers():
		if offer["team"] == team_id:
			offered = true
	if not offered:
		return {"ok": false, "reason": "That team has not offered you the job."}
	if int(state.owner_career["transfer_year"]) == state.current_season:
		return {"ok": false, "reason": "You already changed teams this season."}
	_record_owner_season()
	var w := state.world
	var old_name := w.team_display_name(state.user_team_id)
	state.user_team_id = team_id
	state.owner_career["transfer_year"] = state.current_season
	state.agreed_extensions.clear()
	state.agreed_terms.clear()
	state.agreed_staff_terms.clear()
	_prepare_engine()
	w.add_news(state.current_date, "staff", "%s's owner moves on: %s now has a new owner." % [old_name, w.team_display_name(team_id)], team_id)
	return {"ok": true, "reason": "You are now the owner of %s." % w.team_display_name(team_id)}


# --- the owners' meeting (Owner Mode) ----------------------------------------------------------

func _meeting() -> FcOwnersMeeting:
	return FcOwnersMeeting.new(state.world, league_id)


## True once this season's meeting has been held (it is held once a year, after the season).
func meeting_held() -> bool:
	return state.meeting_year == state.current_season


## Opens the owners' meeting (Owner Mode, season over, before the offseason begins, once a
## season). Returns false if it cannot or there is nothing on the agenda.
func open_meeting() -> bool:
	if state.mode != FcGameState.MODE_OWNER or phase() != PHASE_COMPLETE or meeting_held():
		return false
	var items := _meeting().agenda(state.current_season, state.last_expansion_year, state.user_team_id, state.relocation_log)
	if items.is_empty():
		state.meeting_year = state.current_season
		return false
	var finance := FcFinanceEngine.new(state.world)
	var team: FcTeam = state.world.teams.get_by_id(state.user_team_id)
	var points := FcOwnersMeeting.influence_income(owner_reputation(), finance.market_factor(state.world.cities.get_by_id(team.city_id)))
	state.meeting = {"year": state.current_season, "items": items, "votes": {}, "lobbied": {}, "influence": points, "proposed": false}
	state.offseason_stage = 3
	return true


## The agenda with the current tally of each item: [{"item", "tally", "user_vote" (null/true/false)}].
func meeting_items() -> Array:
	var out: Array = []
	if state.meeting.is_empty():
		return out
	for item in state.meeting["items"]:
		var vote = state.meeting["votes"].get(item["id"], null)
		out.append({"item": item, "tally": _meeting().tally(item, season(), state.current_season, state.user_team_id, vote, state.meeting["lobbied"].get(item["id"], []), _rapport_map()), "user_vote": vote})
	return out


## The player's vote on an item of the agenda. Returns false outside the meeting.
func cast_meeting_vote(item_id: String, yes: bool) -> bool:
	if state.offseason_stage != 3:
		return false
	for item in state.meeting["items"]:
		if item["id"] == item_id:
			state.meeting["votes"][item_id] = yes
			return true
	return false


## The influence points the owner has left in this meeting.
func meeting_influence() -> int:
	return int(state.meeting.get("influence", 0))


## Spends influence to turn one AI owner's vote on an item (a no becomes a yes, a yes becomes a no).
## The cost depends on how strongly the owner leans (1 to 3 points); each owner can be lobbied once
## per item. Returns {"ok": bool, "reason": String, "cost": int}.
func lobby_owner(item_id: String, team_id: int) -> Dictionary:
	if state.offseason_stage != 3:
		return {"ok": false, "reason": "There is no meeting going on.", "cost": 0}
	for entry in meeting_items():
		if entry["item"]["id"] != item_id:
			continue
		for v in entry["tally"]["votes"]:
			if v["team"] != team_id:
				continue
			if v["flipped"]:
				return {"ok": false, "reason": "You already lobbied %s on this." % v["name"], "cost": 0}
			if v["cost"] > meeting_influence():
				return {"ok": false, "reason": "Turning %s costs %d points and you have %d." % [v["name"], v["cost"], meeting_influence()], "cost": v["cost"]}
			state.meeting["influence"] = meeting_influence() - v["cost"]
			var list: Array = state.meeting["lobbied"].get(item_id, [])
			list.append(team_id)
			state.meeting["lobbied"][item_id] = list
			return {"ok": true, "reason": "%s will now vote %s (cost %d)." % [v["name"], "no" if v["yes"] else "yes", v["cost"]], "cost": v["cost"]}
	return {"ok": false, "reason": "That owner or proposal is not part of the meeting.", "cost": 0}


## Proposals the owner could still add to the agenda (one per meeting, FcOwnersMeeting.PROPOSE_COST points).
func proposable_items() -> Array:
	if state.offseason_stage != 3 or state.meeting.get("proposed", false):
		return []
	return _meeting().proposable(state.current_season, state.meeting["items"], state.last_expansion_year, state.user_team_id, state.relocation_log)


## Adds one of proposable_items() to the agenda. Returns {"ok": bool, "reason": String}.
func propose_item(kind: String) -> Dictionary:
	if state.offseason_stage != 3:
		return {"ok": false, "reason": "There is no meeting going on."}
	if state.meeting.get("proposed", false):
		return {"ok": false, "reason": "You have already put an item on the agenda this year."}
	if meeting_influence() < FcOwnersMeeting.PROPOSE_COST:
		return {"ok": false, "reason": "Proposing costs %d points and you have %d." % [FcOwnersMeeting.PROPOSE_COST, meeting_influence()]}
	for item in proposable_items():
		if item["id"] == kind:
			return _add_proposal(item)
	return {"ok": false, "reason": "That cannot be proposed right now."}


func _add_proposal(item: Dictionary) -> Dictionary:
	state.meeting["items"].append(item)
	state.meeting["influence"] = meeting_influence() - FcOwnersMeeting.PROPOSE_COST
	state.meeting["proposed"] = true
	return {"ok": true, "reason": "Your proposal is on the agenda: %s." % item["title"]}


## The cities the owner's franchise could move to, biggest first: [{"name", "region", "population"}].
## Empty if the team may not move this year (moved in the last 10 years, or no meeting).
func relocation_options() -> Array:
	var relocation := FcRelocation.new(state.world, league_id)
	if not relocation.allowed(state.user_team_id, state.current_season, state.relocation_log):
		return []
	var out: Array = []
	for entry in relocation.destinations(state.user_team_id):
		out.append({"name": str(entry["name"]), "region": str(entry["region"]), "population": int(entry["population"])})
	return out


## Puts a move of the owner's own team on the agenda with the destination city and (optionally) a new team
## name chosen by the owner. Costs the same as any proposal. Returns {"ok": bool, "reason": String}.
func propose_relocation(city_name: String, new_nickname: String = "") -> Dictionary:
	if state.offseason_stage != 3:
		return {"ok": false, "reason": "There is no meeting going on."}
	if state.meeting.get("proposed", false):
		return {"ok": false, "reason": "You have already put an item on the agenda this year."}
	if meeting_influence() < FcOwnersMeeting.PROPOSE_COST:
		return {"ok": false, "reason": "Proposing costs %d points and you have %d." % [FcOwnersMeeting.PROPOSE_COST, meeting_influence()]}
	var relocation := FcRelocation.new(state.world, league_id)
	if not relocation.allowed(state.user_team_id, state.current_season, state.relocation_log):
		return {"ok": false, "reason": "Your team moved recently and may not move again yet."}
	var problem := relocation.nickname_problem(state.user_team_id, new_nickname)
	if problem != "":
		return {"ok": false, "reason": problem}
	for existing in state.meeting["items"]:
		if existing["id"] == "relocate:%d" % state.user_team_id:
			return {"ok": false, "reason": "Your move is already on the agenda."}
	var item := _meeting().relocation_item(state.user_team_id, state.current_season, city_name, new_nickname)
	if item.is_empty():
		return {"ok": false, "reason": "That city is not available."}
	item["proposed"] = true
	return _add_proposal(item)


## Counts the votes: every proposal that gets enough yes votes becomes the league's rule, news
## and the log record the outcome, and the meeting ends. Returns
## [{"title", "passed", "yes", "no", "needed", "enacted"}].
func close_meeting() -> Array:
	var results: Array = []
	if state.offseason_stage != 3:
		return results
	var meeting := _meeting()
	var expansion_approved := false
	var entries := meeting_items()
	_update_rapport(entries)
	for entry in entries:
		var item: Dictionary = entry["item"]
		var tally: Dictionary = entry["tally"]
		var enacted := false
		if tally["passes"] and item["id"] == "expansion":
			enacted = true   # carried out by the expansion draft that follows
			expansion_approved = true
			state.last_expansion_year = state.current_season
		elif tally["passes"] and str(item["id"]).begins_with("relocate:"):
			var mover := int(item["mover"])
			var old_city: String = state.world.cities.get_by_id(state.world.teams.get_by_id(mover).city_id).name
			enacted = meeting.enact(item["id"], state.user_team_id, state.current_season, item)
			if enacted:
				state.relocation_log.append([state.current_season, mover, old_city, state.world.cities.get_by_id(state.world.teams.get_by_id(mover).city_id).name])
		elif tally["passes"]:
			enacted = meeting.enact(item["id"], state.user_team_id, state.current_season)
		results.append({"title": item["title"], "passed": tally["passes"], "yes": tally["yes"], "no": tally["no"], "needed": tally["needed"], "enacted": enacted})
		state.meeting_log.append([state.current_season, item["title"], 1 if enacted else 0, tally["yes"], tally["no"]])
		state.world.add_news(state.current_date, "staff", "Owners' meeting: \"%s\" %s (%d for, %d against)." % [item["title"], "passed" if enacted else "failed", tally["yes"], tally["no"]])
	state.meeting = {}
	state.meeting_year = state.current_season
	state.offseason_stage = 0
	if expansion_approved:
		state.expansion = {"year": state.current_season, "protected": FcExpansion.new(state.world, league_id).default_protected(state.user_team_id, state.current_season)}
		state.offseason_stage = 4
	return results


# --- the expansion draft (Owner Mode) -----------------------------------------------------------

## While an approved expansion waits for the owner's protected list:
## {"protected": [player ids], "limit", "new_teams", "picks_per_team", "size"}; {} otherwise.
func expansion_status() -> Dictionary:
	if state.offseason_stage != 4:
		return {}
	var expansion := FcExpansion.new(state.world, league_id)
	var plan_data := expansion.plan(state.current_season)
	if plan_data.is_empty():
		return {}
	return {"protected": state.expansion["protected"], "limit": FcExpansion.PROTECTED_PER_TEAM, "new_teams": plan_data["delta"], "size": plan_data["size"],
		"picks_per_team": expansion.picks_per_new_team(plan_data["delta"], state.world.leagues.get_by_id(league_id).team_count())}


## Chooses the players to protect (at most FcExpansion.PROTECTED_PER_TEAM, all on the owner's roster).
func set_protected_players(player_ids: Array) -> Dictionary:
	if state.offseason_stage != 4:
		return {"ok": false, "reason": "There is no expansion draft pending."}
	var team: FcTeam = state.world.teams.get_by_id(state.user_team_id)
	if player_ids.size() > FcExpansion.PROTECTED_PER_TEAM:
		return {"ok": false, "reason": "You can protect at most %d players." % FcExpansion.PROTECTED_PER_TEAM}
	var kept: Array[int] = []
	for pid in player_ids:
		if not team.roster.contains(pid):
			return {"ok": false, "reason": "A protected player is not on your roster."}
		kept.append(pid)
	state.expansion["protected"] = kept
	return {"ok": true, "reason": "%d players protected." % kept.size()}


## Runs the expansion draft with the owner's protected list (the best players if none was chosen),
## creates the new teams and returns to the normal offseason. Returns the result of
## FcExpansion.execute plus "lost" (the owner's players that were taken: [[player id, new team id]]).
func run_expansion_draft() -> Dictionary:
	if state.offseason_stage != 4:
		return {}
	var year: int = state.expansion["year"]
	var result := FcExpansion.new(state.world, league_id).execute(year, state.user_team_id, state.expansion["protected"])
	state.expansion = {}
	state.offseason_stage = 0
	var lost: Array = []
	state.expansion_log = []
	for pick in result.get("picks", []):
		state.expansion_log.append([year, pick[0], pick[1], pick[2], pick[3]])
		if pick[3] == state.user_team_id:
			lost.append([pick[2], pick[1]])
	result["lost"] = lost
	_prepare_engine()
	return result


# --- the draft (Owner Mode) -----------------------------------------------------------------

## What the general manager did for the owner this offseason (shown in the UI).
var _gm_log: Array[String] = []


## The general manager's talent evaluation (0-100) and name, or {} if there is no GM.
## The owner's general manager's negotiation skill (0-100): it lowers what players, staff and AI teams
## ask for in the owner's deals. A club with no general manager negotiates at 35 (a poor level).
func gm_negotiation() -> float:
	var gm := state.world.staff_in_role(state.user_team_id, FcStaffRole.Id.GENERAL_MANAGER)
	return gm.skills.get_value("negotiation") if gm != null else 35.0


## How well the owner's staff works together: see FcStaffChemistry.evaluate. `staff_id` and `role` preview
## the chemistry if that person were hired (a unique role is replaced).
func staff_chemistry(staff_id: int = 0, role: int = 0) -> Dictionary:
	var replace := {}
	if staff_id > 0:
		replace = {"role": role, "staff_id": staff_id}
	return FcStaffChemistry.new(state.world).evaluate(state.user_team_id, contract_year(), replace)


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


## The owner's direction. philosophy: "win_now", "balanced" or "rebuild"; budget: "frugal",
## "normal" or "aggressive". Returns false for unknown values or outside Owner Mode.
func set_direction(philosophy: String, budget: String) -> bool:
	if not FcGameState.PHILOSOPHIES.has(philosophy) or not FcGameState.BUDGETS.has(budget) or state.mode != FcGameState.MODE_OWNER:
		return false
	state.direction["philosophy"] = philosophy
	state.direction["budget"] = budget
	return true


func philosophy() -> String:
	return state.direction["philosophy"]


## The most payroll the GM may commit: a share of the cap by budget (frugal 92%, normal 100%,
## aggressive 115% but never above the luxury tax line), and no more than 65% of last season's
## revenue (never below the league's minimum payroll) unless the budget is aggressive.
func gm_payroll_limit() -> int:
	var cap := state.world.rules_of_league(league_id).cap
	var share: float = {"frugal": 0.92, "normal": 1.0, "aggressive": 1.15}[state.direction["budget"]]
	var limit := roundi(cap.salary_cap * share)
	if state.direction["budget"] == "aggressive" and cap.luxury_tax_line > 0:
		limit = mini(limit, cap.luxury_tax_line)
	# the GM spends the owner's money carefully: a frugal or normal budget is held to 65% of last season's revenue (never
	# below the league's minimum payroll), whether or not the club is in debt yet. Only an "aggressive" budget, the owner's
	# explicit choice, spends beyond the club's means. (Found by the 50-season owner runs: a GM spending to the cap
	# bankrupts small markets.)
	if state.direction["budget"] != "aggressive":
		var ceiling := FcEconomy.new(state.world).payroll_ceiling(state.user_team_id, true)
		if ceiling >= 0:
			limit = mini(limit, maxi(ceiling, cap.minimum_payroll))
	return limit


## How strongly the direction tilts choices toward potential (+) or the present (-).
func _philosophy_emphasis() -> float:
	return {"win_now": -0.3, "balanced": 0.0, "rebuild": 0.3}[state.direction["philosophy"]]


## How the GM sees a player's worth: the market value plus an error that shrinks with the
## GM's (and scouts') talent evaluation, the same for the same player every time.
func _gm_value(p: FcPlayer, age: int, market: FcPlayerMarket) -> float:
	var noise := FcRng.new(hash("gm:%d:%d" % [state.user_team_id, p.id])).gaussian(0.0, maxf(0.5, _off().draft_noise(state.user_team_id)))
	var value := market.value(p, age) + noise - 2.0 * maxf(0.0, age - 32)   # the GM does not bet on very old players
	match state.direction["philosophy"]:
		"win_now":
			value -= 0.2 * (p.development.potential - FcPlayerRatings.load_default().overall(p))
		"rebuild":
			value += 0.25 * (p.development.potential - FcPlayerRatings.load_default().overall(p)) - 0.8 * maxf(0.0, age - 27)
	return value


## Re-signing by the GM: he keeps players he believes are worth at least the keep line
## (value points), at their asking price, as far as the cap allows.
const GM_KEEP_VALUE := 50.0
## The GM measures players against the league's rotation level (the average value of each team's
## eighth best player, which rises as the league's talent grows): he keeps players within
## GM_KEEP_MARGIN of it and signs free agents above it, never below the fixed minimums.
const GM_KEEP_MARGIN := 2.0
const GM_SIGN_MARGIN := 1.0
## Staff with at least this reputation are kept when the GM handles contracts.
const GM_KEEP_STAFF_REPUTATION := 40
const GM_FREE_AGENT_VALUE := 52.0
const GM_MAX_SIGNINGS := 3


## The average value of the eighth best player of each team: what a rotation player is worth now.
func _league_rotation_value(market: FcPlayerMarket) -> float:
	var w := state.world
	var total := 0.0
	var count := 0
	for tid in w.leagues.get_by_id(league_id).all_team_ids():
		var values: Array = []
		for pid in w.teams.get_by_id(tid).roster.player_ids:
			var p: FcPlayer = w.players.get_by_id(pid)
			values.append(market.value(p, p.age_on(FcDate.new(state.current_season + 1, 7, 1))))
		values.sort()
		values.reverse()
		if values.size() >= 8:
			total += values[7]
			count += 1
	return total / count if count > 0 else GM_KEEP_VALUE


func _gm_re_sign_players() -> void:
	for entry in expiring_staff():
		if entry["agreed"] or entry["member"].reputation < GM_KEEP_STAFF_REPUTATION:
			continue
		var kept := extend_staff(entry["member"].id)
		if kept["ok"]:
			_gm_log.append("Your general manager kept %s (%s)." % [entry["member"].identity.full_name(), FcStaffRole.display_name(entry["role"])])
	var market := FcPlayerMarket.new(FcPlayerRatings.load_default())
	var keep_line := maxf(GM_KEEP_VALUE, _league_rotation_value(market) - GM_KEEP_MARGIN)
	for entry in expiring_players():
		if entry["agreed"]:
			continue
		var p: FcPlayer = entry["player"]
		if _gm_value(p, entry["age"], market) < keep_line:
			continue
		if entry["ask"] + state.world.payroll_of_team(state.user_team_id, state.current_season + 1) > gm_payroll_limit():
			_gm_log.append("Your general manager let %s go: his price does not fit your budget." % p.identity.full_name())
			continue
		var r := extend_contract(p.id)
		if r["ok"]:
			_gm_log.append("Your general manager agreed new terms with %s." % p.identity.full_name())


## Trades by the GM, up to GM_MAX_TRADES, following the owner's direction: a rebuilding
## team sells its veterans to contenders for young players and picks, a win-now team buys
## veterans from the weakest teams; a balanced team makes no trades.
const GM_MAX_TRADES := 2


func _gm_trades() -> void:
	var philosophy := str(state.direction["philosophy"])
	if philosophy == "balanced":
		return
	var finished := season()
	var league: FcLeague = state.world.leagues.get_by_id(league_id)
	var ranking := FcStandings.compute(league, finished.games).league_ranking()   # best first
	var third := maxi(1, floori(ranking.size() / 3.0))
	var partners: Array[int] = []
	var pool: Array[int] = ranking.slice(0, third) if philosophy == "rebuild" else ranking.slice(ranking.size() - third)
	for tid in pool:
		if tid != state.user_team_id:
			partners.append(tid)
	var trades := FcTrades.new(state.world)
	var rng := state.rng.fork("gmtrades")
	var made := 0
	for attempt in partners.size() * 2:
		if made >= GM_MAX_TRADES or partners.is_empty():
			break
		var partner: int = partners[rng.range_int(0, partners.size() - 1)]
		var seller := state.user_team_id if philosophy == "rebuild" else partner
		var buyer := partner if philosophy == "rebuild" else state.user_team_id
		var news_before := state.world.news.size()
		if trades.attempt(league_id, seller, buyer, finished.year + 1, rng):
			made += 1
			_gm_log.append("Your general manager made a trade: %s." % state.world.news[state.world.news.size() - 1]["text"] if state.world.news.size() > news_before else "Your general manager made a trade.")


## In-season moves by the GM ("injuries" delegation). Checked once a day, at most one move
## every GM_MOVE_GAP_DAYS: when injuries leave the team with fewer than GM_MIN_HEALTHY
## healthy players, or a top-eight player is out for GM_LONG_INJURY games or more while
## the healthy group is still thin (13 or fewer), the GM signs the best free agent he can
## afford (preferring the injured player's position). A full roster makes room by releasing
## the weakest player who is not hurt and not in the top eight (the usual buyout applies).
const GM_MIN_HEALTHY := 11
const GM_LONG_INJURY := 10
const GM_MOVE_GAP_DAYS := 7
var _gm_last_move_day: int = -100


func _gm_cover_injuries(s: FcSeason) -> void:
	if s.next_day - _gm_last_move_day < GM_MOVE_GAP_DAYS:
		return
	var w := state.world
	var team: FcTeam = w.teams.get_by_id(state.user_team_id)
	var rules := w.rules_of_league(league_id)
	var ratings := FcPlayerRatings.load_default()
	var healthy := 0
	var ranked: Array = []
	for pid in team.roster.player_ids:
		var p: FcPlayer = w.players.get_by_id(pid)
		ranked.append([ratings.overall(p), p])
		if p.games_out <= 0:
			healthy += 1
	ranked.sort_custom(func(a, b): return a[0] > b[0])
	var missing: FcPlayer = null
	for i in mini(8, ranked.size()):
		var p2: FcPlayer = ranked[i][1]
		if p2.games_out >= GM_LONG_INJURY and (missing == null or p2.games_out > missing.games_out):
			missing = p2
	if healthy >= GM_MIN_HEALTHY and not (missing != null and healthy <= 13):
		return
	var market := FcPlayerMarket.new(ratings)
	var candidates: Array = []
	for entry in free_agent_market(40):
		candidates.append([_gm_value(entry["player"], entry["age"], market), entry["player"], entry["ask"]])
	candidates.sort_custom(func(a, b): return a[0] > b[0])
	var target: FcPlayer = null
	var target_ask := 0
	for c in candidates:
		if w.payroll_of_team(team.id, state.current_season) + c[2] > gm_payroll_limit():
			continue
		if target == null:
			target = c[1]
			target_ask = c[2]
		if missing != null and c[1].primary_position == missing.primary_position:
			target = c[1]
			target_ask = c[2]
			break
	if target == null:
		return
	if team.roster.size() >= rules.roster_max:
		var drop: FcPlayer = null
		var drop_value := INF
		for i in range(8, ranked.size()):
			var q: FcPlayer = ranked[i][1]
			if q.games_out <= 0 and ranked[i][0] < drop_value:
				drop_value = ranked[i][0]
				drop = q
		if drop == null:
			return
		var released := release_player(drop.id)
		if not released["released"]:
			return
	var result := sign_free_agent(target.id)
	if not result["signed"]:
		return
	_gm_last_move_day = s.next_day
	var reason := "to cover injuries" if missing == null else "to replace %s (out %d games)" % [missing.identity.full_name(), missing.games_out]
	w.add_news(state.current_date, "signing", "Your general manager signed %s %s." % [target.identity.full_name(), reason], team.id)


## A report card on the general manager for the last finished season.
## {"grade", "wins", "expected_wins", "payroll", "limit"} or {} before a season is played.
func gm_report() -> Dictionary:
	var report := owner_report()
	if report.is_empty():
		return {}
	# graded by the share of games won above the expectation, so season length does not matter
	var diff: float = float(report["wins"] - report["expected_wins"]) / maxf(1.0, report["games"])
	var grade := "Excellent" if diff >= 0.12 else ("Good" if diff >= 0.03 else ("Satisfactory" if diff >= -0.06 else "Disappointing"))
	return {"grade": grade, "wins": report["wins"], "expected_wins": report["expected_wins"],
		"payroll": state.world.payroll_of_team(state.user_team_id, report["year"]), "limit": gm_payroll_limit()}


## Free agency by the GM: signs up to GM_MAX_SIGNINGS free agents he rates as real
## improvements (at their asking price), while there is roster space and cap room.
func _gm_sign_free_agents() -> void:
	var market := FcPlayerMarket.new(FcPlayerRatings.load_default())
	var team: FcTeam = state.world.teams.get_by_id(state.user_team_id)
	var rules := state.world.rules_of_league(league_id)
	var signed := 0
	var own_values: Array = []
	for pid in team.roster.player_ids:
		var own: FcPlayer = state.world.players.get_by_id(pid)
		own_values.append(_gm_value(own, own.age_on(FcDate.new(contract_year(), 7, 1)), market))
	own_values.sort()
	own_values.reverse()
	# a signing must beat the league's rotation level and the team's own eighth man
	var sign_line := maxf(GM_FREE_AGENT_VALUE, _league_rotation_value(market) + GM_SIGN_MARGIN)
	if own_values.size() >= 8:
		sign_line = maxf(sign_line, own_values[7] + 1.0)
	var ranked: Array = []
	for entry in free_agent_market(40):
		ranked.append([_gm_value(entry["player"], entry["age"], market), entry["player"]])
	ranked.sort_custom(func(a, b): return a[0] > b[0])
	for pair in ranked:
		if signed >= GM_MAX_SIGNINGS or team.roster.size() >= rules.roster_max - 1:
			break
		if pair[0] < sign_line:
			break
		if state.direction["philosophy"] == "rebuild" and pair[1].age_on(FcDate.new(contract_year(), 7, 1)) > 29:
			continue   # a rebuilding team does not sign older players
		var wanted: int = 0
		for entry in free_agent_market(40):
			if entry["player"].id == pair[1].id:
				wanted = entry["ask"]
		if state.world.payroll_of_team(team.id, contract_year()) + wanted > gm_payroll_limit():
			continue
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
	var choice := _off().ai_draft_choice(state.draft_state, state.user_team_id, _draft_rng(), _philosophy_emphasis())
	return user_draft_pick(choice)


## The staff picks for the user from now on and the draft finishes.
func draft_auto_rest() -> void:
	var off := _off()
	while not off.draft_complete(state.draft_state):
		var team := off.draft_team_on_clock(state.draft_state)
		off.make_pick(state.draft_state, league_id, off.ai_draft_choice(state.draft_state, team, _draft_rng(), _philosophy_emphasis() if team == state.user_team_id else 0.0))
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
	if state.mode == FcGameState.MODE_OWNER and state.delegation["trades"]:
		_gm_trades()
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
	var verdict := market.evaluate_offer(p, age, rules.cap, wanted, years, true, gm_negotiation())
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
	var verdict := market.evaluate_offer(p, age, rules.cap, offer, years, false, gm_negotiation())
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
	if team.roster.add(p.id) != OK:
		# never create a contract for a player who could not join the roster
		return {"signed": false, "reason": "Your roster has no room for another player."}
	var c := FcPlayerMarket.make_contract(w.ids.next_id(FcWorld.KIND_CONTRACT), p.id, team.id, year, years, offer, rules.cap, today)
	w.contracts.add(c)
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


## The ticket price that just fills the arena at today's fan interest, brand and arena
## quality (what the AI teams charge). A higher price earns more per fan but empties seats.
func suggested_ticket_price() -> int:
	var w := state.world
	var team: FcTeam = w.teams.get_by_id(state.user_team_id)
	var finance := FcFinanceEngine.new(w)
	var scale := finance.price_scale_for(w.rules_of_league(league_id), w.leagues.get_by_id(league_id))
	return finance.best_price(business(), w.cities.get_by_id(team.city_id), w.arenas.get_by_id(team.arena_id), scale)


## Concession prices as a percent of normal (70-150).
func set_concession_price(percent: int) -> bool:
	if percent < 70 or percent > 150:
		return false
	business().concession_price_pct = percent
	return true


## Playoff ticket prices as a percent of the regular price (100-300).
func set_playoff_premium(percent: int) -> bool:
	if percent < 100 or percent > 300:
		return false
	business().playoff_premium_pct = percent
	return true


## Share of the seats sold as season tickets, in percent (0-60).
func set_season_ticket_share(percent: int) -> bool:
	if percent < 0 or percent > int(FcFinanceEngine.load_constants()["season_ticket_max_share"]):
		return false
	business().season_ticket_share = percent
	return true


## Number of half-price promotion nights per season (0-10).
func set_promotion_nights(nights: int) -> bool:
	if nights < 0 or nights > int(FcFinanceEngine.load_constants()["promo_max_nights"]):
		return false
	business().promotion_nights = nights
	return true


## What the current ticket plan would mean for a regular game at today's demand:
## {"holders", "single", "total", "capacity", "demand", "season_price", "promo_price", "promo_cost"}.
func ticket_plan_preview() -> Dictionary:
	var w := state.world
	var team: FcTeam = w.teams.get_by_id(state.user_team_id)
	var finance := FcFinanceEngine.new(w)
	var rules := w.rules_of_league(league_id)
	var scale := finance.price_scale_for(rules, w.leagues.get_by_id(league_id))
	var arena: FcArena = w.arenas.get_by_id(team.arena_id)
	var city: FcCity = w.cities.get_by_id(team.city_id)
	var b := business()
	var split := finance.ticket_split(b, city, arena, scale, float(b.ticket_price))
	split["capacity"] = arena.capacity
	split["demand"] = roundi(finance.demand(b, city, arena, scale, float(b.ticket_price)))
	split["season_price"] = roundi(b.ticket_price * (1.0 - float(finance.k["season_ticket_discount"])))
	split["promo_price"] = roundi(b.ticket_price * (1.0 - float(finance.k["promo_ticket_discount"])))
	split["promo_cost"] = roundi(float(finance.k["promo_cost"]) * finance.scale_for(rules))
	return split


## Merchandise range: 0 limited, 1 standard, 2 premium.
func set_merch_tier(tier: int) -> bool:
	if tier < 0 or tier > 2:
		return false
	business().merch_tier = tier
	return true


## Sponsorship offers for the coming season (see FcFinanceEngine.sponsor_offers); empty while
## both slots are taken.
func sponsor_offers() -> Array:
	var finance := FcFinanceEngine.new(state.world)
	if business().sponsor_deals.size() >= int(finance.k["sponsor_max_deals"]):
		return []
	return finance.sponsor_offers(state.user_team_id, contract_year(), finance.scale_for(state.world.rules_of_league(league_id)))


## Signs the offer with this sponsor name. Returns {"ok": bool, "reason": String}.
func accept_sponsor(sponsor: String) -> Dictionary:
	for offer in sponsor_offers():
		if offer["sponsor"] == sponsor:
			var finance := FcFinanceEngine.new(state.world)
			var problem := finance.sign_sponsor(business(), offer)
			if problem != "":
				return {"ok": false, "reason": problem}
			return {"ok": true, "reason": "Signed %s for %d year%s: %s a year%s." % [sponsor, offer["years"], "" if offer["years"] == 1 else "s", "$%.1fM" % (offer["amount"] / 1e6), " plus $%.1fM per playoff round won" % (offer["bonus"] / 1e6) if offer["bonus"] > 0 else ""]}
	return {"ok": false, "reason": "That offer is no longer available."}


## Chooses the sponsorship deal style: 0 balanced, 1 steady, 2 performance
## (see FcTeamBusiness.sponsor_plan). It applies when the season's books are settled.
func set_sponsor_plan(plan: int) -> bool:
	if plan < 0 or plan > 2:
		return false
	business().sponsor_plan = plan
	return true


## The most the owner may owe in total: a share of the franchise's value.
func loan_limit() -> int:
	if loans_frozen():
		return 0
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
	if loans_frozen():
		return {"ok": false, "reason": "Lenders froze new loans after restructuring your debt (the freeze ends in %d seasons)." % (int(FcEconomy.load_constants()["restructure_lockout_seasons"]) - (state.current_season - b.restructured_year))}
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


## The most cash the owner may take out now: what is above a reserve (a share of the cap), and
## nothing while the club owes money.
func dividend_limit() -> int:
	var b := business()
	if b.debt > 0:
		return 0
	var cap := state.world.rules_of_league(league_id).cap.salary_cap
	var reserve := roundi(float(FcEconomy.load_constants()["reserve_cap_share"]) * 0.5 * cap)
	return maxi(0, b.cash - reserve)


## Pays the owner a dividend from the club's cash (counted in the owner's own wealth, `distributions`).
## Returns {"ok": bool, "reason": String}.
func take_dividend(amount: int) -> Dictionary:
	var b := business()
	if amount <= 0:
		return {"ok": false, "reason": "Enter an amount above zero."}
	if b.debt > 0:
		return {"ok": false, "reason": "Repay the club's debt before paying yourself."}
	if amount > dividend_limit():
		return {"ok": false, "reason": "The club must keep a cash reserve: you can take at most $%.1fM now." % (dividend_limit() / 1e6)}
	b.cash -= amount
	b.distributions += amount
	return {"ok": true, "reason": "Paid yourself $%.1fM. Your total payouts are $%.1fM." % [amount / 1e6, b.distributions / 1e6]}


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


## Staff want a little less than their asking salary at most (STAFF_FLEXIBILITY) and like
## longer security (STAFF_SECURITY_PER_YEAR less per year above 3 years, more per year below).
const STAFF_FLEXIBILITY := 0.06
const STAFF_SECURITY_PER_YEAR := 0.025


## The least first-year salary this person accepts for a contract of `years`
## (staff re-signing with the owner's team give an extra 3% discount).
func staff_minimum_acceptable(staff_id: int, years: int, own_team: bool = false) -> int:
	var flex := STAFF_FLEXIBILITY + (0.03 if own_team else 0.0) + FcPlayerMarket.NEGOTIATION_EFFECT * (gm_negotiation() - 50.0) / 50.0
	var factor := 1.0 - STAFF_SECURITY_PER_YEAR * clampi(years - 3, -2, 2)
	return int(ceil(asking_salary(staff_id) * (1.0 - flex) * factor / 10000.0)) * 10000


## Hires an unemployed staff member for the user's team. Unique roles (general
## manager, head coach) must be vacant. With no salary given he gets his asking salary; a lower
## offer works if he is flexible enough. Returns an empty string on success or the reason.
func hire_staff(staff_id: int, role: int, years: int, salary_offered: int = -1) -> String:
	var w := state.world
	var m: FcStaffMember = w.staff.get_by_id(staff_id)
	if m == null or m.status != FcStaffMember.Status.ACTIVE:
		return "that person is not available"
	if w.active_staff_contract_of(staff_id) != null:
		return "that person already has a job"
	if FcStaffRole.is_unique_per_team(role) and w.staff_in_role(state.user_team_id, role) != null:
		return "the team already has a %s; fire him first" % FcStaffRole.display_name(role)
	var length := clampi(years, 1, 5)
	var salary := salary_offered if salary_offered > 0 else asking_salary(staff_id)
	var required := staff_minimum_acceptable(staff_id, length)
	if salary < required:
		return "%s wants at least %s a year for %d years" % [m.identity.full_name(), "$%.2fM" % (required / 1e6), length]
	var c := FcStaffContract.new(w.ids.next_id(FcWorld.KIND_STAFF_CONTRACT))
	c.staff_id = staff_id
	c.team_id = state.user_team_id
	c.role = role
	c.signed_on = state.current_date
	for i in length:
		c.years.append(FcContractYear.new(state.current_season + i, roundi(salary * pow(1.04, i) / 10000.0) * 10000))
	w.staff_contracts.add(c)
	engine.refresh_teams()
	return ""


## The user's staff whose contract ends with this season:
## [{"member", "role", "ask", "agreed" (bool)}]. In Owner Mode they leave unless agreed with extend_staff().
func expiring_staff() -> Array:
	var w := state.world
	var out: Array = []
	for sc in w.staff_contracts_of_team(state.user_team_id):
		if sc.end_season() <= state.current_season:
			out.append({"member": w.staff.get_by_id(sc.staff_id), "role": sc.role, "ask": asking_salary(sc.staff_id), "agreed": state.agreed_staff_terms.has(sc.staff_id)})
	return out


## Agrees to keep a staff member whose contract ends this season; the new contract starts
## next season on the agreed terms. Returns {"ok": bool, "reason": String, "required": int}.
func extend_staff(staff_id: int, salary_offered: int = -1, years_offered: int = -1) -> Dictionary:
	var w := state.world
	var c := w.active_staff_contract_of(staff_id)
	if c == null or c.team_id != state.user_team_id:
		return {"ok": false, "reason": "He does not work for you."}
	if c.end_season() > state.current_season:
		return {"ok": false, "reason": "Only staff in the last year of their contract can be extended."}
	if state.agreed_staff_terms.has(staff_id):
		return {"ok": false, "reason": "He has already agreed to stay."}
	var m: FcStaffMember = w.staff.get_by_id(staff_id)
	var years := clampi(years_offered if years_offered > 0 else 3, 1, 5)
	var salary := salary_offered if salary_offered > 0 else asking_salary(staff_id)
	var required := staff_minimum_acceptable(staff_id, years, true)
	if salary < required:
		return {"ok": false, "required": required, "reason": "%s wants at least %s a year for %d years." % [m.identity.full_name(), "$%.2fM" % (required / 1e6), years]}
	state.agreed_staff_terms[staff_id] = [salary, years]
	return {"ok": true, "reason": "%s agreed to stay for %d years at %s a year." % [m.identity.full_name(), years, "$%.2fM" % (salary / 1e6)]}


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
		"wins": rec.wins, "games": games, "expected_wins": roundi(expected), "playoff_rounds_won": rec.playoff_rounds_won,
		"approval": clampi(roundi(approval), 0, 100),
		"restructured_total": business().restructured_total, "loans_frozen": loans_frozen(),
	}


## Every team's books for the last settled season, best profit first, for comparison:
## [{"team", "name", "wins", "revenue", "profit", "payroll", "price", "attendance", "valuation", "profit_rank", "revenue_rank"}].
func league_finances() -> Array:
	var w := state.world
	var finance := FcFinanceEngine.new(w)
	var year := state.current_season if season().status == FcSeason.Status.COMPLETE else state.current_season - 1
	var rows: Array = []
	for tid in w.leagues.get_by_id(league_id).all_team_ids():
		var rec := finance.record_of(tid, year)
		if rec == null:
			continue   # a team that joined after that season has no books yet
		rows.append({"team": tid, "name": w.team_display_name(tid), "wins": rec.wins, "revenue": rec.total_revenue(), "profit": rec.profit(),
			"payroll": rec.expenses["payroll"], "price": rec.ticket_price, "attendance": rec.average_attendance, "valuation": rec.valuation_end})
	rows.sort_custom(func(a, b): return a["profit"] > b["profit"] if a["profit"] != b["profit"] else a["team"] < b["team"])
	for i in rows.size():
		rows[i]["profit_rank"] = i + 1
	var by_revenue := rows.duplicate()
	by_revenue.sort_custom(func(a, b): return a["revenue"] > b["revenue"] if a["revenue"] != b["revenue"] else a["team"] < b["team"])
	for i in by_revenue.size():
		by_revenue[i]["revenue_rank"] = i + 1
	return rows


# --- saving ---------------------------------------------------------------------------------

func autosave(manager: FcSaveManager) -> FcSaveResult:
	return manager.autosave(state)
