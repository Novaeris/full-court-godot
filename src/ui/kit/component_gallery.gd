class_name FcComponentGallery
extends Control
## The Component Gallery: every design token and kit component in every state, on one scrolling page, with switches for the mode
## skin, the touch layout, reduced motion and the text size. It is the visual reference for the design system and the target of the
## screenshot matrix (tools/screenshot_matrix.ps1). Development only: the main menu shows it in editor and debug runs.
## Forced hover/focus/pressed looks are drawn by copying the theme's style for that state onto the button; the real states are
## the theme's, the gallery only shows them side by side.

signal closed

var _skin_id: String = FcModeSkin.NEUTRAL
var _text_index: int = 1
var _layout: VBoxContainer
var _body: VBoxContainer
var _toasts: FcToastStack
var _page: ScrollContainer


func _ready() -> void:
	build()


## Builds (or rebuilds) the whole page for the current skin, touch and text settings.
func build() -> void:
	if _layout == null:
		_layout = VBoxContainer.new()
		_layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(_layout)
		_toasts = FcToastStack.new()
		add_child(_toasts)
	for c in _layout.get_children():
		_layout.remove_child(c)
		c.queue_free()
	theme = FcUiTheme.build(_text_index, FcModeSkin.resolve(_skin_id))
	_layout.add_theme_constant_override("separation", FcUiTokens.SPACE_3)
	_layout.add_child(_header())
	_page = ScrollContainer.new()
	_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_layout.add_child(_page)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", FcUiTokens.SPACE_5)
	_page.add_child(_body)
	_section_colours()
	_section_type()
	_section_buttons()
	_section_inputs()
	_section_feedback()
	_section_data()
	_section_table()
	_section_cards()
	_section_teams()
	_section_players()
	_section_portraits()
	_section_broadcast()
	_section_franchise()
	_section_motion()


## Scrolls the page so a section is at the top (the screenshot tool uses this).
func scroll_to_section(title: String) -> void:
	for c in _body.get_children():
		if c.has_meta("section") and str(c.get_meta("section")) == title:
			_page.scroll_vertical = int(c.position.y)
			return


## Opens one of the overlays so a screenshot can show it: modal_info, modal_confirm, modal_destructive, toasts or loading.
func show_demo(kind: String) -> void:
	match kind:
		"modal_info":
			FcModal.notice(self, "Season complete", "Your results are saved.")
		"modal_confirm":
			FcModal.confirm(self, "Start next season?", "The regular season ends and the offseason begins.", func() -> void: pass)
		"modal_destructive":
			FcModal.confirm(self, "Delete this save?", "This cannot be undone.", func() -> void: pass, true, "Delete")
		"toasts":
			_toasts.push(FcToast.Kind.INFO, "Your lineup was saved.")
			_toasts.push(FcToast.Kind.SUCCESS, "Pack opened: 3 new cards.")
			_toasts.push(FcToast.Kind.WARNING, "Payroll is close to the limit.")
		"loading":
			FcLoadingOverlay.show_on(self, "Simulating the season...")


func section_titles() -> Array:
	var out: Array = []
	for c in _body.get_children():
		if c.has_meta("section"):
			out.append(str(c.get_meta("section")))
	return out


func set_skin(skin_id: String) -> void:
	_skin_id = skin_id
	build()


## Switches the touch layout (controls grow to 44 px) and rebuilds.
func set_touch(on: bool) -> void:
	FcUiTokens.touch_mode = on
	build()


## Turns reduced motion on or off (the next animation follows it).
func set_reduced_motion(on: bool) -> void:
	FcMotion.reduced = on


func set_text_index(index: int) -> void:
	_text_index = clampi(index, 0, 2)
	build()


# --- header -----------------------------------------------------------------------------------------------------------

func _header() -> Control:
	var bar := HFlowContainer.new()
	bar.add_theme_constant_override("h_separation", FcUiTokens.SPACE_4)
	var skins := FcChoiceGroup.new()
	var options: Array = []
	for id in FcModeSkin.ids():
		options.append([id, str(id).capitalize()])
	skins.set_options(options, _skin_id)
	skins.selected.connect(set_skin)
	bar.add_child(skins)
	var sizes := FcChoiceGroup.new()
	sizes.set_options([["0", "Small"], ["1", "Normal"], ["2", "Large"]], str(_text_index))
	sizes.selected.connect(func(id: String) -> void: set_text_index(int(id)))
	bar.add_child(sizes)
	bar.add_child(FcToggle.make("Touch layout", FcUiTokens.touch_mode, set_touch))
	bar.add_child(FcToggle.make("Reduce motion", FcMotion.reduced, set_reduced_motion))
	bar.add_child(FcButton.make("Back", FcButton.Variant.SECONDARY, func() -> void: closed.emit(), "chevron-left"))
	return bar


func _section(title: String, note: String = "") -> VBoxContainer:
	var box := VBoxContainer.new()
	box.set_meta("section", title)
	box.add_theme_constant_override("separation", FcUiTokens.SPACE_2)
	box.add_child(FcUiTables.label(title, FcUiTokens.TYPE_H2, true))
	if note != "":
		var n := FcUiTables.label(note, FcUiTokens.TYPE_SMALL)
		n.theme_type_variation = "MutedLabel"
		n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(n)
	_body.add_child(box)
	return box


func _flow() -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", FcUiTokens.SPACE_3)
	f.add_theme_constant_override("v_separation", FcUiTokens.SPACE_3)
	return f


## A control with a small caption above it. Items hug their content unless `fill` (tab bars, filter bars and tables use the width).
func _captioned(caption: String, control: Control, fill: bool = false) -> Control:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL if fill else Control.SIZE_SHRINK_BEGIN
	v.add_theme_constant_override("separation", 2)
	var c := FcUiTables.label(caption, FcUiTokens.TYPE_MICRO + 1)
	c.theme_type_variation = "CaptionLabel"
	v.add_child(c)
	v.add_child(control)
	return v


## Draws a button as if the pointer were over it (or focused, pressed): the theme's own style for that state.
func _force(button: Button, state: String) -> void:
	var source := button.get_theme_stylebox("hover" if state == "hover" else ("pressed" if state == "pressed" else "normal"))
	if source == null:
		return
	var box := source.duplicate() as StyleBox
	if state == "focus" and box is StyleBoxFlat:
		(box as StyleBoxFlat).border_color = FcUiTokens.TEXT
		(box as StyleBoxFlat).set_border_width_all(2)
	button.add_theme_stylebox_override("normal", box)


# --- sections ---------------------------------------------------------------------------------------------------------

func _section_colours() -> void:
	var s := _section("Colour", "Hardwood Night tokens. Text colours are tested for at least 4.5:1 contrast on every surface.")
	var flow := _flow()
	s.add_child(flow)
	for pair in [["BG", FcUiTokens.BG], ["SURFACE", FcUiTokens.SURFACE], ["RAISED", FcUiTokens.SURFACE_RAISED], ["HIGH", FcUiTokens.SURFACE_HIGH], ["BORDER", FcUiTokens.BORDER],
			["PRIMARY", FcUiTokens.PRIMARY], ["PRIMARY_DEEP", FcUiTokens.PRIMARY_DEEP], ["ACCENT (skin)", FcUiTheme.accent], ["INFO", FcUiTokens.INFO], ["GOLD", FcUiTokens.GOLD], ["SUCCESS", FcUiTokens.SUCCESS],
			["WARNING", FcUiTokens.WARNING], ["DANGER", FcUiTokens.DANGER], ["TEXT", FcUiTokens.TEXT], ["MUTED", FcUiTokens.TEXT_MUTED], ["DISABLED", FcUiTokens.TEXT_DISABLED]]:
		var swatch := Panel.new()
		var chip := StyleBoxFlat.new()
		chip.bg_color = pair[1]
		chip.border_color = FcUiTokens.BORDER
		chip.set_border_width_all(1)
		chip.set_corner_radius_all(4)
		swatch.add_theme_stylebox_override("panel", chip)
		swatch.custom_minimum_size = Vector2(64, 40)
		flow.add_child(_captioned(str(pair[0]), swatch))
	var ramp := _flow()
	s.add_child(FcUiTables.label("Rating ramp", FcUiTokens.TYPE_SMALL))
	s.add_child(ramp)
	for rating in [40, 58, 68, 78, 88, 95]:
		ramp.add_child(FcRatingBadge.new(rating, FcRatingBadge.Size.MEDIUM))


func _section_type() -> void:
	var s := _section("Typography", "Barlow Condensed for headings and big numbers, Inter for text. Sizes scale with the text-size choice above.")
	s.add_child(FcUiTables.label("DISPLAY 40  108", FcUiTokens.TYPE_DISPLAY_XL, true))
	s.add_child(FcUiTables.label("Heading 28: Hardwood Night", FcUiTokens.TYPE_H1, true))
	s.add_child(FcUiTables.label("Heading 22: the franchise report", FcUiTokens.TYPE_H2, true))
	s.add_child(FcUiTables.label("Heading 18: collection progress", FcUiTokens.TYPE_H3, true))
	s.add_child(FcUiTables.label("Body 15: Inter is used for text and tables. The quick brown fox jumps over the lazy dog.", FcUiTokens.TYPE_BODY))
	var small := FcUiTables.label("Small 13 muted: helper text, captions and notes.", FcUiTokens.TYPE_SMALL)
	small.theme_type_variation = "MutedLabel"
	s.add_child(small)
	var numbers := Label.new()
	numbers.theme_type_variation = "NumericLabel"
	numbers.text = "Tabular numerals: 1,111  8,888  0.533  $12.4M  +3  -2"
	s.add_child(numbers)


func _section_buttons() -> void:
	var s := _section("Buttons", "Variants across the top of each row; states are drawn side by side.")
	for variant in [["Primary", FcButton.Variant.PRIMARY], ["Secondary", FcButton.Variant.SECONDARY], ["Destructive", FcButton.Variant.DESTRUCTIVE], ["Ghost", FcButton.Variant.GHOST]]:
		var flow := _flow()
		s.add_child(flow)
		for state in ["default", "hover", "focus", "pressed", "disabled", "loading"]:
			var b := FcButton.make(variant[0], variant[1])
			match state:
				"disabled":
					b.disabled = true
				"loading":
					b.loading = true
			flow.add_child(_captioned("%s / %s" % [variant[0], state], b))
			if state in ["hover", "focus", "pressed"]:
				_force(b, state)
	var icons := _flow()
	s.add_child(icons)
	for icon in ["plus", "settings", "search", "trash-2", "refresh-cw", "x"]:
		icons.add_child(_captioned(icon, FcButton.icon_only(icon, icon)))
	var with_icon := FcButton.make("With icon", FcButton.Variant.PRIMARY, Callable(), "play")
	icons.add_child(_captioned("icon + text", with_icon))


func _section_inputs() -> void:
	var s := _section("Inputs and navigation")
	var tabs := FcTabBar.new()
	tabs.set_tabs([["a", "Overview"], ["b", "Roster"], ["c", "Finances"], ["d", "Draft"], ["e", "Trades"], ["f", "History"]])
	s.add_child(_captioned("Tab bar (scrolls sideways when it does not fit)", tabs, true))
	var group := FcChoiceGroup.new()
	group.set_options([["grid", "Grid"], ["carousel", "Carousel"], ["list", "List"]])
	s.add_child(_captioned("Choice group", group))
	var row := _flow()
	s.add_child(row)
	row.add_child(_captioned("Dropdown", FcDropdown.make([["Any position", ""], ["Guard", "G"], ["Forward", "F"], ["Center", "C"]])))
	var bad := FcDropdown.make([["Pick a team", ""], ["Harbor", "H"]])
	bad.error = true
	row.add_child(_captioned("Dropdown / error", bad))
	row.add_child(_captioned("Toggle", FcToggle.make("Reduce motion", true)))
	row.add_child(_captioned("Toggle / off", FcToggle.make("Sound effects", false)))
	var off := FcToggle.make("Disabled", false)
	off.disabled = true
	row.add_child(_captioned("Toggle / disabled", off))
	var slider := FcSlider.new(0, 100, 5, "%")
	slider.set_value_silent(70)
	slider.custom_minimum_size.x = 260
	row.add_child(_captioned("Slider", slider))
	var bars := _flow()
	s.add_child(bars)
	for pair in [["Accent", FcProgress.Variant.ACCENT, 60], ["Success", FcProgress.Variant.SUCCESS, 85], ["Danger", FcProgress.Variant.DANGER, 20], ["Gold", FcProgress.Variant.GOLD, 45]]:
		var p := FcProgress.new(pair[1])
		p.set_progress(pair[2], 100)
		p.custom_minimum_size.x = 160
		bars.add_child(_captioned("Progress / " + str(pair[0]), p))
	var search_row := _flow()
	s.add_child(search_row)
	search_row.add_child(_captioned("Search", FcSearchField.new("Search players")))
	var loading_search := FcSearchField.new("Searching")
	loading_search.loading = true
	search_row.add_child(_captioned("Search / loading", loading_search))
	var bad_search := FcSearchField.new("Search")
	bad_search.error = true
	bad_search.text = "zz"
	search_row.add_child(_captioned("Search / error", bad_search))
	var filters := FcFilterBar.new()
	filters.add_search("q", "Search name")
	filters.add_dropdown("position", "Any position", [["Guard", "G"], ["Forward", "F"], ["Center", "C"]])
	filters.add_chips("rarity", [["Common", "common"], ["Rare", "rare"], ["Epic", "epic"]], true)
	filters.add_clear_button()
	s.add_child(_captioned("Filter bar", filters, true))
	var tip := FcButton.make("Hover for a tooltip", FcButton.Variant.SECONDARY)
	tip.tooltip_text = "Tooltips use the same panel style everywhere."
	s.add_child(_captioned("Tooltip", tip))


func _section_feedback() -> void:
	var s := _section("Feedback", "Toasts appear at the bottom; modals open over the page.")
	var row := _flow()
	s.add_child(row)
	for pair in [["Info", FcToast.Kind.INFO, "Your lineup was saved."], ["Success", FcToast.Kind.SUCCESS, "Pack opened: 3 new cards."], ["Warning", FcToast.Kind.WARNING, "Payroll is close to the limit."], ["Error", FcToast.Kind.ERROR, "The save could not be written."]]:
		row.add_child(FcButton.make("Toast: " + str(pair[0]), FcButton.Variant.SECONDARY, func() -> void: _toasts.push(pair[1], pair[2])))
	row.add_child(FcButton.make("Modal: info", FcButton.Variant.SECONDARY, func() -> void: FcModal.notice(self, "Season complete", "Your results are saved.")))
	row.add_child(FcButton.make("Modal: confirm", FcButton.Variant.SECONDARY, func() -> void: FcModal.confirm(self, "Start next season?", "The regular season ends and the offseason begins.", func() -> void: _toasts.push(FcToast.Kind.SUCCESS, "Confirmed."))))
	row.add_child(FcButton.make("Modal: destructive", FcButton.Variant.DESTRUCTIVE, func() -> void: FcModal.confirm(self, "Delete this save?", "This cannot be undone.", func() -> void: _toasts.push(FcToast.Kind.WARNING, "Deleted (demo)."), true, "Delete")))
	row.add_child(FcButton.make("Loading overlay (2 s)", FcButton.Variant.SECONDARY, func() -> void:
		var overlay := FcLoadingOverlay.show_on(self, "Simulating the season...")
		get_tree().create_timer(2.0).timeout.connect(overlay.dismiss)))
	var states := _flow()
	s.add_child(states)
	states.add_child(_captioned("Loading", FcLoading.new("Loading the league...")))
	for kind in [[FcEmptyState.Kind.EMPTY, "No cards yet", "Open a pack or play a game to start your collection."], [FcEmptyState.Kind.ERROR, "Could not load the release", "Check the content folder in Settings, then try again."], [FcEmptyState.Kind.SUCCESS, "All caught up", "Every challenge reward has been claimed."]]:
		var state := FcEmptyState.new(kind[1], kind[2], kind[0], "", "Try again" if kind[0] == FcEmptyState.Kind.ERROR else "", Callable())
		states.add_child(_captioned("Empty state / %s" % FcEmptyState.Kind.keys()[kind[0]].to_lower(), state))
	states.add_child(_captioned("Error (with action)", FcEmptyState.error("The save could not be written", "Check free disk space, then try again.", "Try again", func() -> void: _toasts.push(FcToast.Kind.INFO, "Retrying (demo)."))))
	states.add_child(_captioned("Success", FcEmptyState.success("Saved", "Your franchise was saved a moment ago.")))
	var skeleton := FcSkeleton.new(4, 24)
	skeleton.custom_minimum_size.x = 260
	states.add_child(_captioned("Skeleton (loading rows)", skeleton))


func _section_data() -> void:
	var s := _section("Data")
	var tiles := _flow()
	s.add_child(tiles)
	tiles.add_child(FcStatTile.make("Overall", "84", "+2"))
	tiles.add_child(FcStatTile.make("Cash", "$42.1M", "-1.2M"))
	tiles.add_child(FcStatTile.make("Record", "31-12"))
	var chips := _flow()
	s.add_child(chips)
	for pair in [["Neutral", FcStatusChip.Tone.NEUTRAL], ["Info", FcStatusChip.Tone.INFO], ["Ready", FcStatusChip.Tone.SUCCESS], ["Injured", FcStatusChip.Tone.WARNING], ["Out", FcStatusChip.Tone.DANGER]]:
		chips.add_child(FcStatusChip.make(pair[0], pair[1]))
	var lines := VBoxContainer.new()
	lines.custom_minimum_size.x = 260
	lines.add_child(FcStatLine.make("Points per game", "24.3", true))
	lines.add_child(FcStatLine.make("Rebounds", "7.1"))
	lines.add_child(FcStatLine.make("Assists", "5.8"))
	s.add_child(_captioned("Stat lines", lines))
	var rows := [["Maya Okoro", "PG", 84, "24.3"], ["Dev Carter", "C", 79, "11.0"], ["Lena Voss", "SF", 76, "15.6"]]
	var columns := ["Player", "Pos", "OVR", "PPG"]
	s.add_child(_captioned("Data table (desktop)", FcDataTable.build(columns, rows, [0, 60, 60, 80], {"compact": false}), true))
	s.add_child(_captioned("Data table (compact, for touch layouts)", FcDataTable.build(columns, rows, [], {"compact": true}), true))
	s.add_child(_captioned("Data table (empty)", FcDataTable.build(columns, [], [], {"empty_title": "No players", "empty_text": "Sign a free agent to fill this list."}), true))


## FcTable on 400 sample rows (generated here for the demo, not game data): sortable headers, a portrait, rating badges and mini bars.
func _section_table() -> void:
	var s := _section("Table", "FcTable on 400 SAMPLE rows made up for this page. Click a header to sort, click or use the arrow keys to select, Enter to activate. Only about 20 rows exist as controls however long the list is.")
	var teams := [{"name": "Harbor Kings", "abbreviation": "HBK", "primary": "#1F3A5F", "secondary": "#C8A951"}, {"name": "Sky City", "abbreviation": "SKY", "primary": "#7A1F2B", "secondary": "#FFFFFF"},
		{"name": "Pine Wolves", "abbreviation": "PNW", "primary": "#1F5F3A", "secondary": "#EAF0FA"}]
	var firsts := ["Maya", "Dev", "Lena", "Omar", "Priya", "Tomas", "Ines", "Kofi", "Sora", "Hana"]
	var lasts := ["Okoro", "Carter", "Voss", "Haddad", "Rao", "Lind", "Duarte", "Mensah", "Ito", "Park"]
	var positions := ["PG", "SG", "SF", "PF", "C"]
	var rows: Array = []
	for i in 400:
		rows.append({"id": i + 1, "name": "%s %s" % [firsts[(i * 7 + i / 10) % 10], lasts[(i * 3 + i / 7) % 10]], "pos": positions[i % 5], "age": 19 + (i * 7) % 18, "ovr": 45 + (i * 37) % 50,
			"salary": 900000 + ((i * 7919) % 30) * 1000000, "contract": ((i * 13) % 100), "team": teams[i % 3]})
	var columns := [
		{"key": "portrait", "title": "", "width": 56, "kind": "custom", "sortable": false,
			"make": func() -> Control: return FcPlayerPortrait.new(),
			"bind": func(cell: Control, row: Dictionary) -> void: (cell as FcPlayerPortrait).setup(FcPlayerPresentation.subject("table_sample:%d" % row["id"], row["name"], row["team"], int(row["id"]) % 99), 32)},
		{"key": "name", "title": "Player"},
		{"key": "pos", "title": "Pos", "width": 56},
		{"key": "age", "title": "Age", "width": 56, "kind": "number"},
		{"key": "ovr", "title": "OVR", "width": 72, "kind": "rating", "align": "center"},
		{"key": "salary", "title": "Salary", "width": 100, "kind": "number", "format": func(v) -> String: return FcUiTables.money(int(v))},
		{"key": "contract", "title": "Contract used", "width": 130, "kind": "bar"}]
	var table := FcTable.new(columns, rows, {"row_height": 44, "max_rows": 8, "sort_key": "ovr", "sort_ascending": false})
	table.custom_minimum_size.y = 44 * 9 + 2
	s.add_child(table)
	s.add_child(_captioned("Table (compact, for touch layouts)", FcTable.build(columns, rows.slice(0, 3), {"compact": true}), true))
	s.add_child(_captioned("Table (empty)", FcTable.build(columns, [], {"empty_title": "No players", "empty_text": "Sign a free agent to fill this list."}), true))


func _demo_card(rarity: String, overall: int, player: String, extra: Dictionary = {}) -> Dictionary:
	var card := {"card_id": "demo_" + rarity, "rarity": rarity, "overall": overall, "position": "SG", "secondary": "", "name": player, "edition": "Base Edition",
		"team": "Harbor", "badges": ["a", "b"], "quantity": 1, "owned": true, "available": true, "mastery": 0, "art_path": ""}
	card.merge(extra, true)
	return card


func _section_cards() -> void:
	var s := _section("Cards", "Every rarity has its own frame, background and effects. States: hover (lift), focus, selected, inspected, face down, unowned, NEW, mastery frames. Sizes: mini to hero.")
	var rarities := _flow()
	s.add_child(rarities)
	var names := {"common": "Mason Vale", "uncommon": "Rico Tamsin", "rare": "Dev Carter", "epic": "Lena Voss", "legendary": "Maya Okoro", "mythic_future": "Unknown Rarity"}
	var overall := 60
	for rarity in names:
		var card := FcCardFace.new().setup(_demo_card(rarity, overall, names[rarity]))
		rarities.add_child(_captioned(rarity, card))
		overall += 7
	var states := _flow()
	s.add_child(states)
	var base := _demo_card("epic", 83, "Lena Voss")
	var variants := [["default", {}], ["hover", {"lift": 1.0}], ["selected", {"selected": true}], ["inspected", {"inspected": true}], ["face down", {"face_down": true}],
		["NEW", {"tag": "NEW"}], ["duplicate x3", {"tag": "DUPLICATE", "row": {"quantity": 3}}], ["not owned", {"row": {"owned": false}}], ["unavailable", {"row": {"available": false}}],
		["mastery 1", {"row": {"mastery": 1}}], ["mastery 3", {"row": {"mastery": 3}}], ["mastery 5", {"row": {"mastery": 5}}], ["price", {"caption": "500 credits"}]]
	for variant in variants:
		var options: Dictionary = variant[1]
		var row := base.duplicate()
		row.merge(options.get("row", {}), true)
		var card := FcCardFace.new().setup(row, options)
		if options.has("lift"):
			card.lift = float(options["lift"])
		states.add_child(_captioned(str(variant[0]), card))
	var sizes := _flow()
	s.add_child(sizes)
	for kind in ["mini", "small", "standard", "detail", "hero"]:
		var card := FcCardFace.new().setup(_demo_card("legendary", 94, "Maya Okoro"), {"size": FcCardFace.size_for(kind)})
		sizes.add_child(_captioned(kind, card))


## Team identity: every emblem, every crest shape, one crest at every size, home/away/alternate uniforms and 32 sample teams
## (made up for this page from the game's own nickname and colour-scheme lists, not real franchises).
func _section_teams() -> void:
	var s := _section("Teams", "One team, one crest everywhere: the shape comes from a hash of the team key, the emblem from the words of the nickname (a hash when no word matches), the colours from the branding. Teams below are SAMPLES.")
	var world_data = JSON.parse_string(FileAccess.get_file_as_string("res://data/generation/world.json"))
	var nicknames: Array = world_data["nicknames"]
	var schemes: Array = world_data["color_schemes"]
	var cities := ["Harbor", "Ridge", "Marlow", "Kestrel Bay", "Ashford", "Northgate", "Lakeview", "Cedar Falls", "Port Aurel", "Stonebridge", "Westmere", "Alder"]
	var emblems := _flow()
	s.add_child(_captioned("All %d emblems (on one crest shape)" % FcTeamLook.EMBLEMS.size(), emblems, true))
	for e in FcTeamLook.EMBLEMS:
		var l := FcTeamLook.resolve(FcTeamLook.subject("gallery_emblem", "Sample Team", "SMP", "#1F3A5F", "#F2F2F2", "#C8A951"))
		l["emblem"] = e
		l["shape"] = "shield"
		emblems.add_child(_captioned(e, FcTeamCrest.new().setup(l, 64, false)))
	var shapes := _flow()
	s.add_child(_captioned("All %d crest shapes" % FcTeamLook.SHAPES.size(), shapes, true))
	for sh in FcTeamLook.SHAPES:
		var l := FcTeamLook.resolve(FcTeamLook.subject("gallery_shape", "Sample Team", "SMP", "#8B1E2D", "#F5E6C8", "#1B1B1B"))
		l["shape"] = sh
		l["emblem"] = "star"
		shapes.add_child(_captioned(sh, FcTeamCrest.new().setup(l, 96)))
	var sizes := _flow()
	s.add_child(_captioned("One crest at 16, 24, 32, 48, 64, 96 and 128 px", sizes, true))
	var sample := FcTeamLook.resolve(FcTeamLook.subject("gallery_team:3", "Kestrel Bay Falconers", "KBF", "#0E7490", "#FFFFFF", "#FBBF24"))
	for px in [16, 24, 32, 48, 64, 96, 128]:
		sizes.add_child(_captioned(str(px), FcTeamCrest.new().setup(sample, px)))
	var uniforms := _flow()
	s.add_child(_captioned("Home, away and alternate uniforms", uniforms, true))
	for kind in ["home", "away", "alt"]:
		var u: Dictionary = sample["uniforms"][kind]
		uniforms.add_child(_captioned(kind, FcUniformPreview.new().setup({"uniform": {"primary": u["primary"], "secondary": u["secondary"], "number": 7, "abbreviation": sample["abbreviation"]}}, 72)))
	s.add_child(_captioned("Wordmark with crest", FcTeamWordmark.crest_and_name(sample, 56, FcUiTokens.TYPE_H1)))
	var teams := _flow()
	s.add_child(_captioned("32 sample teams", teams, true))
	for i in 32:
		var nick := str(nicknames[(i * 3) % nicknames.size()])
		var scheme: Array = schemes[i % schemes.size()]
		var look := FcTeamLook.resolve(FcTeamLook.subject("gallery_team:%d" % i, "%s %s" % [cities[i % cities.size()], nick], str(nick).substr(0, 3).to_upper(), scheme[0], scheme[1], scheme[2], nick))
		teams.add_child(_captioned(nick, FcTeamCrest.new().setup(look, 80)))


func _section_players() -> void:
	var s := _section("Players", "One resolver gives every player one look in every screen. Faces come from a hash of the player's key (never random); a Career player keeps the look he built; uniforms follow the team.")
	var faces := _flow()
	s.add_child(faces)
	var teams := [{"name": "Harbor Kings", "abbreviation": "HBK", "primary": "#1F3A5F", "secondary": "#C8A951"}, {"name": "Sky City", "abbreviation": "SKY", "primary": "#7A1F2B", "secondary": "#FFFFFF"},
		{"name": "Pine Wolves", "abbreviation": "PNW", "primary": "#1F5F3A", "secondary": "#EAF0FA"}]
	for i in 12:
		var subject := FcPlayerPresentation.subject("gallery_player:%d" % i, "Player %d" % i, teams[i % 3], 4 + i * 3)
		faces.add_child(_captioned("#%d" % i, FcPlayerPortrait.new().setup(subject, 72)))
	var showcase := _flow()
	s.add_child(showcase)
	var built := FcPlayerPresentation.subject("career_player:7", "Maya Okoro", teams[0], 11, {"skin": "tone_5", "hair": "locs", "face": "face_2", "facial_hair": "stubble"})
	var stage := FcShowcaseStage.new().setup(built, 200)
	showcase.add_child(_captioned("Showcase stage (a Career player's built look)", stage))
	showcase.add_child(_captioned("Uniform", FcUniformPreview.new().setup(stage.visual, 90)))
	var other := FcShowcaseStage.new().setup(FcPlayerPresentation.subject("owner_player:12", "Lena Voss", teams[1], 23), 200)
	showcase.add_child(_captioned("Showcase stage (derived look)", other))


## The portrait contact sheet (Phase E): 96 SAMPLE players as headshots, one player at every size, every skin tone by every hair style,
## and the figures with each facial-hair option. Reviewed from screenshots at the founder checkpoint.
func _section_portraits() -> void:
	var s := _section("Portraits", "SAMPLE players made up for this page. The same hash gives the same face at every size; faces differ in head shape, jaw, eyes, brows, nose and mouth even when skin, hair and face options match.")
	var teams := [{"name": "Harbor Kings", "abbreviation": "HBK", "primary": "#1F3A5F", "secondary": "#C8A951"}, {"name": "Sky City", "abbreviation": "SKY", "primary": "#8B1E2D", "secondary": "#F5E6C8"},
		{"name": "Pine Wolves", "abbreviation": "PNW", "primary": "#0B6E4F", "secondary": "#F4F1DE"}, {"name": "Ridge Barons", "abbreviation": "RDG", "primary": "#3B2F8F", "secondary": "#F0F0F0"}]
	var sheet := _flow()
	s.add_child(_captioned("96 headshots at 56 px", sheet, true))
	for i in 96:
		sheet.add_child(FcPlayerPortrait.new().setup(FcPlayerPresentation.subject("portrait_sheet:%d" % i, "Sample %d" % i, teams[i % 4], 1 + i % 99), 56, "head"))
	var sizes := _flow()
	s.add_child(_captioned("One player at 24, 32, 48, 64, 96, 128 px (bust)", sizes, true))
	var one := FcPlayerPresentation.subject("portrait_sheet:7", "Sample Seven", teams[1], 7)
	for px in [24, 32, 48, 64, 96, 128]:
		sizes.add_child(_captioned(str(px), FcPlayerPortrait.new().setup(one, px)))
	for px in [32, 48, 64]:
		sizes.add_child(_captioned("head %d" % px, FcPlayerPortrait.new().setup(one, px, "head")))
	var family := _flow()
	s.add_child(_captioned("The player family: chip rows, small and medium tiles (Owner and Career, rating tiers) beside the Dynasty cards of the same sizes (rarity)", family, true))
	var vm := {"subject": one, "name": "Sample Seven", "position": "SG", "secondary": "SF", "overall": 78, "team": teams[1]}
	var chips := VBoxContainer.new()
	chips.custom_minimum_size.x = 300
	for rating in [91, 78, 66, 52]:
		var row := vm.duplicate()
		row["overall"] = rating
		row["name"] = "Sample Player %d" % rating
		chips.add_child(FcPlayerChip.new().setup(row, "SG  ·  26  ·  SKY"))
	family.add_child(chips)
	family.add_child(_captioned("Tile small", FcPlayerCards.make(vm, FcPlayerCards.Size.SMALL)))
	family.add_child(_captioned("Tile medium", FcPlayerCards.make(vm, FcPlayerCards.Size.MEDIUM)))
	family.add_child(_captioned("Dynasty small", FcCardFace.new().setup(_demo_card("rare", 78, "Sample Seven"), {"size": FcCardFace.SIZE_SMALL})))
	family.add_child(_captioned("Dynasty standard", FcCardFace.new().setup(_demo_card("legendary", 91, "Sample Seven"), {"size": FcCardFace.SIZE_STANDARD})))
	s = _section("Portrait variety", "Skin tones by hair styles, facial hair, and the full-body showcase stage.")
	var grid := _flow()
	s.add_child(_captioned("Every skin tone (rows) by every hair style (columns)", grid, true))
	for skin in ["tone_1", "tone_2", "tone_3", "tone_4", "tone_5", "tone_6"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		for hair in ["bald", "short", "fade", "afro", "braids", "locs", "curly", "long"]:
			row.add_child(FcPlayerPortrait.new().setup(FcPlayerPresentation.subject("portrait_grid:%s:%s" % [skin, hair], "Grid", teams[0], 5, {"skin": skin, "hair": hair, "face": "face_2", "facial_hair": "none"}), 56))
		grid.add_child(row)
	var beards := _flow()
	s.add_child(_captioned("Facial hair: none, stubble, goatee, beard", beards, true))
	for fh in ["none", "stubble", "goatee", "beard"]:
		beards.add_child(FcPlayerPortrait.new().setup(FcPlayerPresentation.subject("portrait_fh:" + fh, "Beard", teams[2], 9, {"skin": "tone_4", "hair": "short", "face": "face_3", "facial_hair": fh}), 96))
	var stages := _flow()
	s.add_child(_captioned("Showcase stage (full body)", stages, true))
	for i in 3:
		stages.add_child(FcShowcaseStage.new().setup(FcPlayerPresentation.subject("portrait_stage:%d" % i, "Stage %d" % i, teams[i], 10 + i), 160))


func _section_broadcast() -> void:
	var s := _section("Broadcast set", "Scorebug, lower third and comparison bars for results screens in every mode.")
	var bug := FcScoreBug.new()
	bug.setup("HBR", 108, "SKY", 101, "Final", FcUiTokens.INFO, FcUiTokens.PRIMARY)
	s.add_child(bug)
	var third := FcLowerThird.new("Player of the game", "Maya Okoro: 31 points, 9 assists")
	s.add_child(third)
	var bars := VBoxContainer.new()
	bars.custom_minimum_size.x = 300
	bars.add_child(FcStatBar.new("Field goal %", 48.2, 43.9, "48.2%", "43.9%"))
	bars.add_child(FcStatBar.new("Rebounds", 41, 47))
	bars.add_child(FcStatBar.new("Turnovers", 11, 15, "", "", true))
	s.add_child(_captioned("Stat bars (the leader is bright; fewer turnovers lead)", bars))


func _section_franchise() -> void:
	var s := _section("Franchise set", "Letterhead and KPI strip for Owner Mode; tinted by the franchise colours.")
	var head := FcLetterhead.new()
	head.setup("Harbor Kings", "Season 3 - General manager", "HBK", "#1F3A5F", "#C8A951")
	s.add_child(head)
	var kpi := FcKpiStrip.new()
	kpi.set_items([{"label": "Cash", "value": "$42.1M", "delta": "-1.2M"}, {"label": "Payroll", "value": "$118M"}, {"label": "Record", "value": "31-12", "delta": "+3"}, {"label": "Attendance", "value": "96%"}])
	s.add_child(kpi)


func _section_motion() -> void:
	var s := _section("Motion", "Replays the standard animations. With Reduce motion on, movement is instant and fades are 80 ms.")
	var stage := _flow()
	s.add_child(stage)
	var sample := FcPanel.new("Sample panel", FcPanel.Variant.RAISED)
	sample.custom_minimum_size = Vector2(180, 80)
	var counter := FcUiTables.label("0", FcUiTokens.TYPE_DISPLAY, true)
	sample.add(counter)
	stage.add_child(sample)
	for pair in [["Pop in", func() -> void: FcMotion.pop_in(sample)], ["Fade in", func() -> void: FcMotion.fade_in(sample)],
			["Count to 12,500", func() -> void: FcMotion.count_to(counter, 0, 12500, 0.9, _with_commas)]]:
		var button := FcButton.make(pair[0], FcButton.Variant.SECONDARY, pair[1])
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		stage.add_child(button)


func _with_commas(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return ("-" if value < 0 else "") + digits + out
