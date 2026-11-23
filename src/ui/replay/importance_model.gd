class_name FcImportanceModel
extends RefCounted
## How much an event matters (Broadcast pass 2, M4, D-071): the ONE place the replay decides that a play is worth seeing again. Highlights,
## key-play marks on the timeline, the highlight reel and automatic bookmarks all read it, so they can never disagree. Pure and deterministic:
## it reads the broadcast timeline (recorded events only) and scores each event by what the graphics already name (a milestone, a run, a lead
## change, a tie, a block, a basket), plus CONTEXT: a three-pointer, clutch time, a close score late in the game, a basket that ended a
## run, and the last basket of the game.
##
## (The camera director's priorities decide which SHOT to take, a different question; they are documented next to it, not merged here.)
##
## An entry is {index, score (raw points), importance (0 to 100, for display and sorting across games), kind, title, detail, reasons [text]}.

const WEIGHT := {FcBroadcastGraphics.MILESTONE: 60, FcBroadcastGraphics.RUN: 50, FcBroadcastGraphics.LEAD_CHANGE: 40, FcBroadcastGraphics.TIED: 30,
	FcBroadcastGraphics.BLOCK: 15, FcBroadcastGraphics.SCORE: 10}
const THREE_BONUS := 5
const CLUTCH_BONUS := 20
const LAST_BASKET_BONUS := 50
## A basket in the second half with the score within this many points: the game is on the line.
const CLOSE_MARGIN := 3
const CLOSE_BONUS := 8
## The raw score that counts as 100 importance (a clutch go-ahead milestone is above it and is capped).
const IMPORTANCE_CEILING := 120


## Every event that is worth a mark, scored: [{index, score, importance, kind, title, detail, reasons}], in game order. Events with no named
## graphic (a plain miss or rebound) are not included.
static func scored(timeline: FcBroadcastTimeline) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if timeline == null or timeline.is_empty():
		return out
	if timeline.cache.has("importance_scored"):
		return timeline.cache["importance_scored"]   # computed once per timeline (highlights, key plays, the reel and the marks all ask)
	var clutch := timeline.clutch_start_index()
	var last_basket := -1
	for e in timeline.model.entries:
		if int(e["type"]) == FcGameEventLog.EV_SHOT_MADE:
			last_basket = int(e["index"])
	var half := int(ceil(float(timeline.model.quarters) / 2.0))
	for i in timeline.size():
		var best := 0
		var top: Dictionary = {}
		for item in FcBroadcastGraphics.items_at(timeline, i):
			var w: int = int(WEIGHT.get(item["kind"], 0))
			if w > best:
				best = w
				top = item
		if best == 0:
			continue
		var e: Dictionary = timeline.model.entries[i]
		var total := best
		var reasons: Array[String] = [str(top["kind"])]
		if int(e["points"]) == 3:
			total += THREE_BONUS
			reasons.append("three-pointer")
		if clutch >= 0 and i >= clutch:
			total += CLUTCH_BONUS
			reasons.append("clutch time")
		var snap := timeline.snapshot(i)
		if int(e["points"]) > 0 and int(e["period"]) > half and absi(int(snap["lead"])) <= CLOSE_MARGIN:
			total += CLOSE_BONUS
			reasons.append("close score")
		if i == last_basket:
			total += LAST_BASKET_BONUS
			reasons.append("last basket")
		out.append({"index": i, "score": total, "importance": importance_of(total), "kind": str(top["kind"]), "title": str(top["title"]),
			"detail": str(top["detail"]), "reasons": reasons})
	timeline.cache["importance_scored"] = out
	return out


## The 0 to 100 importance of a raw score.
static func importance_of(raw_score: int) -> int:
	return clampi(int(round(float(raw_score) * 100.0 / float(IMPORTANCE_CEILING))), 0, 100)


## The entry for one event, or {} when it has no mark.
static func at(timeline: FcBroadcastTimeline, index: int) -> Dictionary:
	for entry in scored(timeline):
		if int(entry["index"]) == index:
			return entry
	return {}


## The best `count` entries at least `min_gap` events apart, in game order (the selection the highlights use).
static func top(entries: Array, count: int, min_gap: int) -> Array[Dictionary]:
	var ranked: Array = entries.duplicate()
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["score"]) > int(b["score"]) if int(a["score"]) != int(b["score"]) else int(a["index"]) < int(b["index"]))
	var out: Array[Dictionary] = []
	for candidate in ranked:
		if out.size() >= count:
			break
		var apart := true
		for chosen in out:
			if absi(int(chosen["index"]) - int(candidate["index"])) < min_gap:
				apart = false
				break
		if apart:
			out.append(candidate)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["index"]) < int(b["index"]))
	return out
