class_name FcDate
extends RefCounted
## A calendar date in the game world (birth dates, contract signing dates...).
## Independent of the real-world clock. Saved as an ISO string "YYYY-MM-DD".

var year: int
var month: int
var day: int


func _init(y: int = 2000, m: int = 1, d: int = 1) -> void:
	year = y
	month = m
	day = d


static func is_leap_year(y: int) -> bool:
	return (y % 4 == 0 and y % 100 != 0) or y % 400 == 0


static func days_in_month(y: int, m: int) -> int:
	match m:
		1, 3, 5, 7, 8, 10, 12:
			return 31
		4, 6, 9, 11:
			return 30
		2:
			return 29 if is_leap_year(y) else 28
	return 0


func is_valid() -> bool:
	return month >= 1 and month <= 12 and day >= 1 and day <= days_in_month(year, month)


## -1 if this date is earlier than other, 0 if equal, 1 if later.
func compare_to(other: FcDate) -> int:
	if year != other.year:
		return -1 if year < other.year else 1
	if month != other.month:
		return -1 if month < other.month else 1
	if day != other.day:
		return -1 if day < other.day else 1
	return 0


func equals(other: FcDate) -> bool:
	return compare_to(other) == 0


func is_before(other: FcDate) -> bool:
	return compare_to(other) < 0


## Whole years from this date to `other` (e.g. a player's age on a given day).
func years_until(other: FcDate) -> int:
	var years := other.year - year
	if other.month < month or (other.month == month and other.day < day):
		years -= 1
	return years


func to_iso() -> String:
	return "%04d-%02d-%02d" % [year, month, day]


## Returns null if the text is not a valid date.
static func from_iso(text: String) -> FcDate:
	var parts := text.split("-")
	if parts.size() != 3:
		return null
	for p in parts:
		if not p.is_valid_int():
			return null
	var d := FcDate.new(int(parts[0]), int(parts[1]), int(parts[2]))
	return d if d.is_valid() else null
