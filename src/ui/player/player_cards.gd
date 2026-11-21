class_name FcPlayerCards
extends RefCounted
## The one family of player presentations, by size (docs/VISUAL_IDENTITY_PLAN.md, section 9). Every size shows the same resolved visual,
## so a player is one person in every mode:
##   CHIP     a list row: head portrait, name, detail, rating badge                           (FcPlayerChip, any width)
##   SMALL    a small tile or collectible card, 112 x 160                                      (Owner/Career FcPlayerTile; Dynasty FcCardFace)
##   MEDIUM   a selection card, 150 x 214                                                      (FcPlayerTile; FcCardFace)
##   LARGE    a large card, 225 x 321 (Dynasty) and the full player profile                    (FcCardFace; FcPlayerProfile)
## Owner and Career use rating tiers for their colour and Dynasty uses rarity; the two colour sets are never mixed (D-047).

enum Size { CHIP, SMALL, MEDIUM, LARGE, HERO }

const PIXELS := {Size.SMALL: Vector2(112, 160), Size.MEDIUM: Vector2(150, 214), Size.LARGE: Vector2(225, 321), Size.HERO: Vector2(300, 428)}


## The pixel size of a card size (the same numbers FcCardFace uses, so tiles and cards sit side by side in one grid).
static func pixels(card_size: Size) -> Vector2:
	return PIXELS.get(card_size, PIXELS[Size.SMALL])


## An Owner/Career player (a FcPlayerPresentation dictionary) in a size: a chip for CHIP, a tile for SMALL and MEDIUM. LARGE and HERO are the
## profile (FcPlayerProfile.open_modal): this returns a MEDIUM tile for them so a caller always gets a control.
static func make(view_model: Dictionary, card_size: Size = Size.SMALL, detail: String = "") -> Control:
	if card_size == Size.CHIP:
		return FcPlayerChip.new().setup(view_model, detail)
	return FcPlayerTile.new().setup(view_model, pixels(card_size) if card_size == Size.SMALL else pixels(Size.MEDIUM))
