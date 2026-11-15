class_name FcStaffRole
extends RefCounted
## The jobs a staff member can hold with a team. Stored as integers in saves;
## never renumber. The set of roles is small and closed (game rules refer to
## them directly), unlike skills which are data-driven.

enum Id {
	NONE = 0,
	GENERAL_MANAGER = 1,
	HEAD_COACH = 2,
	ASSISTANT_COACH = 3,
	SCOUT = 4,
	MEDICAL = 5,
	BUSINESS_EXECUTIVE = 6,
}

const NAMES := {
	0: "None", 1: "General Manager", 2: "Head Coach", 3: "Assistant Coach",
	4: "Scout", 5: "Medical Staff", 6: "Business Executive",
}

## A team can have at most one active staff member in each of these roles.
const UNIQUE_PER_TEAM := [Id.GENERAL_MANAGER, Id.HEAD_COACH]


static func is_valid(value: int) -> bool:
	return value >= Id.GENERAL_MANAGER and value <= Id.BUSINESS_EXECUTIVE


static func display_name(value: int) -> String:
	return NAMES.get(value, "?")


static func is_unique_per_team(value: int) -> bool:
	return UNIQUE_PER_TEAM.has(value)
