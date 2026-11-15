class_name FcStaffGenerator
extends RefCounted
## Generates one staff member for a role. Skills are centered on `level`;
## skills the role is about are boosted and all others lowered, so a head coach
## is strong at coaching and weaker at scouting or finance. Profiles live in
## data/generation/staff_profiles.json.

const ROLE_KEYS := {
	FcStaffRole.Id.GENERAL_MANAGER: "general_manager",
	FcStaffRole.Id.HEAD_COACH: "head_coach",
	FcStaffRole.Id.ASSISTANT_COACH: "assistant_coach",
	FcStaffRole.Id.SCOUT: "scout",
	FcStaffRole.Id.MEDICAL: "medical",
	FcStaffRole.Id.BUSINESS_EXECUTIVE: "business_executive",
}

var _data: FcGenerationData
var _defs: FcDefinitionSet
var _names: FcNameGenerator


func _init(data: FcGenerationData, defs: FcDefinitionSet) -> void:
	_data = data
	_defs = defs
	_names = FcNameGenerator.new(data)


func _profile(role: int) -> Dictionary:
	return _data.staff["roles"][ROLE_KEYS[role]]


## Yearly pay for a role at a given reputation (0-100); whole dollars.
func salary_for(role: int, reputation: int) -> int:
	var profile := _profile(role)
	var t := pow(clampf(reputation / 100.0, 0.0, 1.0), 2.0)
	var raw := lerpf(float(profile["salary_min"]), float(profile["salary_max"]), t)
	return roundi(raw / 10000.0) * 10000


func generate(rng: FcRng, id: int, role: int, level: float, reference_date: FcDate,
		used_names: Dictionary = {}, country_key: String = "") -> FcStaffMember:
	var s := FcStaffMember.new(id, _defs)
	var profile := _profile(role)
	var lvl := clampf(level, 0.0, 99.0)

	var key := country_key if country_key != "" else _names.home_country()
	var nm := _names.generate_unique(rng, key, used_names)
	s.identity.first_name = nm["first"]
	s.identity.last_name = nm["last"]
	s.identity.country = _names.country_name(key)

	var age_min := int(profile["age_min"])
	var age_max := int(profile["age_max"])
	var age := clampi(roundi(rng.gaussian((age_min + age_max) / 2.0, (age_max - age_min) / 5.0)), age_min, age_max)
	s.identity.birth_date = FcPlayerGenerator.birth_date_for_age(rng, age, reference_date)
	s.primary_role = role
	s.experience_years = clampi(roundi(age - rng.gaussian(30.0, 3.0)), 0, 60)
	s.reputation = clampi(roundi(lvl + rng.gaussian(0.0, 8.0)), 5, 99)

	var category_boosts: Dictionary = profile["category_boosts"]
	var skill_boosts: Dictionary = profile["skill_boosts"]
	var penalty := float(_data.staff.get("off_role_penalty", -12))
	for skill_key in _defs.staff_skills.keys():
		var def := _defs.staff_skills.get_def(skill_key)
		var adjust := penalty
		if skill_boosts.has(skill_key):
			adjust = float(skill_boosts[skill_key])
		elif category_boosts.has(def.category):
			adjust = float(category_boosts[def.category])
		s.skills.set_clamped(skill_key, clampi(roundi(lvl + adjust + rng.gaussian(0.0, 9.0)), 5, 99))

	for k in _defs.personality.keys():
		s.personality.set_clamped(k, roundi(rng.gaussian(50.0, 18.0)))
	for k in _defs.philosophy.keys():
		s.philosophy.set_clamped(k, roundi(rng.gaussian(50.0, 22.0)))
	return s
