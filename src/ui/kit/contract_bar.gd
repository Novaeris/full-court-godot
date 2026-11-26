class_name FcContractBar
extends Control
## A contract year by year: one column per season, its height the salary (scaled to the largest year, or to a given maximum so several
## contracts compare), labelled with the season and the amount. The current season is highlighted, past seasons are faded, and option years
## are hatched with "PO" (player option) or "TO" (team option) written on them. Built from FcContract years; it changes nothing.

## [{"season": int, "salary": int, "option": "" | "PO" | "TO", "guaranteed": bool}]
var years: Array = []
var current_season: int = 0
## The salary that fills a column; 0 = the largest year of this contract.
var scale_max: int = 0


func _init() -> void:
	custom_minimum_size = Vector2(220, 96)
	mouse_filter = Control.MOUSE_FILTER_PASS


func setup(year_list: Array, season_now: int, max_salary: int = 0) -> FcContractBar:
	years = year_list
	current_season = season_now
	scale_max = max_salary
	tooltip_text = summary()
	queue_redraw()
	return self


## From a FcContract (option years marked from its FcContractYear option types).
static func years_of(contract: FcContract) -> Array:
	var out: Array = []
	if contract == null:
		return out
	for y in contract.effective_years():
		var option := ""
		if y.option_type == FcContractYear.OptionType.PLAYER:
			option = "PO"
		elif y.option_type == FcContractYear.OptionType.TEAM:
			option = "TO"
		out.append({"season": y.season, "salary": y.salary, "option": option, "guaranteed": y.guaranteed >= y.salary})
	return out


## "2026-27 $12.0M, 2027-28 $12.6M (team option)".
func summary() -> String:
	var parts: Array = []
	for y in years:
		var t := "%d-%02d %s" % [int(y["season"]), (int(y["season"]) + 1) % 100, FcUiTables.money(int(y["salary"]))]
		match str(y.get("option", "")):
			"PO": t += " (player option)"
			"TO": t += " (team option)"
		parts.append(t)
	return ", ".join(parts) if not parts.is_empty() else "No contract"


func _draw() -> void:
	var body := FcUiFonts.body(500, true)
	if body == null:
		body = ThemeDB.fallback_font
	var micro := FcUiTokens.fs(FcUiTokens.TYPE_MICRO)
	if years.is_empty():
		draw_string(body, Vector2(0, size.y * 0.5), "No contract", HORIZONTAL_ALIGNMENT_LEFT, size.x, FcUiTokens.fs(FcUiTokens.TYPE_SMALL), FcUiTokens.TEXT_MUTED)
		return
	var top := 0
	for y in years:
		top = maxi(top, int(y["salary"]))
	if scale_max > 0:
		top = maxi(top, scale_max)
	var n := years.size()
	var gap := 6.0
	var col_w := (size.x - gap * (n - 1)) / float(n)
	var bar_area := size.y - 36.0
	for i in n:
		var y: Dictionary = years[i]
		var season := int(y["season"])
		var h := maxf(4.0, bar_area * float(y["salary"]) / float(maxi(1, top)))
		var x := i * (col_w + gap)
		var rect := Rect2(Vector2(x, 16 + bar_area - h), Vector2(col_w, h))
		var c := FcUiTokens.PRIMARY if season == current_season else FcUiTokens.STEEL
		var alpha := 0.35 if season < current_season else 0.85
		draw_rect(rect, Color(c, alpha))
		var option := str(y.get("option", ""))
		if option != "":
			var stripe := Color(FcUiTokens.BG, 0.45)
			var sx := rect.position.x - rect.size.y
			while sx < rect.end.x:
				var a := Vector2(maxf(sx, rect.position.x), rect.end.y - maxf(0.0, rect.position.x - sx))
				var b := Vector2(minf(sx + rect.size.y, rect.end.x), rect.position.y + maxf(0.0, sx + rect.size.y - rect.end.x))
				draw_line(a, b, stripe, 2.0)
				sx += 8.0
			draw_string(body, Vector2(rect.position.x, rect.position.y + micro + 2), option, HORIZONTAL_ALIGNMENT_CENTER, col_w, micro, FcUiTokens.TEXT)
		draw_string(body, Vector2(x, 12), FcUiTables.money(int(y["salary"])), HORIZONTAL_ALIGNMENT_CENTER, col_w, micro, FcUiTokens.TEXT if season >= current_season else FcUiTokens.TEXT_MUTED)
		draw_string(body, Vector2(x, size.y - 4), "%d-%02d" % [season, (season + 1) % 100], HORIZONTAL_ALIGNMENT_CENTER, col_w, micro, FcUiTokens.TEXT_MUTED)
