class_name FcCrowdPlan
extends RefCounted
## Who sits where in the 3D crowd (Broadcast pass 2, M5): each fan's colour and size, decided by loyalty. The home side's fans mostly wear the
## home colour, the away fans sit in a block at one end, and the rest wear neutral colours; sizes vary a little so a section does not look cloned.
## Pure and deterministic (a seeded FcRng forked from the arena key), so the same game always has the same crowd. The scene applies it to its one
## MultiMesh; this class knows nothing about nodes.
##
## Sides, as in the scene: 0 near sideline, 1 far sideline, 2 left end, 3 right end. `along` is the fan's position along that side, 0 to 1.


## The chance that a fan at (side, along) supports the home team: the side's base share, with the away block taking the far part of its side.
static func home_share(identity: Dictionary, side: int, along: float) -> float:
	var shares: Array = identity["side_home_share"]
	var base := float(shares[clampi(side, 0, shares.size() - 1)])
	if side == 3 and along >= float(identity["away_block_from"]):
		return minf(base, float(identity["away_block_share"]))   # the travelling supporters' block
	return base


## {colors: Array[Color], scales: Array[float]} for fans described by parallel arrays of side and along.
static func plan(identity: Dictionary, sides: Array, alongs: Array) -> Dictionary:
	var rng := FcRng.new(hash(str(identity["key"])) & 0x7FFFFFFF).fork("crowd")
	var palette: Array = identity["neutral_palette"]
	var colors: Array[Color] = []
	var scales: Array[float] = []
	var lo := float(identity["scale_min"])
	var hi := float(identity["scale_max"])
	for i in sides.size():
		var side := int(sides[i])
		var along := float(alongs[i])
		var p_home := home_share(identity, side, along)
		var color: Color
		if rng.next_float() < p_home:
			color = identity["home_color"]
		elif _is_away_zone(side, along) and not rng.chance(float(identity["away_neutral_share"])):
			color = identity["away_color"]   # in the away fans' part of the arena most of the rest support the visitors
		else:
			color = palette[rng.range_int(0, palette.size() - 1)]
		colors.append(color.lightened(rng.range_float(-0.08, 0.12)) if rng.chance(0.5) else color)
		scales.append(rng.range_float(lo, hi))
	return {"colors": colors, "scales": scales}


## Where away fans sit: the whole right end (the away block is its far part) and the far corners of the sidelines next to it.
static func _is_away_zone(side: int, along: float) -> bool:
	return side == 3 or ((side == 0 or side == 1) and along > 0.75)


## The share of each colour group in a plan, for tests and tuning: {home, away, neutral} as fractions of all fans.
static func shares_of(identity: Dictionary, result: Dictionary) -> Dictionary:
	var colors: Array = result["colors"]
	var home := 0
	var away := 0
	for c in colors:
		if _close(c, identity["home_color"]):
			home += 1
		elif _close(c, identity["away_color"]):
			away += 1
	var n := float(maxi(1, colors.size()))
	return {"home": home / n, "away": away / n, "neutral": 1.0 - (home + away) / n}


static func _close(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.14 and absf(a.g - b.g) < 0.14 and absf(a.b - b.b) < 0.14
