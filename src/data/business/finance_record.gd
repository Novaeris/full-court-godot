class_name FcFinanceRecord
extends RefCounted
## One team's financial results for one season. Money is whole dollars.

const SCHEMA_VERSION := 1
const REVENUE_KEYS := ["tickets", "playoffs", "concessions", "merchandise", "sponsorship",
	"broadcasting", "arena_events", "tax_share", "revenue_sharing"]
const EXPENSE_KEYS := ["payroll", "luxury_tax", "staff", "arena_operations", "marketing",
	"travel", "administration", "facilities", "interest", "revenue_sharing", "merchandise_stock", "promotions"]

var id: int
var team_id: int = 0
var year: int = 0
var revenue: Dictionary = {}
var expenses: Dictionary = {}
var wins: int = 0
var losses: int = 0
var playoff_rounds_won: int = 0
var average_attendance: int = 0
var capacity: int = 0
var ticket_price: int = 0
var fan_interest_end: int = 0
var brand_end: int = 0
var cash_end: int = 0
var debt_end: int = 0
var valuation_end: int = 0
## Debt written off by lenders in a restructuring after this season (not part of revenue or expenses, so profit() is
## the operating profit).
var restructuring_writeoff: int = 0
## Whether the team paid luxury tax this season (used for the repeater tax).
var paid_tax: bool = false


func _init(record_id: int = 0) -> void:
	id = record_id
	for k in REVENUE_KEYS:
		revenue[k] = 0
	for k in EXPENSE_KEYS:
		expenses[k] = 0


func total_revenue() -> int:
	var t := 0
	for k in revenue:
		t += int(revenue[k])
	return t


func total_expenses() -> int:
	var t := 0
	for k in expenses:
		t += int(expenses[k])
	return t


func profit() -> int:
	return total_revenue() - total_expenses()


func sellout_rate() -> float:
	return float(average_attendance) / capacity if capacity > 0 else 0.0


func validate() -> Array[String]:
	var errors: Array[String] = []
	if id <= 0 or team_id <= 0:
		errors.append("finance record needs ids")
	for k in revenue:
		if int(revenue[k]) < 0:
			errors.append("negative revenue line %s" % k)
	for k in expenses:
		if int(expenses[k]) < 0:
			errors.append("negative expense line %s" % k)
	if average_attendance < 0 or (capacity > 0 and average_attendance > capacity):
		errors.append("attendance cannot exceed arena capacity")
	return errors


func to_dict() -> Dictionary:
	return {
		"schema": SCHEMA_VERSION, "id": id, "team_id": team_id, "year": year,
		"revenue": revenue.duplicate(), "expenses": expenses.duplicate(),
		"wins": wins, "losses": losses, "playoff_rounds_won": playoff_rounds_won,
		"average_attendance": average_attendance, "capacity": capacity, "ticket_price": ticket_price,
		"fan_interest_end": fan_interest_end, "brand_end": brand_end, "cash_end": cash_end,
		"debt_end": debt_end, "valuation_end": valuation_end, "paid_tax": paid_tax, "restructuring_writeoff": restructuring_writeoff,
	}


static func from_dict(d: Dictionary) -> FcFinanceRecord:
	var r := FcFinanceRecord.new(int(d.get("id", 0)))
	r.team_id = int(d.get("team_id", 0))
	r.year = int(d.get("year", 0))
	for k in d.get("revenue", {}):
		r.revenue[str(k)] = int(d["revenue"][k])
	for k in d.get("expenses", {}):
		r.expenses[str(k)] = int(d["expenses"][k])
	for key in ["wins", "losses", "playoff_rounds_won", "average_attendance", "capacity", "ticket_price",
			"fan_interest_end", "brand_end", "cash_end", "debt_end", "valuation_end"]:
		r.set(key, int(d.get(key, 0)))
	r.paid_tax = bool(d.get("paid_tax", false))
	r.restructuring_writeoff = maxi(0, int(d.get("restructuring_writeoff", 0)))
	return r
