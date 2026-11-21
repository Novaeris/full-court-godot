class_name FcStudioApp
extends Control
## Creator Studio's one screen: pick a draft, check it, approve it, publish it, and manage releases.
##
## All the work is done by the shared classes in src/content (the same code the game uses to read
## the result). This file only shows things and passes the owner's explicit decisions along.
## Nothing here publishes on its own: only the "Approve and publish" button, after a confirmation,
## creates an approval and calls the publisher.

var settings: FcStudioSettings
var defs: FcDefinitionSet
var store: FcLocalContentStore
var workspace: FcDraftWorkspace
var publisher: FcPublisher
var loader: FcContentLoader

var _draft_id: String = ""
var _last_validation: FcContentResult = null

var _root_label: Label
var _drafts: ItemList
var _new_name: LineEdit
var _files_text: RichTextLabel
var _previews: HFlowContainer
var _report: RichTextLabel
var _approver: LineEdit
var _note: LineEdit
var _publish_button: Button
var _releases: ItemList
var _status: Label
var _confirm: ConfirmationDialog
var _folder_dialog: FileDialog


func _ready() -> void:
	setup()


## Builds the screen. Safe to call twice; tests and the smoke tool call it directly.
func setup(studio_settings: FcStudioSettings = null) -> void:
	if _status != null:
		return
	settings = studio_settings if studio_settings != null else FcStudioSettings.new()
	theme = FcUiTheme.build(1)   # the same look as the game (fonts, colours, buttons); the assets junction supplies the fonts
	defs = FcDefinitionSet.load_default()
	_open_store()
	_build_ui()
	refresh_all()


func _open_store() -> void:
	var root := settings.effective_root()
	store = FcLocalContentStore.new(root)
	store.definitions = defs
	workspace = FcDraftWorkspace.new(root.path_join("drafts"), defs)
	publisher = FcPublisher.new(store, defs)
	loader = FcContentLoader.new(store, defs)


# ----- Actions (called by the buttons; also callable directly by tools and tests) -----

func create_draft(display_name: String) -> String:
	var id := workspace.create_draft(display_name, int(Time.get_unix_time_from_system()))
	if id.is_empty():
		_say("Could not create a draft with that name.")
		return ""
	_draft_id = id
	_say("Created draft '%s'. Put definition files in its folder (Open draft folder), then Check." % id)
	refresh_all()
	return id


func select_draft(draft_id: String) -> void:
	_draft_id = draft_id
	_last_validation = null
	refresh_all()


## Checks the selected draft. Never publishes.
func validate_draft() -> FcContentResult:
	if _draft_id.is_empty():
		_say("Choose a draft first.")
		return null
	_last_validation = workspace.validate(_draft_id)
	refresh_all()
	return _last_validation


## The owner's decision. Creates the approval from the typed name and note, then publishes.
## Returns the publisher's result. Called only after the confirmation dialog.
func approve_and_publish(approver_name: String, note: String) -> FcContentResult:
	var validation := validate_draft()
	if validation == null or not validation.is_ok():
		_say("Not published: fix the problems listed above first.")
		return FcContentResult.failure(FcContentResult.Code.INVALID, "the draft does not validate")
	var content := workspace.content_dir(_draft_id)
	var approval := FcApproval.grant(approver_name, note, FcPublisher.draft_hash(content))
	if approval == null:
		_say("Not published: type your name and a short approval note.")
		return FcContentResult.failure(FcContentResult.Code.NOT_APPROVED, "name and note are required")
	settings.approver = approver_name.strip_edges()
	settings.save_file()
	var result := publisher.publish(content, approval)
	if result.is_ok():
		var m: FcContentManifest = result.value
		_say("Published release %s (version %d). It is now the active release." % [m.release_id, m.content_version])
	else:
		_say("Not published: %s" % result.message)
	refresh_all()
	return result


func make_active(release_id: String) -> FcContentResult:
	var result := loader.rollback_to(release_id)
	_say("Release %s is now active." % release_id if result.is_ok() else "Could not activate it: %s" % result.message)
	refresh_all()
	return result


func choose_folder(path: String) -> void:
	if not FcContentPaths.is_valid_root(path):
		_say("That folder cannot be used.")
		return
	settings.content_root = path
	settings.save_file()
	_open_store()
	_draft_id = ""
	_last_validation = null
	refresh_all()


# ----- Screen -----

func refresh_all() -> void:
	if _status == null:
		return
	_root_label.text = "Content folder: %s" % settings.effective_root()
	_drafts.clear()
	var selected := -1
	for d in workspace.list_drafts():
		_drafts.add_item("%s  (%s)" % [d["name"], d["draft_id"]])
		_drafts.set_item_metadata(_drafts.item_count - 1, d["draft_id"])
		if d["draft_id"] == _draft_id:
			selected = _drafts.item_count - 1
	if selected >= 0:
		_drafts.select(selected)
	_refresh_draft_panel()
	_refresh_previews()
	_refresh_releases()


func _refresh_draft_panel() -> void:
	var ready := false
	if _draft_id.is_empty() or not workspace.has_draft(_draft_id):
		_files_text.text = "No draft selected."
		_report.text = ""
	else:
		var files := FcSafeFile.list_files(workspace.content_dir(_draft_id))
		_files_text.text = "Files in this draft (%d):\n%s" % [files.size(), "\n".join(files) if not files.is_empty() else "(none yet)"]
		if _last_validation == null:
			_report.text = "Not checked yet. Press Check."
		elif _last_validation.is_ok():
			_report.text = "[color=green]All checks passed.[/color] The draft can be approved."
			ready = true
		else:
			var lines := "[color=red]%s[/color]" % _last_validation.message
			for p in _last_validation.problems:
				lines += "\n- %s" % p
			_report.text = lines
	_publish_button.disabled = not ready


func _refresh_releases() -> void:
	_releases.clear()
	var active := str(store.read_active().value) if store.read_active().is_ok() else ""
	for r in loader.list_releases():
		var tag := ""
		if r["release_id"] == active:
			tag = "  [ACTIVE]"
		if not r["valid"]:
			tag += "  [DAMAGED]"
		_releases.add_item("version %d   %s%s" % [r["content_version"], r["release_id"], tag])
		_releases.set_item_metadata(_releases.item_count - 1, r["release_id"])


func _say(text: String) -> void:
	if _status != null:
		_status.text = text


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var backdrop := ColorRect.new()
	backdrop.color = FcUiTokens.BG
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", FcUiTokens.SPACE_3)
	var mark := FcBrand.logo(FcBrand.NOVAERIS_MARK, 56, "Novaeris")
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(mark)
	var title_box := VBoxContainer.new()
	title_box.add_theme_constant_override("separation", 0)
	title_box.add_child(FcUiTables.label("Full Court Creator Studio", FcUiTokens.TYPE_H1, true))
	var intro := FcUiTables.label("Edit a draft, check it, then approve it to publish a release the game can load. Nothing reaches the game until you approve.", FcUiTokens.TYPE_SMALL)
	intro.theme_type_variation = "MutedLabel"
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_box.add_child(intro)
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_box)
	box.add_child(header)

	var folder_row := HBoxContainer.new()
	_root_label = Label.new()
	_root_label.theme_type_variation = "MutedLabel"
	_root_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	folder_row.add_child(_root_label)
	folder_row.add_child(_button("Choose folder...", func(): _folder_dialog.popup_centered_ratio(0.6), FcButton.Variant.GHOST))
	folder_row.add_child(_button("Open folder", func(): _open_in_explorer(settings.effective_root()), FcButton.Variant.GHOST))
	box.add_child(folder_row)

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 16)
	box.add_child(columns)

	# Left: drafts and releases
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(340, 0)
	left.add_theme_constant_override("separation", FcUiTokens.SPACE_2)
	columns.add_child(left)
	left.add_child(_heading("Drafts"))
	_drafts = ItemList.new()
	_drafts.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_drafts.item_selected.connect(func(i: int): select_draft(str(_drafts.get_item_metadata(i))))
	left.add_child(_drafts)
	var new_row := HBoxContainer.new()
	_new_name = LineEdit.new()
	_new_name.placeholder_text = "New draft name"
	_new_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_row.add_child(_new_name)
	new_row.add_child(_button("Create", func():
		if create_draft(_new_name.text) != "":
			_new_name.text = "", FcButton.Variant.PRIMARY))
	left.add_child(new_row)
	left.add_child(_heading("Releases"))
	_releases = ItemList.new()
	_releases.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(_releases)
	left.add_child(_button("Make the selected release active (rollback)", func():
		var picked := _releases.get_selected_items()
		if picked.is_empty():
			_say("Select a release first.")
		else:
			make_active(str(_releases.get_item_metadata(picked[0])))))

	# Right: the selected draft, with a read-only preview of its cards
	var right_scroll := ScrollContainer.new()
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	columns.add_child(right_scroll)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", FcUiTokens.SPACE_2)
	right_scroll.add_child(right)
	right.add_child(_heading("Selected draft"))
	_files_text = RichTextLabel.new()
	_files_text.custom_minimum_size = Vector2(0, 120)
	right.add_child(_files_text)
	var draft_row := HBoxContainer.new()
	draft_row.add_child(_button("Open draft folder", func():
		if not _draft_id.is_empty():
			_open_in_explorer(workspace.content_dir(_draft_id))))
	draft_row.add_child(_button("Check", validate_draft, FcButton.Variant.PRIMARY))
	right.add_child(draft_row)
	right.add_child(_heading("Card previews (read-only)"))
	_previews = HFlowContainer.new()
	_previews.add_theme_constant_override("h_separation", FcUiTokens.SPACE_3)
	_previews.add_theme_constant_override("v_separation", FcUiTokens.SPACE_3)
	right.add_child(_previews)
	right.add_child(_heading("Check report"))
	_report = RichTextLabel.new()
	_report.bbcode_enabled = true
	_report.custom_minimum_size = Vector2(0, 120)
	right.add_child(_report)
	right.add_child(_heading("Owner approval"))
	_approver = LineEdit.new()
	_approver.placeholder_text = "Your name (the approver)"
	_approver.text = settings.approver
	right.add_child(_approver)
	_note = LineEdit.new()
	_note.placeholder_text = "Approval note (what this release is)"
	right.add_child(_note)
	_publish_button = _button("Approve and publish...", func(): _confirm.popup_centered(), FcButton.Variant.PRIMARY)
	right.add_child(_publish_button)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	var credit := FcUiTables.label("A Novaeris tool", FcUiTokens.TYPE_SMALL)
	credit.theme_type_variation = "CaptionLabel"
	footer.add_child(credit)
	box.add_child(footer)

	_confirm = ConfirmationDialog.new()
	_confirm.title = "Publish this release?"
	_confirm.dialog_text = "This approves the checked draft and makes it the active release. The game will load it. Previous releases are kept."
	_confirm.confirmed.connect(func(): approve_and_publish(_approver.text, _note.text))
	add_child(_confirm)
	_folder_dialog = FileDialog.new()
	_folder_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_folder_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_folder_dialog.dir_selected.connect(choose_folder)
	add_child(_folder_dialog)


func _button(text: String, action: Callable, variant: FcButton.Variant = FcButton.Variant.SECONDARY) -> Button:
	return FcButton.make(text, variant, action)


func _heading(text: String) -> Label:
	return FcUiTables.label(text, FcUiTokens.TYPE_H3, true)


## Read-only previews of the cards in the selected draft, drawn with the game's own card face (so what you see is how the card will look).
## It only reads the draft's card and player files; nothing is written, and a file that cannot be read is skipped.
func _refresh_previews() -> void:
	for c in _previews.get_children():
		_previews.remove_child(c)
		c.queue_free()
	if _draft_id.is_empty() or not workspace.has_draft(_draft_id):
		return
	var dir := workspace.content_dir(_draft_id)
	var shown := 0
	for path in FcSafeFile.list_files(dir):
		if not str(path).begins_with("cards/") or not str(path).ends_with(".json") or shown >= 8:
			continue
		var card = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(str(path))))
		if not (card is Dictionary):
			continue
		var player = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("players/%s.json" % str(card.get("player_id", "")))))
		var has_player: bool = player is Dictionary
		var overall := int(card.get("overall", player.get("overall", 0) if has_player else 0))
		var player_name := str(player.get("display_name", card.get("title", "?"))) if has_player else str(card.get("title", "?"))
		var row := {"card_id": str(card.get("card_id", "")), "player_id": str(card.get("player_id", "")), "name": player_name, "edition": str(card.get("title", "")),
			"rarity": str(card.get("rarity", "common")), "overall": overall, "position": str(player.get("position", "")) if has_player else "", "team": "", "badges": [],
			"quantity": 1, "owned": true, "available": overall > 0, "mastery": 0, "art_path": str(card.get("art_path", ""))}
		_previews.add_child(FcCardFace.new().setup(row, {"size": FcCardFace.SIZE_SMALL}))
		shown += 1
	if shown == 0:
		var note := FcUiTables.label("No cards in this draft yet.", FcUiTokens.TYPE_SMALL)
		note.theme_type_variation = "MutedLabel"
		_previews.add_child(note)


func _open_in_explorer(path: String) -> void:
	FcSafeFile.make_dir(path)
	OS.shell_open(ProjectSettings.globalize_path(path))
