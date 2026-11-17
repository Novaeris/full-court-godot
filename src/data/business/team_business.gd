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
## Cash the owner has taken out of the club over the years (dividends): the owner's own wealth.
var distributions: int = 0
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
## Practice facility and medical center levels (0-3): faster player development and faster
## injury recovery, at a yearly upkeep (see data/simulation/arena_projects.json).
var practice_level: int = 0
var medical_level: int = 0
## Sponsorship contracts signed by the owner: [{"sponsor": String, "amount": int a year,
## "bonus": int per playoff round won, "years_left": int}]. Each covers a share of the
## sponsorship income with a fixed payment (see data/simulation/finance.json).
var sponsor_deals: Array = []
## Concession prices as a percent of the normal level (70-150). Higher prices earn more
## per fan up to a point but cost fan interest.
var concession_price_pct: int = 100
## Playoff ticket prices as a percent of the regular price (100-300; the default 160 is what the
## league's teams charge). Playoff demand is higher than in the regular season, so a higher
## premium earns more until the arena stops selling out.
var playoff_premium_pct: int = 160
## Merchandise range: 0 limited, 1 standard (default, also the AI teams), 2 premium: more
## sales but a bigger stock cost (see data/simulation/finance.json).
var merch_tier: int = 1
const MERCH_TIERS := ["Limited", "Standard", "Premium"]


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
	if distributions < 0:
		errors.append("distributions cannot be negative")
	if valuation < 0:
		errors.append("valuation cannot be negative")
	if sponsor_plan < 0 or sponsor_plan > 2:
		errors.append("unknown sponsorship plan")
	return errors


func to_dict() -> Dictionary:
	return {
		"schema": SCHEMA_VERSION, "id": id, "ticket_price": ticket_price,
		"marketing_budget": marketing_budget, "facilities_level": facilities_level,
		"fan_interest": fan_interest, "brand": brand, "cash": cash, "debt": debt, "valuation": valuation, "distributions": distributions, "mid_level_used_season": mid_level_used_season, "sponsor_plan": sponsor_plan, "projects": projects.duplicate(true), "suites_level": suites_level, "practice_level": practice_level, "medical_level": medical_level, "sponsor_deals": sponsor_deals.duplicate(true), "concession_price_pct": concession_price_pct, "playoff_premium_pct": playoff_premium_pct, "merch_tier": merch_tier,
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
	b.distributions = maxi(0, int(d.get("distributions", 0)))
	b.mid_level_used_season = int(d.get("mid_level_used_season", 0))
	b.sponsor_plan = clampi(int(d.get("sponsor_plan", 0)), 0, 2)
	b.suites_level = int(d.get("suites_level", 0))
	b.practice_level = clampi(int(d.get("practice_level", 0)), 0, 3)
	b.medical_level = clampi(int(d.get("medical_level", 0)), 0, 3)
	for deal in d.get("sponsor_deals", []):
		b.sponsor_deals.append({"sponsor": str(deal["sponsor"]), "amount": int(deal["amount"]), "bonus": int(deal["bonus"]), "years_left": int(deal["years_left"])})
	b.concession_price_pct = clampi(int(d.get("concession_price_pct", 100)), 70, 150)
	b.playoff_premium_pct = clampi(int(d.get("playoff_premium_pct", 160)), 100, 300)
	b.merch_tier = clampi(int(d.get("merch_tier", 1)), 0, 2)
	for item in d.get("projects", []):
		b.projects.append({"key": str(item["key"]), "seasons_left": int(item["seasons_left"])})
	return b
