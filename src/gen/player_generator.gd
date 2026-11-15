class_name FcPlayerGenerator
extends RefCounted
## Generates one believable player from an FcPlayerSpec.
##
## How it works (so results are coherent, not random noise):
##  - Body size comes from the position profile (centers are taller, guards
##    lighter) with natural spread; weight follows height; wingspan follows height.
##  - Each attribute = overall level + position offset + a shared "latent" for
##    its category + individual noise. The latents (skill, athleticism, IQ) make
##    a player who is athletic in one physical area likely athletic in others.
##  - Tendencies blend what the player is good at with his position's habits.
##  - Potential grows with the years left before his peak age.
## Position profiles live in data/generation/position_profiles.json.

const NOISE_SD := 7.0
const MIN_ATTRIBUTE := 5
const MAX_ATTRIBUTE := 99

## Which attributes a tendency follows (the rest of the tendency is the
## position's habit plus noise). Tendencies not listed here are position + noise.
const TENDENCY_SOURCES := {
	"three_point_tendency": ["three_point"],
	"mid_range_tendency": ["mid_range"],
	"drive_tendency": ["ball_handling", "speed"],
	"post_tendency": ["strength", "close_finishing"],
	"pass_tendency": ["passing"],
	"gamble_tendency": ["steals"],
	"offensive_rebound_tendency": ["rebounding"],
}

const CATEGORY_LATENT := {"offensive": "skill", "defensive": "skill", "physical": "athleticism", "mental": "iq"}

## The positions a player can reasonably also play.
const ADJACENT_POSITIONS := {
	FcPosition.Id.PG: [FcPosition.Id.SG],
	FcPosition.Id.SG: [FcPosition.Id.PG, FcPosition.Id.SF],
	FcPosition.Id.SF: [FcPosition.Id.SG, FcPosition.Id.PF],
	FcPosition.Id.PF: [FcPosition.Id.SF, FcPosition.Id.C],
	FcPosition.Id.C: [FcPosition.Id.PF],
}

var _data: FcGenerationData
var _defs: FcDefinitionSet
var _names: FcNameGenerator


func _init(data: FcGenerationData, defs: FcDefinitionSet) -> void:
	_data = data
	_defs = defs
	_names = FcNameGenerator.new(data)


## Young players have not reached their ability yet and old players decline.
## Takes a "prime" level and returns the player's level at `age`.
static func age_adjusted_level(level: float, age: int) -> float:
	if age < 24:
		return level - (24 - age) * 2.0
	if age > 31:
		return level - (age - 31) * 1.8
	return level


## A birth date such that the person is exactly `age` on `reference`.
## Birth days are limited to 1-28 so every month is valid.
static func birth_date_for_age(rng: FcRng, age: int, reference: FcDate) -> FcDate:
	var month := rng.range_int(1, 12)
	var day := rng.range_int(1, 28)
	var year := reference.year - age
	if month > reference.month or (month == reference.month and day > reference.day):
		year -= 1
	return FcDate.new(year, month, day)


func generate(rng: FcRng, id: int, spec: FcPlayerSpec) -> FcPlayer:
	var p := FcPlayer.new(id, _defs)
	var level := clampf(spec.level, 0.0, 99.0)
	var profile: Dictionary = _data.positions["positions"][FcPosition.abbreviation(spec.position)]
	var offsets: Dictionary = profile["offsets"]
	var tendency_offsets: Dictionary = profile["tendency_offsets"]

	# Identity
	var country_key := spec.country_key if spec.country_key != "" else _names.home_country()
	var nm := _names.generate_unique(rng, country_key, spec.used_names)
	p.identity.first_name = nm["first"]
	p.identity.last_name = nm["last"]
	p.identity.country = _names.country_name(country_key)
	p.identity.birth_date = birth_date_for_age(rng, spec.age, spec.reference_date)

	# Positions
	p.primary_position = spec.position
	if rng.chance(0.55):
		var options: Array = ADJACENT_POSITIONS[spec.position]
		p.secondary_position = options[rng.range_int(0, options.size() - 1)]

	# Body
	var height := clampi(roundi(rng.gaussian(float(profile["height_mean"]), float(profile["height_sd"]))), 170, 235)
	var bmi := clampf(rng.gaussian(float(profile["bmi_mean"]), 1.2), 20.0, 32.0)
	p.physical.height_cm = height
	p.physical.weight_kg = roundi(bmi * pow(height / 100.0, 2.0))
	p.physical.wingspan_cm = clampi(height + roundi(rng.gaussian(6.0, 4.0)), height - 3, height + 20)
	var hand_roll := rng.next_float()
	p.physical.handedness = FcPlayerPhysical.Handedness.RIGHT if hand_roll < 0.88 \
		else (FcPlayerPhysical.Handedness.LEFT if hand_roll < 0.98 else FcPlayerPhysical.Handedness.BOTH)

	# Basketball attributes
	var latents := {
		"skill": rng.gaussian(0.0, 5.0),
		"athleticism": rng.gaussian(0.0, 6.0),
		"iq": rng.gaussian(0.0, 6.0),
	}
	for key in _defs.attributes.keys():
		var def := _defs.attributes.get_def(key)
		var latent: float = latents[CATEGORY_LATENT.get(def.category, "skill")]
		var value := level + float(offsets.get(key, 0.0)) + latent + rng.gaussian(0.0, NOISE_SD)
		p.attributes.set_clamped(key, clampi(roundi(value), MIN_ATTRIBUTE, MAX_ATTRIBUTE))

	# Tendencies
	for key in _defs.tendencies.keys():
		var habit := 50.0 + float(tendency_offsets.get(key, 0.0))
		var sources: Array = TENDENCY_SOURCES.get(key, [])
		var target := habit
		var spread := 15.0
		if not sources.is_empty():
			var total := 0.0
			for s in sources:
				total += p.attributes.get_value(str(s))
			target = 0.5 * (total / sources.size()) + 0.5 * habit
			spread = 10.0
		p.tendencies.set_clamped(key, roundi(target + rng.gaussian(0.0, spread)))

	# Personality
	for key in _defs.personality.keys():
		p.personality.set_clamped(key, roundi(rng.gaussian(50.0, 18.0)))

	# Development profile
	var peak := clampi(roundi(rng.gaussian(27.0, 2.0)), 22, 32)
	var growth_years := maxi(0, peak - spec.age)
	var yearly_growth := clampf(rng.gaussian(2.2, 1.0), 0.0, 5.0)
	p.development.peak_age = peak
	p.development.potential = clampi(roundi(level + growth_years * yearly_growth), roundi(level), 99)
	p.development.development_rate = clampf(rng.gaussian(1.0, 0.2), 0.5, 1.5)
	p.development.volatility = clampf(rng.gaussian(0.25, 0.1), 0.05, 0.7)
	return p
