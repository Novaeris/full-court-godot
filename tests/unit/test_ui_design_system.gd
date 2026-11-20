extends FcTestCase
## The design system itself (docs/UI_POLISH_PLAN.md, section 3): contrast of every text colour on every surface, the mode skins and
## their whitelist, the theme (type variations, text scale), fonts, icons, rating tiers and the reduce-motion preference.

const SURFACES := [FcUiTokens.BG, FcUiTokens.SURFACE, FcUiTokens.SURFACE_RAISED]
const PREFS_PATH := "user://test_prefs_design_system.cfg"


func after_each() -> void:
	FcMotion.reduced = false
	FcUiTokens.touch_mode = false
	FcUiTheme.build(1)   # puts the text scale, accent and skin back to the defaults for the tests that follow
	DirAccess.remove_absolute(PREFS_PATH)


# --- contrast -------------------------------------------------------------------------------------------------------

func test_contrast_maths_is_right() -> void:
	assert_between(FcUiContrast.ratio(Color.WHITE, Color.BLACK), 20.9, 21.1, "white on black is 21:1")
	assert_between(FcUiContrast.ratio(Color.WHITE, Color.WHITE), 0.99, 1.01, "identical colours are 1:1")


func test_body_text_is_readable_on_every_surface() -> void:
	for surface in SURFACES:
		assert_true(FcUiContrast.ratio(FcUiTokens.TEXT, surface) >= 7.0, "text on %s" % str(surface))
		assert_true(FcUiContrast.ratio(FcUiTokens.TEXT_MUTED, surface) >= 4.5, "muted text on %s" % str(surface))
		assert_true(FcUiContrast.ratio(FcUiTokens.GOLD, surface) >= 4.5, "heading colour on %s" % str(surface))


func test_status_and_accent_colours_are_readable_as_text() -> void:
	for color in [FcUiTokens.PRIMARY, FcUiTokens.INFO, FcUiTokens.STEEL, FcUiTokens.SUCCESS, FcUiTokens.WARNING, FcUiTokens.DANGER]:
		for surface in SURFACES:
			assert_true(FcUiContrast.ratio(color, surface) >= 4.5, "%s on %s" % [str(color), str(surface)])
	assert_true(FcUiContrast.ratio(FcUiTokens.TEXT_DISABLED, FcUiTokens.SURFACE) >= 3.0, "disabled text is dim but still legible")


func test_text_on_solid_buttons_is_readable() -> void:
	for fill in [FcUiTokens.PRIMARY, FcUiTokens.DANGER, FcUiTokens.INFO, FcUiTokens.STEEL]:
		assert_true(FcUiContrast.ratio(FcUiContrast.readable_on(fill), fill) >= 4.5, "button text on %s" % str(fill))


func test_every_rating_tier_colour_is_readable_on_its_badge() -> void:
	var tiers := FcUiRatingTiers.load_default()
	for color in tiers.colors():
		var badge := FcUiTokens.SURFACE_RAISED.lerp(color, 0.16)
		assert_true(FcUiContrast.ratio(color, badge) >= 4.5, "tier %s on its badge" % str(color))
		assert_true(FcUiContrast.ratio(color, FcUiTokens.SURFACE) >= 4.5, "tier %s on a surface" % str(color))


func test_status_chip_tones_are_readable_on_their_fill() -> void:
	for tone in FcStatusChip.COLORS:
		var color: Color = FcStatusChip.COLORS[tone]
		assert_true(FcUiContrast.ratio(color, FcUiTokens.SURFACE.lerp(color, 0.15)) >= 4.5, "chip tone %s" % str(tone))


func test_ensure_lightens_a_dark_colour_until_it_passes() -> void:
	var dark := Color("1F3A5F")
	assert_true(FcUiContrast.ratio(dark, FcUiTokens.SURFACE_RAISED) < 4.5, "the franchise default navy is too dark")
	assert_true(FcUiContrast.ratio(FcUiContrast.ensure(dark, FcUiTokens.SURFACE_RAISED), FcUiTokens.SURFACE_RAISED) >= 4.5, "ensure() fixes it")


# --- skins ----------------------------------------------------------------------------------------------------------

func test_every_skin_resolves_with_a_readable_accent() -> void:
	assert_eq(FcModeSkin.ids().size(), 4, "neutral, broadcast, collectible, franchise")
	for id in FcModeSkin.ids():
		var skin := FcModeSkin.resolve(id)
		assert_eq(skin["id"], id)
		for surface in SURFACES:
			assert_true(FcUiContrast.ratio(skin["accent"], surface) >= 4.5, "%s accent on %s" % [id, str(surface)])


func test_a_skin_can_only_change_the_whitelisted_properties() -> void:
	var skin := FcModeSkin.resolve(FcModeSkin.NEUTRAL, {"density": 1.1, "danger_color": Color.RED, "TEXT": Color.BLACK, "header": "letterhead"})
	assert_eq(skin["density"], 1.1)
	assert_eq(skin["header"], "letterhead")
	assert_true(not skin.has("danger_color") and not skin.has("TEXT"), "non-whitelisted keys are dropped")
	for key in skin:
		assert_true(key in FcModeSkin.WHITELIST or key == "id", "unexpected skin key " + str(key))


func test_skin_values_are_clamped_and_unknown_ids_fall_back() -> void:
	var skin := FcModeSkin.resolve("no_such_skin", {"density": 5.0, "motion": -2.0})
	assert_eq(skin["id"], FcModeSkin.NEUTRAL, "unknown id becomes neutral")
	assert_eq(skin["density"], 1.2, "density clamps")
	assert_eq(skin["motion"], 0.0, "motion clamps")


func test_the_three_personalities_differ_in_character_not_in_components() -> void:
	var broadcast := FcModeSkin.resolve(FcModeSkin.BROADCAST)
	var collectible := FcModeSkin.resolve(FcModeSkin.COLLECTIBLE)
	var franchise := FcModeSkin.resolve(FcModeSkin.FRANCHISE)
	assert_eq(broadcast["header"], "lower_third")
	assert_eq(collectible["background"], "spotlight")
	assert_eq(franchise["header"], "letterhead")
	assert_true(franchise["motion"] < collectible["motion"], "Owner is calmer than Dynasty")
	assert_eq(broadcast["numerals"], "display", "broadcast shows condensed numerals")


func test_franchise_skin_takes_a_team_colour_and_stays_readable() -> void:
	var navy := FcModeSkin.franchise("#1F3A5F")
	assert_true(FcUiContrast.ratio(navy["accent"], FcUiTokens.SURFACE_RAISED) >= 4.5, "a dark team colour is lightened")
	var invalid := FcModeSkin.franchise("not a colour")
	assert_eq(invalid["accent"], FcModeSkin.resolve(FcModeSkin.FRANCHISE)["accent"], "an invalid colour keeps the default")


# --- theme ----------------------------------------------------------------------------------------------------------

func test_the_theme_defines_every_variation_the_kit_uses() -> void:
	var t := FcUiTheme.build(1)
	var expected := {"PrimaryButton": "Button", "DangerButton": "Button", "GhostButton": "Button", "IconButton": "GhostButton", "TabButton": "Button",
		"ChipButton": "Button", "SegmentButton": "Button", "HeadingLabel": "Label", "DisplayLabel": "Label", "NumericLabel": "Label",
		"MutedLabel": "Label", "CaptionLabel": "Label", "RaisedPanel": "PanelContainer", "FlatPanel": "PanelContainer", "ModalPanel": "PanelContainer",
		"KpiPanel": "PanelContainer", "LetterheadPanel": "PanelContainer", "LowerThirdPanel": "PanelContainer", "ScorePanel": "PanelContainer",
		"ErrorLineEdit": "LineEdit", "ErrorOption": "OptionButton", "SuccessProgress": "ProgressBar", "DangerProgress": "ProgressBar", "GoldProgress": "ProgressBar"}
	for name in expected:
		assert_eq(str(t.get_type_variation_base(name)), expected[name], "variation " + name)


func test_the_theme_uses_the_bundled_fonts() -> void:
	var t := FcUiTheme.build(1)
	assert_true(t.default_font != null, "Inter is the default font")
	assert_true(t.get_font("font", "HeadingLabel") != null, "headings use a font")
	assert_true(FcUiFonts.display(600) != null and FcUiFonts.display(700) != FcUiFonts.display(600), "Barlow Condensed has distinct weights")
	assert_true(FcUiFonts.body(400) != FcUiFonts.body(700), "Inter has distinct weights")
	assert_true(FcUiFonts.body(400) == FcUiFonts.body(400), "fonts are cached")
	assert_true(FcUiFonts.body(400, true) != FcUiFonts.body(400, false), "tabular figures are a separate face")


func test_text_scale_reaches_headings_and_labels() -> void:
	FcUiTheme.build(0)
	var small := FcUiTables.label("x", 28)
	assert_eq(small.get_theme_font_size("font_size"), 24, "28 at Small is 24")
	FcUiTheme.build(2)
	var large := FcUiTables.label("x", 28)
	assert_eq(large.get_theme_font_size("font_size"), 34, "28 at Large is 34")
	var heading := FcUiTables.label("x", 28, true)
	assert_eq(heading.get_theme_font_size("font_size"), roundi(34 * 1.12), "headings are drawn slightly larger (condensed face)")
	assert_eq(heading.theme_type_variation, "HeadingLabel", "bold labels are headings in the display font")
	FcUiTheme.build(1)
	assert_eq(FcUiTables.label("x", 15).get_theme_font_size("font_size"), 15, "Normal is the design size")
	assert_eq(FcUiTheme.font_size(0), 13, "the body sizes of the three settings are unchanged")
	assert_eq(FcUiTheme.font_size(2), 18)


func test_text_never_scales_below_ten_pixels() -> void:
	FcUiTheme.build(0)
	assert_eq(FcUiTokens.fs(11), 10, "11 at Small is 10, not 9")


func test_the_theme_follows_the_skin_accent_and_density() -> void:
	FcUiTheme.build(1, FcModeSkin.resolve(FcModeSkin.BROADCAST))
	assert_eq(FcUiTheme.accent, FcModeSkin.resolve(FcModeSkin.BROADCAST)["accent"])
	var roomy := FcUiTheme.build(1, FcModeSkin.resolve(FcModeSkin.COLLECTIBLE))
	var tight := FcUiTheme.build(1, FcModeSkin.resolve(FcModeSkin.BROADCAST))
	assert_true(roomy.get_constant("separation", "VBoxContainer") > tight.get_constant("separation", "VBoxContainer"), "Dynasty is roomier than broadcast screens")


func test_old_theme_constants_still_exist_for_existing_screens() -> void:
	assert_eq(FcUiTheme.BACKGROUND, FcUiTokens.BG)
	assert_eq(FcUiTheme.ACCENT, FcUiTokens.PRIMARY)
	assert_eq(FcUiTheme.SIZE_NAMES.size(), 3)
	assert_eq(FcUiTheme.SIZES.size(), 3)


# --- icons, tiers, preferences ------------------------------------------------------------------------------------------

func test_icons_load_and_unknown_icons_are_harmless() -> void:
	for icon in ["check", "x", "search", "loader", "info", "circle-check", "triangle-alert", "circle-alert", "layers", "plus", "settings", "chevron-left", "trophy"]:
		assert_true(FcUiIcons.has_icon(icon), "icon " + icon)
	assert_true(FcUiIcons.texture("no-such-icon") == null)
	assert_true(FcUiIcons.texture("") == null)
	var rect := FcUiIcons.rect("no-such-icon")
	assert_true(rect.texture == null, "a missing icon is an empty rect, not an error")
	rect.free()


func test_bundled_assets_carry_their_licences() -> void:
	for path in ["res://assets/fonts/OFL-Inter.txt", "res://assets/fonts/OFL-BarlowCondensed.txt", "res://assets/icons/lucide/LICENSE.txt", "res://assets/README.md"]:
		assert_true(FileAccess.file_exists(path), "licence file " + path)
	assert_true("ISC" in FileAccess.get_file_as_string("res://assets/icons/lucide/LICENSE.txt"), "Lucide is ISC licensed")
	assert_true("SIL OPEN FONT LICENSE" in FileAccess.get_file_as_string("res://assets/fonts/OFL-Inter.txt").to_upper(), "Inter is OFL")


func test_rating_tiers_follow_the_data_file() -> void:
	var tiers := FcUiRatingTiers.load_default()
	assert_eq(tiers.tier_count(), 6)
	assert_eq(tiers.tier_for(0)["name"], "Reserve")
	assert_eq(tiers.tier_for(54)["name"], "Reserve")
	assert_eq(tiers.tier_for(55)["name"], "Depth")
	assert_eq(tiers.tier_for(92)["name"], "Elite")
	assert_eq(tiers.tier_for(99)["name"], "Elite")
	assert_eq(tiers.tier_for(-5)["name"], "Reserve", "out of range falls to the lowest tier")
	var distinct := {}
	for c in tiers.colors():
		distinct[c.to_html()] = true
	assert_eq(distinct.size(), 6, "every tier has its own colour")


func test_a_missing_tier_file_still_gives_a_usable_tier() -> void:
	var tiers := FcUiRatingTiers.load_default("res://data/ui/does_not_exist.json")
	assert_eq(tiers.tier_count(), 1)
	assert_eq(tiers.color_for(80), FcUiTokens.TEXT_MUTED)


func test_reduce_motion_is_remembered_in_preferences() -> void:
	var prefs := FcPreferences.new(PREFS_PATH)
	assert_true(not prefs.reduce_motion, "off by default")
	prefs.reduce_motion = true
	assert_true(prefs.save_file(), "saved")
	assert_true(FcPreferences.new(PREFS_PATH).reduce_motion, "loaded back")


func test_the_app_applies_the_motion_preference_on_start() -> void:
	var app := FcApp.new()
	app.preferences = FcPreferences.new(PREFS_PATH)
	app.preferences.reduce_motion = true
	app.saves = FcSaveManager.new("user://test_saves_design_system")
	Engine.get_main_loop().root.add_child(app)
	app.setup()
	assert_true(FcMotion.reduced, "the app turns reduced motion on from the saved preference")
	Engine.get_main_loop().root.remove_child(app)
	app.free()
	FcSafeFile.remove_tree("user://test_saves_design_system")
