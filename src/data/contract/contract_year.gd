class_name FcContractYear
extends RefCounted
## One season of a contract. Money is whole dollars (int), never floats.
## A season is identified by the calendar year in which it starts (2026 means
## the 2026-27 season).
##
## Options: a PLAYER or TEAM option year only takes effect if exercised. A
## DECLINED option year is treated as not part of the contract.

enum OptionType { NONE = 0, PLAYER = 1, TEAM = 2 }
enum OptionStatus { UNDECIDED = 0, EXERCISED = 1, DECLINED = 2 }

var season: int = 2026
var salary: int = 0
## Portion of the salary the team owes even if the player is released.
var guaranteed: int = 0
var option_type: int = OptionType.NONE
var option_status: int = OptionStatus.UNDECIDED


func _init(season_year: int = 2026, salary_amount: int = 0, guaranteed_amount: int = -1) -> void:
	season = season_year
	salary = salary_amount
	guaranteed = salary_amount if guaranteed_amount < 0 else guaranteed_amount


## False only for a declined option year.
func is_in_effect() -> bool:
	return not (option_type != OptionType.NONE and option_status == OptionStatus.DECLINED)


func validate() -> Array[String]:
	var errors: Array[String] = []
	if season < 1800 or season > 2300:
		errors.append("contract season %d is out of range" % season)
	if salary < 0:
		errors.append("salary cannot be negative")
	if guaranteed < 0 or guaranteed > salary:
		errors.append("guaranteed money must be between 0 and the salary")
	if option_type < OptionType.NONE or option_type > OptionType.TEAM:
		errors.append("invalid option type")
	if option_status < OptionStatus.UNDECIDED or option_status > OptionStatus.DECLINED:
		errors.append("invalid option status")
	if option_type == OptionType.NONE and option_status != OptionStatus.UNDECIDED:
		errors.append("option status set on a year without an option")
	return errors


func to_dict() -> Dictionary:
	return {
		"season": season, "salary": salary, "guaranteed": guaranteed,
		"option_type": option_type, "option_status": option_status,
	}


static func from_dict(data: Dictionary) -> FcContractYear:
	var y := FcContractYear.new(int(data.get("season", 0)), int(data.get("salary", 0)), int(data.get("guaranteed", 0)))
	y.option_type = int(data.get("option_type", OptionType.NONE))
	y.option_status = int(data.get("option_status", OptionStatus.UNDECIDED))
	return y
