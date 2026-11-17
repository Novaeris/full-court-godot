class_name FcCapRules
extends RefCounted
## Salary rules. The default is a SOFT CAP WITH A HARD LIMIT:
##
##   payroll
##   ──────────────────────────────────────────────  hard limit: NO team may ever exceed it
##   ...restricted zone: exceptions unavailable, trades must match salaries 1-for-1...
##   ──────────────────────────────────────────────  restriction line
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
##
## EXTRA RULES (each can be switched off by setting it to 0 / false):
##   tax sharing        the collected luxury tax is paid out to teams under the cap
##   repeater tax       a higher tax rate for teams that pay tax year after year
##   restriction line   above it a team loses its exception and must match trade salaries
##   rookie scale       a fixed pay scale for draft picks by pick number
##   cornerstone ext.   one long-tenured star per team may earn more than the normal maximum
##   cap holds          unsigned own free agents still count against the cap space
##   sign-and-trade     restricted for teams above the restriction/tax line
##   no-trade clauses   a player with one must consent to a trade
##
## Money is whole dollars. This class only ANSWERS rule questions; the
## free-agency, trade and draft systems will call these checks.
## All terms here are our own or generic; none are copied branding.

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

## Share of the collected luxury tax paid out, split equally among teams at or
## under the cap (0 = the league keeps it all).
var tax_distribution_percent: int = 100
## Extra tax rate (percentage points) for repeat taxpayers (0 = no repeater tax).
var repeater_tax_extra_percent: int = 100
## A team is a repeat taxpayer if it paid tax in at least this many of the last 4 seasons.
var repeater_years_required: int = 3
## Payroll line between the tax line and the hard limit (0 = none).
var restriction_line: int = 177000000
## Rookie scale: first-year salary of the first and the last draft pick.
var rookie_scale_top: int = 11200000
var rookie_scale_bottom: int = 1100000
var rookie_contract_years: int = 4
## Seasons of a rookie contract that are guaranteed; later ones are team options.
var rookie_guaranteed_years: int = 2
## Cornerstone extension: a star who has spent enough seasons with his team may
## sign a contract up to this salary (above the normal maximum).
var cornerstone_enabled: bool = true
var cornerstone_max_salary: int = 49000000
var cornerstone_min_seasons_with_team: int = 6
var cornerstone_max_per_team: int = 1
var cap_holds_enabled: bool = true
## An unsigned own free agent counts this % of his previous salary against the cap.
var cap_hold_percent: int = 120
var sign_and_trade_allowed: bool = true
var no_trade_clauses_allowed: bool = true
## Seasons with a team before a player can be given a no-trade clause.
var no_trade_min_seasons_with_team: int = 8


## Payroll no team may exceed, or 0 if there is none.
## Multiplies every money amount of the cap system by `factor` (rounded to $10,000): the cap, the
## tax line, the hard limit, salary floors and ceilings, exceptions, the rookie scale. Used when
## the owners vote the cap up or down.
func scale_money(factor: float) -> void:
	salary_cap = _scaled(salary_cap, factor)
	luxury_tax_line = _scaled(luxury_tax_line, factor)
	hard_limit = _scaled(hard_limit, factor)
	minimum_payroll = _scaled(minimum_payroll, factor)
	min_player_salary = _scaled(min_player_salary, factor)
	max_player_salary = _scaled(max_player_salary, factor)
	mid_level_exception = _scaled(mid_level_exception, factor)
	restriction_line = _scaled(restriction_line, factor)
	rookie_scale_top = _scaled(rookie_scale_top, factor)
	rookie_scale_bottom = _scaled(rookie_scale_bottom, factor)
	cornerstone_max_salary = _scaled(cornerstone_max_salary, factor)


func _scaled(amount: int, factor: float) -> int:
	return int(roundi(amount * factor / 10000.0)) * 10000 if amount > 0 else amount


func effective_limit() -> int:
	match cap_type:
		"hard":
			return salary_cap
		"soft":
			return hard_limit
	return 0


## "under_minimum", "under_cap", "over_cap", "over_tax", "over_restriction" or "over_limit".
func payroll_tier(payroll: int) -> String:
	var limit := effective_limit()
	if limit > 0 and payroll > limit:
		return "over_limit"
	if restriction_line > 0 and payroll > restriction_line:
		return "over_restriction"
	if luxury_tax_line > 0 and payroll > luxury_tax_line:
		return "over_tax"
	if payroll > salary_cap:
		return "over_cap"
	if payroll < minimum_payroll:
		return "under_minimum"
	return "under_cap"


func cap_space(payroll: int) -> int:
	return maxi(0, salary_cap - payroll)


## Luxury tax owed. `tax_seasons_in_last_four` = how many of the previous four
## seasons the team already paid tax (for the repeater rate).
func luxury_tax(payroll: int, tax_seasons_in_last_four: int = 0) -> int:
	if luxury_tax_line <= 0 or payroll <= luxury_tax_line:
		return 0
	return _percent_of(payroll - luxury_tax_line, tax_rate_for(tax_seasons_in_last_four))


## The tax rate (percent) a team pays given its recent tax history.
func tax_rate_for(tax_seasons_in_last_four: int) -> int:
	if repeater_tax_extra_percent > 0 and tax_seasons_in_last_four >= repeater_years_required:
		return luxury_tax_rate_percent + repeater_tax_extra_percent
	return luxury_tax_rate_percent


## Pays out the luxury tax. `payrolls` maps team id -> payroll; `repeat_counts`
## (optional) maps team id -> tax seasons in the last four.
## Returns {"collected": int, "distributed": int, "retained": int, "payouts": {team id: dollars}}.
## Eligible teams are those at or under the cap; each gets an equal share of
## `tax_distribution_percent` of the tax. Money that cannot be split (or when
## nobody is eligible) is retained by the league.
func distribute_luxury_tax(payrolls: Dictionary, repeat_counts: Dictionary = {}) -> Dictionary:
	var collected := 0
	var eligible: Array[int] = []
	for tid in payrolls:
		collected += luxury_tax(int(payrolls[tid]), int(repeat_counts.get(tid, 0)))
		if int(payrolls[tid]) <= salary_cap:
			eligible.append(int(tid))
	eligible.sort()
	var pool := _percent_of(collected, tax_distribution_percent)
	var payouts := {}
	var distributed := 0
	if not eligible.is_empty() and pool > 0:
		var share := floori(float(pool) / eligible.size())
		for tid in eligible:
			payouts[tid] = share
		distributed = share * eligible.size()
	return {"collected": collected, "distributed": distributed, "retained": collected - distributed, "payouts": payouts}


## Money a team below the minimum payroll still owes its players.
func minimum_payroll_shortfall(payroll: int) -> int:
	return maxi(0, minimum_payroll - payroll)


## First-year salary of a draft pick (1 = first pick) in a draft of
## `total_picks`. The scale falls smoothly from rookie_scale_top to
## rookie_scale_bottom, rounded to $10,000.
func rookie_salary(pick: int, total_picks: int) -> int:
	if total_picks <= 1 or pick <= 1:
		return rookie_scale_top
	var p := clampi(pick, 1, total_picks)
	var t := float(p - 1) / float(total_picks - 1)
	var ratio := float(rookie_scale_bottom) / float(rookie_scale_top)
	return clampi(_money(rookie_scale_top * pow(ratio, t)), min_player_salary, max_player_salary)


## May a team sign a cornerstone extension? `seasons_with_team` is the
## player's tenure; `has_accolade` is whether he met the performance
## criterion (e.g. an award; the awards system will supply it);
## `current_cornerstones` is how many the team already has.
func check_cornerstone_extension(seasons_with_team: int, has_accolade: bool, current_cornerstones: int, salary: int) -> FcRuleCheck:
	if not cornerstone_enabled:
		return FcRuleCheck.denied("this league has no cornerstone extension")
	if seasons_with_team < cornerstone_min_seasons_with_team:
		return FcRuleCheck.denied("needs at least %d seasons with the team" % cornerstone_min_seasons_with_team)
	if not has_accolade:
		return FcRuleCheck.denied("the player has not met the performance criterion")
	if current_cornerstones >= cornerstone_max_per_team:
		return FcRuleCheck.denied("the team already has %d cornerstone contract%s" % [cornerstone_max_per_team, "" if cornerstone_max_per_team == 1 else "s"])
	if salary > cornerstone_max_salary:
		return FcRuleCheck.denied("above the cornerstone maximum of %d" % cornerstone_max_salary)
	return FcRuleCheck.ok()


## The cap hold left on the books for an unsigned own free agent.
func cap_hold_amount(previous_salary: int) -> int:
	if not cap_holds_enabled:
		return 0
	return clampi(_percent_of(previous_salary, cap_hold_percent), min_player_salary, max_player_salary)


## May a team with this payroll receive a player through a sign-and-trade?
func check_sign_and_trade(receiving_payroll: int) -> FcRuleCheck:
	if not sign_and_trade_allowed:
		return FcRuleCheck.denied("sign-and-trade deals are not allowed in this league")
	var line := restriction_line if restriction_line > 0 else luxury_tax_line
	if line > 0 and receiving_payroll > line:
		return FcRuleCheck.denied("a team above %d cannot receive a sign-and-trade player" % line)
	return FcRuleCheck.ok()


## Can this player be given a no-trade clause?
func can_grant_no_trade(seasons_with_team: int) -> bool:
	return no_trade_clauses_allowed and seasons_with_team >= no_trade_min_seasons_with_team


## Does trading this contract need the player's consent?
func trade_requires_consent(contract: FcContract) -> bool:
	return no_trade_clauses_allowed and contract.no_trade


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
			if restriction_line > 0 and payroll_before >= restriction_line:
				return FcRuleCheck.denied("above the restriction line of %d the mid-level exception is unavailable" % restriction_line)
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
	if restriction_line > 0 and after > restriction_line:
		return FcRuleCheck.denied("above the restriction line of %d a team may not take back more salary than it sends out" % restriction_line)
	if incoming > _percent_of(outgoing, trade_matching_percent) + 100000:
		return FcRuleCheck.denied("over the cap: incoming salary may be at most %d%% of outgoing (+$100,000)" % trade_matching_percent)
	return FcRuleCheck.ok()


## Contract terms that break these rules (empty = fine).
func validate_contract(contract: FcContract) -> Array[String]:
	var errors: Array[String] = []
	var years := contract.effective_years()
	var salary_ceiling := max_player_salary
	if contract.is_cornerstone:
		if not cornerstone_enabled:
			errors.append("this league has no cornerstone extension")
		else:
			salary_ceiling = cornerstone_max_salary
	if contract.no_trade and not no_trade_clauses_allowed:
		errors.append("this league does not allow no-trade clauses")
	if years.size() > max_contract_years:
		errors.append("a contract may last at most %d years" % max_contract_years)
	for i in years.size():
		var s := years[i].salary
		if s < min_player_salary or s > salary_ceiling:
			errors.append("salary %d in %d is outside %d-%d" % [s, years[i].season, min_player_salary, salary_ceiling])
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
	# extra rules
	if tax_distribution_percent < 0 or tax_distribution_percent > 100:
		errors.append("tax distribution must be 0-100%")
	if repeater_tax_extra_percent < 0 or repeater_tax_extra_percent > 500:
		errors.append("repeater tax extra rate must be 0-500%")
	if repeater_tax_extra_percent > 0 and (repeater_years_required < 1 or repeater_years_required > 4):
		errors.append("repeater tax applies after 1-4 tax seasons out of the last 4")
	if restriction_line != 0:
		var floor_line := maxi(salary_cap, luxury_tax_line)
		if restriction_line < floor_line:
			errors.append("the restriction line cannot be below the cap or the tax line")
		if effective_limit() > 0 and restriction_line > effective_limit():
			errors.append("the restriction line cannot be above the hard limit")
	if rookie_scale_top < rookie_scale_bottom or rookie_scale_bottom < min_player_salary or rookie_scale_top > max_player_salary:
		errors.append("the rookie scale must run from the first pick down to at least the minimum salary, and not above the maximum")
	if rookie_contract_years < 1 or rookie_contract_years > max_contract_years:
		errors.append("rookie contract length must be 1 to the maximum contract length")
	if rookie_guaranteed_years < 0 or rookie_guaranteed_years > rookie_contract_years:
		errors.append("guaranteed rookie years cannot exceed the rookie contract length")
	if cornerstone_enabled:
		if cornerstone_max_salary <= max_player_salary:
			errors.append("the cornerstone maximum must be above the normal maximum salary")
		if cap_type != "none" and cornerstone_max_salary > salary_cap:
			errors.append("the cornerstone maximum cannot exceed the salary cap")
		if effective_limit() > 0 and cornerstone_max_salary > effective_limit():
			errors.append("the cornerstone maximum cannot exceed the hard limit")
		if cornerstone_min_seasons_with_team < 1 or cornerstone_max_per_team < 1:
			errors.append("cornerstone tenure and per-team limits must be at least 1")
	if cap_hold_percent < 0 or cap_hold_percent > 300:
		errors.append("cap hold must be 0-300% of the previous salary")
	if no_trade_min_seasons_with_team < 0:
		errors.append("no-trade tenure cannot be negative")
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
		"tax_distribution_percent": tax_distribution_percent,
		"repeater_tax_extra_percent": repeater_tax_extra_percent,
		"repeater_years_required": repeater_years_required,
		"restriction_line": restriction_line,
		"rookie_scale_top": rookie_scale_top, "rookie_scale_bottom": rookie_scale_bottom,
		"rookie_contract_years": rookie_contract_years,
		"rookie_guaranteed_years": rookie_guaranteed_years,
		"cornerstone_enabled": cornerstone_enabled,
		"cornerstone_max_salary": cornerstone_max_salary,
		"cornerstone_min_seasons_with_team": cornerstone_min_seasons_with_team,
		"cornerstone_max_per_team": cornerstone_max_per_team,
		"cap_holds_enabled": cap_holds_enabled, "cap_hold_percent": cap_hold_percent,
		"sign_and_trade_allowed": sign_and_trade_allowed,
		"no_trade_clauses_allowed": no_trade_clauses_allowed,
		"no_trade_min_seasons_with_team": no_trade_min_seasons_with_team,
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
	# Rules added later: a save made before them gets everything switched OFF
	# (so loading an old league never changes how it plays).
	r.tax_distribution_percent = int(data.get("tax_distribution_percent", 0))
	r.repeater_tax_extra_percent = int(data.get("repeater_tax_extra_percent", 0))
	r.repeater_years_required = int(data.get("repeater_years_required", 3))
	r.restriction_line = int(data.get("restriction_line", 0))
	r.rookie_scale_top = int(data.get("rookie_scale_top", r.min_player_salary))
	r.rookie_scale_bottom = int(data.get("rookie_scale_bottom", r.min_player_salary))
	r.rookie_contract_years = int(data.get("rookie_contract_years", 1))
	r.rookie_guaranteed_years = int(data.get("rookie_guaranteed_years", 1))
	r.cornerstone_enabled = bool(data.get("cornerstone_enabled", false))
	r.cornerstone_max_salary = int(data.get("cornerstone_max_salary", r.max_player_salary))
	r.cornerstone_min_seasons_with_team = int(data.get("cornerstone_min_seasons_with_team", 6))
	r.cornerstone_max_per_team = int(data.get("cornerstone_max_per_team", 1))
	r.cap_holds_enabled = bool(data.get("cap_holds_enabled", false))
	r.cap_hold_percent = int(data.get("cap_hold_percent", 120))
	r.sign_and_trade_allowed = bool(data.get("sign_and_trade_allowed", true))
	r.no_trade_clauses_allowed = bool(data.get("no_trade_clauses_allowed", false))
	r.no_trade_min_seasons_with_team = int(data.get("no_trade_min_seasons_with_team", 8))
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
	r.tax_distribution_percent = int(p.get("tax_distribution_percent", 0))
	r.repeater_tax_extra_percent = int(p.get("repeater_tax_extra_percent", 0))
	r.repeater_years_required = int(p.get("repeater_years_required", 3))
	r.restriction_line = _money(cap * float(p.get("restriction_ratio", 0.0)))
	r.rookie_scale_top = _money(cap * float(p.get("rookie_top_ratio", 0.08)))
	r.rookie_scale_bottom = maxi(r.min_player_salary, _money(cap * float(p.get("rookie_bottom_ratio", 0.008))))
	r.rookie_contract_years = int(p.get("rookie_contract_years", 4))
	r.rookie_guaranteed_years = int(p.get("rookie_guaranteed_years", 2))
	r.cornerstone_enabled = bool(p.get("cornerstone_enabled", false))
	r.cornerstone_max_salary = _money(cap * float(p.get("cornerstone_ratio", 0.35)))
	r.cornerstone_min_seasons_with_team = int(p.get("cornerstone_min_seasons", 6))
	r.cornerstone_max_per_team = int(p.get("cornerstone_max_per_team", 1))
	r.cap_holds_enabled = bool(p.get("cap_holds_enabled", false))
	r.cap_hold_percent = int(p.get("cap_hold_percent", 120))
	r.sign_and_trade_allowed = bool(p.get("sign_and_trade_allowed", true))
	r.no_trade_clauses_allowed = bool(p.get("no_trade_clauses_allowed", false))
	r.no_trade_min_seasons_with_team = int(p.get("no_trade_min_seasons", 8))
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
