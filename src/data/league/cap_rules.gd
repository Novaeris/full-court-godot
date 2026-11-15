class_name FcCapRules
extends RefCounted
## Salary rules. The default is a SOFT CAP WITH A HARD LIMIT:
##
##   payroll
##   ──────────────────────────────────────────────  hard limit: NO team may ever exceed it
##   ...taxed zone...
##   ──────────────────────────────────────────────  luxury tax line: every dollar above is taxed
##   ...over the cap: only exceptions allowed...
##   ──────────────────────────────────────────────  soft cap: free agents need cap space below it
##   ...cap space...
##   ──────────────────────────────────────────────  minimum payroll: teams below must pay the gap
##
## Over the soft cap a team may still: re-sign its own players, use one
## mid-level exception, sign minimum contracts, and sign draft picks, but it
## can never cross the hard limit. This stops a rich team from signing
## everyone while still letting good teams keep their stars.
##
## cap_type:
##   "soft": as above (hard_limit 0 = no hard limit).
##   "hard": payroll may never exceed salary_cap; no exceptions.
##   "none": nothing is enforced except min/max salary and contract rules;
##           payroll above the tax line is taxed. salary_cap is then only a
##           reference size used for scaling and generation.
## Money is whole dollars. This class only ANSWERS rule questions; the
## free-agency and trade systems will call these checks.

const TYPES := ["soft", "hard", "none"]
enum SigningKind { CAP_SPACE = 0, OWN_PLAYER = 1, MID_LEVEL = 2, MINIMUM = 3, ROOKIE = 4 }

var cap_type: String = "soft"
var salary_cap: int = 140000000
## Payroll above this is taxed (0 = no tax).
var luxury_tax_line: int = 168000000
## Dollars of tax per dollar over the line, in percent (150 = $1.50 per $1).
var luxury_tax_rate_percent: int = 150
## Absolute payroll ceiling for "soft" leagues (0 = none).
var hard_limit: int = 189000000
## Teams below this must pay the shortfall to their players.
var minimum_payroll: int = 119000000
var min_player_salary: int = 1100000
var max_player_salary: int = 42000000
## Size of the single mid-level exception each team gets per season (0 = none).
var mid_level_exception: int = 12600000
## May a team exceed the cap to re-sign its own players?
var own_player_exception: bool = true
## May a team exceed the cap to sign minimum-salary players?
var minimum_contract_exception: bool = true
## Over-the-cap trades: incoming salary may be at most this % of outgoing (+$100k).
var trade_matching_percent: int = 125
var max_contract_years: int = 5
## Largest year-over-year raise inside a contract, in percent.
var max_annual_raise_percent: int = 8


## Payroll no team may exceed, or 0 if there is none.
func effective_limit() -> int:
	match cap_type:
		"hard":
			return salary_cap
		"soft":
			return hard_limit
	return 0


## "under_minimum", "under_cap", "over_cap", "over_tax" or "over_limit".
func payroll_tier(payroll: int) -> String:
	var limit := effective_limit()
	if limit > 0 and payroll > limit:
		return "over_limit"
	if luxury_tax_line > 0 and payroll > luxury_tax_line:
		return "over_tax"
	if payroll > salary_cap:
		return "over_cap"
	if payroll < minimum_payroll:
		return "under_minimum"
	return "under_cap"


func cap_space(payroll: int) -> int:
	return maxi(0, salary_cap - payroll)


func luxury_tax(payroll: int) -> int:
	if luxury_tax_line <= 0 or payroll <= luxury_tax_line:
		return 0
	return _percent_of(payroll - luxury_tax_line, luxury_tax_rate_percent)


## Money a team below the minimum payroll still owes its players.
func minimum_payroll_shortfall(payroll: int) -> int:
	return maxi(0, minimum_payroll - payroll)


## May a team with `payroll_before` sign a player at `salary` this way?
func check_signing(payroll_before: int, salary: int, kind: int) -> FcRuleCheck:
	if salary < min_player_salary:
		return FcRuleCheck.denied("below the minimum salary of %d" % min_player_salary)
	if salary > max_player_salary:
		return FcRuleCheck.denied("above the maximum salary of %d" % max_player_salary)
	var after := payroll_before + salary
	var limit := effective_limit()
	if limit > 0 and after > limit:
		return FcRuleCheck.denied("would put payroll over the %s of %d" % ["hard cap" if cap_type == "hard" else "hard limit", limit])
	if cap_type == "none":
		return FcRuleCheck.ok()
	match kind:
		SigningKind.CAP_SPACE:
			if after > salary_cap:
				return FcRuleCheck.denied("not enough cap space (payroll would be %d over a cap of %d)" % [after, salary_cap])
		SigningKind.OWN_PLAYER:
			if not own_player_exception:
				return FcRuleCheck.denied("this league has no own-player exception; cap space is required")
			if cap_type == "hard" and after > salary_cap:
				return FcRuleCheck.denied("would exceed the hard cap")
		SigningKind.MID_LEVEL:
			if cap_type == "hard" or mid_level_exception <= 0:
				return FcRuleCheck.denied("this league has no mid-level exception")
			if salary > mid_level_exception:
				return FcRuleCheck.denied("above the mid-level exception of %d" % mid_level_exception)
		SigningKind.MINIMUM:
			if cap_type == "hard" and after > salary_cap:
				return FcRuleCheck.denied("would exceed the hard cap")
			if not minimum_contract_exception:
				if after > salary_cap:
					return FcRuleCheck.denied("this league has no minimum-contract exception")
			elif salary != min_player_salary:
				return FcRuleCheck.denied("the minimum-contract exception only covers minimum salaries")
		SigningKind.ROOKIE:
			if cap_type == "hard" and after > salary_cap:
				return FcRuleCheck.denied("would exceed the hard cap")
	return FcRuleCheck.ok()


## May a team with `payroll_before` complete a trade that brings in
## `incoming` salary and sends out `outgoing`?
func check_trade(payroll_before: int, incoming: int, outgoing: int) -> FcRuleCheck:
	var after := payroll_before + incoming - outgoing
	var limit := effective_limit()
	if limit > 0 and after > limit and incoming > outgoing:
		return FcRuleCheck.denied("would put payroll over the limit of %d" % limit)
	if cap_type == "none" or after <= salary_cap or incoming <= outgoing:
		return FcRuleCheck.ok()
	if cap_type == "hard":
		return FcRuleCheck.denied("would put payroll over the hard cap")
	if incoming > _percent_of(outgoing, trade_matching_percent) + 100000:
		return FcRuleCheck.denied("over the cap: incoming salary may be at most %d%% of outgoing (+$100,000)" % trade_matching_percent)
	return FcRuleCheck.ok()


## Contract terms that break these rules (empty = fine).
func validate_contract(contract: FcContract) -> Array[String]:
	var errors: Array[String] = []
	var years := contract.effective_years()
	if years.size() > max_contract_years:
		errors.append("a contract may last at most %d years" % max_contract_years)
	for i in years.size():
		var s := years[i].salary
		if s < min_player_salary or s > max_player_salary:
			errors.append("salary %d in %d is outside %d-%d" % [s, years[i].season, min_player_salary, max_player_salary])
		if i > 0 and s > _percent_of(years[i - 1].salary, 100 + max_annual_raise_percent) + 10000:
			errors.append("raise into %d exceeds %d%%" % [years[i].season, max_annual_raise_percent])
	return errors


## Internal consistency of the rule set itself.
func validate() -> Array[String]:
	var errors: Array[String] = []
	if not TYPES.has(cap_type):
		errors.append("cap type must be one of %s" % str(TYPES))
		return errors
	if salary_cap <= 0:
		errors.append("salary cap must be positive")
		return errors
	if min_player_salary <= 0 or max_player_salary < min_player_salary:
		errors.append("player salary range is invalid")
	if cap_type != "none" and max_player_salary > salary_cap:
		errors.append("the maximum player salary cannot exceed the salary cap")
	if luxury_tax_line != 0 and luxury_tax_line < salary_cap:
		errors.append("the luxury tax line cannot be below the salary cap")
	if cap_type == "hard" and luxury_tax_line != 0:
		errors.append("a hard cap has no luxury tax (payroll can never exceed the cap)")
	if cap_type == "soft" and hard_limit != 0 and hard_limit < maxi(salary_cap, luxury_tax_line):
		errors.append("the hard limit cannot be below the cap or the tax line")
	if minimum_payroll < 0 or minimum_payroll > salary_cap:
		errors.append("the minimum payroll must be between 0 and the cap")
	if mid_level_exception < 0 or mid_level_exception > max_player_salary:
		errors.append("the mid-level exception must be between 0 and the maximum salary")
	if luxury_tax_rate_percent < 0 or luxury_tax_rate_percent > 500:
		errors.append("tax rate must be 0-500%")
	if trade_matching_percent < 100 or trade_matching_percent > 300:
		errors.append("trade matching must be 100-300%")
	if max_contract_years < 1 or max_contract_years > 7:
		errors.append("maximum contract length must be 1-7 years")
	if max_annual_raise_percent < 0 or max_annual_raise_percent > 30:
		errors.append("maximum annual raise must be 0-30%")
	return errors


func to_dict() -> Dictionary:
	return {
		"cap_type": cap_type, "salary_cap": salary_cap, "luxury_tax_line": luxury_tax_line,
		"luxury_tax_rate_percent": luxury_tax_rate_percent, "hard_limit": hard_limit,
		"minimum_payroll": minimum_payroll, "min_player_salary": min_player_salary,
		"max_player_salary": max_player_salary, "mid_level_exception": mid_level_exception,
		"own_player_exception": own_player_exception,
		"minimum_contract_exception": minimum_contract_exception,
		"trade_matching_percent": trade_matching_percent,
		"max_contract_years": max_contract_years,
		"max_annual_raise_percent": max_annual_raise_percent,
	}


static func from_dict(data: Dictionary) -> FcCapRules:
	var r := FcCapRules.new()
	r.cap_type = str(data.get("cap_type", r.cap_type))
	r.salary_cap = int(data.get("salary_cap", r.salary_cap))
	r.luxury_tax_line = int(data.get("luxury_tax_line", r.luxury_tax_line))
	r.luxury_tax_rate_percent = int(data.get("luxury_tax_rate_percent", r.luxury_tax_rate_percent))
	r.hard_limit = int(data.get("hard_limit", r.hard_limit))
	r.minimum_payroll = int(data.get("minimum_payroll", r.minimum_payroll))
	r.min_player_salary = int(data.get("min_player_salary", r.min_player_salary))
	r.max_player_salary = int(data.get("max_player_salary", r.max_player_salary))
	r.mid_level_exception = int(data.get("mid_level_exception", r.mid_level_exception))
	r.own_player_exception = bool(data.get("own_player_exception", r.own_player_exception))
	r.minimum_contract_exception = bool(data.get("minimum_contract_exception", r.minimum_contract_exception))
	r.trade_matching_percent = int(data.get("trade_matching_percent", r.trade_matching_percent))
	r.max_contract_years = int(data.get("max_contract_years", r.max_contract_years))
	r.max_annual_raise_percent = int(data.get("max_annual_raise_percent", r.max_annual_raise_percent))
	return r


## Builds a coherent rule set from a named preset (data/rules/cap_presets.json)
## and a cap size. Returns null if the preset does not exist.
static func from_preset(preset_name: String, cap: int, presets: Dictionary) -> FcCapRules:
	var p = presets.get("presets", {}).get(preset_name, null)
	if not (p is Dictionary):
		return null
	var r := FcCapRules.new()
	r.cap_type = str(p["cap_type"])
	r.salary_cap = cap
	r.luxury_tax_line = _money(cap * float(p["tax_ratio"]))
	r.luxury_tax_rate_percent = int(p["tax_rate_percent"])
	r.hard_limit = _money(cap * float(p["hard_ratio"]))
	r.minimum_payroll = _money(cap * float(p["floor_ratio"]))
	r.min_player_salary = _money(cap * float(p["min_salary_ratio"]))
	r.max_player_salary = _money(cap * float(p["max_salary_ratio"]))
	r.mid_level_exception = _money(cap * float(p["mid_level_ratio"]))
	r.own_player_exception = bool(p["own_player_exception"])
	r.minimum_contract_exception = bool(p["minimum_contract_exception"])
	r.trade_matching_percent = int(p["trade_matching_percent"])
	return r


static func load_presets() -> Dictionary:
	var file := FileAccess.open("res://data/rules/cap_presets.json", FileAccess.READ)
	if file == null:
		return {}
	var parsed = FcChecks.parse_json(file.get_as_text())
	return parsed if parsed is Dictionary else {}


## amount x percent / 100, without integer-division surprises.
static func _percent_of(amount: int, percent: int) -> int:
	return floori(float(amount) * percent / 100.0)


## Rounds to the nearest $10,000.
static func _money(amount: float) -> int:
	return roundi(amount / 10000.0) * 10000
