class_name FcUiContrast
extends RefCounted
## WCAG contrast maths, used by tests to prove that every text colour is readable on the surfaces it appears on, and at
## runtime to lighten an accent colour (a franchise colour, say) until it is readable.


## Relative luminance of a colour (0 black to 1 white), as the WCAG definition says.
static func luminance(c: Color) -> float:
	return 0.2126 * _channel(c.r) + 0.7152 * _channel(c.g) + 0.0722 * _channel(c.b)


## Contrast ratio between two opaque colours, 1 (identical) to 21 (black on white).
static func ratio(a: Color, b: Color) -> float:
	var la := luminance(a)
	var lb := luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


## `c` lightened step by step until it reaches `minimum` contrast against `against` (white if it cannot).
static func ensure(c: Color, against: Color, minimum: float = 4.5) -> Color:
	var out := c
	for i in 40:
		if ratio(out, against) >= minimum:
			return out
		out = out.lightened(0.06)
	return Color.WHITE


## The text colour (dark or light) that reads better on `fill`.
static func readable_on(fill: Color) -> Color:
	return FcUiTokens.BG if ratio(FcUiTokens.BG, fill) >= ratio(FcUiTokens.TEXT, fill) else FcUiTokens.TEXT


static func _channel(v: float) -> float:
	return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)
