class_name FcModeSkin
extends RefCounted
## The presentation personality of a game mode. All skins share the same tokens and components; a skin may change ONLY the
## properties in WHITELIST (anything else passed to resolve() is ignored), so the three modes cannot drift into three different UIs.
##   neutral      menu, settings, shell
##   broadcast    post-game in every mode, and Career: condensed numerals, lower-third headers, tighter density
##   collectible  Dynasty: roomy density, spotlight backdrop, the most motion
##   franchise    Owner: calm, tinted by the user's franchise colour, letterhead headers
## FcUiTheme.build(size, skin) turns the resolved skin into a Theme; screens ask the skin for the background treatment and header style.

const NEUTRAL := "neutral"
const BROADCAST := "broadcast"
const COLLECTIBLE := "collectible"
const FRANCHISE := "franchise"

## The only keys a skin (or an override) may set.
const WHITELIST := ["accent", "background", "density", "header", "motion", "numerals"]

const SKINS := {
	NEUTRAL: {"accent": FcUiTokens.PRIMARY, "background": "flat", "density": 1.0, "header": "plain", "motion": 1.0, "numerals": "body"},
	BROADCAST: {"accent": FcUiTokens.INFO, "background": "grid", "density": 0.9, "header": "lower_third", "motion": 0.8, "numerals": "display"},
	COLLECTIBLE: {"accent": FcUiTokens.PRIMARY, "background": "spotlight", "density": 1.1, "header": "banner", "motion": 1.0, "numerals": "display"},
	FRANCHISE: {"accent": FcUiTokens.STEEL, "background": "flat", "density": 0.95, "header": "letterhead", "motion": 0.5, "numerals": "body"},
}


static func ids() -> Array:
	return SKINS.keys()


## The skin `id` (neutral when unknown) with whitelisted `overrides` applied. The accent is lightened until it is readable
## on every surface, so a dark franchise colour can never make text or buttons unreadable.
static func resolve(id: String, overrides: Dictionary = {}) -> Dictionary:
	var skin: Dictionary = SKINS.get(id, SKINS[NEUTRAL]).duplicate()
	for key in overrides:
		if key in WHITELIST:
			skin[key] = overrides[key]
	skin["id"] = id if SKINS.has(id) else NEUTRAL
	skin["density"] = clampf(float(skin["density"]), 0.8, 1.2)
	skin["motion"] = clampf(float(skin["motion"]), 0.0, 1.0)
	skin["accent"] = FcUiContrast.ensure(skin["accent"], FcUiTokens.SURFACE_RAISED, 4.5)
	return skin


## The Franchise skin tinted with a team's primary colour ("#RRGGBB", as in FcTeamBranding). An invalid colour keeps the default.
static func franchise(primary_hex: String) -> Dictionary:
	if FcChecks.is_hex_color(primary_hex):
		return resolve(FRANCHISE, {"accent": Color(primary_hex)})
	return resolve(FRANCHISE)
