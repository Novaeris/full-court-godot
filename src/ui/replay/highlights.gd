class_name FcHighlights
extends RefCounted
## Highlight selection for a replay (master plan B6): which events of a game are worth jumping to. Pure and deterministic: it reads the broadcast
## timeline (recorded events only), scores every event by what the graphics already name (a lead change, a run, a milestone, a block, a
## three-pointer, a tie) with a bonus inside clutch time and for the last basket of the game, then keeps the best ones that are at least
## MIN_GAP events apart. Nothing is stored or changed; the same game always gives the same highlights, in game order.

const MIN_GAP := 8
const DEFAULT_COUNT := 8

## Up to `count` highlights as [{"index", "score", "importance", "kind", "title", "detail", "reasons"}], in game order. The scoring lives in
## FcImportanceModel (one source of truth for highlights, key-play marks, the reel and bookmarks).
static func select(timeline: FcBroadcastTimeline, count: int = DEFAULT_COUNT) -> Array[Dictionary]:
	if timeline == null or timeline.is_empty() or count <= 0:
		return []
	return FcImportanceModel.top(FcImportanceModel.scored(timeline), count, MIN_GAP)


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
