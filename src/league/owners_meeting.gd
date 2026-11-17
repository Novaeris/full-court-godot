class_name FcOwnersMeeting
extends RefCounted
## The league owners' meeting held after each season (D-031): a few proposals to change the
## league's rules, voted on by every franchise. The AI owners have no fixed personalities: each
## vote comes from the team's CURRENT situation (record, payroll, profit) plus a fresh mood every
## year, so the same proposal can pass one year and fail the next. Items that change the cap
## need a two-thirds majority, everything else a simple majority.
##
## An item is {"id": kind, "family", "title", "detail", "supermajority": bool}. Everything here is
## derived from the rules and the year, so the agenda can be rebuilt at any time.

const FAMILIES := ["cap", "roster", "series", "lottery", "season", "playoffs"]
const AGENDA_SIZE := 3
## The chance each year that an expansion is added to the agenda (when one is possible).
const EXPANSION_CHANCE := 0.25
const ROSTER_LIMITS := [13, 17]
const SEASON_STEP := 10
const SEASON_LIMITS := [40, 110]
const CAP_STEP := 0.05
const MOOD := 0.5
## Influence (D-031, simple version): points the owner earns for each meeting and spends on
## lobbying (turning one owner's vote) or proposing an item. They do not carry over.
const PROPOSE_COST := 5
const LOBBY_COSTS := [[0.5, 1], [1.0, 2]]   # a lean up to 0.5 costs 1, up to 1.0 costs 2, anything stronger 3
const LOBBY_MAX_COST := 3


## Points for one meeting: 2 for being at the table, up to 5 from the owner's reputation
## (reputation / 20) and up to 3 from the size of the market (market factor 0.6 -> 0, 1.8 -> 3).
static func influence_income(reputation: int, market_factor: float) -> int:
	return 2 + roundi(clampf(reputation / 20.0, 0.0, 5.0)) + roundi(clampf((market_factor - 0.6) / 1.2 * 3.0, 0.0, 3.0))


## What it costs to turn an owner whose vote leans `lean` (either way).
static func lobby_cost(lean: float) -> int:
	for step in LOBBY_COSTS:
		if absf(lean) <= step[0]:
			return step[1]
	return LOBBY_MAX_COST


## Every kind of proposal the owner could add to the agenda (valid for the current rules, not
## already on it): [{"id", "family", "title", "detail", "supermajority", "proposed": true}].
func proposable(year: int, on_agenda: Array, last_expansion_year: int = 0) -> Array:
	var rules := world.rules_of_league(league_id)
	var league: FcLeague = world.leagues.get_by_id(league_id)
	var taken := {}
	for item in on_agenda:
		taken[item["id"]] = true
	var out: Array = []
	for family in FAMILIES:
		for kind in _kinds_of(family):
			if taken.has(kind):
				continue
			var trial := FcLeagueRules.from_dict(rules.to_dict())
			if apply_to(trial, league, kind) and trial.validate(league).is_empty() and _affordable(kind, trial, league, year):
				var item := _item(kind, family, rules, trial, league)
				item["proposed"] = true
				out.append(item)
	var expansion := _expansion_item(year, last_expansion_year)
	if not expansion.is_empty() and not taken.has("expansion"):
		expansion["proposed"] = true
		out.append(expansion)
	return out

var world: FcWorld
var league_id: int


func _init(game_world: FcWorld, league: int) -> void:
	world = game_world
	league_id = league


## The agenda for a year: AGENDA_SIZE items from different families, each a proposal that
## would pass the rule checks if adopted. The same list every time for the same rules and year.
func agenda(year: int, last_expansion_year: int = 0) -> Array:
	var rules := world.rules_of_league(league_id)
	var league: FcLeague = world.leagues.get_by_id(league_id)
	var rng := FcRng.new(hash("agenda:%d:%d" % [league_id, year]))
	var families := FAMILIES.duplicate()
	var out: Array = []
	while out.size() < AGENDA_SIZE and not families.is_empty():
		var family: String = families.pop_at(rng.range_int(0, families.size() - 1))
		var kinds := _kinds_of(family)
		if rng.chance(0.5):
			kinds.reverse()
		for kind in kinds:
			var trial := FcLeagueRules.from_dict(rules.to_dict())
			if apply_to(trial, league, kind) and trial.validate(league).is_empty() and _affordable(kind, trial, league, year):
				out.append(_item(kind, family, rules, trial, league))
				break
	# once in a while an expansion is on the table too (never twice within MIN_GAP_YEARS)
	var expansion := _expansion_item(year, last_expansion_year)
	if not expansion.is_empty() and rng.chance(EXPANSION_CHANCE):
		out.append(expansion)
	return out


## The expansion proposal, or {} if the league cannot grow or grew too recently.
func _expansion_item(year: int, last_expansion_year: int) -> Dictionary:
	if last_expansion_year > 0 and year - last_expansion_year < FcExpansion.MIN_GAP_YEARS:
		return {}
	var expansion := FcExpansion.new(world, league_id)
	var plan_data := expansion.plan(year)
	if plan_data.is_empty():
		return {}
	var names: Array[String] = []
	for entry in plan_data["cities"]:
		names.append(str(entry["name"]))
	return {"id": "expansion", "family": "expansion", "title": "Expand the league to %d teams" % plan_data["size"],
		"detail": "New franchises in %s. Each existing owner receives an expansion fee of about $%.1fM. The conferences and divisions are redrawn, the new teams start with weaker players and join the next draft. Needs three quarters of the votes." % [", ".join(names), expansion.fee_per_owner(plan_data["delta"]) / 1e6],
		"supermajority": true}


## A lower cap is only proposed if no team's payroll, this season or next, would be over the new
## hard limit (existing contracts are not torn up).
func _affordable(kind: String, trial: FcLeagueRules, league: FcLeague, year: int) -> bool:
	if kind != "cap_down":
		return true
	var limit := trial.cap.effective_limit()
	if limit <= 0:
		return true
	for tid in league.all_team_ids():
		if world.payroll_of_team(tid, year) > limit or world.payroll_of_team(tid, year + 1) > limit:
			return false
	return true


func _kinds_of(family: String) -> Array:
	return {
		"cap": ["cap_up", "cap_down"], "roster": ["roster_up", "roster_down"], "series": ["series_longer", "series_shorter"],
		"lottery": ["lottery_bigger", "lottery_smaller"], "season": ["season_longer", "season_shorter"], "playoffs": ["playoffs_bigger", "playoffs_smaller"],
	}[family]


func _item(kind: String, family: String, before: FcLeagueRules, after: FcLeagueRules, league: FcLeague) -> Dictionary:
	var title := ""
	var detail := ""
	match kind:
		"cap_up", "cap_down":
			title = "Raise the salary cap by 5%" if kind == "cap_up" else "Lower the salary cap by 5%"
			detail = "Cap $%.1fM to $%.1fM; the tax line, hard limit and salary scales move with it. Existing contracts do not change, so teams near the hard limit may have to release players." % [before.cap.salary_cap / 1e6, after.cap.salary_cap / 1e6]
		"roster_up", "roster_down":
			title = "Allow %d players per roster" % after.roster_max
			detail = "The roster maximum goes from %d to %d players." % [before.roster_max, after.roster_max]
		"series_longer", "series_shorter":
			title = "Make the first playoff round a best of %d" % after.playoffs.series_lengths[0]
			detail = "Round one goes from a best of %d to a best of %d. Longer series favour the stronger team." % [before.playoffs.series_lengths[0], after.playoffs.series_lengths[0]]
		"lottery_bigger":
			title = "Start a draft lottery" if before.draft.lottery_teams == 0 else "Draw one more pick in the draft lottery"
			detail = "The lottery draws %d top picks among the worst %d non-playoff teams (now: %s)." % [after.draft.lottery_picks, after.draft.lottery_teams, "no lottery" if before.draft.lottery_teams == 0 else "%d picks" % before.draft.lottery_picks]
		"lottery_smaller":
			title = "Abolish the draft lottery" if after.draft.lottery_teams == 0 else "Draw one fewer pick in the draft lottery"
			detail = "The worst record %s." % ("always picks first" if after.draft.lottery_teams == 0 else "is more likely to pick first: %d picks are drawn instead of %d" % [after.draft.lottery_picks, before.draft.lottery_picks])
		"season_longer", "season_shorter":
			var games_before := before.season.games_per_team(league)
			var games_after := after.season.games_per_team(league)
			title = "Play %d games a season" % games_after
			detail = "The regular season goes from %d to %d games (more gates and more wear, or less of both)." % [games_before, games_after]
		"playoffs_bigger", "playoffs_smaller":
			title = "Playoffs with %d teams" % after.playoffs.team_count
			detail = "The playoff field goes from %d to %d teams." % [before.playoffs.team_count, after.playoffs.team_count]
	return {"id": kind, "family": family, "title": title, "detail": detail, "supermajority": family == "cap"}


## Changes `rules` the way the proposal says. Returns false if it does not apply (nothing is
## then guaranteed about the rules, so callers use a copy).
func apply_to(rules: FcLeagueRules, league: FcLeague, kind: String) -> bool:
	match kind:
		"expansion":
			return false   # not a change to the rules: see enact
		"cap_up", "cap_down":
			if rules.cap.cap_type == "none":
				return false
			rules.cap.scale_money(1.0 + CAP_STEP if kind == "cap_up" else 1.0 - CAP_STEP)
			return true
		"roster_up":
			if rules.roster_max >= ROSTER_LIMITS[1]:
				return false
			rules.roster_max += 1
			return true
		"roster_down":
			if rules.roster_max <= maxi(ROSTER_LIMITS[0], rules.roster_min):
				return false
			rules.roster_max -= 1
			return true
		"series_longer", "series_shorter":
			var options := FcPlayoffRules.SERIES_OPTIONS
			var index := options.find(rules.playoffs.series_lengths[0])
			var target := index + (1 if kind == "series_longer" else -1)
			if index < 0 or target < 1 or target >= options.size():   # never below best of 3
				return false
			rules.playoffs.series_lengths[0] = options[target]
			return true
		"lottery_bigger":
			if rules.draft.lottery_teams == 0:
				var suggested := FcDraftRules.suggest(league.team_count())
				rules.draft.lottery_teams = suggested.lottery_teams
				rules.draft.lottery_picks = suggested.lottery_picks
				return true
			if rules.draft.lottery_picks >= 4 or rules.draft.lottery_picks >= rules.draft.lottery_teams:
				return false
			rules.draft.lottery_picks += 1
			return true
		"lottery_smaller":
			if rules.draft.lottery_teams == 0:
				return false
			if rules.draft.lottery_picks > 1:
				rules.draft.lottery_picks -= 1
			else:
				rules.draft.lottery_teams = 0
			return true
		"season_longer", "season_shorter":
			var games := rules.season.games_per_team(league)
			var wanted := games + (SEASON_STEP if kind == "season_longer" else -SEASON_STEP)
			if wanted < SEASON_LIMITS[0] or wanted > SEASON_LIMITS[1]:
				return false
			var suggested_season := FcSeasonRules.suggest(league, wanted)
			if suggested_season.games_per_team(league) == games:
				return false
			rules.season = suggested_season
			return true
		"playoffs_bigger", "playoffs_smaller":
			var current := rules.playoffs.team_count
			for step in [2, 4, 6]:
				var count: int = current + (step if kind == "playoffs_bigger" else -step)
				if count < 2 or count > league.team_count():
					continue
				var trial := FcPlayoffRules.from_dict(rules.playoffs.to_dict())
				trial.team_count = count
				var rounds := trial.round_count(league)
				var lengths: Array[int] = []
				for i in rounds:
					lengths.append(rules.playoffs.series_lengths[mini(i, rules.playoffs.series_lengths.size() - 1)])
				trial.series_lengths = lengths
				if trial.validate(league).is_empty():
					rules.playoffs = trial
					return true
			return false
	return false


## Makes a passed proposal law. Returns false if it no longer applies or would break the rules.
## The league is then brought in line: contracts outside new salary bounds are moved into them,
## and teams over a lowered roster maximum release their weakest players (`user_team_id`'s
## team is told in the news). `year` is the season whose values decide who is weakest.
func enact(kind: String, user_team_id: int = 0, year: int = 2026) -> bool:
	if kind == "expansion":
		return not FcExpansion.new(world, league_id).execute(year).is_empty()
	var rules := world.rules_of_league(league_id)
	var league: FcLeague = world.leagues.get_by_id(league_id)
	var trial := FcLeagueRules.from_dict(rules.to_dict())
	if not apply_to(trial, league, kind) or not trial.validate(league).is_empty():
		return false
	rules.cap = trial.cap
	rules.roster_max = trial.roster_max
	rules.playoffs = trial.playoffs
	rules.draft = trial.draft
	rules.season = trial.season
	if kind.begins_with("cap_"):
		_refit_contracts(rules.cap)
	if kind == "roster_down":
		trim_rosters(rules.roster_max, user_team_id, year)
	return true


## Moves every active contract inside the cap system's salary bounds (a higher minimum raises the
## smallest contracts, a lower maximum trims the biggest).
func _refit_contracts(cap: FcCapRules) -> void:
	for c in world.contracts.all():
		if c.status != FcContract.Status.ACTIVE:
			continue
		var ceiling := cap.cornerstone_max_salary if c.is_cornerstone else cap.max_player_salary
		for y in c.years:
			y.salary = clampi(y.salary, cap.min_player_salary, ceiling)
			y.guaranteed = mini(y.guaranteed, y.salary)


## Teams over the roster maximum release their weakest players until they fit.
func trim_rosters(roster_max: int, user_team_id: int, year: int) -> int:
	var off := FcOffseason.new(world)
	var released := 0
	for team in world.teams.all():
		while team.roster.size() > roster_max:
			var before: Array = team.roster.player_ids.duplicate()
			off._waive_worst(team, year)
			released += 1
			if team.id == user_team_id:
				for pid in before:
					if not team.roster.contains(pid):
						world.add_news(FcDate.new(year, 7, 1), "signing", "%s was released: the league lowered the roster maximum to %d." % [world.player_name(pid), roster_max], team.id)
	return released


# --- voting ----------------------------------------------------------------------------------------

## What each owner needs to know about its team: rank (1 = best record), profit as a share of the
## cap, and payroll as a share of the cap.
func situations(finished: FcSeason) -> Dictionary:
	var league: FcLeague = world.leagues.get_by_id(league_id)
	var cap_value := float(world.rules_of_league(league_id).cap.salary_cap)
	var ranking := FcStandings.compute(league, finished.games).league_ranking()
	var finance := FcFinanceEngine.new(world)
	var out := {}
	for i in ranking.size():
		var tid: int = ranking[i]
		var rec := finance.record_of(tid, finished.year)
		out[tid] = {"rank": i + 1, "of": ranking.size(), "profit": (rec.profit() / cap_value) if rec != null else 0.0,
			"payroll": world.payroll_of_team(tid, finished.year) / cap_value if cap_value > 0 else 1.0}
	return out


## One AI owner's vote on a proposal: {"yes", "reason", "lean"}. `lean` is the strength of the
## feeling (positive = in favour) including this year's mood.
func vote_of(team_id: int, item: Dictionary, situation: Dictionary, year: int) -> Dictionary:
	var rules := world.rules_of_league(league_id)
	var rank_fraction: float = float(situation["rank"] - 1) / maxf(1.0, situation["of"] - 1.0)   # 0 = best, 1 = worst
	var down: bool = str(item["id"]).ends_with("_down") or item["id"] in ["series_shorter", "lottery_smaller", "season_shorter", "playoffs_smaller"]
	# each term: [feeling about the "more" version, reason when it is a yes, reason when it is a no]
	var terms: Array = []
	match item["family"]:
		"cap":
			var over: float = situation["payroll"] - 1.0
			terms.append([4.0 * over, "is over the cap and wants room to spend" if over > 0 else "has cap room and wants to use it", "does not want a cap below its payroll" if over > 0 else "has no need for more cap room"])
			terms.append([6.0 * situation["profit"], "can afford higher costs", "cannot afford higher costs"])
		"roster":
			terms.append([0.4 if rank_fraction < 0.33 else (-0.1 if rank_fraction > 0.66 else 0.0), "wants depth for the playoff push", "does not need the extra bodies"])
			terms.append([-0.6 if situation["profit"] < 0 else 0.0, "can carry another player", "does not want another salary to pay"])
		"series":
			terms.append([0.5 if rank_fraction < 0.4 else (-0.4 if rank_fraction > 0.6 else 0.0), "the better team usually wins a longer series", "wants more chance of an upset"])
		"lottery":
			terms.append([0.5 if rank_fraction > 0.5 else (-0.5 if rank_fraction < 0.3 else 0.0), "needs help from the draft", "does not want bad teams rewarded"])
		"season":
			terms.append([0.4 if situation["profit"] > 0.04 else (-0.5 if situation["profit"] < 0 else 0.0), "more home games mean more gate money", "more games mean more costs"])
		"expansion":
			terms.append([0.5 if situation["profit"] < 0.03 else -0.1, "wants a share of the expansion fee", "does not need the fee"])
			terms.append([-0.5 if rank_fraction < 0.3 else (0.2 if rank_fraction > 0.7 else 0.0), "more teams to beat", "does not want more competition for the title"])
		"playoffs":
			var spots := rules.playoffs.team_count
			var rank: int = situation["rank"]
			var bubble := rank > spots - 2 and rank <= spots + 7
			var top := rank <= spots * 0.3
			terms.append([0.6 if bubble else (-0.4 if top else 0.0), "is on the bubble and wants a spot" if bubble else "more playoff games mean more revenue", "a bigger field dilutes the playoffs" if top else "worries about missing out"])
	var mood := FcRng.new(hash("mood:%d:%s:%d" % [year, item["id"], team_id])).range_float(-MOOD, MOOD)
	var score := mood
	var reason := "no strong feelings"
	var strongest := 0.0
	for t in terms:
		var weight: float = -t[0] if down else t[0]
		score += weight
		if absf(weight) > strongest and absf(weight) > 0.001:
			strongest = absf(weight)
			reason = t[1] if weight > 0 else t[2]
	if strongest < absf(mood) and strongest < 0.2:
		reason = "in a good mood" if mood > 0 else "in a bad mood"
	return {"yes": score > 0.0, "reason": reason, "lean": score}


## The tally for one item: every AI owner's vote, plus the player's if given (null = not voted).
## {"votes": [{"team", "name", "yes", "reason", "lean"}], "yes", "no", "needed", "passes"}.
## The player's own team is left out of the AI votes: the player decides for it.
## `flipped` lists the owners the player has lobbied: their vote is the opposite of what it would be.
func tally(item: Dictionary, finished: FcSeason, year: int, user_team_id: int, user_vote, flipped: Array = []) -> Dictionary:
	var league: FcLeague = world.leagues.get_by_id(league_id)
	var situation := situations(finished)
	var votes: Array = []
	var yes := 0
	var no := 0
	for tid in league.all_team_ids():
		if tid == user_team_id:
			continue
		var v := vote_of(tid, item, situation[tid], year)
		var was_flipped := flipped.has(tid)
		if was_flipped:
			v = {"yes": not v["yes"], "reason": "persuaded by you", "lean": v["lean"]}
		votes.append({"team": tid, "name": world.team_display_name(tid), "yes": v["yes"], "reason": v["reason"], "lean": v["lean"], "flipped": was_flipped, "cost": lobby_cost(v["lean"])})
		if v["yes"]:
			yes += 1
		else:
			no += 1
	if user_vote != null:
		if user_vote:
			yes += 1
		else:
			no += 1
	var total := league.all_team_ids().size()
	var fraction := 0.75 if item["id"] == "expansion" else (2.0 / 3.0 if item["supermajority"] else 0.5)
	var needed := ceili(total * fraction) if fraction > 0.5 else floori(total / 2.0) + 1
	return {"votes": votes, "yes": yes, "no": no, "needed": needed, "passes": yes >= needed}
