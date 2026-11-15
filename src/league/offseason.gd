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
	var new_year := finished.year + 1
	var report := {}
	report.merge(progress_and_retire(league_id, finished.year, new_year, rng.fork("progress")))
	report.merge(expire_contracts(league_id, finished.year))
	report["re_signed"] = re_sign(league_id, new_year, rng.fork("resign"))
	report["drafted"] = run_draft(league_id, finished, new_year, rng.fork("draft"))
	report["trades"] = FcTrades.new(world).run(league_id, finished, new_year, rng.fork("trades"))
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
		if team.roster.size() >= rules.roster_max:
			continue
		var age := _age(p, new_year)
		var worth := market.value(p, age)
		var wants := clampf(0.30 + (worth - 45.0) / 55.0, 0.08, 0.96)
		wants += (p.personality.get_value("loyalty") - 50.0) / 400.0
		if not rng.chance(wants):
			continue
		var ask := market.asking_salary(p, age, rules.cap)
		var check := rules.cap.check_signing(payroll(team.id, new_year), ask, FcCapRules.SigningKind.OWN_PLAYER)
		if not check.allowed:
			continue
		_sign(team, p, ask, market.desired_years(age, rules.cap), new_year, today, rules)
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

## Returns the number of players drafted. Order: teams that missed the playoffs
## by worst record first, then playoff teams by worst record (no lottery in v1).
func run_draft(league_id: int, finished: FcSeason, new_year: int, rng: FcRng) -> int:
	var league := _league(league_id)
	var rules := _rules(league_id)
	var team_ids := league.all_team_ids()
	var standings := FcStandings.compute(league, finished.games)
	var ranking := standings.league_ranking()
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
	order.append_array(missed)
	order.append_array(qualified)

	var total_picks := team_ids.size() * DRAFT_ROUNDS
	_used_names_refresh()
	var prospects := _make_prospects(total_picks + UNDRAFTED_EXTRA, new_year, rng)
	var available: Array[FcPlayer] = prospects.duplicate()
	var today := FcDate.new(new_year, 7, 1)
	var results: Array = []
	var pick := 0
	for round_number in range(1, DRAFT_ROUNDS + 1):
		for team_id in order:
			pick += 1
			var team: FcTeam = world.teams.get_by_id(team_id)
			var gm := world.staff_in_role(team_id, FcStaffRole.Id.GENERAL_MANAGER)
			var noise := 6.0 - (gm.skills.get_value("talent_evaluation") / 20.0 if gm != null else 2.5)
			var best: FcPlayer = null
			var best_score := -INF
			for p in available:
				var score := market.value(p, _age(p, new_year)) + rng.gaussian(0.0, maxf(0.5, noise))
				if score > best_score:
					best_score = score
					best = p
			available.erase(best)
			best.status = FcPlayer.Status.ACTIVE
			results.append([round_number, pick, team_id, best.id])
			if pick == 1:
				world.add_news(FcDate.new(new_year, 6, 25), "draft", "%s select %s with the first pick of the draft" % [world.team_display_name(team_id), best.identity.full_name()], team_id)
			# Late picks only get a roster spot when the team has room (otherwise the
			# player is released into free agency, as second-rounders often are).
			if round_number > 1 and team.roster.size() >= rules.roster_max - 2:
				continue
			if team.roster.size() >= rules.roster_max:
				_waive_worst(team, new_year)
			var salary := rules.cap.rookie_salary(pick, total_picks)
			var c := FcPlayerMarket.make_contract(world.ids.next_id(FcWorld.KIND_CONTRACT), best.id, team_id,
				new_year, rules.cap.rookie_contract_years, salary, rules.cap, today)
			for i in c.years.size():
				if i >= rules.cap.rookie_guaranteed_years:
					c.years[i].option_type = FcContractYear.OptionType.TEAM
			world.contracts.add(c)
			team.roster.add(best.id)
	for p in available:
		p.status = FcPlayer.Status.ACTIVE   # undrafted: free agents
	finished.draft = results
	return results.size()


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
			if team.roster.size() >= rules.roster_max - 1:
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
