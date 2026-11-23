class_name FcSpotlightModel
extends RefCounted
## The player spotlight at an event (Broadcast pass 2, M2): who the broadcast puts a card on and what the card says. Pure: the player is the
## one named by the recorded event (the scorer, the blocker, the milestone player) and every number is the running line from
## FcBroadcastTimeline.player_line, which the unit tests compare with the box score. A spotlight shows for the graphic kinds listed in
## data/ui/broadcast_identity.json; other events give {}.
##
## Result: {player_id, name, number (display number, 0 = none), position, side, stats [[label, value]], kind}.


static func at(timeline: FcBroadcastTimeline, index: int) -> Dictionary:
	if timeline == null or timeline.is_empty():
		return {}
	index = clampi(index, 0, timeline.size() - 1)
	var top := FcBroadcastGraphics.top_item_at(timeline, index)
	if top.is_empty() or not (str(top["kind"]) in FcBroadcastStyle.spotlight_kinds()):
		return {}
	var e: Dictionary = timeline.model.entries[index]
	var pid := 0
	match str(top["kind"]):
		FcBroadcastGraphics.SCORE:
			pid = int(e["a"])
		FcBroadcastGraphics.BLOCK:
			pid = int(e["b"])
		FcBroadcastGraphics.MILESTONE:
			var m: Dictionary = timeline.snapshot(index)["milestone"]
			pid = int(m.get("player_id", 0))
	if pid == 0:
		return {}
	var box := timeline.model.box
	var found = null
	for p in box.players:
		if p.player_id == pid:
			found = p
			break
	if found == null:
		return {}
	var line := timeline.player_line(index, pid)
	var stats: Array = []
	for field in FcBroadcastStyle.spotlight_stats():
		stats.append([str(field[1]), int(line.get(str(field[0]), 0))])
	return {"player_id": pid, "name": FcPlayByPlay.short_name(found.name), "number": int(FcJerseyNumbers.for_box(box).get(pid, 0)),
		"position": FcPosition.abbreviation(found.position), "side": int(top["side"]) if int(top["side"]) >= 0 else int(e["side"]), "stats": stats, "kind": str(top["kind"])}


## The card's one-line stat text, "12 PTS  ·  4 REB  ·  3 AST".
static func stat_text(spotlight: Dictionary) -> String:
	var parts: Array[String] = []
	for s in spotlight.get("stats", []):
		parts.append("%d %s" % [int(s[1]), str(s[0])])
	return "  ·  ".join(parts)
