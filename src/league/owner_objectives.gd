class_name FcOwnerObjectives
extends RefCounted
## The owner's goals for a season (D-077 C3): three or four measurable targets set once when the season starts, from what the franchise
## can reasonably expect (its payroll rank, last season's record and books), kept unchanged for the whole season, and judged once when it
## ends. Pure: the controller gathers the numbers and stores the result in FcGameState.owner_objectives.
##
## Objective kinds (each a Dictionary {"kind", "text", "target", "actual", "met", "status"}):
##   wins         win at least `target` regular-season games
##   playoffs     reach at least playoff round `target` (1 = qualify)
##   profit       finish the season with a profit of at least `target` dollars (can be negative: "lose no more than")
##   development  a player aged 23 or younger plays at least `target` minutes a game (over at least half the season)

const STATUS_OPEN := "open"
const STATUS_MET := "met"
const STATUS_MISSED := "missed"


## `p`: {"games": int (regular-season games per team), "expected_wins": float, "last_wins": int (-1 when unknown),
##  "last_profit": int, "has_books": bool, "playoff_teams": int, "teams": int}.
static func generate(p: Dictionary) -> Array:
	var games := int(p.get("games", 80))
	var expected := float(p.get("expected_wins", games * 0.5))
	var out: Array = []
	# the expectation, but never below last season's total when the team is expected to be at least as good (owners want progress)
	var win_target := roundi(expected)
	var last_wins := int(p.get("last_wins", -1))
	if last_wins >= 0 and expected >= last_wins:
		win_target = maxi(win_target, last_wins + 1)
	win_target = clampi(win_target, 1, games - 1)
	out.append(_make("wins", "Win at least %d games" % win_target, win_target))
	var share := expected / float(maxi(1, games))
	var qualify_share := float(p.get("playoff_teams", 8)) / float(maxi(1, int(p.get("teams", 16))))
	if share >= 0.60:
		out.append(_make("playoffs", "Reach the second round of the playoffs", 2))
	elif share >= 0.5 - (qualify_share - 0.5) * 0.5 - 0.03:
		out.append(_make("playoffs", "Make the playoffs", 1))
	if bool(p.get("has_books", false)):
		var last := int(p.get("last_profit", 0))
		var target := 0 if last < 0 else roundi(last * 0.8 / 100000.0) * 100000
		out.append(_make("profit", "Make a profit" if target <= 0 else "Make a profit of at least %s" % _money(target), target))
	out.append(_make("development", "Give a player aged 23 or younger at least 20 minutes a game", 20))
	return out


## Judges each objective with the finished season's numbers. `r`: {"wins": int, "playoff_round": int (0 = missed, 1 = qualified and lost in
## round one, 2 = reached round two, ...), "profit": int (or null when the books are not settled), "young_minutes": float (the most minutes a
## game of a player aged 23 or younger with at least half the games)}.
static func evaluate(objectives: Array, r: Dictionary) -> Array:
	var out: Array = []
	for o in objectives:
		var e: Dictionary = (o as Dictionary).duplicate()
		match str(e["kind"]):
			"wins":
				e["actual"] = int(r.get("wins", 0))
				e["met"] = int(e["actual"]) >= int(e["target"])
			"playoffs":
				e["actual"] = int(r.get("playoff_round", 0))
				e["met"] = int(e["actual"]) >= int(e["target"])
			"profit":
				if r.get("profit") == null:
					e["actual"] = 0
					e["met"] = false
				else:
					e["actual"] = int(r["profit"])
					e["met"] = int(e["actual"]) >= int(e["target"])
			"development":
				e["actual"] = roundi(float(r.get("young_minutes", 0.0)))
				e["met"] = float(r.get("young_minutes", 0.0)) >= float(e["target"])
		e["status"] = STATUS_MET if bool(e.get("met", false)) else STATUS_MISSED
		out.append(e)
	return out


## Reputation change for a judged list: +3 for each objective met, -2 for each missed (a full sweep is worth a lot more than one miss costs).
static func reputation_delta(judged: Array) -> int:
	var delta := 0
	for o in judged:
		delta += 3 if str(o.get("status", "")) == STATUS_MET else (-2 if str(o.get("status", "")) == STATUS_MISSED else 0)
	return delta


## How far along an open objective is during the season, as text ("12 of 45 wins", "currently 6th, in a playoff place").
static func progress_text(o: Dictionary, now: Dictionary) -> String:
	match str(o.get("kind", "")):
		"wins":
			return "%d of %d wins, %d games left" % [int(now.get("wins", 0)), int(o["target"]), int(now.get("games_left", 0))]
		"playoffs":
			return "in a playoff place" if bool(now.get("in_playoff_place", false)) else "outside the playoff places"
		"profit":
			return "settled when the season's books close"
		"development":
			return "best young player: %.1f minutes a game" % float(now.get("young_minutes", 0.0))
	return ""


static func _make(kind: String, text: String, target: int) -> Dictionary:
	return {"kind": kind, "text": text, "target": target, "actual": 0, "met": false, "status": STATUS_OPEN}


static func _money(v: int) -> String:
	return "$%.1fM" % (v / 1e6)
