class_name FcScheduleBuilder
extends RefCounted
## Turns the matchup plan (who plays whom how often, home or away) into a
## calendar: which game is played on which day.
##
## Rules it follows:
##  - A team plays at most one game a day.
##  - Games are spread evenly: every team is "on pace" for its total through
##    the season. A team that is behind pace is scheduled first; one that is
##    ahead rests.
##  - Back-to-back days are avoided unless a team is well behind pace.
##  - Long home or away stands are discouraged.
##  - The season lasts about 2 days per game played by each team (an 80-game
##    season is about 160 days); any games left over are added at the end.
## Reproducible: same league, rules and rng seed = same calendar.

const DAYS_PER_GAME := 2.0
const TRAVEL_STREAK_LIMIT := 3


## Returns the games ordered by day. Each game has day, home_id and away_id set.
static func build(league: FcLeague, season: FcSeasonRules, rng: FcRng) -> Array[FcScheduledGame]:
	var plan := FcMatchupPlanner.plan(league, season)
	var games: Array[FcScheduledGame] = []
	for pair in plan.pairs:
		for i in int(pair["games"]):
			var a_hosts: bool = i < int(pair["a_home"])
			games.append(FcScheduledGame.new(0, pair["a"] if a_hosts else pair["b"], pair["b"] if a_hosts else pair["a"]))
	_shuffle(games, rng)

	var team_ids: Array[int] = league.all_team_ids()
	var per_team := season.games_per_team(league)
	var total_days := maxi(1, ceili(per_team * DAYS_PER_GAME))
	var remaining := {}     # team id -> Array of indexes into `games` not yet scheduled
	var played := {}        # team id -> games scheduled so far
	var last_day := {}      # team id -> last day it played
	var home_run := {}      # team id -> consecutive home (+) or away (-) games
	var expected := {}      # team id -> total games it must play
	for t in team_ids:
		remaining[t] = []
		played[t] = 0
		last_day[t] = -10
		home_run[t] = 0
		expected[t] = 0
	for i in games.size():
		remaining[games[i].home_id].append(i)
		remaining[games[i].away_id].append(i)
		expected[games[i].home_id] += 1
		expected[games[i].away_id] += 1
	var done: Array[bool] = []
	done.resize(games.size())
	done.fill(false)

	var scheduled: Array[FcScheduledGame] = []
	var day := 0
	var guard := total_days * 3 + 50
	while scheduled.size() < games.size() and day < guard:
		var behind := {}
		for t in team_ids:
			var pace := float(expected[t]) * minf(1.0, float(day + 1) / total_days)
			behind[t] = pace - played[t]
		var order: Array[int] = team_ids.duplicate()
		order.sort_custom(func(a, b):
			var da: float = behind[a] + FcScheduleBuilder.rng_noise(a, day)
			var db: float = behind[b] + FcScheduleBuilder.rng_noise(b, day)
			return da > db)
		var used := {}
		for t in order:
			if used.has(t) or played[t] >= expected[t]:
				continue
			# a team well ahead of pace rests today (unless the calendar has run out)
			if behind[t] < -0.2 and day < total_days:
				continue
			if last_day[t] == day - 1 and behind[t] < 1.0 and day < total_days:
				continue
			var best_index := -1
			var best_score := -INF
			for i in remaining[t]:
				if done[i]:
					continue
				var g := games[i]
				var other := g.away_id if g.home_id == t else g.home_id
				if used.has(other):
					continue
				if last_day[other] == day - 1 and behind[other] < 1.0 and day < total_days:
					continue
				var score: float = behind[other] + rng.next_float() * 0.6
				# discourage long home/away stands for both teams
				score -= _streak_penalty(home_run[g.home_id], true) + _streak_penalty(home_run[g.away_id], false)
				if score > best_score:
					best_score = score
					best_index = i
			if best_index < 0:
				continue
			var chosen := games[best_index]
			chosen.day = day
			done[best_index] = true
			used[chosen.home_id] = true
			used[chosen.away_id] = true
			for team in [chosen.home_id, chosen.away_id]:
				played[team] += 1
				last_day[team] = day
			home_run[chosen.home_id] = maxi(0, home_run[chosen.home_id]) + 1
			home_run[chosen.away_id] = mini(0, home_run[chosen.away_id]) - 1
			scheduled.append(chosen)
		day += 1
	# Anything still unscheduled (very unusual) goes on following days one by one.
	for i in games.size():
		if not done[i]:
			games[i].day = day
			scheduled.append(games[i])
			day += 1
	scheduled.sort_custom(func(a: FcScheduledGame, b: FcScheduledGame): return a.day < b.day)
	return scheduled


## Number of days a schedule spans (last day + 1).
static func length_in_days(games: Array[FcScheduledGame]) -> int:
	var last := 0
	for g in games:
		last = maxi(last, g.day)
	return last + 1


static func rng_noise(team_id: int, day: int) -> float:
	# deterministic pseudo-noise so the sort order is stable and varied day to day
	return float(absi(hash("%d:%d" % [team_id, day])) % 1000) / 4000.0


static func _streak_penalty(run: int, hosting: bool) -> float:
	var same_direction := run if hosting else -run
	if same_direction >= TRAVEL_STREAK_LIMIT:
		return 1.5 + (same_direction - TRAVEL_STREAK_LIMIT) * 0.5
	return 0.0


static func _shuffle(games: Array[FcScheduledGame], rng: FcRng) -> void:
	for i in range(games.size() - 1, 0, -1):
		var j := rng.range_int(0, i)
		var tmp := games[i]
		games[i] = games[j]
		games[j] = tmp
