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
## Career statistics by player id: rows of [year, team id, gp, seconds, points, fgm, fga, tpm, tpa, ftm, fta, oreb, dreb, ast, stl, blk, tov, pf]
## (one per regular season). Kept forever, unlike the season's own detailed statistics.
var careers: Dictionary = {}
## Injury history by player id: rows {year, injury, games, severe} (the season it happened in, what it was, games missed after medical care, and whether it
## cost athleticism for good). Newest last, at most INJURY_HISTORY_LIMIT per player. Added after the first saves existed: a save without it loads as empty.
var injury_history: Dictionary = {}
const INJURY_HISTORY_LIMIT := 12
## Draft picks that changed hands: "year:round:original team id" -> owner team id.
## A pick not listed belongs to the team it was created for. `year` is the year of the
## season that starts after the draft (the 2027 draft follows the 2026-27 season).
var pick_owners: Dictionary = {}
const CAREER_COLUMNS := ["year", "team", "gp", "seconds", "points", "fgm", "fga", "tpm", "tpa", "ftm", "fta", "oreb", "dreb", "ast", "stl", "blk", "tov", "pf"]
const NEWS_LIMIT := 300
## Structured transactions (D-077 E): every signing, release, trade and staff move, newest last, with a stable id from `ids` (kind "txn").
## [{"id", "date" (ISO), "kind" ("signing" | "release" | "trade" | "staff" | "draft" | "retirement"), "text", "team", "other" (team id or 0),
##   "players": [ids]}]. Kept to the last TRANSACTION_LIMIT.
var transactions: Array = []
const TRANSACTION_LIMIT := 3000
const KIND_TRANSACTION := "txn"
## Each player's overall and potential at the end of every season he played (D-077: the profile's rating history): {player id: [[year,
## overall, potential], ...]}.
var rating_history: Dictionary = {}
var finances: FcRepository = FcMemoryRepository.new()


func _init(defs: FcDefinitionSet) -> void:
	definitions = defs


## The team whose roster contains this player, or null (free agent).
func team_of_player(player_id: int) -> FcTeam:
	for t in teams.all():
		if t.roster.contains(player_id):
			return t
	return null


## Forgets contracts (players and staff) that ended or were terminated more than two seasons
## before `year`: nothing needs them (careers and history are stored separately), and keeping
## them forever makes every contract lookup slower, so a 50-season league would crawl.
## Returns how many were removed.
func prune_old_contracts(year: int) -> int:
	var removed := 0
	for c in contracts.all():
		if c.status != FcContract.Status.ACTIVE and c.end_season() < year - 2:
			contracts.remove(c.id)
			removed += 1
	for sc in staff_contracts.all():
		if sc.status != FcContract.Status.ACTIVE and sc.end_season() < year - 2:
			staff_contracts.remove(sc.id)
			removed += 1
	return removed


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


static func pick_key(year: int, round_number: int, original_team_id: int) -> String:
	return "%d:%d:%d" % [year, round_number, original_team_id]


## Who owns this draft pick right now.
func pick_owner(year: int, round_number: int, original_team_id: int) -> int:
	return int(pick_owners.get(pick_key(year, round_number, original_team_id), original_team_id))


func set_pick_owner(year: int, round_number: int, original_team_id: int, owner_team_id: int) -> void:
	var key := pick_key(year, round_number, original_team_id)
	if owner_team_id == original_team_id:
		pick_owners.erase(key)
	else:
		pick_owners[key] = owner_team_id


## Forgets ownership records of drafts that have been held (through `year`).
func prune_picks(year: int) -> void:
	for key in pick_owners.keys():
		if int(str(key).split(":")[0]) <= year:
			pick_owners.erase(key)


## Adds a news item (kinds: "injury", "milestone", "champion", "award", "signing", "retirement", "draft", "staff"). `txn` links it to the
## transaction it reports (0 = none).
func add_news(date: FcDate, kind: String, text: String, team_id: int = 0, txn: int = 0) -> void:
	var item := {"date": date.to_iso(), "kind": kind, "text": text, "team": team_id}
	if txn > 0:
		item["txn"] = txn
	news.append(item)
	if news.size() > NEWS_LIMIT:
		news = news.slice(news.size() - NEWS_LIMIT)


## Records a transaction and its news item (the news keeps its old kind, `news_kind`, so the news feed reads as before). Returns the
## transaction id.
func add_transaction(date: FcDate, kind: String, text: String, team_id: int, player_ids: Array = [], other_team_id: int = 0, news_kind: String = "signing") -> int:
	var id := ids.next_id(KIND_TRANSACTION)
	var players_copy: Array = []
	for pid in player_ids:
		players_copy.append(int(pid))
	transactions.append({"id": id, "date": date.to_iso(), "kind": kind, "text": text, "team": team_id, "other": other_team_id, "players": players_copy})
	if transactions.size() > TRANSACTION_LIMIT:
		transactions = transactions.slice(transactions.size() - TRANSACTION_LIMIT)
	if news_kind != "":
		add_news(date, news_kind, text, team_id, id)
	return id


## Transactions dated `iso` (a day of the calendar), oldest first.
func transactions_on(iso: String) -> Array:
	return transactions.filter(func(t: Dictionary) -> bool: return str(t["date"]) == iso)


## Records a player's end-of-season overall and potential (replacing an existing row for the same year).
func record_rating(player_id: int, year: int, overall: int, potential: int) -> void:
	if not rating_history.has(player_id):
		rating_history[player_id] = []
	var rows: Array = rating_history[player_id]
	for i in range(rows.size() - 1, -1, -1):
		if int(rows[i][0]) == year:
			rows.remove_at(i)
	rows.append([year, overall, potential])


## Remembers an injury in the player's history (the oldest rows drop off past the limit).
func record_injury(player_id: int, year: int, injury: String, games: int, severe: bool) -> void:
	if not injury_history.has(player_id):
		injury_history[player_id] = []
	var rows: Array = injury_history[player_id]
	rows.append({"year": year, "injury": injury, "games": games, "severe": severe})
	if rows.size() > INJURY_HISTORY_LIMIT:
		rows.pop_front()


func injuries_of(player_id: int) -> Array:
	return injury_history.get(player_id, [])


func team_display_name(team_id: int) -> String:
	var t: FcTeam = teams.get_by_id(team_id)
	if t == null:
		return "-"
	var c: FcCity = cities.get_by_id(t.city_id)
	return t.identity.display_name(c.name if c != null else "")


func player_name(player_id: int) -> String:
	var p: FcPlayer = players.get_by_id(player_id)
	return p.identity.full_name() if p != null else "-"


## Adds a finished regular season's player statistics to every player's career.
func record_career(season: FcSeason) -> void:
	for pid in season.stats.lines:
		var l: Dictionary = season.stats.lines[pid]
		var row: Array = [season.year, l["team"]]
		for key in FcSeasonStats.KEYS:
			row.append(l[key])
		if not careers.has(pid):
			careers[pid] = []
		# replace an existing row for the same year (a season can be recorded twice)
		var rows: Array = careers[pid]
		for i in range(rows.size() - 1, -1, -1):
			if rows[i][0] == season.year:
				rows.remove_at(i)
		rows.append(row)


## Career totals for a player: {"seasons", "gp", "points", "rebounds", "assists", ...}.
func career_totals(player_id: int) -> Dictionary:
	var t := {"seasons": 0, "gp": 0, "seconds": 0, "points": 0, "rebounds": 0, "ast": 0, "stl": 0, "blk": 0}
	for row in careers.get(player_id, []):
		t["seasons"] += 1
		t["gp"] += row[2]
		t["seconds"] += row[3]
		t["points"] += row[4]
		t["rebounds"] += row[11] + row[12]
		t["ast"] += row[13]
		t["stl"] += row[14]
		t["blk"] += row[15]
	return t


## Player ids with the highest career total of a stat ("points", "rebounds", "ast", "stl", "blk", "gp").
func career_leaders(stat: String, count: int = 10) -> Array[int]:
	var totals := {}
	for pid in careers:
		totals[pid] = career_totals(pid)[stat]
	var ids: Array[int] = []
	for pid in totals:
		ids.append(int(pid))
	ids.sort_custom(func(a: int, b: int): return totals[a] > totals[b] if totals[a] != totals[b] else a < b)
	return ids.slice(0, count)


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
			for e in team_rules.cap.validate_contract(c, season):
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
		"careers": _careers_dict(),
		"injury_history": _injury_history_dict(),
		"pick_owners": pick_owners.duplicate(),
		"finances": _dicts_of(finances),
		"transactions": transactions.duplicate(true),
		"rating_history": _rating_history_dict(),
	}


func _rating_history_dict() -> Dictionary:
	var out := {}
	for pid in rating_history:
		out[str(pid)] = (rating_history[pid] as Array).duplicate(true)
	return out


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
	var raw_picks = data.get("pick_owners", {})
	if raw_picks is Dictionary:
		for key in raw_picks:
			w.pick_owners[str(key)] = int(raw_picks[key])
	var raw_careers: Dictionary = data.get("careers", {})
	for key in raw_careers:
		var rows: Array = []
		for row in raw_careers[key]:
			var ints: Array = []
			for v in row:
				ints.append(int(v))
			rows.append(ints)
		w.careers[int(key)] = rows
	var raw_injuries = data.get("injury_history", {})   # added later: missing = empty
	if raw_injuries is Dictionary:
		for key in raw_injuries:
			var rows: Array = []
			for row in raw_injuries[key]:
				rows.append({"year": int(row.get("year", 0)), "injury": str(row.get("injury", "")), "games": int(row.get("games", 0)), "severe": bool(row.get("severe", false))})
			w.injury_history[int(key)] = rows
	for item in data.get("news", []):
		var restored := {"date": str(item["date"]), "kind": str(item["kind"]), "text": str(item["text"]), "team": int(item["team"])}
		if item.has("txn"):
			restored["txn"] = int(item["txn"])
		w.news.append(restored)
	for t in data.get("transactions", []):   # added in data version 5: missing = none
		var players: Array = []
		for pid in t.get("players", []):
			players.append(int(pid))
		w.transactions.append({"id": int(t.get("id", 0)), "date": str(t.get("date", "")), "kind": str(t.get("kind", "")), "text": str(t.get("text", "")),
			"team": int(t.get("team", 0)), "other": int(t.get("other", 0)), "players": players})
	var raw_ratings = data.get("rating_history", {})
	if raw_ratings is Dictionary:
		for key in raw_ratings:
			var rows: Array = []
			for row in raw_ratings[key]:
				rows.append([int(row[0]), int(row[1]), int(row[2])])
			w.rating_history[int(key)] = rows
	for d in data.get("businesses", []):
		_report(w.businesses.add(FcTeamBusiness.from_dict(d)), "team business", errors)
	for d in data.get("finances", []):
		_report(w.finances.add(FcFinanceRecord.from_dict(d)), "finance record", errors)
	return w


func _injury_history_dict() -> Dictionary:
	var out := {}
	for pid in injury_history:
		out[str(pid)] = injury_history[pid].duplicate(true)
	return out


func _careers_dict() -> Dictionary:
	var out := {}
	for pid in careers:
		out[str(pid)] = careers[pid].duplicate(true)
	return out


static func _report(err: Error, label: String, errors: Array[String]) -> void:
	if err != OK:
		errors.append("could not load %s (error %d)" % [label, err])


static func _dicts_of(repo: FcRepository) -> Array:
	var out: Array = []
	for e in repo.all():
		out.append(e.to_dict())
	return out
