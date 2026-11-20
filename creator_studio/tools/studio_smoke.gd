extends SceneTree
## Scripted end-to-end check of Creator Studio (run from the creator_studio folder):
##   godot_console --headless --path creator_studio --script res://tools/studio_smoke.gd
## It drives the real screen through its action methods in a scratch content folder: create a draft,
## see it fail validation, fix it, approve and publish twice, roll back, and read the result back with
## the game's own loader. Add "-- --screenshot" (without --headless) to also save a picture of the screen.

const ROOT := "user://smoke_content"
var _failures: int = 0


func _check(condition: bool, text: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + text)
	else:
		print("ok:   " + text)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	FcSafeFile.remove_tree(ROOT)
	DirAccess.remove_absolute("user://smoke_settings.cfg")
	var settings := FcStudioSettings.new("user://smoke_settings.cfg")
	settings.content_root = ROOT
	var app := FcStudioApp.new()
	app.setup(settings)
	root.add_child(app)
	await process_frame

	var draft := app.create_draft("Smoke Test")
	_check(draft == "smoke_test", "draft created")
	_check(app.validate_draft() != null and not app.validate_draft().is_ok(), "an empty draft fails the check")
	_check(app._publish_button.disabled, "publish stays disabled until the check passes")

	var ws := app.workspace
	ws.save_definition(draft, "players/smoke_player.json", {"player_id": "smoke_player", "display_name": "Smoke Player",
		"position": "SG", "attributes": {"three_point": 70}})
	ws.save_definition(draft, "cards/smoke_card.json", {"card_id": "smoke_card", "player_id": "smoke_player",
		"title": "Smoke Card", "rarity": "common", "revision": 1})
	_check(app.validate_draft().is_ok(), "the filled draft passes")
	_check(not app._publish_button.disabled, "publish is enabled after a passing check")

	var refused := app.approve_and_publish("", "")
	_check(not refused.is_ok() and app.store.list_release_ids().is_empty(), "no name and note: nothing published")
	var first := app.approve_and_publish("Owner", "first release")
	_check(first.is_ok(), "approved and published: %s" % first.message)
	ws.save_definition(draft, "cards/smoke_card_two.json", {"card_id": "smoke_card_two", "player_id": "smoke_player",
		"title": "Smoke Card Two", "rarity": "rare", "revision": 1})
	var second := app.approve_and_publish("Owner", "second release")
	_check(second.is_ok(), "second release published")
	_check(app.store.list_release_ids().size() == 2, "both releases kept")

	var game_side := FcContentLoader.new(FcLocalContentStore.new(ROOT), FcDefinitionSet.load_default())
	var report := game_side.load_active()
	_check(report.loaded_release_id == (second.value as FcContentManifest).release_id and report.catalog.has_card("smoke_card_two"),
		"the game's loader reads the newest release")
	_check(app.make_active((first.value as FcContentManifest).release_id).is_ok(), "rolled back from the screen")
	_check(not game_side.load_active().catalog.has_card("smoke_card_two"), "the game now sees the older release")
	_check(app._releases.item_count == 2, "both releases are listed on the screen")

	if "--screenshot" in OS.get_cmdline_user_args():
		for i in 5:
			await process_frame
		var image := root.get_texture().get_image()
		image.save_png(ProjectSettings.globalize_path("user://studio_screenshot.png"))
		print("screenshot: " + ProjectSettings.globalize_path("user://studio_screenshot.png"))
	FcSafeFile.remove_tree(ROOT)
	print("Studio smoke: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)
