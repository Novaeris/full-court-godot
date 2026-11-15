class_name FcMatchupPlanner
extends RefCounted
## Turns a league structure plus season rules into a fair list of matchups:
## how many times each pair meets and who hosts.
##
## FAIRNESS: when two teams meet an even number of times they split the home
## games equally. When they meet an odd number of times (e.g. once), one team
## has the extra home game. Those extra home games are assigned by walking
## closed trails through the "odd pairs" graph and orienting each edge along
## the walk, which gives every team (almost) as many extra home as extra away
## games. Result: every team's home and away totals differ by at most 1.
## (Odd-degree teams are paired through a dummy node so every walk closes.)
##
## This proves a season of these rules CAN be played fairly. Building the
## actual calendar (dates, travel, back-to-backs) is a later system.

const DUMMY := 0


static func plan(league: FcLeague, season: FcSeasonRules) -> FcMatchupPlan:
	var result := FcMatchupPlan.new()
	var team_ids: Array[int] = league.all_team_ids()
	team_ids.sort()

	# 1. games per pair, and the graph of odd-game pairs
	var pair_games: Array[Dictionary] = []
	var odd_a: Array[int] = []
	var odd_b: Array[int] = []
	for i in team_ids.size():
		for j in range(i + 1, team_ids.size()):
			var a := team_ids[i]
			var b := team_ids[j]
			var games := _games_between(league, season, a, b)
			if games <= 0:
				continue
			pair_games.append({"a": a, "b": b, "games": games})
			if games % 2 == 1:
				odd_a.append(a)
				odd_b.append(b)

	# 2. connect odd-degree teams to a dummy node so all degrees are even
	var degree := {}
	for k in odd_a.size():
		degree[odd_a[k]] = int(degree.get(odd_a[k], 0)) + 1
		degree[odd_b[k]] = int(degree.get(odd_b[k], 0)) + 1
	var from_ids: Array[int] = odd_a.duplicate()
	var to_ids: Array[int] = odd_b.duplicate()
	var real_edge_count := odd_a.size()
	for tid in team_ids:
		if int(degree.get(tid, 0)) % 2 == 1:
			from_ids.append(tid)
			to_ids.append(DUMMY)

	# 3. orient edges by closed walks: the team we leave hosts the extra game
	var host_of_edge := _orient(from_ids, to_ids)

	# 4. build the plan
	var extra_host := {}  # "a:b" -> team id hosting the extra game
	for e in real_edge_count:
		extra_host["%d:%d" % [odd_a[e], odd_b[e]]] = host_of_edge[e]
	for pg in pair_games:
		var games: int = pg["games"]
		var half := floori(games / 2.0)
		var a_home := half
		var b_home := half
		if games % 2 == 1:
			if extra_host["%d:%d" % [pg["a"], pg["b"]]] == pg["a"]:
				a_home += 1
			else:
				b_home += 1
		result._add(pg["a"], pg["b"], games, a_home, b_home)
	return result


## Games these two teams play each other under the rules.
static func _games_between(league: FcLeague, season: FcSeasonRules, a: int, b: int) -> int:
	var div_a := league.division_of_team(a)
	var div_b := league.division_of_team(b)
	if div_a == null or div_b == null:
		return 0
	if div_a == div_b:
		return season.games_per_division_opponent
	if league.conference_of_team(a) == league.conference_of_team(b):
		return season.games_per_conference_opponent
	return season.games_per_other_conference_opponent


## Orients every edge (from[i], to[i]) so that each vertex has equal in- and
## out-degree. Returns, per edge, the vertex it is directed FROM.
## Requires every vertex to have even degree.
static func _orient(from_ids: Array[int], to_ids: Array[int]) -> Array[int]:
	var edge_count := from_ids.size()
	var adjacency := {}
	for e in edge_count:
		for v in [from_ids[e], to_ids[e]]:
			if not adjacency.has(v):
				adjacency[v] = []
			adjacency[v].append(e)
	var used: Array[bool] = []
	used.resize(edge_count)
	used.fill(false)
	var cursor := {}
	for v in adjacency:
		cursor[v] = 0
	var directed_from: Array[int] = []
	directed_from.resize(edge_count)

	var vertices: Array = adjacency.keys()
	vertices.sort()
	for start in vertices:
		while true:
			var v: int = start
			var walked := false
			while true:
				var next_edge := _next_unused(adjacency[v], cursor, v, used)
				if next_edge < 0:
					break
				walked = true
				used[next_edge] = true
				directed_from[next_edge] = v
				v = to_ids[next_edge] if from_ids[next_edge] == v else from_ids[next_edge]
			if not walked:
				break
	return directed_from


static func _next_unused(edges: Array, cursor: Dictionary, vertex: int, used: Array[bool]) -> int:
	var i: int = cursor[vertex]
	while i < edges.size() and used[edges[i]]:
		i += 1
	cursor[vertex] = i
	return edges[i] if i < edges.size() else -1
