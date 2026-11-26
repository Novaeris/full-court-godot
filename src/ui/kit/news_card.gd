class_name FcNewsCard
extends PanelContainer
## One story of the league news: a category tag, the headline, an optional deck (one or two sentences), the date, and an optional team
## crest or player portrait. Importance (tier 0 = a brief, 1 = normal, 2 = major, 3 = the lead story) sets the size and the accent bar, so
## the most important story reads first. It shows the text it is given; the Network builds stories only from real league events.

signal activated

const TIER_BRIEF := 0
const TIER_NORMAL := 1
const TIER_MAJOR := 2
const TIER_LEAD := 3

var story: Dictionary = {}


func _init() -> void:
	theme_type_variation = "RaisedPanel"
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_ALL


## `data`: {"headline": String, "deck": String, "kind": String (tag text), "date": String, "tier": int, "team_look": Dictionary (optional),
## "player": Dictionary (a FcPlayerPresentation subject, optional), "tone": String (calendar tone, optional)}.
func setup(data: Dictionary) -> FcNewsCard:
	story = data
	for c in get_children():
		remove_child(c)
		c.queue_free()
	var tier := clampi(int(data.get("tier", TIER_NORMAL)), TIER_BRIEF, TIER_LEAD)
	var accent := FcCalendarGrid.tone_color(str(data.get("tone", "primary" if tier >= TIER_MAJOR else "info")))
	var style := StyleBoxFlat.new()
	style.bg_color = FcUiTokens.SURFACE_RAISED
	style.border_color = accent
	style.border_width_left = 4 if tier >= TIER_MAJOR else 2
	style.set_corner_radius_all(FcUiTokens.RADIUS_CARD)
	style.content_margin_left = FcUiTokens.SPACE_4
	style.content_margin_right = FcUiTokens.SPACE_4
	style.content_margin_top = FcUiTokens.SPACE_3
	style.content_margin_bottom = FcUiTokens.SPACE_3
	add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", FcUiTokens.SPACE_3)
	add_child(row)
	var player: Dictionary = data.get("player", {})
	var look: Dictionary = data.get("team_look", {})
	if not player.is_empty() and tier >= TIER_NORMAL:
		var portrait := FcPlayerPortrait.new().setup(player, 96 if tier == TIER_LEAD else 56)
		portrait.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(portrait)
	elif not look.is_empty():
		var crest := FcTeamCrest.new().setup(look, 64 if tier == TIER_LEAD else 40, false)
		crest.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(crest)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", FcUiTokens.SPACE_1)
	row.add_child(text)
	var meta := HBoxContainer.new()
	meta.add_theme_constant_override("separation", FcUiTokens.SPACE_2)
	if str(data.get("kind", "")) != "":
		meta.add_child(FcStatusChip.make(str(data["kind"]).to_upper(), FcStatusChip.Tone.WARNING if tier >= TIER_MAJOR else FcStatusChip.Tone.INFO))
	if str(data.get("date", "")) != "":
		var date := Label.new()
		date.text = str(data["date"])
		date.theme_type_variation = "CaptionLabel"
		meta.add_child(date)
	text.add_child(meta)
	var headline := Label.new()
	headline.text = str(data.get("headline", ""))
	headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	headline.theme_type_variation = "DisplayLabel" if tier == TIER_LEAD else ("HeadingLabel" if tier >= TIER_NORMAL else "")
	text.add_child(headline)
	if str(data.get("deck", "")) != "" and tier >= TIER_NORMAL:
		var deck := Label.new()
		deck.text = str(data["deck"])
		deck.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		deck.theme_type_variation = "MutedLabel"
		text.add_child(deck)
	tooltip_text = str(data.get("headline", ""))
	return self


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		activated.emit()
	elif event.is_action_pressed("ui_accept") and has_focus():
		accept_event()
		activated.emit()
