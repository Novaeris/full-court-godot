class_name FcTeamBusiness
extends RefCounted
## The business side of one franchise (its id equals the team id). These are
## the things an owner controls or that build up over the years: ticket price,
## marketing budget, arena facilities, fan interest, brand, cash and debt.
## Season-by-season results are FcFinanceRecord entries.

const SCHEMA_VERSION := 1

var id: int
## Average ticket price in dollars.
var ticket_price: int = 95
## Yearly marketing spend in dollars.
var marketing_budget: int = 8000000
## Arena quality 0-100: raises demand and concessions, but costs upkeep and decays.
var facilities_level: int = 50
## How much the city cares about the team, 0-100 (follows winning).
var fan_interest: int = 50
## The team's brand strength, 0-100 (drives merchandise and sponsors).
var brand: int = 50
var cash: int = 40000000
var debt: int = 0
var valuation: int = 0
## Season in which the mid-level exception was last used (0 = never); it can be used once a season.
var mid_level_used_season: int = 0
## Sponsorship deal style (owner choice): 0 balanced (default, also used by AI teams),
## 1 steady (smaller guaranteed money, ignores results), 2 performance (smaller base,
## pays much more for winning and playoff success).
var sponsor_plan: int = 0
const SPONSOR_PLANS := ["Balanced", "Steady", "Performance"]
## Arena projects under way: [{"key": String, "seasons_left": int}, ...] (see data/simulation/arena_projects.json).
var projects: Array = []
## Levels of luxury suites built (each raises arena event income).
var suites_level: int = 0


func _init(team_id: int = 0) -> void:
	id = team_id


func validate() -> Array[String]:
	var errors: Array[String] = []
	if id <= 0:
		errors.append("business id must be the team id (positive)")
	if ticket_price < 1 or ticket_price > 5000:
		errors.append("ticket price %d is out of range" % ticket_price)
	if marketing_budget < 0:
		errors.append("marketing budget cannot be negative")
	for pair in [["facilities", facilities_level], ["fan interest", fan_interest], ["brand", brand]]:
		if pair[1] < 0 or pair[1] > 100:
			errors.append("%s must be 0-100" % pair[0])
	if cash < 0 or debt < 0:
		errors.append("cash and debt cannot be negative (a shortfall becomes debt)")
	if valuation < 0:
		errors.append("valuation cannot be negative")
	if sponsor_plan < 0 or sponsor_plan > 2:
		errors.append("unknown sponsorship plan")
	return errors


func to_dict() -> Dictionary:
	return {
		"schema": SCHEMA_VERSION, "id": id, "ticket_price": ticket_price,
		"marketing_budget": marketing_budget, "facilities_level": facilities_level,
		"fan_interest": fan_interest, "brand": brand, "cash": cash, "debt": debt, "valuation": valuation, "mid_level_used_season": mid_level_used_season, "sponsor_plan": sponsor_plan, "projects": projects.duplicate(true), "suites_level": suites_level,
	}


static func from_dict(d: Dictionary) -> FcTeamBusiness:
	var b := FcTeamBusiness.new(int(d.get("id", 0)))
	b.ticket_price = int(d.get("ticket_price", b.ticket_price))
	b.marketing_budget = int(d.get("marketing_budget", b.marketing_budget))
	b.facilities_level = int(d.get("facilities_level", b.facilities_level))
	b.fan_interest = int(d.get("fan_interest", b.fan_interest))
	b.brand = int(d.get("brand", b.brand))
	b.cash = int(d.get("cash", b.cash))
	b.debt = int(d.get("debt", b.debt))
	b.valuation = int(d.get("valuation", b.valuation))
	b.mid_level_used_season = int(d.get("mid_level_used_season", 0))
	b.sponsor_plan = clampi(int(d.get("sponsor_plan", 0)), 0, 2)
	b.suites_level = int(d.get("suites_level", 0))
	for item in d.get("projects", []):
		b.projects.append({"key": str(item["key"]), "seasons_left": int(item["seasons_left"])})
	return b
