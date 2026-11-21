class_name FcUiTokens
extends RefCounted
## The design tokens of Full Court ("Hardwood Night"): every colour, size, spacing step, radius and duration the UI uses.
## Screens and components take values from here (through FcUiTheme or directly), never from literals, so the look can be
## changed in one place and checked by tests (contrast, the style lint). See docs/UI_POLISH_PLAN.md, section 3.

# --- colours -------------------------------------------------------------------------------------------------------
const BG := Color("0B1020")
const SURFACE := Color("111A2E")
## "Court Slate".
const SURFACE_RAISED := Color("17233D")
## "Elevated Surface": the third step (popovers, selected rows, hover fills). Added by the Visual Identity milestone (D-057).
const SURFACE_HIGH := Color("202F4D")
const BORDER := Color("2A3856")
## "Court Orange" (was F58C29). All of PRIMARY, INFO and GOLD pass 4.5:1 on BG, SURFACE, SURFACE_RAISED and SURFACE_HIGH (D-057).
const PRIMARY := Color("FF8A24")
## The deeper orange of the Full Court logo's underline: for gradients and glows, not for text.
const PRIMARY_DEEP := Color("E65300")
## "Electric Blue" (was 3DA5FF).
const INFO := Color("39A9FF")
## Lightened from #6C8EBF to reach 4.5:1 on SURFACE_HIGH.
const STEEL := Color("7C9DCB")
## "Championship Gold" (was FFC857).
const GOLD := Color("FFB547")
const SUCCESS := Color("3DD68C")
const WARNING := Color("F5B93A")
## Lightened (was #F2605D) so it reaches 4.5:1 as text on every surface including SURFACE_HIGH (the contrast test enforces this).
const DANGER := Color("F5726F")
const TEXT := Color("EAF0FA")
const TEXT_MUTED := Color("9AA8C2")
const TEXT_DISABLED := Color("5F6B84")
## The dim layer behind a modal (translucent, so it is not a text colour).
const SCRIM := Color(0.02, 0.03, 0.07, 0.72)
const TRANSPARENT := Color(0, 0, 0, 0)

# --- type ----------------------------------------------------------------------------------------------------------
const TYPE_DISPLAY_XL := 40
const TYPE_DISPLAY := 32
const TYPE_H1 := 28
const TYPE_H2 := 22
const TYPE_H3 := 18
const TYPE_BODY := 15
const TYPE_SMALL := 13
const TYPE_MICRO := 11
## Text scale per setting (Small, Normal, Large). The body size at each setting is TYPE_BODY * scale (13, 15, 18).
const TEXT_SCALES := [0.87, 1.0, 1.2]

# --- spacing, radii, targets ----------------------------------------------------------------------------------------
const SPACE_1 := 4
const SPACE_2 := 8
const SPACE_3 := 12
const SPACE_4 := 16
const SPACE_5 := 24
const SPACE_6 := 32
const SPACE_7 := 48
const RADIUS_CONTROL := 6
const RADIUS_PANEL := 12
const RADIUS_CARD := 12
const RADIUS_MODAL := 16
const TOUCH_TARGET := 44
const DESKTOP_TARGET := 32

# --- motion (seconds) ------------------------------------------------------------------------------------------------
const DUR_FAST := 0.09
const DUR_BASE := 0.18
const DUR_SLOW := 0.28
## The longest any fade lasts when the player asks for reduced motion.
const DUR_REDUCED_FADE := 0.08

## The current text scale. Set by FcUiTheme.build (one theme is active at a time); labels created through FcUiTables use fs().
static var text_scale: float = 1.0
## True on touch layouts (Phase 3 sets it from the layout profile): controls grow to the touch target size.
static var touch_mode: bool = false


## A font size scaled by the player's text-size setting (never below 10).
static func fs(size: int) -> int:
	return maxi(10, roundi(size * text_scale))


## The smallest height of a button, tab or field on the current layout.
static func min_target() -> int:
	return TOUCH_TARGET if touch_mode else DESKTOP_TARGET


## Adds a soft drop shadow to a style box. Level 0 none, 1 raised card, 2 popup, 3 modal.
static func elevate(style: StyleBoxFlat, level: int) -> StyleBoxFlat:
	level = clampi(level, 0, 3)
	style.shadow_size = [0, 4, 10, 22][level]
	style.shadow_offset = Vector2(0, [0, 2, 4, 8][level])
	style.shadow_color = Color(0, 0, 0, [0.0, 0.30, 0.38, 0.5][level])
	return style
