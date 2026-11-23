class_name FcHighlights
extends RefCounted
## Highlight selection for a replay (master plan B6): which events of a game are worth jumping to. Pure and deterministic: it reads the broadcast
## timeline (recorded events only), scores every event by what the graphics already name (a lead change, a run, a milestone, a block, a
## three-pointer, a tie) with a bonus inside clutch time and for the last basket of the game, then keeps the best ones that are at least
## MIN_GAP events apart. Nothing is stored or changed; the same game always gives the same highlights, in game order.

const MIN_GAP := 8
const DEFAULT_COUNT := 8

const WEIGHT := {FcBroadcastGraphics.MILESTONE: 60, FcBroadcastGraphics.RUN: 50, FcBroadcastGraphics.LEAD_CHANGE: 40, FcBroadcastGraphics.TIED: 30,
	FcBroadcastGraphics.BLOCK: 15, FcBroadcastGraphics.SCORE: 10}
const THREE_BONUS := 5
const CLUTCH_BONUS := 20
const LAST_BASKET_BONUS := 50


## Up to `count` highlights as [{"index", "score", "kind", "title", "detail"}], in game order.
static func select(timeline: FcBroadcastTimeline, count: int = DEFAULT_COUNT) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if timeline == null or timeline.is_empty() or count <= 0:
		return out
	var clutch := timeline.clutch_start_index()
	var last_basket := -1
	for e in timeline.model.entries:
		if int(e["type"]) == FcGameEventLog.EV_SHOT_MADE:
			last_basket = int(e["index"])
	var scored: Array[Dictionary] = []
	for i in timeline.size():
		var items := FcBroadcastGraphics.items_at(timeline, i)
		var best := 0
		var top: Dictionary = {}
		for item in items:
			var w: int = int(WEIGHT.get(item["kind"], 0))
			if w > best:
				best = w
				top = item
		if best == 0:
			continue
		var total := best
		if int(timeline.model.entries[i]["points"]) == 3:
			total += THREE_BONUS
		if clutch >= 0 and i >= clutch:
			total += CLUTCH_BONUS
		if i == last_basket:
			total += LAST_BASKET_BONUS
		scored.append({"index": i, "score": total, "kind": str(top["kind"]), "title": str(top["title"]), "detail": str(top["detail"])})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["score"]) > int(b["score"]) if int(a["score"]) != int(b["score"]) else int(a["index"]) < int(b["index"]))
	for candidate in scored:
		if out.size() >= count:
			break
		var apart := true
		for chosen in out:
			if absi(int(chosen["index"]) - int(candidate["index"])) < MIN_GAP:
				apart = false
				break
		if apart:
			out.append(candidate)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["index"]) < int(b["index"]))
	return out


## The highlight after (`direction` 1) or before (-1) event `index`; {} when there is none that way.
static func neighbor(highlights: Array, index: int, direction: int) -> Dictionary:
	if direction > 0:
		for h in highlights:
			if int(h["index"]) > index:
				return h
	else:
		for k in range(highlights.size() - 1, -1, -1):
			if int(highlights[k]["index"]) < index:
				return highlights[k]
	return {}
