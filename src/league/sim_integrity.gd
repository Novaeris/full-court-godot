class_name FcSimIntegrity
extends RefCounted
## Checks that a game state is consistent with the rules of time (D-077 B). Pure and read-only: it returns a list of problems in plain
## words (empty when all is well). Run by the tests after every kind of advancement, after loading in debug builds, and by the Creator
## Studio save inspector. What it checks, for every season still held in detail:
##   - every game has a stable id, and no id appears twice (across all seasons);
##   - regular-season games before the season's cursor are played, games after it are not (no game skipped, none played early);
##   - a played game has a winner (no ties) and a compact result line whose top scorers belong to the two teams;
##   - every day log entry names only played games of that day, and its standings checksum matches the standings rebuilt from the results
##     up to that day (so a stored report can never disagree with the results);
##   - no transaction id appears twice and every transaction is dated;
##   - every stored box score adds up: the players' points are the team's score.


static func check(state: FcGameState) -> Array[String]:
	var out: Array[String] = []
	var w := state.world
	var seen_ids := {}
	for season in w.seasons.all():
		if season.archived:
			continue
		_check_season(w, season, seen_ids, out)
	var txn_ids := {}
	for t in w.transactions:
		var id := int(t.get("id", 0))
		if id <= 0:
			out.append("a transaction has no id: %s" % str(t.get("text", "")))
		elif txn_ids.has(id):
			out.append("transaction %d is recorded twice" % id)
		txn_ids[id] = true
		if FcDate.from_iso(str(t.get("date", ""))) == null:
			out.append("transaction %d has no valid date" % id)
	return out


static func _check_season(w: FcWorld, season: FcSeason, seen_ids: Dictionary, out: Array[String]) -> void:
	var label := "season %d" % season.year
	var by_id := {}
	for g in season.games:
		if g.id <= 0:
			out.append("%s: a game on day %d has no id" % [label, g.day])
			continue
		if seen_ids.has(g.id):
			out.append("%s: game id %d is used twice" % [label, g.id])
		seen_ids[g.id] = true
		by_id[g.id] = g
		if g.series == 0 and season.status == FcSeason.Status.REGULAR:
			if g.day < season.next_day and not g.played:
				out.append("%s: game %d (day %d) was skipped" % [label, g.id, g.day])
			if g.day >= season.next_day and g.played:
				out.append("%s: game %d (day %d) was played before its day" % [label, g.id, g.day])
		if g.played:
			if g.home_score == g.away_score:
				out.append("%s: game %d ended in a tie" % [label, g.id])
			for row in g.line.get("top", []):
				if row.size() < 5:
					out.append("%s: game %d has a short result line" % [label, g.id])
				elif int(row[4]) != g.home_id and int(row[4]) != g.away_id:
					out.append("%s: game %d lists a performer of another team" % [label, g.id])
	var league: FcLeague = w.leagues.get_by_id(season.league_id)
	for day in season.day_log:
		var entry: Dictionary = season.day_log[day]
		for gid in entry.get("g", []):
			var g: FcScheduledGame = by_id.get(int(gid))
			if g == null:
				out.append("%s: the day %d log names an unknown game %d" % [label, int(day), int(gid)])
			elif not g.played or g.day != int(day):
				out.append("%s: the day %d log names game %d, which was not played that day" % [label, int(day), int(gid)])
		if entry.has("c") and league != null:
			var upto: Array[FcScheduledGame] = []
			for g in season.games:
				if g.played and g.day <= int(day):
					upto.append(g)
			var expected := standings_checksum(FcStandings.compute(league, upto))
			if int(entry["c"]) != expected:
				out.append("%s: the day %d log disagrees with the results (standings checksum)" % [label, int(day)])
	for entry in season.recent_boxes:
		var box := FcBoxScore.from_dict(entry["box"])
		var sums := [0, 0]
		for p in box.players:
			sums[0 if p.team_id == box.team_ids[0] else 1] += p.points
		if sums[0] != box.scores[0] or sums[1] != box.scores[1]:
			out.append("%s: a stored box score does not add up (%d-%d vs %d-%d)" % [label, sums[0], sums[1], box.scores[0], box.scores[1]])


## A number that changes when any team's wins or losses change: the standings fingerprint kept in each day's log.
static func standings_checksum(standings: FcStandings) -> int:
	var keys := standings.records.keys()
	keys.sort()
	var parts: Array = []
	for t in keys:
		parts.append("%d:%d:%d" % [int(t), int(standings.records[t]["w"]), int(standings.records[t]["l"])])
	return absi(hash(",".join(parts)))
