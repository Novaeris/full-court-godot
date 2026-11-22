class_name FcPlayByPlay
extends RefCounted
## Turns a game's event rows (FcGameEventLog) plus its box score into a readable timeline: the period and running score at
## every event, a sentence for each, and who is on the court at any moment. Pure and read-only; all modes share it (the replay
## screen, the post-game screen and the history list all read these entries).
##
## The period and the score are DERIVED from the rows here, never stored, so the timeline can never disagree with the events
## (and tests check that the derived totals equal the box score).

const ORDINALS := ["1st", "2nd", "3rd", "4th"]

## Event types that appear in the feed. Starters and period markers are bookkeeping, shown only where noted.
const HIDDEN := [FcGameEventLog.EV_STARTER]


## One Dictionary per event, in order:
## {"index", "type", "period", "clock" (seconds left, float), "clock_text" ("4:31"), "side", "abbr", "home", "away",
##  "points" (scored by this event), "a", "b", "x", "text", "visible"}
static func entries(log: FcGameEventLog, box: FcBoxScore, quarters: int = 4) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var names := _names(box)
	var score := [0, 0]
	var period := 1
	for i in log.rows.size():
		var row: Array = log.rows[i]
		var type: int = row[FcGameEventLog.COL_TYPE]
		var side: int = row[FcGameEventLog.COL_SIDE]
		var a: int = row[FcGameEventLog.COL_A]
		var b: int = row[FcGameEventLog.COL_B]
		var x: int = row[FcGameEventLog.COL_X]
		if type == FcGameEventLog.EV_PERIOD_START or type == FcGameEventLog.EV_PERIOD_END:
			period = x
		var points := 0
		if type == FcGameEventLog.EV_SHOT_MADE:
			points = FcGameEventLog.points_of(x)
		elif type == FcGameEventLog.EV_FREE_THROW and x == 1:
			points = 1
		if points > 0:
			score[side] += points
		var tenths: int = row[FcGameEventLog.COL_CLOCK]
		out.append({
			"index": i, "type": type, "period": period, "clock": tenths / 10.0, "clock_text": clock_text(tenths),
			"side": side, "abbr": box.abbreviations[side] if side >= 0 and side < 2 else "",
			"home": score[0], "away": score[1], "points": points, "a": a, "b": b, "x": x,
			"text": _describe(type, side, a, b, x, i, period, quarters, names, box, score),
			"visible": not HIDDEN.has(type),
		})
	return out


## "4:31" for 271 seconds (2710 tenths); under a minute shows tenths-free seconds, e.g. "0:09".
static func clock_text(tenths: int) -> String:
	var secs := ceili(maxi(0, tenths) / 10.0)
	return "%d:%02d" % [floori(secs / 60.0), secs % 60]


## "Marcus Hill" -> "M. Hill"; a single name is kept as is.
static func short_name(full_name: String) -> String:
	var parts := full_name.strip_edges().split(" ", false)
	if parts.size() < 2:
		return full_name
	return "%s. %s" % [parts[0].substr(0, 1), " ".join(parts.slice(1))]


## The five players on court for each side just AFTER event `upto` (inclusive): [[ids], [ids]].
static func on_court(entry_list: Array[Dictionary], upto: int) -> Array:
	var court: Array = [[], []]
	for i in mini(upto + 1, entry_list.size()):
		var e: Dictionary = entry_list[i]
		if e["type"] == FcGameEventLog.EV_STARTER:
			court[e["side"]].append(e["a"])
		elif e["type"] == FcGameEventLog.EV_SUBSTITUTION:
			var list: Array = court[e["side"]]
			var at := list.find(e["b"])
			if at >= 0:
				list[at] = e["a"]
			else:
				list.append(e["a"])
	return court


## Index of the first event of `period` (-1 if it never happened).
static func period_start_index(entry_list: Array[Dictionary], period: int) -> int:
	for e in entry_list:
		if e["type"] == FcGameEventLog.EV_PERIOD_START and e["x"] == period:
			return e["index"]
	return -1


static func period_name(period: int, quarters: int = 4) -> String:
	if period <= quarters:
		return "%s quarter" % ORDINALS[clampi(period - 1, 0, ORDINALS.size() - 1)]
	var n := period - quarters
	return "overtime" if n == 1 else "overtime %d" % n


# --- sentences ---------------------------------------------------------------------------------------

static func _names(box: FcBoxScore) -> Dictionary:
	var out := {}
	for p in box.players:
		out[p.player_id] = short_name(p.name)
	return out


static func _who(names: Dictionary, id: int) -> String:
	return str(names.get(id, "A player"))


static func _describe(type: int, side: int, a: int, b: int, x: int, index: int, period: int, quarters: int,
		names: Dictionary, box: FcBoxScore, score: Array) -> String:
	var who := _who(names, a)
	match type:
		FcGameEventLog.EV_PERIOD_START:
			return "Tip-off." if x == 1 else "Start of the %s." % period_name(x, quarters)
		FcGameEventLog.EV_PERIOD_END:
			return "End of the %s." % period_name(x, quarters)
		FcGameEventLog.EV_GAME_END:
			return "Final: %s %d, %s %d." % [box.abbreviations[0], score[0], box.abbreviations[1], score[1]]
		FcGameEventLog.EV_SHOT_MADE:
			var line := _pick(index, _made_phrases(x)) % who
			if b != 0:
				line += " (assist: %s)" % _who(names, b)
			return line
		FcGameEventLog.EV_SHOT_MISSED:
			return _pick(index, _missed_phrases(x)) % who
		FcGameEventLog.EV_SHOT_BLOCKED:
			return "%s's shot is blocked by %s." % [who, _who(names, b)]
		FcGameEventLog.EV_REBOUND:
			if a == 0:
				return "%s team rebound." % box.abbreviations[side]
			return "%s with the %s rebound." % [who, "offensive" if x == 1 else "defensive"]
		FcGameEventLog.EV_TURNOVER:
			if b != 0:
				return "%s turns it over, stolen by %s." % [who, _who(names, b)]
			return "%s turns it over." % who
		FcGameEventLog.EV_FOUL:
			match x:
				FcGameEventLog.FOUL_SHOOTING:
					return "%s commits a shooting foul." % who
				FcGameEventLog.FOUL_INTENTIONAL:
					return "%s fouls on purpose to stop the clock." % who
			return "%s commits a foul." % who
		FcGameEventLog.EV_FREE_THROW:
			return "%s %s free throw %d of %d." % [who, "makes" if x == 1 else "misses", floori(b / 10.0), b % 10]
		FcGameEventLog.EV_SUBSTITUTION:
			return "%s enters for %s." % [who, _who(names, b)]
		FcGameEventLog.EV_INJURY:
			return "%s is hurt and will miss %d game%s." % [who, b, "" if b == 1 else "s"]
	return ""


static func _made_phrases(kind: int) -> Array:
	match kind:
		FcGameEventLog.SHOT_THREE:
			return ["%s hits a three-pointer", "%s drains a three", "%s connects from deep"]
		FcGameEventLog.SHOT_MID:
			return ["%s makes a jumper", "%s hits a mid-range shot", "%s sinks a pull-up jumper"]
	return ["%s scores at the rim", "%s finishes inside", "%s drives for two"]


static func _missed_phrases(kind: int) -> Array:
	match kind:
		FcGameEventLog.SHOT_THREE:
			return ["%s misses a three-pointer", "%s's three rims out"]
		FcGameEventLog.SHOT_MID:
			return ["%s misses a jumper", "%s's mid-range shot is off"]
	return ["%s misses at the rim", "%s can't finish inside"]


## A varied but repeatable choice: the same event always reads the same.
static func _pick(index: int, options: Array) -> String:
	return str(options[index % options.size()])
