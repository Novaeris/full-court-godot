class_name FcPlayerProgression
extends RefCounted
## Yearly player development, decline and retirement. Run once per offseason.
##
## Growth: until his peak age a player moves toward his potential: each year he
## gains about (potential - overall) / (years left until the peak) overall
## points, scaled by his development rate, work ethic and his coaches' skill at
## player development. Decline: after the peak he loses ground every year,
## physical attributes first and fastest, mental ones last. Every attribute also
## gets random noise (more for volatile players), so two players with the same
## profile do not age identically.
## All numbers are in data/simulation/progression.json.

const DATA_PATH := "res://data/simulation/progression.json"

var _cfg: Dictionary
var _ratings: FcPlayerRatings
var _catalog: FcAttributeCatalog


func _init(defs: FcDefinitionSet, ratings: FcPlayerRatings) -> void:
	_ratings = ratings
	_catalog = defs.attributes
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	var parsed = FcChecks.parse_json(file.get_as_text()) if file != null else null
	_cfg = parsed if parsed is Dictionary else {}


## Changes the player's attributes for one year of aging. `age` is his age at
## the start of the new season; `coach_development` is the average player-
## development skill (0-100) of his team's coaches (50 = neutral).
## Returns {"before": overall, "after": overall}.
func progress(player: FcPlayer, age: int, coach_development: float, rng: FcRng) -> Dictionary:
	var before := _ratings.overall(player)
	var dev := player.development
	var growth_points := 0.0
	var decline_points := 0.0
	if age <= dev.peak_age:
		var years_left := dev.peak_age - age + 1
		growth_points = clampf((dev.potential - before) / years_left, 0.0, float(_cfg["growth_cap"]))
		growth_points *= dev.development_rate
		growth_points *= 1.0 + (coach_development - 50.0) / 50.0 * float(_cfg["coach_effect"])
		growth_points *= 1.0 + (player.attributes.get_value("work_ethic") - 50.0) / 50.0 * float(_cfg["work_ethic_effect"])
	else:
		decline_points = (age - dev.peak_age) * float(_cfg["decline_per_year"])
		var late := maxi(0, age - int(_cfg["late_decline_after_age"]))
		decline_points *= 1.0 + late * float(_cfg["late_decline_extra"])
	var noise_sd := float(_cfg["noise_base"]) + dev.volatility * float(_cfg["noise_volatility"])
	for key in _catalog.keys():
		var category := _catalog.get_def(key).category
		var delta := 0.0
		if growth_points > 0.0:
			delta = growth_points * float(_cfg["category_growth"].get(category, 1.0))
		elif decline_points > 0.0:
			var factor := float(_cfg["category_decline"].get(category, 1.0))
			if category == "physical":
				# physical decline starts earlier: treat the player as older for it
				var shifted := age + int(_cfg["physical_decline_age_shift"]) - dev.peak_age
				factor *= 1.0 + maxf(0.0, shifted - (age - dev.peak_age)) * 0.1
			delta = -decline_points * factor
		delta += rng.gaussian(0.0, noise_sd)
		player.attributes.set_clamped(key, player.attributes.get_value(key) + roundi(delta))
	var after := _ratings.overall(player)
	# Potential can never be below what the player already is.
	dev.potential = maxi(dev.potential, clampi(roundi(after), 0, 100))
	if age > dev.peak_age:
		dev.potential = clampi(roundi(after), 0, 100)
	return {"before": before, "after": after}


## Chance (0-1) that the player retires after this season.
func retirement_chance(age: int, overall: float) -> float:
	if age >= int(_cfg["retire_forced_age"]):
		return 1.0
	var start := int(_cfg["retire_start_age"])
	if age < start:
		return 0.0
	var chance := (age - start + 1) * float(_cfg["retire_per_year"])
	if overall < float(_cfg["retire_low_overall_below"]):
		chance += float(_cfg["retire_low_overall_bonus"])
	return clampf(chance, 0.0, 1.0)


func should_retire(player: FcPlayer, age: int, rng: FcRng) -> bool:
	return rng.chance(retirement_chance(age, _ratings.overall(player)))
