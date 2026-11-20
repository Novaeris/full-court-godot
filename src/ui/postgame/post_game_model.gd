class_name FcPostGameModel
extends RefCounted
## The post-game view-model, the same for every mode: built from a finished game's box score (the dictionary FcBoxScore.to_dict()
## produces) plus what only the calling mode knows (which side is the user's team, a face for each player, season implications, rewards).
## It is PURE: it reads the box score and changes nothing, uses no random numbers and has no nodes, so it can be tested headless
## and the screen can only show what is in it. Nothing here decides a game or touches a save.
##
## The "player of the game" is a DISPLAY ranking (weights in data/ui/pog.json), clearly labelled as such, never an award or a stat.

const POG_PATH := "res://data/ui/pog.json"


## options (all optional): user_side (0 or 1; -1 when the user is not playing), subjects {sim player id: subject dict for FcPlayerVisual},
## implications [String], rewards [String].
static func build(box_dict: Dictionary, options: Dictionary = {}) -> Dictionary:
	var box := FcBoxScore.from_dict(box_dict)
	var user_side: int = int(options.get("user_side", -1))
	var subjects: Dictionary = options.get("subjects", {})
	var sides: Array = []
	var winner := box.winner_side()
	for i in 2:
		sides.append({"name": box.team_names[i], "abbr": box.abbreviations[i], "score": box.scores[i], "periods": (box.period_scores[i] as Array).duplicate(),
			"won": i == winner, "team_id": box.team_ids[i], "is_user": i == user_side})
	var result := ""
	if user_side >= 0:
		result = "win" if winner == user_side else "loss"
	var performers := _ranked(box, subjects)
	return {
		"sides": sides, "user_side": user_side, "result": result, "overtimes": box.overtimes, "status": status_text(box.overtimes),
		"headline": headline(box, user_side), "line_score": line_score(box), "comparison": comparison(box),
		"performers": performers.slice(0, 3), "pog": _player_of_the_game(box, winner, subjects), "tables": [_table(box, 0), _table(box, 1)],
		"implications": (options.get("implications", []) as Array).duplicate(), "rewards": (options.get("rewards", []) as Array).duplicate(),
		"injuries": (box.injuries as Array).size(),
	}


static func status_text(overtimes: int) -> String:
	if overtimes <= 0:
		return "Final"
	return "Final/OT" if overtimes == 1 else "Final/%dOT" % overtimes


## "X won 104-98 over Y" from the user's side, or a neutral "X beat Y 104-98" when the user is not in the game.
static func headline(box: FcBoxScore, user_side: int) -> String:
	var winner := box.winner_side()
	var loser := 1 - winner
	if user_side < 0:
		return "%s beat %s %d-%d" % [box.team_names[winner], box.team_names[loser], box.scores[winner], box.scores[loser]]
	if winner == user_side:
		return "%s won %d-%d over %s" % [box.team_names[user_side], box.scores[user_side], box.scores[1 - user_side], box.team_names[1 - user_side]]
	return "%s lost %d-%d to %s" % [box.team_names[user_side], box.scores[user_side], box.scores[1 - user_side], box.team_names[1 - user_side]]


## {columns, rows}: one row per team, a column per quarter (overtime periods named), then the total.
static func line_score(box: FcBoxScore) -> Dictionary:
	var count: int = (box.period_scores[0] as Array).size()
	var columns: Array = [""]
	for p in count:
		if p < 4:
			columns.append(str(p + 1))
		else:
			columns.append("OT" if p == 4 else "OT%d" % (p - 3))
	columns.append("T")
	var rows: Array = []
	for side in 2:
		var row: Array = [box.abbreviations[side]]
		for v in box.period_scores[side]:
			row.append(int(v))
		row.append(box.scores[side])
		rows.append(row)
	return {"columns": columns, "rows": rows}


static func pct(made: int, attempts: int) -> int:
	return roundi(100.0 * made / attempts) if attempts > 0 else 0


## The team comparison bars: [{id, label, left, right, left_text, right_text, lower_is_better}] (left is side 0, the home team).
static func comparison(box: FcBoxScore) -> Array:
	var a := box.team_totals(0)
	var b := box.team_totals(1)
	var rows: Array = []
	rows.append(_pair("fg", "Field goal %", pct(a["fgm"], a["fga"]), pct(b["fgm"], b["fga"]), "%d%%", false))
	rows.append(_pair("three", "3-point %", pct(a["tpm"], a["tpa"]), pct(b["tpm"], b["tpa"]), "%d%%", false))
	rows.append(_pair("ft", "Free throw %", pct(a["ftm"], a["fta"]), pct(b["ftm"], b["fta"]), "%d%%", false))
	rows.append(_pair("reb", "Rebounds", a["oreb"] + a["dreb"], b["oreb"] + b["dreb"], "%d", false))
	rows.append(_pair("ast", "Assists", a["ast"], b["ast"], "%d", false))
	rows.append(_pair("stl", "Steals", a["stl"], b["stl"], "%d", false))
	rows.append(_pair("blk", "Blocks", a["blk"], b["blk"], "%d", false))
	rows.append(_pair("tov", "Turnovers", a["tov"], b["tov"], "%d", true))
	return rows


static func _pair(id: String, label: String, left: int, right: int, format: String, lower_is_better: bool) -> Dictionary:
	return {"id": id, "label": label, "left": left, "right": right, "left_text": format % left, "right_text": format % right, "lower_is_better": lower_is_better}


## A player's display score from the data/ui/pog.json weights (the same score ranks the top performers and picks the player of the game).
static func display_score(p: FcPlayerGameStats, weights: Dictionary) -> float:
	return (p.points * float(weights.get("points", 1.0)) + p.rebounds() * float(weights.get("rebounds", 0.0)) + p.ast * float(weights.get("assists", 0.0))
		+ p.stl * float(weights.get("steals", 0.0)) + p.blk * float(weights.get("blocks", 0.0)) + p.tov * float(weights.get("turnovers", 0.0))
		+ (p.fga - p.fgm) * float(weights.get("missed_fg", 0.0)) + (p.fta - p.ftm) * float(weights.get("missed_ft", 0.0))
		+ p.plus_minus * float(weights.get("plus_minus", 0.0)))


static func config() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(POG_PATH))
	return parsed if parsed is Dictionary else {"weights": {"points": 1.0}, "label": "Player of the game", "note": ""}


## Everyone who played, best display score first (ties by points, then name: stable, so the same game always ranks the same way).
static func _ranked(box: FcBoxScore, subjects: Dictionary) -> Array:
	var weights: Dictionary = config().get("weights", {})
	var out: Array = []
	for side in 2:
		for p in box.players_of(side):
			if p.seconds == 0:
				continue
			out.append(_entry(p, side, display_score(p, weights), subjects))
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		if x["score"] != y["score"]:
			return x["score"] > y["score"]
		if x["points"] != y["points"]:
			return x["points"] > y["points"]
		return str(x["name"]) < str(y["name"]))
	return out


static func _entry(p: FcPlayerGameStats, side: int, score: float, subjects: Dictionary) -> Dictionary:
	var subject: Dictionary = subjects.get(p.player_id, FcPlayerPresentation.subject("player:%d" % p.player_id, p.name))
	return {"pid": p.player_id, "name": p.name, "side": side, "points": p.points, "rebounds": p.rebounds(), "assists": p.ast, "steals": p.stl, "blocks": p.blk,
		"score": snappedf(score, 0.01), "line": "%d PTS  %d REB  %d AST" % [p.points, p.rebounds(), p.ast], "subject": subject}


static func _player_of_the_game(box: FcBoxScore, winner: int, subjects: Dictionary) -> Dictionary:
	var cfg := config()
	var weights: Dictionary = cfg.get("weights", {})
	var best: Dictionary = {}
	var min_seconds := int(cfg.get("minimum_seconds", 0))
	for side in 2:
		if bool(cfg.get("winners_only", true)) and side != winner:
			continue
		for p in box.players_of(side):
			if p.seconds < min_seconds or p.seconds == 0:
				continue
			var e := _entry(p, side, display_score(p, weights) + (float(cfg.get("winner_bonus", 0.0)) if side == winner else 0.0), subjects)
			if best.is_empty() or e["score"] > best["score"] or (e["score"] == best["score"] and str(e["name"]) < str(best["name"])):
				best = e
	if not best.is_empty():
		best["label"] = str(cfg.get("label", "Player of the game"))
		best["note"] = str(cfg.get("note", ""))
	return best


static func _table(box: FcBoxScore, side: int) -> Dictionary:
	var list := box.players_of(side)
	list.sort_custom(func(a: FcPlayerGameStats, b: FcPlayerGameStats) -> bool: return a.seconds > b.seconds)
	var rows: Array = []
	for p in list:
		if p.seconds == 0:
			continue
		rows.append([p.name, FcPosition.abbreviation(p.position), "%d:%02d" % [p.seconds / 60, p.seconds % 60], p.points, p.rebounds(), p.ast, p.stl, p.blk, p.tov,
			"%d-%d" % [p.fgm, p.fga], "%d-%d" % [p.tpm, p.tpa], "%d-%d" % [p.ftm, p.fta], "%+d" % p.plus_minus])
	return {"side": side, "name": box.team_names[side], "abbr": box.abbreviations[side],
		"columns": ["Player", "Pos", "Min", "PTS", "REB", "AST", "STL", "BLK", "TO", "FG", "3P", "FT", "+/-"], "rows": rows}
