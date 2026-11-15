class_name FcWorld
extends RefCounted
## The whole basketball universe's data in one place: attribute definitions,
## the ID generator, and one repository per entity type. It also checks that
## entities agree with each other (no contract pointing at a missing player,
## no player on two rosters...). It holds data only: no simulation, no UI.
##
## to_dict()/from_dict() produce the snapshot the future save system will wrap
## with slots, metadata, versioning and atomic file writing.

const SCHEMA_VERSION := 1

const KIND_PLAYER := "player"
const KIND_TEAM := "team"
const KIND_CONTRACT := "contract"
const KIND_CITY := "city"
const KIND_ARENA := "arena"
const KIND_STAFF := "staff"
const KIND_STAFF_CONTRACT := "staff_contract"
const KIND_LEAGUE := "league"
const KIND_CONFERENCE := "conference"
const KIND_DIVISION := "division"
const KIND_RULES := "league_rules"
const KIND_SEASON := "season"
const KIND_FINANCE := "finance"

var definitions: FcDefinitionSet
var ids := FcIdGenerator.new()
var players: FcRepository = FcMemoryRepository.new()
var teams: FcRepository = FcMemoryRepository.new()
var contracts: FcRepository = FcMemoryRepository.new()
var cities: FcRepository = FcMemoryRepository.new()
var arenas: FcRepository = FcMemoryRepository.new()
var staff: FcRepository = FcMemoryRepository.new()
var staff_contracts: FcRepository = FcMemoryRepository.new()
var leagues: FcRepository = FcMemoryRepository.new()
var rules: FcRepository = FcMemoryRepository.new()
var seasons: FcRepository = FcMemoryRepository.new()
## Business state per team (id = team id) and yearly financial results.
var businesses: FcRepository = FcMemoryRepository.new()
## News feed, newest last: [{"date": ISO text, "kind": String, "text": String, "team": team id or 0}, ...]. Kept to the last NEWS_LIMIT items.
var news: Array = []
const NEWS_LIMIT := 300
var finances: FcRepository = FcMemoryRepository.new()


func _init(defs: FcDefinitionSet) -> void:
	definitions = defs


## The team whose roster contains this player, or null (free agent).
func team_of_player(player_id: int) -> FcTeam:
	for t in teams.all():
		if t.roster.contains(player_id):
			return t
	return null


## The player's ACTIVE contract, or null.
func active_contract_of(player_id: int) -> FcContract:
	for c in contracts.all():
		if c.player_id == player_id and c.status == FcContract.Status.ACTIVE:
			return c
	return null


## The league that contains this team, or null.
func league_of_team(team_id: int) -> FcLeague:
	for l in leagues.all():
		if l.contains_team(team_id):
			return l
	return null


## Adds a news item (kinds: "injury", "milestone", "champion", "award", "signing", "retirement", "draft", "staff").
func add_news(date: FcDate, kind: String, text: String, team_id: int = 0) -> void:
	news.append({"date": date.to_iso(), "kind": kind, "text": text, "team": team_id})
	if news.size() > NEWS_LIMIT:
		news = news.slice(news.size() - NEWS_LIMIT)


func team_display_name(team_id: int) -> String:
	var t: FcTeam = teams.get_by_id(team_id)
	if t == null:
		return "-"
	var c: FcCity = cities.get_by_id(t.city_id)
	return t.identity.display_name(c.name if c != null else "")


func player_name(player_id: int) -> String:
	var p: FcPlayer = players.get_by_id(player_id)
	return p.identity.full_name() if p != null else "-"


## The season of a league for a given year, or null.
func season_of(league_id: int, year: int) -> FcSeason:
	for s in seasons.all():
		if s.league_id == league_id and s.year == year:
			return s
	return null


## The rules of a league, or null.
func rules_of_league(league_id: int) -> FcLeagueRules:
	for r in rules.all():
		if r.league_id == league_id:
			return r
	return null


## The rules of the league this team plays in, or null.
func rules_of_team(team_id: int) -> FcLeagueRules:
	var league := league_of_team(team_id)
	return rules_of_league(league.id) if league != null else null


## Sum of the cap hits of a team's ACTIVE player contracts in a season.
func payroll_of_team(team_id: int, season: int) -> int:
	var total := 0
	for c in contracts.all():
		if c.team_id == team_id and c.status == FcContract.Status.ACTIVE:
			total += c.cap_hit_for(season)
	return total


## The staff member's ACTIVE staff contract (their current job), or null.
func active_staff_contract_of(staff_id: int) -> FcStaffContract:
	for c in staff_contracts.all():
		if c.staff_id == staff_id and c.status == FcContract.Status.ACTIVE:
			return c
	return null


## ACTIVE staff contracts of a team (its current staff), optionally only one role.
func staff_contracts_of_team(team_id: int, role: int = FcStaffRole.Id.NONE) -> Array[FcStaffContract]:
	var out: Array[FcStaffContract] = []
	for c in staff_contracts.all():
		if c.team_id == team_id and c.status == FcContract.Status.ACTIVE \
				and (role == FcStaffRole.Id.NONE or c.role == role):
			out.append(c)
	return out


## The staff member currently holding a unique role (GM, head coach) with the team, or null.
func staff_in_role(team_id: int, role: int) -> FcStaffMember:
	var held := staff_contracts_of_team(team_id, role)
	return staff.get_by_id(held[0].staff_id) if not held.is_empty() else null


## Full integrity check. Returns problems as readable text; empty = healthy.
## Pass `season` (e.g. the current season) to also check team payrolls against
## the league's hard limit; without it only season-independent rules are checked.
func validate(season: int = 0) -> Array[String]:
	var errors: Array[String] = []

	for c in cities.all():
		for e in c.validate():
			errors.append("city %d: %s" % [c.id, e])
	for a in arenas.all():
		for e in a.validate():
			errors.append("arena %d: %s" % [a.id, e])
		if a.city_id > 0 and not cities.has_id(a.city_id):
			errors.append("arena %d: city %d does not exist" % [a.id, a.city_id])
	for p in players.all():
		for e in p.validate():
			errors.append("player %d: %s" % [p.id, e])
	for t in teams.all():
		for e in t.validate():
			errors.append("team %d: %s" % [t.id, e])
		if t.city_id > 0 and not cities.has_id(t.city_id):
			errors.append("team %d: city %d does not exist" % [t.id, t.city_id])
		if t.arena_id > 0 and not arenas.has_id(t.arena_id):
			errors.append("team %d: arena %d does not exist" % [t.id, t.arena_id])

	var active_by_player := {}
	for c in contracts.all():
		for e in c.validate():
			errors.append("contract %d: %s" % [c.id, e])
		if c.player_id > 0 and not players.has_id(c.player_id):
			errors.append("contract %d: player %d does not exist" % [c.id, c.player_id])
		if c.team_id > 0 and not teams.has_id(c.team_id):
			errors.append("contract %d: team %d does not exist" % [c.id, c.team_id])
		if c.status == FcContract.Status.ACTIVE:
			if active_by_player.has(c.player_id):
				errors.append("player %d has more than one active contract" % c.player_id)
			active_by_player[c.player_id] = c

	var team_league := {}  # team id -> league id
	for l in leagues.all():
		for e in l.validate():
			errors.append("league %d: %s" % [l.id, e])
		for tid in l.all_team_ids():
			if not teams.has_id(tid):
				errors.append("league %d: team %d does not exist" % [l.id, tid])
			elif team_league.has(tid) and team_league[tid] != l.id:
				errors.append("team %d is in leagues %d and %d" % [tid, team_league[tid], l.id])
			team_league[tid] = l.id
	if leagues.count() > 0:
		for t in teams.all():
			if not team_league.has(t.id):
				errors.append("team %d is not in any league" % t.id)

	for sn in seasons.all():
		var season_league: FcLeague = leagues.get_by_id(sn.league_id)
		if season_league == null:
			errors.append("season %d: league %d does not exist" % [sn.id, sn.league_id])
			continue
		for e in sn.validate(season_league):
			errors.append("season %d: %s" % [sn.id, e])
	for b in businesses.all():
		if not teams.has_id(b.id):
			errors.append("business %d: team does not exist" % b.id)
		for e in b.validate():
			errors.append("business %d: %s" % [b.id, e])
	for fr in finances.all():
		if not teams.has_id(fr.team_id):
			errors.append("finance record %d: team %d does not exist" % [fr.id, fr.team_id])
		for e in fr.validate():
			errors.append("finance record %d: %s" % [fr.id, e])
	var rules_per_league := {}
	for r in rules.all():
		var league: FcLeague = leagues.get_by_id(r.league_id)
		if league == null:
			errors.append("rules %d: league %d does not exist" % [r.id, r.league_id])
			continue
		for e in r.validate(league):
			errors.append("rules %d: %s" % [r.id, e])
		if rules_per_league.has(r.league_id):
			errors.append("league %d has more than one set of rules" % r.league_id)
		rules_per_league[r.league_id] = r
	for c in contracts.all():
		var team_rules := rules_of_team(c.team_id)
		if team_rules != null and c.status == FcContract.Status.ACTIVE:
			for e in team_rules.cap.validate_contract(c):
				errors.append("contract %d breaks league rules: %s" % [c.id, e])
	for t in teams.all():
		var team_rules := rules_of_team(t.id)
		if team_rules == null:
			continue
		if t.roster.size() > team_rules.roster_max:
			errors.append("team %d has %d players but the league maximum is %d" % [t.id, t.roster.size(), team_rules.roster_max])
		if season > 0:
			var payroll := payroll_of_team(t.id, season)
			var limit := team_rules.cap.effective_limit()
			if limit > 0 and payroll > limit:
				errors.append("team %d payroll %d exceeds the league limit %d" % [t.id, payroll, limit])

	for s in staff.all():
		for e in s.validate():
			errors.append("staff %d: %s" % [s.id, e])
	var active_job_by_staff := {}
	var unique_roles := {}  # "team:role" -> staff contract id
	for c in staff_contracts.all():
		for e in c.validate():
			errors.append("staff contract %d: %s" % [c.id, e])
		var member: FcStaffMember = staff.get_by_id(c.staff_id)
		if c.staff_id > 0 and member == null:
			errors.append("staff contract %d: staff %d does not exist" % [c.id, c.staff_id])
		if c.team_id > 0 and not teams.has_id(c.team_id):
			errors.append("staff contract %d: team %d does not exist" % [c.id, c.team_id])
		if c.status != FcContract.Status.ACTIVE:
			continue
		if member != null and member.status == FcStaffMember.Status.RETIRED:
			errors.append("staff contract %d: staff %d is retired but has an active contract" % [c.id, c.staff_id])
		if active_job_by_staff.has(c.staff_id):
			errors.append("staff %d has more than one active contract" % c.staff_id)
		active_job_by_staff[c.staff_id] = c.id
		if FcStaffRole.is_unique_per_team(c.role):
			var key := "%d:%d" % [c.team_id, c.role]
			if unique_roles.has(key):
				errors.append("team %d has more than one active %s" % [c.team_id, FcStaffRole.display_name(c.role)])
			unique_roles[key] = c.id

	var rostered := {}
	for t in teams.all():
		for pid in t.roster.player_ids:
			var p: FcPlayer = players.get_by_id(pid)
			if p == null:
				errors.append("team %d: roster player %d does not exist" % [t.id, pid])
				continue
			if rostered.has(pid):
				errors.append("player %d is on rosters of teams %d and %d" % [pid, rostered[pid], t.id])
			rostered[pid] = t.id
			if p.status == FcPlayer.Status.RETIRED:
				errors.append("team %d: roster player %d is retired" % [t.id, pid])
			var contract: FcContract = active_by_player.get(pid, null)
			if contract == null or contract.team_id != t.id:
				errors.append("team %d: roster player %d has no active contract with this team" % [t.id, pid])
	return errors


func to_dict() -> Dictionary:
	return {
		"schema": SCHEMA_VERSION,
		"ids": ids.to_dict(),
		"cities": _dicts_of(cities),
		"arenas": _dicts_of(arenas),
		"teams": _dicts_of(teams),
		"players": _dicts_of(players),
		"contracts": _dicts_of(contracts),
		"staff": _dicts_of(staff),
		"staff_contracts": _dicts_of(staff_contracts),
		"leagues": _dicts_of(leagues),
		"rules": _dicts_of(rules),
		"seasons": _dicts_of(seasons),
		"businesses": _dicts_of(businesses),
		"news": news.duplicate(true),
		"finances": _dicts_of(finances),
	}


## Rebuilds a world from a snapshot. Entities that cannot be added (duplicate
## or invalid id) are reported in the returned `errors` array.
static func from_dict(data: Dictionary, defs: FcDefinitionSet, errors: Array[String] = []) -> FcWorld:
	var w := FcWorld.new(defs)
	w.ids.from_dict(data.get("ids", {}))
	for d in data.get("cities", []):
		_report(w.cities.add(FcCity.from_dict(d)), "city", errors)
	for d in data.get("arenas", []):
		_report(w.arenas.add(FcArena.from_dict(d)), "arena", errors)
	for d in data.get("teams", []):
		_report(w.teams.add(FcTeam.from_dict(d)), "team", errors)
	for d in data.get("players", []):
		_report(w.players.add(FcPlayer.from_dict(d, defs)), "player", errors)
	for d in data.get("contracts", []):
		_report(w.contracts.add(FcContract.from_dict(d)), "contract", errors)
	# Staff sections were added after the first saves existed; missing = empty.
	for d in data.get("staff", []):
		_report(w.staff.add(FcStaffMember.from_dict(d, defs)), "staff member", errors)
	for d in data.get("staff_contracts", []):
		_report(w.staff_contracts.add(FcStaffContract.from_dict(d)), "staff contract", errors)
	for d in data.get("leagues", []):
		_report(w.leagues.add(FcLeague.from_dict(d)), "league", errors)
	for d in data.get("rules", []):
		_report(w.rules.add(FcLeagueRules.from_dict(d)), "league rules", errors)
	for d in data.get("seasons", []):
		_report(w.seasons.add(FcSeason.from_dict(d)), "season", errors)
	for item in data.get("news", []):
		w.news.append({"date": str(item["date"]), "kind": str(item["kind"]), "text": str(item["text"]), "team": int(item["team"])})
	for d in data.get("businesses", []):
		_report(w.businesses.add(FcTeamBusiness.from_dict(d)), "team business", errors)
	for d in data.get("finances", []):
		_report(w.finances.add(FcFinanceRecord.from_dict(d)), "finance record", errors)
	return w


static func _report(err: Error, label: String, errors: Array[String]) -> void:
	if err != OK:
		errors.append("could not load %s (error %d)" % [label, err])


static func _dicts_of(repo: FcRepository) -> Array:
	var out: Array = []
	for e in repo.all():
		out.append(e.to_dict())
	return out
