class_name FcRarityStyle
extends RefCounted
## How each rarity LOOKS. Rarity must be more than a border colour, so every rarity has its own colours, frame, background pattern
## and effects (docs/UI_POLISH_PLAN.md, section 3):
##   common     matte slate, one thin keyline, flat background
##   uncommon   green, a double keyline, faint diagonal lines
##   rare       blue, a bevelled frame, a vertical gradient, a light sweep on hover
##   epic       purple, ornate corner marks, radiating light behind the portrait, a sweep on hover
##   legendary  gold, a foil frame, a rainbow holo wash, a sweep on hover, the biggest reveal
## `intensity` (0 to 4) is how strong the reveal effects are (Phase 6). An UNKNOWN rarity id (a future content release) never fails:
## it gets the common look with its own name, so new rarities can be published without a game update.

const STYLES := {
	"common": {"color": Color("9AA3B2"), "dark": Color("2B313D"), "frame": "plain", "pattern": "flat", "sweep": false, "intensity": 0},
	"uncommon": {"color": Color("5CC884"), "dark": Color("173324"), "frame": "double", "pattern": "diagonal", "sweep": false, "intensity": 1},
	"rare": {"color": Color("5299F5"), "dark": Color("14284A"), "frame": "bevel", "pattern": "gradient", "sweep": true, "intensity": 2},
	"epic": {"color": Color("B273F5"), "dark": Color("2C1A4A"), "frame": "ornate", "pattern": "rays", "sweep": true, "intensity": 3},
	"legendary": {"color": Color("FAC748"), "dark": Color("4A3512"), "frame": "foil", "pattern": "holo", "sweep": true, "intensity": 4},
}
const FALLBACK := "common"

const FRAME_COLORS := {"bronze": Color("CC8047"), "silver": Color("CCD6E6"), "gold": Color("FACC52"), "platinum": Color("9EEBF0"), "diamond": Color("94CCFF")}


## The style of a rarity id (the common look for an unknown id).
static func of(rarity: String) -> Dictionary:
	return STYLES.get(rarity, STYLES[FALLBACK])


static func known(rarity: String) -> bool:
	return STYLES.has(rarity)


static func color(rarity: String) -> Color:
	return of(rarity)["color"]


static func dark(rarity: String) -> Color:
	return of(rarity)["dark"]


## The display name ("Epic"); an unknown id is capitalised as it is.
static func label(rarity: String) -> String:
	return rarity.replace("_", " ").capitalize()


## Reveal intensity 0 to 4 (an unknown rarity reveals quietly).
static func intensity(rarity: String) -> int:
	return int(of(rarity)["intensity"])


## The mastery frame colour for a level (0 none, 1 bronze ... 5 diamond), or fully transparent for none.
static func mastery_color(level: int) -> Color:
	var names := ["", "bronze", "silver", "gold", "platinum", "diamond"]
	var name: String = names[clampi(level, 0, 5)]
	return FRAME_COLORS[name] if name != "" else FcUiTokens.TRANSPARENT
