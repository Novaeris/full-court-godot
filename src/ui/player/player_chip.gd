class_name FcPlayerChip
extends HBoxContainer
## The player in a ROW (a roster line, a draft board, a trade list, a box score line): a head portrait, the name with a quiet second line
## (position, age, team: whatever the caller gives), and the rating badge. Built from the same resolved visual and rating tiers as the
## tiles and cards, so one player is one face and one rating colour in every list. Use it as a table cell (FcTable "custom" column) or alone.
## `compact` drops the second line for dense lists.

var portrait: FcPlayerPortrait
var name_label: Label
var detail_label: Label
var badge: FcRatingBadge


## `view_model` is a FcPlayerPresentation dictionary; `detail` is the second line ("PG  ·  24  ·  HBK"), `show_rating` adds the badge.
func setup(view_model: Dictionary, detail: String = "", show_rating: bool = true, portrait_px: int = 40, compact: bool = false) -> FcPlayerChip:
	for c in get_children():
		c.queue_free()
	add_theme_constant_override("separation", FcUiTokens.SPACE_2)
	portrait = FcPlayerPortrait.new().setup(view_model["subject"], portrait_px, "head")
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(portrait)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.add_theme_constant_override("separation", 0)
	name_label = FcUiTables.label(str(view_model.get("name", "?")), FcUiTokens.TYPE_BODY)
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(name_label)
	detail_label = FcUiTables.label(detail, FcUiTokens.TYPE_SMALL - 1)
	detail_label.theme_type_variation = "MutedLabel"
	detail_label.clip_text = true
	detail_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	detail_label.visible = detail != "" and not compact
	text.add_child(detail_label)
	add_child(text)
	if show_rating:
		badge = FcRatingBadge.new(int(view_model.get("overall", 0)), FcRatingBadge.Size.SMALL)
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		add_child(badge)
	tooltip_text = "%s, %d overall" % [str(view_model.get("name", "?")), int(view_model.get("overall", 0))]
	return self
