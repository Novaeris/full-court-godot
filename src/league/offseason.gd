class_name FcOffseason
extends RefCounted
## Everything that happens between two seasons for AI-controlled decisions:
##   1. progress_and_retire   players age (develop or decline); some retire
##   2. expire_contracts      contracts that ended free their players
##   3. re_sign               teams re-sign some of their own expiring players
##   4. run_draft             a prospect class is created and drafted (reverse standings)
##   5. free_agency           teams sign free agents within the salary rules
##   6. fill_rosters          every team ends with a legal roster
## run() does all six. A human owner's decisions (Owner Mode) will plug in
## between steps later; for now every team is run by the same AI.
##
## All signings go through FcCapRules.check_signing, so soft cap, hard cap,
## exceptions and the hard limit are respected. Randomness uses the FcRng
## passed in, so an offseason is reproducible.

const DRAFT_ROUNDS := 2
const UNDRAFTED_EXTRA := 20
const FRESH_FREE_AGENTS := 12
const MARKET_ROUNDS := 14

## Teams run by a human: their expiring players are NOT re-signed automatically
## (the owner decides with FcGameController.extend_contract; the rest become free agents).
var human_team_ids: Array[int] = []
## Players the human owner agreed to keep: they are re-signed at their asking price (if still legal).
var agreed_re_signs: Array[int] = []
## The agreed terms: player id -> [first-year salary, years] (missing = the asking price).
var agreed_terms: Dictionary = {}
## Teams a human runs by hand: AI free agency skips them (fill_rosters still keeps rosters legal).
var manual_free_agency_team_ids: Array[int] = []
var world: FcWorld
var ratings := FcPlayerRatings.load_default()
var market: FcPlayerMarket
var progression: FcPlayerProgression
var generator: FcPlayerGenerator
var _gen_data := FcGenerationData.load_default()
var _used_names: Dictionary = {}


func _init(game_world: FcWorld) -> void:
	world = game_world
	market = FcPlayerMarket.new(ratings)
	progression = FcPlayerProgression.new(world.definitions, ratings)
	generator = FcPlayerGenerator.new(_gen_data, world.definitions)


## Runs the whole offseason after `finished` (a COMPLETE FcSeason). `new_year` is
## the year of the season about to start. Returns a report of counts.
func run(league_id: int, finished: FcSeason, rng: FcRng) -> Dictionary:
	var report := run_first_half(league_id, finished, rng)
	report.merge(run_second_half(league_id, finished, rng))
	return report


## Aging and retirement, expiring contracts, re-signing, the draft and AI trades,
## all automatic (Dynasty Mode, tools and tests). A human owner uses the pieces
## instead (run_before_draft, prepare_draft / make_pick / finish_draft,
## run_after_draft) so they can draft and sign free agents before run_second_half.
## Uses the same random streams either way.
func run_first_half(league_id: int, finished: FcSeason, rng: FcRng) -> Dictionary:
	var report := run_before_draft(league_id, finished, rng)
	report["drafted"] = run_draft(league_id, finished, finished.year + 1, rng.fork("draft"))
	report.merge(run_after_draft(league_id, finished, rng))
	return report


## Archiving, aging and retirement, contracts ending, re-signing.
func run_before_draft(league_id: int, finished: FcSeason, rng: FcRng) -> Dictionary:
	var new_year := finished.year + 1
	var report := {}
	# keep the detailed data of the last two seasons; older ones keep only their history
	for s in world.seasons.all():
		if s.league_id == league_id and s.year <= finished.year - 2:
			s.archive()
	report.merge(progress_and_retire(league_id, finished.year, new_year, rng.fork("progress")))
	report.merge(expire_contracts(league_id, finished.year))
	report["re_signed"] = re_sign(league_id, new_year, rng.fork("resign"))
	return report


## AI trades (after the draft).
func run_after_draft(league_id: int, finished: FcSeason, rng: FcRng) -> Dictionary:
	return {"trades": FcTrades.new(world).run(league_id, finished, finished.year + 1, rng.fork("trades"))}


## AI free agency, legal rosters and staff changes.
func run_second_half(league_id: int, finished: FcSeason, rng: FcRng) -> Dictionary:
	var new_year := finished.year + 1
	var report := {}
	report["signed"] = free_agency(league_id, new_year, rng.fork("market"))
	report.merge(fill_rosters(league_id, new_year, rng.fork("fill")))
	report.merge(staff_rollover(league_id, finished.year, new_year, rng.fork("staff")))
	return report


# --- helpers -------------------------------------------------------------------

func _league(league_id: int) -> FcLeague:
	return world.leagues.get_by_id(league_id)


func _rules(league_id: int) -> FcLeagueRules:
	return world.rules_of_league(league_id)


func _age(player: FcPlayer, new_year: int) -> int:
	return player.age_on(FcDate.new(new_year, 7, 1))


func _on_a_roster() -> Dictionary:
	var out := {}
	for t in world.teams.all():
		for pid in t.roster.player_ids:
			out[pid] = t.id
	return out


func _coach_development(team_id: int) -> float:
	var total := 0.0
	var count := 0
	for sc in world.staff_contracts_of_team(team_id):
		if sc.role == FcStaffRole.Id.HEAD_COACH or sc.role == FcStaffRole.Id.ASSISTANT_COACH:
			var member: FcStaffMember = world.staff.get_by_id(sc.staff_id)
			if member != null:
				total += member.skills.get_value("player_development")
				count += 1
	return total / count if count > 0 else 50.0


func payroll(team_id: int, season_year: int) -> int:
	return world.payroll_of_team(team_id, season_year)


func _remove_from_roster(player_id: int) -> void:
	for t in world.teams.all():
		if t.roster.contains(player_id):
			t.roster.remove(player_id)


func _terminate_contract(player_id: int, status: int) -> void:
	var c := world.active_contract_of(player_id)
	if c != null:
		c.status = status


func _used_names_refresh() -> void:
	_used_names.clear()
	for p in world.players.all():
		_used_names[p.identity.full_name()] = true


# --- 1. aging and retirement -----------------------------------------------------

func progress_and_retire(league_id: int, finished_year: int, new_year: int, rng: FcRng) -> Dictionary:
	var team_of := _on_a_roster()
	var coach_cache := {}
	var retired := 0
	var progressed := 0
	for p in world.players.all():
		if p.status != FcPlayer.Status.ACTIVE:
			continue
		# the summer heals most injuries; very long ones carry over
		if p.games_out > 0:
			p.games_out = maxi(0, p.games_out - 60)
			if p.games_out == 0:
				p.injury = ""
		var age := _age(p, new_year)
		var team_id: int = team_of.get(p.id, 0)
		if team_id > 0 and not coach_cache.has(team_id):
			coach_cache[team_id] = _coach_development(team_id)
		var coach: float = coach_cache.get(team_id, 50.0)
		progression.progress(p, age, coach, rng)
		progressed += 1
		if progression.should_retire(p, age, rng):
			p.status = FcPlayer.Status.RETIRED
			p.retired_season = finished_year
			if ratings.overall(p) >= 58.0:
				world.add_news(FcDate.new(new_year, 6, 30), "retirement", "%s has retired after a long career" % p.identity.full_name(), team_id)
			_remove_from_roster(p.id)
			_terminate_contract(p.id, FcContract.Status.TERMINATED)
			retired += 1
	return {"progressed": progressed, "retired": retired}


# --- 2. contract expiry --------------------------------------------------------------

## Contracts whose last season has passed end; their players leave the roster.
## Returns {"expired": count, "expiring": [[player id, team id, last salary], ...]}.
func expire_contracts(league_id: int, finished_year: int) -> Dictionary:
	var expiring: Array = []
	for c in world.contracts.all():
		if c.status == FcContract.Status.ACTIVE and c.end_season() <= finished_year:
			c.status = FcContract.Status.EXPIRED
			var team: FcTeam = world.teams.get_by_id(c.team_id)
			if team != null:
				team.roster.remove(c.player_id)
			expiring.append([c.player_id, c.team_id, c.salary_for(c.end_season())])
	_last_expiring = expiring
	return {"expired": expiring.size()}


var _last_expiring: Array = []


# --- 3. re-signing -----------------------------------------------------------------------

func re_sign(league_id: int, new_year: int, rng: FcRng) -> int:
	var rules := _rules(league_id)
	var signed := 0
	var today := FcDate.new(new_year, 7, 1)
	for entry in _last_expiring:
		var p: FcPlayer = world.players.get_by_id(entry[0])
		var team: FcTeam = world.teams.get_by_id(entry[1])
		if p == null or team == null or p.status != FcPlayer.Status.ACTIVE:
			continue
		var agreed := human_team_ids.has(team.id) and agreed_re_signs.has(p.id)
		if human_team_ids.has(team.id) and not agreed:
			continue
		if team.roster.size() >= rules.roster_max:
			continue
		var age := _age(p, new_year)
		var worth := market.value(p, age)
		var wants := clampf(0.30 + (worth - 45.0) / 55.0, 0.08, 0.96)
		wants += (p.personality.get_value("loyalty") - 50.0) / 400.0
		if not agreed and not rng.chance(wants):
			continue
		var ask := market.asking_salary(p, age, rules.cap)
		var years := market.desired_years(age, rules.cap)
		if agreed and agreed_terms.has(p.id):
			ask = int(agreed_terms[p.id][0])
			years = int(agreed_terms[p.id][1])
		var check := rules.cap.check_signing(payroll(team.id, new_year), ask, FcCapRules.SigningKind.OWN_PLAYER)
		if not check.allowed:
			continue
		_sign(team, p, ask, years, new_year, today, rules)
		signed += 1
	return signed


func _sign(team: FcTeam, player: FcPlayer, salary: int, years: int, first_season: int, today: FcDate, rules: FcLeagueRules) -> void:
	var c := FcPlayerMarket.make_contract(world.ids.next_id(FcWorld.KIND_CONTRACT), player.id, team.id,
		first_season, years, salary, rules.cap, today)
	world.contracts.add(c)
	team.roster.add(player.id)
	if salary >= rules.cap.max_player_salary * 0.55:
		world.add_news(today, "signing", "%s sign %s for %s a year over %d years" % [world.team_display_name(team.id), player.identity.full_name(), "$%.1fM" % (salary / 1e6), years], team.id)


# --- 4. the draft ----------------------------------------------------------------------------
#
# The draft is a small state machine so a human owner can pick for their team:
#   ds = prepare_draft(...)            creates the class and the order (lottery included)
#   make_pick(ds, ...)                 one pick for the team on the clock (AI or human choice)
#   finish_draft(ds, finished)         undrafted prospects become free agents, results are stored
# `ds` is a plain Dictionary (saved with the game while the draft is under way):
#   {"year", "order" (round-one team ids), "total", "next" (1-based pick on the clock),
#    "available" (prospect ids), "results" ([[round, pick, team id, player id], ...])}

## Teams that missed the playoffs pick first (worst record first, or by lottery),
## then playoff teams by worst record. Creates the prospects.
func prepare_draft(league_id: int, finished: FcSeason, new_year: int, rng: FcRng) -> Dictionary:
	var league := _league(league_id)
	var rules := _rules(league_id)
	var team_ids := league.all_team_ids()
	var ranking := FcStandings.compute(league, finished.games).league_ranking()
	var order: Array[int] = []
	var qualified: Array[int] = []
	var missed: Array[int] = []
	for t in ranking:
		if finished.playoffs != null and finished.playoffs.qualified(t):
			qualified.append(t)
		else:
			missed.append(t)
	missed.reverse()
	qualified.reverse()
	missed = FcDraftLottery.order(missed, rules.draft, rng.fork("lottery"))
	order.append_array(missed)
	order.append_array(qualified)
	var total_picks := team_ids.size() * DRAFT_ROUNDS
	_used_names_refresh()
	var prospects := _make_prospects(total_picks + UNDRAFTED_EXTRA, new_year, rng.fork("prospects"))
	var available: Array = []
	for p in prospects:
		available.append(p.id)
	return {"year": new_year, "order": order, "total": total_picks, "next": 1, "available": available, "results": [], "workouts": []}


func draft_complete(ds: Dictionary) -> bool:
	return int(ds["next"]) > int(ds["total"])


## The team whose turn it is (the owner of the pick, which can differ from the team
## the pick was created for after a pick trade).
func draft_team_on_clock(ds: Dictionary) -> int:
	return world.pick_owner(int(ds["year"]), draft_round_on_clock(ds), draft_original_on_clock(ds))


## The team this pick was created for (its slot in the order).
func draft_original_on_clock(ds: Dictionary) -> int:
	var order: Array = ds["order"]
	return int(order[(int(ds["next"]) - 1) % order.size()])


func draft_round_on_clock(ds: Dictionary) -> int:
	return floori(float(int(ds["next"]) - 1) / (ds["order"] as Array).size()) + 1


## Which prospect a team's staff would pick right now (the AI's choice, also used
## to "let the staff pick" for a human). Each team sees prospects with its own
## error (see draft_noise); the noise is reproducible from the pick number.
## `emphasis` > 0 favours potential over current ability (a rebuilding direction), < 0 the opposite.
func ai_draft_choice(ds: Dictionary, team_id: int, rng: FcRng, emphasis: float = 0.0) -> int:
	var pick_rng := rng.fork("pick%d" % int(ds["next"]))
	var noise := maxf(0.5, draft_noise(team_id))
	var best := 0
	var best_score := -INF
	for pid in ds["available"]:
		var p: FcPlayer = world.players.get_by_id(int(pid))
		var score := market.value(p, _age(p, int(ds["year"]))) + pick_rng.gaussian(0.0, noise) + emphasis * (p.development.potential - ratings.overall(p))
		if score > best_score:
			best_score = score
			best = int(pid)
	return best


## The team on the clock takes `prospect_id`; returns false if he is not available.
func make_pick(ds: Dictionary, league_id: int, prospect_id: int) -> bool:
	var available: Array = ds["available"]
	var index := -1
	for i in available.size():
		if int(available[i]) == prospect_id:
			index = i
	if index < 0 or draft_complete(ds):
		return false
	var rules := _rules(league_id)
	var new_year: int = int(ds["year"])
	var pick: int = int(ds["next"])
	var round_number := draft_round_on_clock(ds)
	var team_id := draft_team_on_clock(ds)
	var original_id := draft_original_on_clock(ds)
	var team: FcTeam = world.teams.get_by_id(team_id)
	var best: FcPlayer = world.players.get_by_id(prospect_id)
	available.remove_at(index)
	best.status = FcPlayer.Status.ACTIVE
	(ds["results"] as Array).append([round_number, pick, team_id, best.id, original_id])
	ds["next"] = pick + 1
	if pick == 1:
		world.add_news(FcDate.new(new_year, 6, 25), "draft", "%s select %s with the first pick of the draft" % [world.team_display_name(team_id), best.identity.full_name()], team_id)
	# Late picks only get a roster spot when the team has room (otherwise the
	# player is released into free agency, as second-rounders often are).
	if round_number > 1 and team.roster.size() >= rules.roster_max - 2:
		return true
	if team.roster.size() >= rules.roster_max:
		_waive_worst(team, new_year)
	var salary := rules.cap.rookie_salary(pick, int(ds["total"]))
	var c := FcPlayerMarket.make_contract(world.ids.next_id(FcWorld.KIND_CONTRACT), best.id, team_id,
		new_year, rules.cap.rookie_contract_years, salary, rules.cap, FcDate.new(new_year, 7, 1))
	for i in c.years.size():
		if i >= rules.cap.rookie_guaranteed_years:
			c.years[i].option_type = FcContractYear.OptionType.TEAM
	world.contracts.add(c)
	team.roster.add(best.id)
	return true


## Ends the draft: undrafted prospects become free agents and the results are stored.
func finish_draft(ds: Dictionary, finished: FcSeason) -> int:
	for pid in ds["available"]:
		world.players.get_by_id(int(pid)).status = FcPlayer.Status.ACTIVE
	ds["available"] = []
	world.prune_picks(int(ds["year"]))
	finished.draft = (ds["results"] as Array).duplicate(true)
	return finished.draft.size()


## The whole draft with AI choices for every team. `rng` is the draft stream.
## Returns the number of players drafted.
func run_draft(league_id: int, finished: FcSeason, new_year: int, rng: FcRng) -> int:
	var ds := prepare_draft(league_id, finished, new_year, rng)
	while not draft_complete(ds):
		make_pick(ds, league_id, ai_draft_choice(ds, draft_team_on_clock(ds), rng))
	return finish_draft(ds, finished)


## What a team's scouts report about a prospect: estimates with ranges that hold the
## truth about 80% of the time. Better GMs and scouts give narrower, more accurate
## reports. The error is fixed for a team and prospect (reproducible, so the board
## does not change when it is redrawn). {"ovr", "ovr_low", "ovr_high", "pot", "pot_low",
## "pot_high", "value"}.
func scouting_report(team_id: int, prospect: FcPlayer, year: int, worked_out: bool = false) -> Dictionary:
	var sd := maxf(SCOUTING_MIN_SD, draft_noise(team_id))
	var pot_sd := sd * POTENTIAL_UNCERTAINTY
	var seed_text := "scout:%d:%d" % [team_id, prospect.id]
	if worked_out:
		# a private workout gives a much clearer (and independent) look
		sd = maxf(WORKOUT_MIN_SD, sd * WORKOUT_SHARPNESS)
		pot_sd = sd * WORKOUT_POTENTIAL_UNCERTAINTY
		seed_text = "workout:%d:%d" % [team_id, prospect.id]
	var noise := FcRng.new(hash(seed_text))
	var half := ceili(1.28 * sd)
	var pot_half := ceili(1.28 * pot_sd)
	var ovr := clampi(roundi(ratings.overall(prospect) + noise.gaussian(0.0, sd)), 1, 99)
	var pot := clampi(roundi(prospect.development.potential + noise.gaussian(0.0, pot_sd)), 1, 99)
	return {
		"ovr": ovr, "ovr_low": maxi(1, ovr - half), "ovr_high": mini(99, ovr + half),
		"pot": pot, "pot_low": maxi(1, pot - pot_half), "pot_high": mini(99, pot + pot_half),
		"value": market.value(prospect, _age(prospect, year)) + noise.gaussian(0.0, sd),
		"worked_out": worked_out, "character": character_note(prospect),
	}


## Private workouts: the owner may invite a few prospects; their reports are much sharper
## and show a note on their character.
const WORKOUT_SLOTS := 5
const WORKOUT_SHARPNESS := 0.4
const WORKOUT_MIN_SD := 1.0
const WORKOUT_POTENTIAL_UNCERTAINTY := 1.2


## The personality trait this prospect stands out for ("Very high Work Ethic").
func character_note(prospect: FcPlayer) -> String:
	var catalog: FcAttributeCatalog = world.definitions.personality
	var best_key := ""
	var best_gap := -1
	for key in catalog.keys():
		var gap := absi(prospect.personality.get_value(key) - 50)
		if gap > best_gap:
			best_gap = gap
			best_key = key
	if best_key == "":
		return ""
	var level := prospect.personality.get_value(best_key)
	return "%s %s" % ["High" if level >= 50 else "Low", catalog.get_def(best_key).display_name]


## How far off a team's view of a prospect can be (standard deviation in value
## points). A good GM helps, and so do scouts: every 100 points of scouting
## accuracy across a team's scouts removes SCOUT_NOISE_PER_100, up to
## SCOUT_NOISE_MAX. Never below 0.5.
const BASE_NOISE := 6.0
const SCOUT_NOISE_PER_100 := 1.2
const SCOUT_NOISE_MAX := 3.0


## Even the best scouts cannot see a teenager perfectly, and potential is harder to
## read than current ability.
const SCOUTING_MIN_SD := 2.0
const POTENTIAL_UNCERTAINTY := 1.5


func draft_noise(team_id: int) -> float:
	var gm := world.staff_in_role(team_id, FcStaffRole.Id.GENERAL_MANAGER)
	var noise := BASE_NOISE - (gm.skills.get_value("talent_evaluation") / 20.0 if gm != null else 2.5)
	var accuracy := 0.0
	for sc in world.staff_contracts_of_team(team_id, FcStaffRole.Id.SCOUT):
		var scout: FcStaffMember = world.staff.get_by_id(sc.staff_id)
		if scout != null:
			accuracy += scout.skills.get_value("scouting_accuracy")
	noise -= minf(SCOUT_NOISE_MAX, accuracy / 100.0 * SCOUT_NOISE_PER_100)
	return maxf(0.5, noise)


func _make_prospects(count: int, new_year: int, rng: FcRng) -> Array[FcPlayer]:
	var out: Array[FcPlayer] = []
	var positions: Array[int] = []
	for i in count:
		positions.append(FcPosition.Id.PG + (i % 5))
	for i in count:
		var spec := FcPlayerSpec.new()
		spec.age = [19, 19, 20, 20, 21, 22][rng.range_int(0, 5)]
		spec.position = positions[rng.range_int(0, positions.size() - 1)]
		spec.level = clampf(rng.gaussian(41.0, 7.0), 25.0, 64.0)
		spec.country_key = FcNameGenerator.new(_gen_data).pick_origin(rng, "", 0.0)
		spec.reference_date = FcDate.new(new_year, 7, 1)
		spec.used_names = _used_names
		var p := generator.generate(rng, world.ids.next_id(FcWorld.KIND_PLAYER), spec)
		p.status = FcPlayer.Status.PROSPECT
		world.players.add(p)
		out.append(p)
	return out


# --- 5. free agency ----------------------------------------------------------------------------

func _free_agents() -> Array[FcPlayer]:
	var on := _on_a_roster()
	var out: Array[FcPlayer] = []
	for p in world.players.all():
		if p.status == FcPlayer.Status.ACTIVE and not on.has(p.id):
			out.append(p)
	return out


func free_agency(league_id: int, new_year: int, rng: FcRng) -> int:
	var rules := _rules(league_id)
	var league := _league(league_id)
	var today := FcDate.new(new_year, 7, 1)
	var pool := _free_agents()
	var values := {}
	for p in pool:
		values[p.id] = market.value(p, _age(p, new_year))
	pool.sort_custom(func(a: FcPlayer, b: FcPlayer): return values[a.id] > values[b.id])
	var mle_used := {}
	var signed := 0
	for round_number in MARKET_ROUNDS:
		var order: Array[int] = league.all_team_ids()
		order.sort_custom(func(a: int, b: int): return rules.cap.cap_space(payroll(a, new_year)) > rules.cap.cap_space(payroll(b, new_year)))
		var signed_this_round := 0
		for team_id in order:
			var team: FcTeam = world.teams.get_by_id(team_id)
			if manual_free_agency_team_ids.has(team_id) or team.roster.size() >= rules.roster_max - 1:
				continue
			var spent := payroll(team_id, new_year)
			for p in pool:
				if world.team_of_player(p.id) != null:
					continue
				var age := _age(p, new_year)
				var ask := market.asking_salary(p, age, rules.cap)
				var kind := -1
				var offer := ask
				if rules.cap.check_signing(spent, ask, FcCapRules.SigningKind.CAP_SPACE).allowed:
					kind = FcCapRules.SigningKind.CAP_SPACE
				elif not mle_used.has(team_id) and rules.cap.check_signing(spent, ask, FcCapRules.SigningKind.MID_LEVEL).allowed:
					kind = FcCapRules.SigningKind.MID_LEVEL
					mle_used[team_id] = true
				elif ask <= int(rules.cap.min_player_salary * 1.35):
					offer = rules.cap.min_player_salary
					if rules.cap.check_signing(spent, offer, FcCapRules.SigningKind.MINIMUM).allowed:
						kind = FcCapRules.SigningKind.MINIMUM
				if kind < 0:
					continue
				_sign(team, p, offer, market.desired_years(age, rules.cap), new_year, today, rules)
				pool.erase(p)
				signed += 1
				signed_this_round += 1
				break
		if signed_this_round == 0:
			break
	return signed


# --- 6. legal rosters ------------------------------------------------------------------------------

func fill_rosters(league_id: int, new_year: int, rng: FcRng) -> Dictionary:
	var rules := _rules(league_id)
	var league := _league(league_id)
	var today := FcDate.new(new_year, 7, 1)
	var waived := 0
	var emergency := 0
	_used_names_refresh()
	# fresh free agents (players from outside the league's system) keep the pool healthy
	var spec_rng := rng.fork("fresh")
	for i in FRESH_FREE_AGENTS:
		var spec := FcPlayerSpec.new()
		spec.age = spec_rng.range_int(23, 30)
		spec.position = FcPosition.Id.PG + spec_rng.range_int(0, 4)
		spec.level = clampf(spec_rng.gaussian(43.0, 6.0), 28.0, 60.0)
		spec.country_key = FcNameGenerator.new(_gen_data).pick_origin(spec_rng, "", 0.0)
		spec.reference_date = today
		spec.used_names = _used_names
		world.players.add(generator.generate(spec_rng, world.ids.next_id(FcWorld.KIND_PLAYER), spec))
	for team_id in league.all_team_ids():
		var team: FcTeam = world.teams.get_by_id(team_id)
		team.roster.max_size = rules.roster_max
		while team.roster.size() > rules.roster_max:
			_waive_worst(team, new_year)
			waived += 1
		if team.roster.size() >= rules.roster_min:
			continue
		var pool := _free_agents()
		pool.sort_custom(func(a: FcPlayer, b: FcPlayer): return market.value(a, _age(a, new_year)) > market.value(b, _age(b, new_year)))
		for p in pool:
			if team.roster.size() >= rules.roster_min:
				break
			if rules.cap.check_signing(payroll(team_id, new_year), rules.cap.min_player_salary, FcCapRules.SigningKind.MINIMUM).allowed:
				_sign(team, p, rules.cap.min_player_salary, 1, new_year, today, rules)
	return {"waived": waived, "emergency": emergency}


# --- 7. staff ---------------------------------------------------------------------------------------

## Staff age: skills drift a little, experience grows, older staff may retire.
## Expired staff contracts are renewed (70%) or the vacancy is filled from the
## pool of staff without a job (best reputation first); if the pool has nobody
## suitable a new person is generated. Every team keeps the same number of
## staff in each role.
func staff_rollover(league_id: int, finished_year: int, new_year: int, rng: FcRng) -> Dictionary:
	var rules := _rules(league_id)
	var league := _league(league_id)
	var today := FcDate.new(new_year, 7, 1)
	var staff_gen := FcStaffGenerator.new(_gen_data, world.definitions)
	var retired := 0
	var renewed := 0
	var hired := 0
	var vacancies: Array = []   # [team id, role]
	# 1. aging and retirement
	for m in world.staff.all():
		if m.status != FcStaffMember.Status.ACTIVE:
			continue
		m.experience_years += 1
		for key in world.definitions.staff_skills.keys():
			m.skills.set_clamped(key, m.skills.get_value(key) + roundi(rng.gaussian(0.0, 1.2)))
		var age: int = m.age_on(FcDate.new(new_year, 7, 1))
		var chance: float = 1.0 if age >= 72 else (0.0 if age < 62 else (age - 61) * 0.12)
		if rng.chance(chance):
			m.status = FcStaffMember.Status.RETIRED
			m.retired_season = finished_year
			var job := world.active_staff_contract_of(m.id)
			if job != null:
				job.status = FcContract.Status.TERMINATED
				vacancies.append([job.team_id, job.role])
			retired += 1
	# 2. expired contracts: renew or vacate
	for c in world.staff_contracts.all():
		if c.status == FcContract.Status.ACTIVE and c.end_season() <= finished_year:
			var m: FcStaffMember = world.staff.get_by_id(c.staff_id)
			c.status = FcContract.Status.EXPIRED
			if m != null and m.status == FcStaffMember.Status.ACTIVE and rng.chance(0.7):
				world.staff_contracts.add(_staff_contract(c.staff_id, c.team_id, c.role, m.reputation, new_year, rng, staff_gen, today))
				renewed += 1
			else:
				vacancies.append([c.team_id, c.role])
	# 3. fill vacancies
	for v in vacancies:
		var best: FcStaffMember = null
		for m in world.staff.all():
			if m.status == FcStaffMember.Status.ACTIVE and m.primary_role == v[1] and world.active_staff_contract_of(m.id) == null:
				if best == null or m.reputation > best.reputation:
					best = m
		if best == null:
			best = staff_gen.generate(rng, world.ids.next_id(FcWorld.KIND_STAFF), v[1], clampf(rng.gaussian(52.0, 10.0), 30.0, 80.0), today, _names_taken_staff())
			world.staff.add(best)
		world.staff_contracts.add(_staff_contract(best.id, v[0], v[1], best.reputation, new_year, rng, staff_gen, today))
		hired += 1
	return {"staff_retired": retired, "staff_renewed": renewed, "staff_hired": hired}


func _names_taken_staff() -> Dictionary:
	var taken := {}
	for m in world.staff.all():
		taken[m.identity.full_name()] = true
	for p in world.players.all():
		taken[p.identity.full_name()] = true
	return taken


func _staff_contract(staff_id: int, team_id: int, role: int, reputation: int, new_year: int, rng: FcRng, staff_gen: FcStaffGenerator, today: FcDate) -> FcStaffContract:
	var c := FcStaffContract.new(world.ids.next_id(FcWorld.KIND_STAFF_CONTRACT))
	c.staff_id = staff_id
	c.team_id = team_id
	c.role = role
	c.signed_on = today
	var years := rng.range_int(1, 3)
	var salary := staff_gen.salary_for(role, reputation)
	for i in years:
		c.years.append(FcContractYear.new(new_year + i, roundi(salary * pow(1.04, i) / 10000.0) * 10000))
	return c


## Releases the team's lowest-value player (his contract is terminated).
func _waive_worst(team: FcTeam, new_year: int) -> void:
	var worst_id := 0
	var worst_value := INF
	for pid in team.roster.player_ids:
		var p: FcPlayer = world.players.get_by_id(pid)
		var v := market.value(p, _age(p, new_year))
		if v < worst_value:
			worst_value = v
			worst_id = pid
	if worst_id > 0:
		team.roster.remove(worst_id)
		_terminate_contract(worst_id, FcContract.Status.TERMINATED)
