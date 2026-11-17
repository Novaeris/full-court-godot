class_name FcStaffChemistry
extends RefCounted
## How well a team's staff works together (Owner Mode). The data was already there: every staff member
## has a coaching/management philosophy and personality. Chemistry (0-100) has four parts:
##   AGREEMENT   do the general manager, head coach and assistants want the same things (pace, threes,
##               defense, ball movement, youth, stars, risk)? Measured as the philosophy distance.
##   PERSONALITY teamwork of each person (professionalism, adaptability, not too much ego); two big egos
##               in one office clash.
##   ROSTER FIT  does the head coach's philosophy suit the players he has (their three-point habits, how
##               young the roster is)?
##   CONTINUITY  staff who have worked together for years know each other.
## Chemistry moves player development: every point above or below 60 changes the coaching level by
## DEVELOPMENT_PER_POINT (see FcOffseason). Everything is derived, nothing is saved.

const WEIGHTS := {"agreement": 0.35, "personality": 0.25, "roster_fit": 0.25, "continuity": 0.15}
## A philosophy distance of 0 is 100 points, and each point of average difference costs this much.
const DISTANCE_COST := 1.8
const EGO_CLASH_LEVEL := 70
const EGO_CLASH_COST := 12.0
const CONTINUITY_BASE := 40.0
const CONTINUITY_PER_YEAR := 15.0
const DEVELOPMENT_PER_POINT := 0.15
const NEUTRAL := 60.0
const PHILOSOPHY_KEYS := ["pace_preference", "three_point_emphasis", "defensive_aggression", "ball_movement", "youth_focus", "star_reliance", "risk_tolerance"]

var world: FcWorld


func _init(game_world: FcWorld) -> void:
	world = game_world


## The chemistry of a team's staff in `year`. `replace` optionally swaps one person in for a preview of a hire:
## {"role": FcStaffRole.Id, "staff_id": int} (a unique role is replaced, other roles are added).
## Returns {"score": int, "label": String, "parts": [{"key", "name", "value", "note"}], "development_bonus": float}.
func evaluate(team_id: int, year: int, replace: Dictionary = {}) -> Dictionary:
	var people := _people(team_id, year, replace)
	var gm: FcStaffMember = _in_role(people, FcStaffRole.Id.GENERAL_MANAGER)
	var coach: FcStaffMember = _in_role(people, FcStaffRole.Id.HEAD_COACH)
	var assistants: Array = people.filter(func(p): return p["role"] == FcStaffRole.Id.ASSISTANT_COACH)
	var parts: Array = []
	parts.append(_agreement(gm, coach, assistants))
	parts.append(_personality(people))
	parts.append(_roster_fit(coach, team_id, year))
	parts.append(_continuity(people))
	var total := 0.0
	for part in parts:
		total += float(WEIGHTS[part["key"]]) * float(part["value"])
	var score := clampi(roundi(total), 0, 100)
	return {"score": score, "label": label_for(score), "parts": parts, "development_bonus": development_bonus(score)}


static func label_for(score: int) -> String:
	if score >= 80:
		return "Excellent"
	if score >= 65:
		return "Good"
	if score >= 50:
		return "Average"
	if score >= 35:
		return "Poor"
	return "Toxic"


## Coaching-level points added to player development by a chemistry score (negative when it is poor).
static func development_bonus(score: int) -> float:
	return (float(score) - NEUTRAL) * DEVELOPMENT_PER_POINT


func _people(team_id: int, year: int, replace: Dictionary) -> Array:
	var out: Array = []
	for sc in world.staff_contracts_of_team(team_id):
		if replace.has("role") and FcStaffRole.is_unique_per_team(int(replace["role"])) and sc.role == int(replace["role"]):
			continue
		var m: FcStaffMember = world.staff.get_by_id(sc.staff_id)
		if m != null:
			out.append({"role": sc.role, "member": m, "years": maxi(0, year - sc.signed_on.year)})
	if replace.has("staff_id"):
		var hired: FcStaffMember = world.staff.get_by_id(int(replace["staff_id"]))
		if hired != null:
			out.append({"role": int(replace["role"]), "member": hired, "years": 0})
	return out


func _in_role(people: Array, role: int) -> FcStaffMember:
	for p in people:
		if p["role"] == role:
			return p["member"]
	return null


func _distance(a: FcStaffMember, b: FcStaffMember) -> float:
	var total := 0.0
	for key in PHILOSOPHY_KEYS:
		total += absf(float(a.philosophy.get_value(key)) - float(b.philosophy.get_value(key)))
	return total / PHILOSOPHY_KEYS.size()


func _agreement(gm: FcStaffMember, coach: FcStaffMember, assistants: Array) -> Dictionary:
	var distances: Array[float] = []
	if gm != null and coach != null:
		distances.append(_distance(gm, coach))
	if coach != null and not assistants.is_empty():
		var d := 0.0
		for a in assistants:
			d += _distance(coach, a["member"])
		distances.append(d / assistants.size())
	if distances.is_empty():
		return {"key": "agreement", "name": "Agreement on how to play", "value": 50.0, "note": "Not enough staff to compare."}
	var mean := 0.0
	for d in distances:
		mean += d
	mean /= distances.size()
	var value := clampf(100.0 - DISTANCE_COST * mean, 0.0, 100.0)
	return {"key": "agreement", "name": "Agreement on how to play", "value": value,
		"note": "The general manager, head coach and assistants differ by %.0f points on average on pace, threes, defense, passing, youth, stars and risk." % mean}


func _personality(people: Array) -> Dictionary:
	if people.is_empty():
		return {"key": "personality", "name": "Personalities", "value": 50.0, "note": "No staff."}
	var total := 0.0
	var big_egos := 0
	for p in people:
		var m: FcStaffMember = p["member"]
		total += 0.4 * m.personality.get_value("professionalism") + 0.3 * m.personality.get_value("adaptability") + 0.3 * (100.0 - m.personality.get_value("ego"))
		if m.personality.get_value("ego") >= EGO_CLASH_LEVEL:
			big_egos += 1
	var clashes := big_egos * (big_egos - 1) / 2
	var value := clampf(total / people.size() - EGO_CLASH_COST * clashes, 0.0, 100.0)
	var note := "Professional and flexible people work well together."
	if clashes > 0:
		note = "%d people with very big egos in one office: they clash." % big_egos
	return {"key": "personality", "name": "Personalities", "value": value, "note": note}


func _roster_fit(coach: FcStaffMember, team_id: int, year: int) -> Dictionary:
	if coach == null:
		return {"key": "roster_fit", "name": "Coach and roster fit", "value": 50.0, "note": "No head coach."}
	var team: FcTeam = world.teams.get_by_id(team_id)
	var three := 0.0
	var young := 0
	var count := 0
	for pid in team.roster.player_ids:
		var p: FcPlayer = world.players.get_by_id(pid)
		three += p.tendencies.get_value("three_point_tendency")
		if p.age_on(FcDate.new(year, 7, 1)) <= 24:
			young += 1
		count += 1
	if count == 0:
		return {"key": "roster_fit", "name": "Coach and roster fit", "value": 50.0, "note": "No players."}
	var three_gap := absf(float(coach.philosophy.get_value("three_point_emphasis")) - three / count)
	var young_gap := absf(float(coach.philosophy.get_value("youth_focus")) - minf(100.0, 200.0 * young / count))
	var value := clampf(100.0 - (three_gap + young_gap) / 2.0 * 1.5, 0.0, 100.0)
	return {"key": "roster_fit", "name": "Coach and roster fit", "value": value,
		"note": "The head coach's taste for threes is %.0f points from what the players do, and for youth %.0f points from the roster's age." % [three_gap, young_gap]}


func _continuity(people: Array) -> Dictionary:
	if people.is_empty():
		return {"key": "continuity", "name": "Years together", "value": CONTINUITY_BASE, "note": "No staff."}
	var years := 0.0
	for p in people:
		years += float(p["years"])
	years /= people.size()
	return {"key": "continuity", "name": "Years together", "value": clampf(CONTINUITY_BASE + CONTINUITY_PER_YEAR * years, 0.0, 100.0),
		"note": "The staff have worked together for %.1f years on average." % years}
