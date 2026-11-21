class_name FcLayoutProfile
extends RefCounted
## Decides which PRESENTATION TARGET the window is: desktop or mobile (they are different layouts, not one squeezed layout), and how
## much room there is (compact, regular, wide). Screens and the shell ask this instead of looking at the window themselves.
## Rules (docs/UI_POLISH_PLAN.md, section 3):
##   mobile   = a mobile operating system, or a touch screen with a window narrower than MOBILE_MAX_WIDTH; the player can force
##              Desktop or Mobile in Settings (override), for testing and for unusual devices
##   size     = compact below COMPACT_WIDTH, wide from WIDE_WIDTH, regular between
## It also turns the device's safe area (notches, rounded corners, system bars) into margins. Pure logic: nothing here touches
## the scene tree, so it is fully unit-tested.

signal changed(profile: FcLayoutProfile)

const DESKTOP := "desktop"
const MOBILE := "mobile"
const AUTO := "auto"
const COMPACT := "compact"
const REGULAR := "regular"
const WIDE := "wide"
const COMPACT_WIDTH := 700
const WIDE_WIDTH := 1100
const MOBILE_MAX_WIDTH := 900

## "auto", "desktop" or "mobile" (the player's choice in Settings).
var override: String = AUTO
## Set by the app from the device: is this a mobile OS, and is a touch screen present?
var mobile_os: bool = false
var touch_available: bool = false
var mode: String = DESKTOP
var size_class: String = REGULAR


## The mode and size class for a window of `size`, without changing anything.
## The UI scale factor for a phone: the screen's density relative to Android's 160 dpi baseline, so a 1080 px wide, 420 dpi phone gets 2.6 and
## the window is about 412 logical px wide, the width the mobile layouts are designed for. Without it the project's 1280 px design width
## (stretch mode canvas_items) squeezes the whole UI to 84% on a phone: tiny text and touch targets under 44 dp (found on the Android emulator).
## Clamped to 1.0-4.0; an unknown density (0 or less) gives 1.0.
static func phone_scale(dpi: int) -> float:
	if dpi <= 0:
		return 1.0
	return clampf(float(dpi) / 160.0, 1.0, 4.0)


static func classify(size: Vector2, is_mobile_os: bool, has_touch: bool, choice: String = AUTO) -> Dictionary:
	var target := DESKTOP
	if choice == MOBILE or choice == DESKTOP:
		target = choice
	elif is_mobile_os or (has_touch and size.x < MOBILE_MAX_WIDTH):
		target = MOBILE
	var width_class := COMPACT if size.x < COMPACT_WIDTH else (WIDE if size.x >= WIDE_WIDTH else REGULAR)
	return {"mode": target, "size_class": width_class}


## Re-evaluates for a window size. Emits changed and returns true when the mode or size class is different now.
func update(size: Vector2) -> bool:
	var result := classify(size, mobile_os, touch_available, override)
	if result["mode"] == mode and result["size_class"] == size_class:
		return false
	mode = result["mode"]
	size_class = result["size_class"]
	changed.emit(self)
	return true


func is_mobile() -> bool:
	return mode == MOBILE


func is_compact() -> bool:
	return size_class == COMPACT


## Margins in pixels for a device safe area: `area` is the usable rectangle, `screen` the full screen. Never negative; a safe
## area that is empty or the whole screen gives zeros (desktops report the screen minus the taskbar, so callers only apply this on mobile).
## `scale` is the window's content scale factor: the safe area is in physical pixels but the UI lays out in logical ones, so the margins are divided by it
## (without that a phone's status bar became a band 2.6 times too tall; found on the Android emulator).
static func safe_margins(area: Rect2i, screen: Vector2i, scale: float = 1.0) -> Dictionary:
	if area.size.x <= 0 or area.size.y <= 0 or screen.x <= 0 or screen.y <= 0:
		return {"left": 0, "top": 0, "right": 0, "bottom": 0}
	var k := maxf(scale, 0.01)
	return {
		"left": ceili(maxi(0, area.position.x) / k), "top": ceili(maxi(0, area.position.y) / k),
		"right": ceili(maxi(0, screen.x - area.end.x) / k), "bottom": ceili(maxi(0, screen.y - area.end.y) / k),
	}
