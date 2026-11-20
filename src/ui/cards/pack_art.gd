class_name FcPackArt
extends Control
## Procedural pack artwork (no image files): a foil wrapper with crimped ends, tinted by the pack's TIER (the best rarity the pack can
## contain, from its published odds; a fixed pack is steel blue), the pack name, the number of cards and a diagonal sheen. It can play a
## tear animation (`tear`): the top strip peels away and light bursts out. The tier colours come from FcRarityStyle, so a new rarity
## published later still gets a (common-looking) pack. Presentation only: it draws a pack listing, it never decides what a pack holds.

const SIZE := Vector2(150, 210)

var pack: Dictionary = {}
var tier: String = "common"
## 0 (sealed) to 1 (fully torn): animated by tear().
var tear_progress: float = 0.0:
	set(v):
		tear_progress = v
		queue_redraw()


func _init() -> void:
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## `listing` is a pack listing from the controller (name, cards_per_pack, fixed, odds).
func setup(listing: Dictionary, size_override: Vector2 = SIZE) -> FcPackArt:
	pack = listing
	tier = tier_of(listing)
	custom_minimum_size = size_override
	queue_redraw()
	return self


## The best rarity a pack can give (its highest rarity with a nonzero published weight), or "fixed" for a pack with exact contents.
static func tier_of(listing: Dictionary) -> String:
	if bool(listing.get("fixed", false)):
		return "fixed"
	var best := "common"
	var odds: Dictionary = listing.get("odds", {})
	for rarity in odds:
		if int(odds[rarity]) > 0 and FcDynastyContentRules.rarity_rank(str(rarity)) > FcDynastyContentRules.rarity_rank(best):
			best = str(rarity)
	return best


static func tier_color(tier_id: String) -> Color:
	return FcUiTokens.STEEL if tier_id == "fixed" else FcRarityStyle.color(tier_id)


## Plays the tear (instant when motion is reduced). Returns the tween or null.
func tear(seconds: float = 0.45) -> Tween:
	return FcMotion.tween_property(self, "tear_progress", 1.0, seconds)


func _draw() -> void:
	var s := size.x / 150.0
	var color := tier_color(tier)
	var dark := FcRarityStyle.dark(tier) if tier != "fixed" else FcUiTokens.SURFACE_RAISED
	var top_cut := 34.0 * s
	# the sealed body below the tear line
	var body := Rect2(0, top_cut, size.x, size.y - top_cut)
	_foil(body, color, dark, s)
	# the strip that peels away: it lifts and tilts as tear_progress grows
	var lift := tear_progress * 26.0 * s
	draw_set_transform(Vector2(size.x * 0.5, top_cut) + Vector2(tear_progress * 18.0 * s, -lift), -tear_progress * 0.5, Vector2.ONE)
	draw_rect(Rect2(-size.x * 0.5, -top_cut, size.x, top_cut), color.darkened(0.15))
	_crimp(-size.x * 0.5, -top_cut, size.x, s, color.lightened(0.2))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_crimp(0, size.y - 8 * s, size.x, s, color.lightened(0.2))
	# the name and the card count on the wrapper
	var display := FcUiFonts.display(700)
	var font: Font = display if display != null else ThemeDB.fallback_font
	var name_text := str(pack.get("name", "Pack"))
	var fs := int(22 * s)
	while fs > 10 and font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > size.x - 20 * s:
		fs -= 1
	var w := font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, Vector2((size.x - w) / 2.0, size.y * 0.56), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, FcUiTokens.TEXT)
	var count := "%d CARD%s" % [int(pack.get("cards_per_pack", 0)), "" if int(pack.get("cards_per_pack", 0)) == 1 else "S"]
	var cw := font.get_string_size(count, HORIZONTAL_ALIGNMENT_LEFT, -1, int(14 * s)).x
	draw_string(font, Vector2((size.x - cw) / 2.0, size.y * 0.56 + 22 * s), count, HORIZONTAL_ALIGNMENT_LEFT, -1, int(14 * s), Color(FcUiTokens.TEXT, 0.8))
	# a burst of light from the tear
	if tear_progress > 0.05:
		var origin := Vector2(size.x / 2.0, top_cut)
		for i in 9:
			var angle := -PI + i * PI / 8.0
			var length := (30.0 + 60.0 * tear_progress) * s
			draw_line(origin, origin + Vector2(cos(angle), sin(angle)) * length, Color(1, 1, 1, 0.55 * (1.0 - tear_progress * 0.5)), 2.0 * s)


func _foil(rect: Rect2, color: Color, dark: Color, s: float) -> void:
	var top := dark.lerp(color, 0.55)
	var bottom := dark.darkened(0.3)
	draw_polygon(PackedVector2Array([rect.position, rect.position + Vector2(rect.size.x, 0), rect.end, rect.position + Vector2(0, rect.size.y)]), PackedColorArray([top, top, bottom, bottom]))
	# a diagonal sheen across the foil
	draw_polygon(PackedVector2Array([Vector2(size.x * 0.34, rect.position.y), Vector2(size.x * 0.58, rect.position.y), Vector2(size.x * 0.26, rect.end.y), Vector2(size.x * 0.02, rect.end.y)]), PackedColorArray([Color(1, 1, 1, 0.16)]))
	# faint court lines
	var c := Vector2(size.x / 2.0, rect.position.y + rect.size.y * 0.5)
	draw_arc(c, 34 * s, 0.0, TAU, 40, Color(1, 1, 1, 0.12), 1.5 * s, true)
	draw_line(Vector2(8 * s, c.y), Vector2(size.x - 8 * s, c.y), Color(1, 1, 1, 0.12), 1.5 * s)
	var edge := StyleBoxFlat.new()
	edge.draw_center = false
	edge.border_color = color.lightened(0.25)
	edge.set_border_width_all(maxi(1, roundi(2 * s)))
	draw_style_box(edge, rect)


func _crimp(x: float, y: float, width: float, s: float, color: Color) -> void:
	var teeth := 14
	var step := width / teeth
	for i in teeth:
		var x0 := x + i * step
		draw_polygon(PackedVector2Array([Vector2(x0, y), Vector2(x0 + step * 0.5, y + 8 * s), Vector2(x0 + step, y)]), PackedColorArray([color]))
