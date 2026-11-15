class_name FcPlayoffBuilder
extends RefCounted
## Builds the playoff bracket from the final regular-season standings and the
## league's playoff rules (qualification, bracket type, team count, series
## lengths). See FcPlayoffRules for the meaning of the options.
##
## Seeding: with "division_leaders", every division winner is seeded above all
## wildcard teams (ordered by record among themselves); with "seeding", teams
## are simply ordered by record. Brackets are fixed (1 plays the last seed, 2
## the second to last...), with byes for the top seeds when the bracket is not
## a power of two. Home court goes to the team with the better record.


static func build(league: FcLeague, standings: FcStandings, rules: FcPlayoffRules) -> FcPlayoffs:
	var po := FcPlayoffs.new()
	po.rounds = rules.round_count(league)
	var league_rank := standings.league_ranking()
	var rank_of := {}
	for i in league_rank.size():
		rank_of[league_rank[i]] = i + 1
	var leaders: Dictionary = standings.division_leaders() if rules.qualification == "division_leaders" else {}
	var leader_ids := {}
	for d in leaders:
		leader_ids[leaders[d]] = true

	var counter := [0]
	if rules.bracket == "conference" and league.conferences.size() > 1:
		var per_bracket := rules.bracket_size(league)
		var champions_from: Array[int] = []   # series numbers of each conference's final
		for c in league.conferences.size():
			var pool: Array[int] = standings.conference_ranking(league.conferences[c])
			var seeded := _seed(pool, leader_ids, per_bracket)
			_add_qualifiers(po, seeded, leader_ids, rank_of, c)
			var final_number := _build_bracket(po, seeded, rank_of, rules, "conference", c, 0, counter)
			champions_from.append(final_number)
		# stage 2: conference champions meet (seeded by regular-season record)
		var round_offset := _ceil_log2(per_bracket)
		_build_finals(po, champions_from, rules, round_offset, counter)
	else:
		var pool: Array[int] = league_rank.duplicate()
		var seeded := _seed(pool, leader_ids, rules.team_count)
		_add_qualifiers(po, seeded, leader_ids, rank_of, -1)
		_build_bracket(po, seeded, rank_of, rules, "league", -1, 0, counter)
	_resolve_byes(po)
	return po


## The qualifying teams in seed order: division leaders first (best record
## first), then the best remaining records, up to `count`.
static func _seed(ordered: Array[int], leader_ids: Dictionary, count: int) -> Array[int]:
	var seeded: Array[int] = []
	for t in ordered:
		if leader_ids.has(t):
			seeded.append(t)
	for t in ordered:
		if seeded.size() >= count:
			break
		if not leader_ids.has(t):
			seeded.append(t)
	return seeded.slice(0, count)


static func _add_qualifiers(po: FcPlayoffs, seeded: Array[int], leader_ids: Dictionary, rank_of: Dictionary, bracket: int) -> void:
	for i in seeded.size():
		po.qualifiers.append({"team": seeded[i], "bracket": bracket, "seed": i + 1, "leader": leader_ids.has(seeded[i]), "rank": rank_of[seeded[i]]})


## Creates all series of one bracket; returns the number of its final series.
static func _build_bracket(po: FcPlayoffs, seeded: Array[int], rank_of: Dictionary, rules: FcPlayoffRules,
		stage: String, bracket: int, round_offset: int, counter: Array) -> int:
	var size := seeded.size()
	var padded := _next_power_of_two(size)
	var order := _bracket_order(padded)
	var previous: Array[FcPlayoffSeries] = []
	var round_number := 1 + round_offset
	var current: Array[FcPlayoffSeries] = []
	for i in range(0, padded, 2):
		var s := FcPlayoffSeries.new()
		counter[0] += 1
		s.number = counter[0]
		s.round = round_number
		s.stage = stage
		s.bracket = bracket
		s.best_of = _series_length(rules, round_number)
		var seed_a: int = order[i]
		var seed_b: int = order[i + 1]
		if seed_a <= size:
			s.seed_a = seed_a
			s.team_a = seeded[seed_a - 1]
			s.rank_a = rank_of[s.team_a]
		if seed_b <= size:
			s.seed_b = seed_b
			s.team_b = seeded[seed_b - 1]
			s.rank_b = rank_of[s.team_b]
		s.is_bye = s.team_a == 0 or s.team_b == 0
		po.series.append(s)
		current.append(s)
	while current.size() > 1:
		previous = current
		current = []
		round_number += 1
		for i in range(0, previous.size(), 2):
			var s := FcPlayoffSeries.new()
			counter[0] += 1
			s.number = counter[0]
			s.round = round_number
			s.stage = stage
			s.bracket = bracket
			s.best_of = _series_length(rules, round_number)
			s.source_a = previous[i].number
			s.source_b = previous[i + 1].number
			po.series.append(s)
			current.append(s)
	return current[0].number


## The final stage: conference champions, seeded by regular-season rank.
static func _build_finals(po: FcPlayoffs, champion_sources: Array[int], rules: FcPlayoffRules, round_offset: int, counter: Array) -> void:
	# Seeds are decided when the champions are known; so build a bracket whose first-round
	# series are fed by the conference finals, in a fixed order, and pair by position.
	var current: Array[int] = champion_sources.duplicate()
	var round_number := round_offset
	while current.size() > 1:
		round_number += 1
		var next: Array[int] = []
		var i := 0
		while i < current.size():
			if i + 1 >= current.size():
				next.append(current[i])   # odd one out advances (bye) to the next finals round
				i += 1
				continue
			var s := FcPlayoffSeries.new()
			counter[0] += 1
			s.number = counter[0]
			s.round = round_number
			s.stage = "finals"
			s.best_of = _series_length(rules, round_number)
			s.source_a = current[i]
			s.source_b = current[i + 1]
			po.series.append(s)
			next.append(s.number)
			i += 2
		current = next


## Series with a bye advance immediately so later rounds see their team.
static func _resolve_byes(po: FcPlayoffs) -> void:
	for s in po.series:
		if s.is_bye and not s.is_complete():
			s.winner_id = s.team_a if s.team_a > 0 else s.team_b
	# propagate any completed series' winners into the series they feed
	var changed := true
	while changed:
		changed = false
		for s in po.series:
			if s.source_a > 0 and s.team_a == 0:
				var src := po.get_series(s.source_a)
				if src.is_complete():
					s.team_a = src.winner_id
					s.rank_a = _rank_for(po, src.winner_id)
					changed = true
			if s.source_b > 0 and s.team_b == 0:
				var src2 := po.get_series(s.source_b)
				if src2.is_complete():
					s.team_b = src2.winner_id
					s.rank_b = _rank_for(po, src2.winner_id)
					changed = true


static func _rank_for(po: FcPlayoffs, team_id: int) -> int:
	for q in po.qualifiers:
		if q["team"] == team_id:
			return q["rank"]
	return 999


## Pushes a finished series' winner into the series it feeds. Call after every series completes.
static func advance(po: FcPlayoffs) -> void:
	_resolve_byes(po)


static func _series_length(rules: FcPlayoffRules, round_number: int) -> int:
	var lengths := rules.series_lengths
	return lengths[mini(round_number, lengths.size()) - 1] if not lengths.is_empty() else 7


## Standard bracket positions: [1, 8, 4, 5, 2, 7, 3, 6] for 8.
static func _bracket_order(size: int) -> Array[int]:
	var order: Array[int] = [1]
	var n := 1
	while n < size:
		n *= 2
		var next: Array[int] = []
		for s in order:
			next.append(s)
			next.append(n + 1 - s)
		order = next
	return order


static func _next_power_of_two(n: int) -> int:
	var v := 1
	while v < n:
		v *= 2
	return v


static func _ceil_log2(n: int) -> int:
	var rounds := 0
	var v := 1
	while v < n:
		v *= 2
		rounds += 1
	return rounds
