class_name FcGameSimulator
extends RefCounted
## Simulates one basketball game possession by possession and returns an
## FcBoxScore. Headless: no scenes, no UI. All randomness comes from the FcRng
## passed in, so the same teams + seed always give the identical game.
##
## HOW A POSSESSION WORKS
##  1. A non-shooting foul may happen (free throws once the team is in the bonus).
##  2. The ball handler may turn it over (steals credited).
##  3. A shooter is chosen by scoring ability and usage; he picks a three, a
##     mid-range shot or a drive/rim attempt from his own tendencies and his
##     coach's style.
##  4. The shot can be blocked, can draw a shooting foul, and goes in with a
##     probability built from the shooter's skill, the defenders' ratings,
##     whether it was assisted, fatigue, home court, the coaches and his
##     hot/cold form that night.
##  5. A miss goes to a rebound contest; an offensive rebound keeps the possession.
## Between possessions each coach may substitute for fatigue, foul trouble,
## close finishes and blowouts.
##
## EVERY balance number is in data/simulation/tuning.json; player composite
## ratings are in data/simulation/ratings.json.
## NOT included: timeouts, technical fouls, the shot clock (no violations), jump balls and individual matchups (defense uses lineup
## averages). Injuries and intentional fouling ARE simulated (EV_INJURY, FOUL_INTENTIONAL in game_event_log.gd).

const END := 0
const CONTINUE := 1
const THREE := 0
const MID := 1
const RIM := 2

var _t: Dictionary
var _rng: FcRng
var _teams: Array[FcGameTeam] = []
var _court: Array = [[], []]
var _score: Array[int] = [0, 0]
var _period_points: Array = [[], []]
var _team_fouls: Array[int] = [0, 0]
var _clock: float = 0.0
var _period: int = 1
## This game's shared pace shift in seconds per possession (a fast or slow game for BOTH teams).
var _game_pace_shift: float = 0.0
## Points each side has scored above (+) or below (-) what its shot odds expected so far.
var _luck: Array[float] = [0.0, 0.0]
var _injuries: Array = []
## Optional play-by-play recorder. When set, the game is written down as it is played; it never changes the game
## (the recorder only reads state and never uses the random generator).
var recorder: FcGameEventLog = null


## `tuning` overrides the shipped values (used by tests and tools). `era`
## picks a playing style from data/simulation/eras.json ("" = the default era).
func _init(tuning: Dictionary = {}, era: String = "") -> void:
	_t = load_tuning(era)
	for key in tuning:
		_t[key] = tuning[key]


static func for_era(era: String) -> FcGameSimulator:
	return FcGameSimulator.new({}, era)


static func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = FcChecks.parse_json(file.get_as_text())
	return parsed if parsed is Dictionary else {}


## Base tuning plus the overlay of the chosen era (see eras.json).
static func load_tuning(era: String = "") -> Dictionary:
	var tuning := _load_json("res://data/simulation/tuning.json")
	var eras := load_eras()
	var key := era if era != "" else str(eras.get("default", ""))
	var overlay: Dictionary = eras.get("eras", {}).get(key, {}).get("tuning", {})
	for k in overlay:
		tuning[k] = overlay[k]
	return tuning


static func load_eras() -> Dictionary:
	return _load_json("res://data/simulation/eras.json")


## Era keys, e.g. ["early_2010s", "mid_2010s", "late_2010s"].
static func era_keys() -> Array[String]:
	var out: Array[String] = []
	for k in load_eras().get("eras", {}):
		out.append(str(k))
	return out


## Plays the whole game. Side 0 is `home`, side 1 is `away`.
func simulate(home: FcGameTeam, away: FcGameTeam, rng: FcRng) -> FcBoxScore:
	_rng = rng
	_teams = [home, away]
	_score = [0, 0]
	_period_points = [[], []]
	_team_fouls = [0, 0]
	_luck = [0.0, 0.0]
	_injuries = []
	if recorder != null:
		recorder.clear()
	for side in 2:
		_court[side] = []
		for p in _teams[side].players:
			p.energy = 100.0
			p.fouls = 0
			p.on_court = false
			p.injured = false
			p.injury_games = 0
			p.injury_name = ""
			p.seconds_f = 0.0
			p.stats = FcPlayerGameStats.new()
			p.stats.player_id = p.id
			p.stats.team_id = _teams[side].team_id
			p.stats.name = p.name
			p.stats.position = p.position
			p.form = _rng.gaussian(0.0, float(_t["form_sd"])) * (1.0 - p.consistency / 200.0)
		for p in _select_lineup(_teams[side]):
			_put_on_court(side, p)
			p.stats.started = true
			_log(FcGameEventLog.EV_STARTER, side, p.id)

	_game_pace_shift = _rng.gaussian(0.0, float(_t["game_pace_sd"]))
	var possession_side := _rng.range_int(0, 1)  # who wins the opening tip
	var quarters := int(_t["quarters"])
	_period = 1
	while _period <= 12:
		_clock = float(_t["quarter_seconds"]) if _period <= quarters else float(_t["overtime_seconds"])
		_team_fouls = [0, 0]
		_period_points[0].append(0)
		_period_points[1].append(0)
		if _period > 1:
			_recover_between_periods()
		_log(FcGameEventLog.EV_PERIOD_START, 0, 0, 0, _period)
		var side := (possession_side + _period - 1) % 2
		while _clock > 0.0:
			_play_possession(side)
			side = 1 - side
			_substitutions(0)
			_substitutions(1)
		_log(FcGameEventLog.EV_PERIOD_END, 0, 0, 0, _period)
		if _period >= quarters and _score[0] != _score[1]:
			break
		_period += 1
	_log(FcGameEventLog.EV_GAME_END, 0, 0)
	return _finish()


# --- possession ----------------------------------------------------------

func _play_possession(o: int) -> void:
	var d := 1 - o
	var first := true
	while _clock > 0.0:
		var dur := _sample_duration() if first else clampf(_rng.gaussian(float(_t["putback_seconds"]), 2.0), 2.0, 10.0)
		if first and _fouling_to_stop_the_clock(o, d):
			dur = minf(float(_t["intentional_foul_seconds"]), _clock)
			_use_time(dur)
			_commit_foul(d, _pick_fouler(d), FcGameEventLog.FOUL_INTENTIONAL)
			var outcome := END
			if _team_fouls[d] >= int(_t["bonus_fouls"]):
				outcome = _free_throws(o, d, _pick_scorer(o), 2)
			first = false
			if outcome == END:
				return
			continue
		if first and _chasing_a_tie(o):
			dur = _clock   # a team that can still tie holds the ball for the last shot
		dur = minf(dur, _clock)
		_use_time(dur)
		var result := _action(o, d, first)
		first = false
		if result == END:
			return


## One attempt at scoring. Returns END when the possession is over, CONTINUE
## when the offense keeps the ball (offensive rebound, non-bonus foul).
func _action(o: int, d: int, check_turnover: bool) -> int:
	# 1. non-shooting foul
	var aggression_d: float = _teams[d].tactics["aggression"]
	var p_foul := float(_t["nonshooting_foul"]) + (aggression_d - 50.0) * float(_t["foul_aggression_slope"])
	if _rng.chance(p_foul):
		_commit_foul(d, _pick_fouler(d), FcGameEventLog.FOUL_PERSONAL)
		if _team_fouls[d] >= int(_t["bonus_fouls"]):
			return _free_throws(o, d, _pick_scorer(o), 2)
		return CONTINUE

	# 2. turnover
	if check_turnover:
		var steal_d := _avg(d, "steal")
		var secure_o := _avg(o, "ball_security")
		var p_tov := float(_t["turnover_base"]) + (steal_d - secure_o) * float(_t["turnover_slope"]) \
			+ (aggression_d - 50.0) * float(_t["turnover_aggression_slope"]) - (1.0 if o == 0 else 0.0) * 0.004
		if _rng.chance(clampf(p_tov, 0.04, 0.3)):
			var handler := _pick_weighted(_court[o], _weights(o, "ball_security", 2.0, true))
			handler.stats.tov += 1
			var thief_id := 0
			if _rng.chance(float(_t["steal_share"])):
				var thief := _pick_weighted(_court[d], _weights(d, "steal", 3.0, true))
				thief.stats.stl += 1
				thief_id = thief.id
			_log(FcGameEventLog.EV_TURNOVER, o, handler.id, thief_id)
			return END

	# 3. shot
	var shooter := _pick_scorer(o)
	var kind := _pick_shot_type(shooter, o)
	if _chasing_a_tie(o) and _clock <= 0.5:
		kind = _tie_shot_kind(o, kind)
	var passer: FcSimPlayer = null
	var assisted := _rng.chance(_assist_chance(kind, o))
	if assisted:
		passer = _pick_passer(o, shooter)
	var p_make := _make_probability(kind, shooter, o, d, assisted)
	var shot_points := 3.0 if kind == THREE else 2.0

	# 4a. block
	if kind != THREE:
		var base_block := float(_t["block_rim"]) if kind == RIM else float(_t["block_mid"])
		var p_block: float = base_block * pow(maxf(_avg(d, "block"), 5.0) / 50.0, 1.4) * (1.15 - shooter.ratings["finishing"] / 200.0)
		if _rng.chance(clampf(p_block, 0.0, 0.4)):
			shooter.stats.fga += 1
			var blocker := _pick_weighted(_court[d], _weights(d, "block", 3.0, true))
			blocker.stats.blk += 1
			_log(FcGameEventLog.EV_SHOT_BLOCKED, o, shooter.id, blocker.id, kind)
			return _rebound(o, d)

	# 4b. shooting foul
	var base_foul := float(_t["foul_three"])
	if kind == RIM:
		base_foul = float(_t["foul_rim"])
	elif kind == MID:
		base_foul = float(_t["foul_mid"])
	var p_sf := base_foul * (0.6 + 0.8 * (shooter.tend_drive / 100.0)) * (0.7 + 0.6 * _avg_foul_tendency(d) / 100.0) \
		* (1.0 + (aggression_d - 50.0) / 250.0)
	var fouled := _rng.chance(clampf(p_sf, 0.0, 0.5))
	var made := _rng.chance(p_make)
	_luck[o] += (shot_points if made else 0.0) - p_make * shot_points
	if fouled:
		_commit_foul(d, _pick_fouler(d), FcGameEventLog.FOUL_SHOOTING)
		if made:
			_record_field_goal(shooter, kind, passer, o)
			return _free_throws(o, d, shooter, 1)
		return _free_throws(o, d, shooter, 3 if kind == THREE else 2)

	# 4c. normal attempt
	shooter.stats.fga += 1
	if kind == THREE:
		shooter.stats.tpa += 1
	if made:
		_record_field_goal(shooter, kind, passer, o, false)
		return END
	_log(FcGameEventLog.EV_SHOT_MISSED, o, shooter.id, 0, kind)
	return _rebound(o, d)


func _record_field_goal(shooter: FcSimPlayer, kind: int, passer: FcSimPlayer, o: int, counts_attempt: bool = true) -> void:
	if counts_attempt:
		shooter.stats.fga += 1
		if kind == THREE:
			shooter.stats.tpa += 1
	shooter.stats.fgm += 1
	var pts := 3 if kind == THREE else 2
	if kind == THREE:
		shooter.stats.tpm += 1
	shooter.stats.points += pts
	if passer != null:
		passer.stats.ast += 1
	_log(FcGameEventLog.EV_SHOT_MADE, o, shooter.id, passer.id if passer != null else 0, kind)
	_add_points(o, pts)


## Free throws; returns END (made last / defense rebound) or CONTINUE (offensive rebound).
func _free_throws(o: int, d: int, shooter: FcSimPlayer, count: int) -> int:
	var made_last := false
	for i in count:
		var p: float = float(_t["ft_base"]) + float(_t["ft_slope"]) * shooter.ratings["free_throw"] \
			+ shooter.form * 0.5 - (1.0 - shooter.freshness()) * 0.03
		shooter.stats.fta += 1
		made_last = _rng.chance(clampf(p, 0.3, 0.97))
		_log(FcGameEventLog.EV_FREE_THROW, o, shooter.id, (i + 1) * 10 + count, 1 if made_last else 0)
		if made_last:
			shooter.stats.ftm += 1
			shooter.stats.points += 1
			_add_points(o, 1)
	if made_last:
		return END
	return _rebound(o, d)


func _rebound(o: int, d: int) -> int:
	if _rng.chance(float(_t["team_rebound"])):
		var team_ends := _rng.chance(0.65)
		_log(FcGameEventLog.EV_REBOUND, d if team_ends else o, 0, 0, 0 if team_ends else 1)
		return END if team_ends else CONTINUE
	var off_w := _weights(o, "rebound", float(_t["rebound_exponent"]), true)
	for i in off_w.size():
		off_w[i] *= 0.6 + 0.8 * _court[o][i].tend_oreb / 100.0
	var def_w := _weights(d, "rebound", float(_t["rebound_exponent"]), true)
	var off_total := 0.0
	for w in off_w:
		off_total += w
	var def_total := 0.0
	for w in def_w:
		def_total += w
	var p_off := float(_t["offensive_rebound_factor"]) * off_total / (float(_t["offensive_rebound_factor"]) * off_total + def_total)
	if _rng.chance(p_off):
		var off_rebounder := _pick_weighted(_court[o], off_w)
		off_rebounder.stats.oreb += 1
		_log(FcGameEventLog.EV_REBOUND, o, off_rebounder.id, 0, 1)
		return CONTINUE
	var def_rebounder := _pick_weighted(_court[d], def_w)
	def_rebounder.stats.dreb += 1
	_log(FcGameEventLog.EV_REBOUND, d, def_rebounder.id, 0, 0)
	return END


func _commit_foul(side: int, fouler: FcSimPlayer, kind: int = FcGameEventLog.FOUL_PERSONAL) -> void:
	fouler.fouls += 1
	fouler.stats.pf += 1
	_team_fouls[side] += 1
	_log(FcGameEventLog.EV_FOUL, side, fouler.id, 0, kind)
	if fouler.fouls >= int(_t["foul_out"]):
		_force_substitution(side, fouler)


# --- probabilities -----------------------------------------------------------

func _make_probability(kind: int, shooter: FcSimPlayer, o: int, d: int, assisted: bool) -> float:
	var p: float
	var defense: float
	var assist_bonus: float
	match kind:
		THREE:
			p = float(_t["three_base"]) + float(_t["three_slope"]) * shooter.ratings["three"]
			defense = _avg(d, "perimeter_d")
			assist_bonus = float(_t["assist_bonus_three"])
		MID:
			p = float(_t["mid_base"]) + float(_t["mid_slope"]) * shooter.ratings["mid"]
			defense = _avg(d, "perimeter_d") * 0.5 + _avg(d, "interior_d") * 0.5
			assist_bonus = float(_t["assist_bonus_mid"])
		_:
			p = float(_t["rim_base"]) + float(_t["rim_slope"]) * shooter.ratings["finishing"]
			defense = _avg(d, "interior_d") * 0.7 + _avg(d, "perimeter_d") * 0.3
			assist_bonus = float(_t["assist_bonus_rim"])
	p -= (defense - 50.0) * float(_t["defense_slope"])
	if assisted:
		p += assist_bonus
	p += shooter.form
	p -= (1.0 - shooter.freshness()) * 100.0 * float(_t["fatigue_slope"])
	if o == 0:
		p += float(_t["home_court_bonus"])
	p += (float(_teams[o].tactics["offense"]) - 50.0) * float(_t["strategy_slope"])
	p -= (float(_teams[d].tactics["defense"]) - 50.0) * float(_t["strategy_slope"])
	# Mean reversion: a team shooting above its odds tonight cools off a little (defenses adjust).
	p -= _luck[o] * float(_t["luck_regression"])
	return clampf(p, 0.05, 0.92)


func _assist_chance(kind: int, o: int) -> float:
	var base := float(_t["assisted_three"])
	if kind == MID:
		base = float(_t["assisted_mid"])
	elif kind == RIM:
		base = float(_t["assisted_rim"])
	var flow := 0.75 + float(_teams[o].tactics["ball_movement"]) / 200.0
	var playmaking := 0.85 + _avg(o, "playmaking") / 333.0
	return clampf(base * flow * playmaking, 0.05, 0.95)


func _pick_shot_type(shooter: FcSimPlayer, o: int) -> int:
	var three_emphasis: float = _teams[o].tactics["three"]
	var w_three: float = shooter.tend_three * (0.55 + shooter.ratings["three"] / 100.0) * (0.7 + 0.6 * three_emphasis / 100.0) * float(_t["mix_three"])
	var w_rim: float = ((shooter.tend_drive + shooter.tend_post) / 2.0) * (0.55 + shooter.ratings["finishing"] / 100.0) * float(_t["mix_rim"])
	var w_mid: float = shooter.tend_mid * (0.3 + shooter.ratings["mid"] / 100.0) * float(_t["mix_mid"])
	var idx := _rng.weighted_index([maxf(w_three, 0.1), maxf(w_mid, 0.1), maxf(w_rim, 0.1)])
	return idx


## True late in regulation (4th quarter, last `late_tie_window_seconds`) when `o` trails by 1-3 points: such a
## team plays for the last shot and can still force overtime. Real games end in a tie more often than
## a pure shot-by-shot model produces because trailing teams do this.
func _chasing_a_tie(o: int) -> bool:
	if _period != int(_t["quarters"]) or _clock > float(_t["late_tie_window_seconds"]):
		return false
	var behind: int = _score[1 - o] - _score[o]
	return behind >= 1 and behind <= 3


## Late in a close game the trailing team fouls on purpose to stop the clock and get the ball back: 4th quarter,
## under `intentional_foul_window_seconds`, the defense trails by 1-`intentional_foul_max_deficit` and does it with
## probability `intentional_foul_chance`. The leading team then shoots free throws (in the bonus) and can miss them.
func _fouling_to_stop_the_clock(o: int, d: int) -> bool:
	if _period != int(_t["quarters"]) or _clock > float(_t["intentional_foul_window_seconds"]):
		return false
	var deficit: int = _score[o] - _score[d]
	if deficit < 1 or deficit > int(_t["intentional_foul_max_deficit"]):
		return false
	return _rng.chance(float(_t["intentional_foul_chance"]))


## The shot a team takes with the last possession when it trails: a three when down 3, a two when down 2 (or 1).
func _tie_shot_kind(o: int, normal: int) -> int:
	var behind: int = _score[1 - o] - _score[o]
	if behind == 3:
		return THREE
	if normal == THREE:
		return RIM if _rng.chance(0.6) else MID
	return normal


# --- choosing players --------------------------------------------------------

func _pick_scorer(o: int) -> FcSimPlayer:
	var weights: Array = []
	for p in _court[o]:
		var w: float = pow(clampf(p.ratings["scoring"], 5.0, float(_t["usage_max_rating"])) / 50.0, float(_t["usage_exponent"])) * (0.6 + 0.8 * (1.0 - p.tend_pass / 100.0))
		weights.append(w * (0.5 + 0.5 * p.freshness()) * (1.0 + 0.35 * p.usage_pref))
	return _pick_weighted(_court[o], weights)


func _pick_passer(o: int, shooter: FcSimPlayer) -> FcSimPlayer:
	var weights: Array = []
	for p in _court[o]:
		weights.append(0.001 if p == shooter else pow(maxf(p.ratings["playmaking"], 5.0) / 50.0, float(_t["passer_exponent"])) * pow(0.5 + p.tend_pass / 100.0, 2.0))
	return _pick_weighted(_court[o], weights)


func _pick_fouler(d: int) -> FcSimPlayer:
	var weights: Array = []
	for p in _court[d]:
		weights.append((0.5 + p.tend_foul / 100.0) * (1.4 - p.ratings["overall"] / 150.0) * (1.0 + (1.0 - p.freshness())))
	return _pick_weighted(_court[d], weights)


## Weights for the on-court players from one composite, raised to `power`.
func _weights(side: int, key: String, power: float, fatigue: bool) -> Array:
	var out: Array = []
	for p in _court[side]:
		var v: float = maxf(p.ratings[key], 5.0)
		if fatigue:
			v *= 0.7 + 0.3 * p.freshness()
		out.append(pow(v / 50.0, power))
	return out


func _pick_weighted(list: Array, weights: Array) -> FcSimPlayer:
	return list[_rng.weighted_index(weights)]


## Average composite of the five on court, reduced when they are tired.
func _avg(side: int, key: String) -> float:
	var total := 0.0
	for p in _court[side]:
		total += p.ratings[key] * (1.0 - (1.0 - p.freshness()) * 0.35)
	return total / 5.0


func _avg_foul_tendency(side: int) -> float:
	var total := 0.0
	for p in _court[side]:
		total += p.tend_foul
	return total / 5.0


# --- time, energy, substitutions -----------------------------------------

func _sample_duration() -> float:
	var pace: float = (float(_teams[0].tactics["pace"]) + float(_teams[1].tactics["pace"])) / 2.0
	var mean := float(_t["possession_seconds"]) - (pace - 50.0) / 50.0 * float(_t["pace_seconds"]) + _game_pace_shift
	return clampf(_rng.gaussian(mean, float(_t["possession_seconds_sd"])), float(_t["min_possession_seconds"]), 24.0)


func _use_time(seconds: float) -> void:
	_clock -= seconds
	var hurt: Array = []   # injuries are handled after the loop so lineups are not changed mid-count
	for side in 2:
		for p in _teams[side].players:
			if p.on_court:
				p.seconds_f += seconds
				p.energy = maxf(0.0, p.energy - seconds * float(_t["energy_drain_per_second"]) * (1.3 - 0.6 * p.stamina / 100.0))
				if float(_t["injury_per_minute"]) > 0.0 and not p.injured:
					var chance := float(_t["injury_per_minute"]) * seconds / 60.0 * (1.4 - 0.8 * p.durability / 100.0)
					chance *= 1.25 - float(_teams[side].tactics["injury_prevention"]) / 200.0
					if _rng.chance(chance):
						hurt.append([side, p])
			else:
				p.energy = minf(100.0, p.energy + seconds * float(_t["energy_recover_per_second"]) * (0.7 + p.stamina / 100.0 * 0.6))
	for entry in hurt:
		_injure(entry[0], entry[1])


## A player is hurt: he leaves the game (if someone can replace him) and misses games.
func _injure(side: int, p: FcSimPlayer) -> void:
	var bench: Array[FcSimPlayer] = []
	for q in _teams[side].players:
		if not q.on_court and not q.injured and q.fouls < int(_t["foul_out"]):
			bench.append(q)
	if bench.is_empty():
		return   # nobody to replace him: he plays through it
	var roll := _rng.next_float()
	var severity := 0
	if roll < 0.60:
		severity = _rng.range_int(1, 5)
	elif roll < 0.88:
		severity = _rng.range_int(6, 20)
	elif roll < 0.97:
		severity = _rng.range_int(21, 60)
	else:
		severity = _rng.range_int(61, 82)
	p.injured = true
	p.injury_games = severity
	p.injury_name = _injury_name(severity)
	_injuries.append([p.id, severity, p.injury_name])
	_log(FcGameEventLog.EV_INJURY, side, p.id, severity)
	_force_substitution(side, p)


func _injury_name(severity: int) -> String:
	var names: Array = ["sprained ankle", "bruised knee", "sore back", "strained hamstring", "bruised hip"]
	if severity > 60:
		names = ["torn ACL", "ruptured Achilles", "fractured leg"]
	elif severity > 20:
		names = ["stress reaction in the foot", "torn meniscus", "broken hand", "fractured wrist"]
	elif severity > 5:
		names = ["sprained knee", "strained groin", "sprained ankle", "calf strain"]
	return names[_rng.range_int(0, names.size() - 1)]


func _recover_between_periods() -> void:
	var quarters := int(_t["quarters"])
	var amount := float(_t["quarter_break_recovery"])
	if _period == floori(quarters / 2.0) + 1:
		amount = float(_t["halftime_recovery"])
	for side in 2:
		for p in _teams[side].players:
			p.energy = minf(100.0, p.energy + amount)


func _put_on_court(side: int, p: FcSimPlayer) -> void:
	p.on_court = true
	_court[side].append(p)


func _take_off_court(side: int, p: FcSimPlayer) -> void:
	p.on_court = false
	_court[side].erase(p)


func _select_lineup(team: FcGameTeam) -> Array[FcSimPlayer]:
	var chosen: Array[FcSimPlayer] = []
	var pool: Array = team.players.duplicate()
	while chosen.size() < 5 and not pool.is_empty():
		var best: FcSimPlayer = null
		var best_score := -INF
		for p in pool:
			var s: float = p.overall + _position_bonus(chosen, p) + p.role_bonus
			if s > best_score:
				best_score = s
				best = p
		chosen.append(best)
		pool.erase(best)
	return chosen


## The five who would start for `team` under the same rule the game uses (for the game-day preview).
func projected_starters(team: FcGameTeam) -> Array[FcSimPlayer]:
	return _select_lineup(team)


## Bonus for a player who fills a missing role (a guard or a big man).
func _position_bonus(lineup: Array, candidate: FcSimPlayer) -> float:
	var guards := 0
	var bigs := 0
	for p in lineup:
		if p.position == FcPosition.Id.PG or p.position == FcPosition.Id.SG:
			guards += 1
		elif p.position == FcPosition.Id.PF or p.position == FcPosition.Id.C:
			bigs += 1
	var bonus := 0.0
	var is_guard := candidate.position == FcPosition.Id.PG or candidate.position == FcPosition.Id.SG
	var is_big := candidate.position == FcPosition.Id.PF or candidate.position == FcPosition.Id.C
	if guards == 0 and is_guard:
		bonus += float(_t["position_balance_bonus"])
	if bigs == 0 and is_big:
		bonus += float(_t["position_balance_bonus"])
	if guards >= 3 and is_guard:
		bonus -= float(_t["position_balance_bonus"])
	if bigs >= 3 and is_big:
		bonus -= float(_t["position_balance_bonus"])
	return bonus


## At most one substitution per dead ball, per team.
func _substitutions(side: int) -> void:
	var team := _teams[side]
	var margin := _score[side] - _score[1 - side]
	var late_close := _period >= int(_t["quarters"]) and _clock < 300.0 and absi(margin) <= 8
	var garbage := _period >= int(_t["quarters"]) and _clock < 420.0 and absi(margin) >= int(_t["garbage_margin"])
	var management_shift := (50.0 - float(team.tactics["game_management"])) * 0.12
	var out_threshold := float(_t["sub_out_energy"]) + management_shift
	if late_close:
		out_threshold = float(_t["late_game_sub_out_energy"]) + management_shift
	var bench: Array[FcSimPlayer] = []
	for p in team.players:
		if not p.on_court and not p.injured and p.fouls < int(_t["foul_out"]):
			bench.append(p)
	if bench.is_empty():
		return

	if garbage:
		_garbage_time_substitution(side, bench)
		return

	# Who needs to leave: players in foul trouble first, then the most tired.
	var leaving: FcSimPlayer = null
	var priority := INF
	for p in _court[side]:
		var in_trouble := false
		if _period < int(_t["quarters"]):
			in_trouble = p.fouls >= int(_t["foul_trouble_early"])
		elif not late_close:
			in_trouble = p.fouls >= int(_t["foul_out"]) - 1
		var tired: bool = p.energy < out_threshold - 8.0 * p.minutes_pref \
			or (p.seconds_f > float(_t["minutes_soft_cap_seconds"]) * (1.0 + 0.08 * p.minutes_pref) and not late_close)
		if not in_trouble and not tired:
			continue
		var key: float = p.energy - (1000.0 if in_trouble else 0.0)
		if key < priority:
			priority = key
			leaving = p
	if leaving == null:
		return
	var replacement := _best_replacement(side, leaving, bench, float(_t["sub_in_energy"]))
	if replacement != null:
		_swap(side, leaving, replacement)


func _garbage_time_substitution(side: int, bench: Array[FcSimPlayer]) -> void:
	var team := _teams[side]
	var best_on_court: FcSimPlayer = null
	for p in _court[side]:
		if team.players.find(p) < 7 and (best_on_court == null or p.overall > best_on_court.overall):
			best_on_court = p
	if best_on_court == null:
		return
	var choice: FcSimPlayer = null
	for p in bench:
		if team.players.find(p) >= 7 and p.energy >= 50.0 and (choice == null or p.overall > choice.overall):
			choice = p
	if choice != null:
		_swap(side, best_on_court, choice)


func _force_substitution(side: int, leaving: FcSimPlayer) -> void:
	var bench: Array[FcSimPlayer] = []
	for p in _teams[side].players:
		if not p.on_court and not p.injured and p.fouls < int(_t["foul_out"]):
			bench.append(p)
	var replacement := _best_replacement(side, leaving, bench, 0.0)
	if replacement != null:
		_swap(side, leaving, replacement)


func _best_replacement(side: int, leaving: FcSimPlayer, bench: Array[FcSimPlayer], min_energy: float) -> FcSimPlayer:
	var remaining: Array = _court[side].duplicate()
	remaining.erase(leaving)
	var best: FcSimPlayer = null
	var best_score := -INF
	for p in bench:
		if p.energy < min_energy:
			continue
		var score := p.overall * (0.65 + 0.35 * p.freshness()) + _position_bonus(remaining, p) + 6.0 * p.minutes_pref
		if score > best_score:
			best_score = score
			best = p
	return best


func _swap(side: int, leaving: FcSimPlayer, entering: FcSimPlayer) -> void:
	_take_off_court(side, leaving)
	_put_on_court(side, entering)
	_log(FcGameEventLog.EV_SUBSTITUTION, side, entering.id, leaving.id)


# --- play-by-play recording -------------------------------------------------------

## Writes one event to the recorder (if there is one). Reads state only: no random numbers, so it cannot change a game.
func _log(type: int, side: int, a: int = 0, b: int = 0, x: int = 0) -> void:
	if recorder != null:
		recorder.add(type, roundi(_clock * 10.0), side, a, b, x)


# --- scoring bookkeeping -------------------------------------------------------

func _add_points(side: int, points: int) -> void:
	_score[side] += points
	_period_points[side][_period_points[side].size() - 1] += points
	for p in _court[side]:
		p.stats.plus_minus += points
	for p in _court[1 - side]:
		p.stats.plus_minus -= points


func _finish() -> FcBoxScore:
	var box := FcBoxScore.new()
	box.overtimes = maxi(0, _period_points[0].size() - int(_t["quarters"]))
	box.injuries = _injuries.duplicate(true)
	for side in 2:
		box.team_ids[side] = _teams[side].team_id
		box.team_names[side] = _teams[side].name
		box.abbreviations[side] = _teams[side].abbreviation
		box.scores[side] = _score[side]
		box.period_scores[side] = _period_points[side].duplicate()
		for p in _teams[side].players:
			p.stats.seconds = roundi(p.seconds_f)
			box.players.append(p.stats)
	for side in 2:
		var totals := box.team_totals(side)
		box.possessions[side] = totals["fga"] + 0.44 * totals["fta"] - totals["oreb"] + totals["tov"]
	return box
