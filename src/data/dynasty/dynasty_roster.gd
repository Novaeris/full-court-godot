class_name FcDynastyRoster
extends RefCounted
## The 13-card roster of a Dynasty team: 5 starters (slots 0-4: PG, SG, SF, PF, C), 7 bench (5-11, in rotation order) and
## 1 reserve (12). Cards are stored by stable card_id only. `minutes` is the rotation setting per slot:
## -1 fewer minutes, 0 normal, +1 more (the simulation's own minutes preference, see FcSimPlayer).

const SIZE := 13
const STARTERS := 5
const BENCH_END := 12
const SLOT_POSITIONS := [1, 2, 3, 4, 5]  # FcPosition.Id of the starter slots

var slots: Array = []
var minutes: Array = []


func _init() -> void:
	clear()


func clear() -> void:
	slots = []
	minutes = []
	for i in SIZE:
		slots.append("")
		minutes.append(0)


static func slot_name(index: int) -> String:
	if index < STARTERS:
		return "Starter %s" % FcPosition.abbreviation(SLOT_POSITIONS[index])
	if index < BENCH_END:
		return "Bench %d" % (index - STARTERS + 1)
	return "Reserve"


func filled_count() -> int:
	var n := 0
	for s in slots:
		if str(s) != "":
			n += 1
	return n


func slot_of(card_id: String) -> int:
	return slots.find(card_id)


func card_ids() -> Array[String]:
	var out: Array[String] = []
	for s in slots:
		if str(s) != "":
			out.append(str(s))
	return out


func to_dict() -> Dictionary:
	return {"slots": slots.duplicate(), "minutes": minutes.duplicate()}


static func from_dict(data: Dictionary) -> FcDynastyRoster:
	var r := FcDynastyRoster.new()
	var s = data.get("slots", [])
	var m = data.get("minutes", [])
	for i in SIZE:
		r.slots[i] = str(s[i]) if s is Array and i < s.size() else ""
		r.minutes[i] = clampi(int(m[i]), -1, 1) if m is Array and i < m.size() else 0
	return r
