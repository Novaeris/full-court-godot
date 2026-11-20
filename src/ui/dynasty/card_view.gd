class_name FcCardView
extends RefCounted
## The player card API the Dynasty screens use. A card row from FcCollectionQuery (or a plain card view) goes in; a clickable,
## keyboard-focusable Control (an FcCardFace) comes out. The drawing, rarity treatments, states and flip live in src/ui/cards.

const SIZE := FcCardFace.SIZE_STANDARD
const SMALL := FcCardFace.SIZE_SMALL


## `row` is a card view, optionally with owned/quantity/mastery (collection rows). `options`: size (Vector2), on_click (Callable),
## caption (extra line, e.g. a price), tag (a small badge such as NEW or DUPLICATE), face_down (the back of a card, for pack reveals),
## selected, inspected.
static func build(row: Dictionary, options: Dictionary = {}) -> FcCardFace:
	return FcCardFace.new().setup(row, options)
