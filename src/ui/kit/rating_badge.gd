class_name FcRatingBadge
extends PanelContainer
## A player rating (0 to 99) in a rounded tile coloured by its tier (data/ui/rating_tiers.json: slate, steel, cyan, orange, gold).
## One treatment for every rating in the game, so a 78 looks the same in a roster, a profile and a trade. Sizes: SMALL (tables),
## MEDIUM, LARGE (hero numbers). Never uses rarity colours.

enum Size { SMALL, MEDIUM, LARGE }

const FONT_SIZES := {Size.SMALL: 14, Size.MEDIUM: 20, Size.LARGE: 34}
const MIN_WIDTHS := {Size.SMALL: 34, Size.MEDIUM: 46, Size.LARGE: 72}

static var _tiers: FcUiRatingTiers = null

var value: int = 0
var number := Label.new()
var badge_size: Size = Size.MEDIUM


func _init(rating: int = 0, tile_size: Size = Size.MEDIUM) -> void:
	badge_size = tile_size
	number.theme_type_variation = "DisplayLabel"
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(number)
	custom_minimum_size.x = MIN_WIDTHS[tile_size]
	set_rating(rating)


func set_rating(rating: int) -> void:
	value = clampi(rating, 0, 99)
	number.text = str(value)
	number.add_theme_font_size_override("font_size", FcUiTokens.fs(FONT_SIZES[badge_size]))
	var color := tier_color(value)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(color.r, color.g, color.b, 0.16)
	box.border_color = color
	box.set_border_width_all(1)
	box.set_corner_radius_all(FcUiTokens.RADIUS_CONTROL)
	box.content_margin_left = 6
	box.content_margin_right = 6
	box.content_margin_top = 1
	box.content_margin_bottom = 1
	add_theme_stylebox_override("panel", box)
	number.add_theme_color_override("font_color", color)
	tooltip_text = str(tier_for(value)["name"])


static func tiers() -> FcUiRatingTiers:
	if _tiers == null:
		_tiers = FcUiRatingTiers.load_default()
	return _tiers


static func tier_for(rating: int) -> Dictionary:
	return tiers().tier_for(rating)


static func tier_color(rating: int) -> Color:
	return tiers().color_for(rating)
