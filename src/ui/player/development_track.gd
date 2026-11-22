class_name FcDevelopmentTrack
extends Control
## A player's development as a timeline: the ages 18 to 38 as a bar in three zones (growing, prime, declining), a marker for the age NOW and a
## flag for the expected peak, with the overall now and the potential written under it. It draws only the numbers it is given (age, peak age,
## overall, potential: the same values the "outlook" lines already show), and the whole picture is also the tooltip text, so the shape is never
## the only carrier of meaning. The prime is the peak age plus or minus three seasons; nothing here is a forecast the game does not already make.

const FIRST_AGE := 18
const LAST_AGE := 38

var age: int = 0
var peak_age: int = 0
var overall: int = 0
var potential: int = 0


func _init() -> void:
	custom_minimum_size = Vector2(260, 78)
	mouse_filter = Control.MOUSE_FILTER_PASS


func setup(player_age: int, peak: int, overall_now: int, potential_now: int) -> FcDevelopmentTrack:
	age = player_age
	peak_age = peak
	overall = overall_now
	potential = potential_now
	tooltip_text = summary()
	queue_redraw()
	return self


## The picture in words.
func summary() -> String:
	var phase := "still growing" if age < peak_age - 3 else ("in his prime" if age <= peak_age + 3 else "past his prime")
	return "Age %d (%s). Expected to peak at %d. Overall %d, potential %d." % [age, phase, peak_age, overall, potential]


func _x(a: float, width: float) -> float:
	return clampf((a - FIRST_AGE) / float(LAST_AGE - FIRST_AGE), 0.0, 1.0) * width


func _draw() -> void:
	var pad := 8.0
	var width := size.x - pad * 2.0
	var bar := Rect2(pad, 26.0, width, 12.0)
	var prime_from := float(peak_age - 3)
	var prime_to := float(peak_age + 3)
	var zones := [
		[float(FIRST_AGE), prime_from, FcUiTokens.INFO.darkened(0.25)],
		[prime_from, prime_to, FcUiTokens.SUCCESS],
		[prime_to, float(LAST_AGE), FcUiTokens.TEXT_MUTED.darkened(0.35)],
	]
	for z in zones:
		var x0 := pad + _x(z[0], width)
		var x1 := pad + _x(z[1], width)
		if x1 > x0:
			draw_rect(Rect2(x0, bar.position.y, x1 - x0, bar.size.y), z[2])
	var font := ThemeDB.fallback_font
	for tick in [18, 22, 26, 30, 34, 38]:
		var tx := pad + _x(float(tick), width)
		draw_line(Vector2(tx, bar.end.y), Vector2(tx, bar.end.y + 4.0), FcUiTokens.TEXT_MUTED, 1.0)
		draw_string(font, Vector2(tx - 6.0, bar.end.y + 16.0), str(tick), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, FcUiTokens.TEXT_MUTED)
	# the expected peak: a thin flag above the bar
	var px := pad + _x(float(peak_age), width)
	draw_line(Vector2(px, 14.0), Vector2(px, bar.position.y), FcUiTokens.SUCCESS, 2.0)
	draw_string(font, Vector2(px + 4.0, 22.0), "peak %d" % peak_age, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, FcUiTokens.SUCCESS)
	# the age now: a marker that crosses the bar
	var ax := pad + _x(float(age), width)
	draw_circle(Vector2(ax, bar.position.y + bar.size.y / 2.0), 8.0, FcUiTokens.TEXT)
	draw_circle(Vector2(ax, bar.position.y + bar.size.y / 2.0), 5.0, FcUiTokens.BG)
	draw_string(font, Vector2(clampf(ax - 14.0, 0.0, size.x - 44.0), size.y - 6.0), "now %d" % age, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, FcUiTokens.TEXT)
