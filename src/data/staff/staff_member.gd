class_name FcStaffMember
extends RefCounted
## A coach, general manager, scout, medical or business executive as a stable
## entity. Mirrors FcPlayer's structure:
##   identity     (FcPersonIdentity)  who they are
##   skills       (FcAttributeSet)    professional skills (data-driven catalog)
##   personality  (FcAttributeSet)    off-court traits (same catalog as players)
##   philosophy   (FcAttributeSet)    how they like to run things (pace, youth focus...)
##
## NOT stored here: which team they work for and in what job. That is an
## FcStaffContract (by staff_id), so a person can change jobs and keep history.
## `primary_role` is the profession they are known for, used when browsing the
## hiring pool; the job they actually hold is on their contract.

const SCHEMA_VERSION := 1

enum Status { ACTIVE = 0, RETIRED = 1 }

var id: int
var status: int = Status.ACTIVE
## Season in which they retired; 0 while not retired.
var retired_season: int = 0
var primary_role: int = FcStaffRole.Id.ASSISTANT_COACH
## Standing in the basketball world, 0-100. Drives salary demands and who
## will take a job with whom.
var reputation: int = 50
## Years of professional experience.
var experience_years: int = 0

var identity := FcPersonIdentity.new()
var skills: FcAttributeSet
var personality: FcAttributeSet
var philosophy: FcAttributeSet


func _init(staff_id: int, defs: FcDefinitionSet) -> void:
	id = staff_id
	skills = FcAttributeSet.new(defs.staff_skills)
	personality = FcAttributeSet.new(defs.personality)
	philosophy = FcAttributeSet.new(defs.philosophy)


func age_on(date: FcDate) -> int:
	return identity.birth_date.years_until(date)


func validate() -> Array[String]:
	var errors: Array[String] = []
	if id <= 0:
		errors.append("staff id must be positive")
	errors.append_array(identity.validate())
	errors.append_array(skills.validate())
	errors.append_array(personality.validate())
	errors.append_array(philosophy.validate())
	if not FcStaffRole.is_valid(primary_role):
		errors.append("primary role is invalid")
	if reputation < 0 or reputation > 100:
		errors.append("reputation must be 0-100")
	if experience_years < 0 or experience_years > 60:
		errors.append("experience years must be 0-60")
	if status < Status.ACTIVE or status > Status.RETIRED:
		errors.append("invalid status %d" % status)
	elif status == Status.RETIRED and retired_season <= 0:
		errors.append("retired staff member needs a retirement season")
	elif status != Status.RETIRED and retired_season != 0:
		errors.append("only retired staff may have a retirement season")
	return errors


func to_dict() -> Dictionary:
	return {
		"schema": SCHEMA_VERSION, "id": id, "status": status,
		"retired_season": retired_season, "primary_role": primary_role,
		"reputation": reputation, "experience_years": experience_years,
		"identity": identity.to_dict(), "skills": skills.to_dict(),
		"personality": personality.to_dict(), "philosophy": philosophy.to_dict(),
	}


static func from_dict(data: Dictionary, defs: FcDefinitionSet) -> FcStaffMember:
	var s := FcStaffMember.new(int(data.get("id", 0)), defs)
	s.status = int(data.get("status", Status.ACTIVE))
	s.retired_season = int(data.get("retired_season", 0))
	s.primary_role = int(data.get("primary_role", FcStaffRole.Id.ASSISTANT_COACH))
	s.reputation = int(data.get("reputation", 50))
	s.experience_years = int(data.get("experience_years", 0))
	s.identity = FcPersonIdentity.from_dict(data.get("identity", {}))
	s.skills = FcAttributeSet.from_dict(defs.staff_skills, data.get("skills", {}))
	s.personality = FcAttributeSet.from_dict(defs.personality, data.get("personality", {}))
	s.philosophy = FcAttributeSet.from_dict(defs.philosophy, data.get("philosophy", {}))
	return s
