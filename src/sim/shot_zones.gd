class_name FcShotZones
extends RefCounted
## The court zones of a shot chart, in one place for the simulation (which records where a shot was taken) and the UI (which colours the
## zones). Coordinates are metres on a half court seen from above: x across (0 to 15, the left sideline to the right one), y out from the
## baseline (0 to 14). The basket is at (7.5, 1.575). Measurements follow common international court markings (three-point arc 6.75 m,
## corner lines 0.9 m from the sidelines, paint 4.9 m wide and 5.8 m deep, restricted arc 1.25 m); they are geometry, not anyone's brand.
## Pure: no UI, no randomness. Zone ids are saved data (shot spots, M2 of D-077): never rename one.

const WIDTH := 15.0
const DEPTH := 14.0
const HOOP := Vector2(7.5, 1.575)
const THREE_RADIUS := 6.75
const CORNER_X := 0.9
const PAINT_HALF_WIDTH := 2.45
const PAINT_DEPTH := 5.8
const RIM_RADIUS := 1.25

const RIM := "rim"
const PAINT := "paint"
const MID_LEFT := "mid_left"
const MID_CENTER := "mid_center"
const MID_RIGHT := "mid_right"
const CORNER3_LEFT := "corner3_left"
const CORNER3_RIGHT := "corner3_right"
const WING3_LEFT := "wing3_left"
const WING3_RIGHT := "wing3_right"
const TOP3 := "top3"

## Every zone, in display order, with its name.
const ZONES := [
	[RIM, "At the rim"], [PAINT, "Paint"], [MID_LEFT, "Mid-range left"], [MID_CENTER, "Mid-range centre"], [MID_RIGHT, "Mid-range right"],
	[CORNER3_LEFT, "Left corner three"], [WING3_LEFT, "Left wing three"], [TOP3, "Top of the key three"], [WING3_RIGHT, "Right wing three"],
	[CORNER3_RIGHT, "Right corner three"],
]


static func ids() -> Array[String]:
	var out: Array[String] = []
	for z in ZONES:
		out.append(str(z[0]))
	return out


static func display_name(zone_id: String) -> String:
	for z in ZONES:
		if z[0] == zone_id:
			return str(z[1])
	return zone_id


## True when a spot is behind the three-point line (corner lines and arc).
static func is_three(spot: Vector2) -> bool:
	if spot.x <= CORNER_X or spot.x >= WIDTH - CORNER_X:
		return true
	return spot.distance_to(HOOP) >= THREE_RADIUS and spot.y > HOOP.y


## The zone of a spot (metres). Spots off the half court are clamped onto it.
static func zone_of(spot: Vector2) -> String:
	var p := Vector2(clampf(spot.x, 0.0, WIDTH), clampf(spot.y, 0.0, DEPTH))
	if is_three(p):
		var corner_depth := HOOP.y + sqrt(maxf(0.0, THREE_RADIUS * THREE_RADIUS - (HOOP.x - CORNER_X) * (HOOP.x - CORNER_X)))
		if p.y <= corner_depth:
			return CORNER3_LEFT if p.x < HOOP.x else CORNER3_RIGHT
		var angle := rad_to_deg(atan2(p.y - HOOP.y, p.x - HOOP.x))   # 0 = to the right, 90 = straight out
		if angle < 60.0:
			return WING3_RIGHT
		if angle > 120.0:
			return WING3_LEFT
		return TOP3
	if p.distance_to(HOOP) <= RIM_RADIUS:
		return RIM
	if absf(p.x - HOOP.x) <= PAINT_HALF_WIDTH and p.y <= PAINT_DEPTH:
		return PAINT
	if p.x < HOOP.x - PAINT_HALF_WIDTH:
		return MID_LEFT
	if p.x > HOOP.x + PAINT_HALF_WIDTH:
		return MID_RIGHT
	return MID_CENTER


## The shot kind of the simulation (FcGameEventLog.SHOT_THREE, SHOT_MID, SHOT_RIM) a zone belongs to.
static func shot_type_of(zone_id: String) -> int:
	match zone_id:
		RIM, PAINT:
			return FcGameEventLog.SHOT_RIM
		CORNER3_LEFT, CORNER3_RIGHT, WING3_LEFT, WING3_RIGHT, TOP3:
			return FcGameEventLog.SHOT_THREE
	return FcGameEventLog.SHOT_MID
