class_name FcContentService
extends RefCounted
## What the game holds to use content: the preferences' content folder, the loader and the
## latest load report. Screens and Dynasty ask this for the catalog; they never open release
## files themselves.

var preferences: FcPreferences
var store: FcLocalContentStore
var loader: FcContentLoader
var report: FcContentLoadReport = FcContentLoadReport.new()


func _init(player_preferences: FcPreferences, attribute_definitions: FcDefinitionSet = null,
		starter_directory: String = FcContentLoader.STARTER_DIR) -> void:
	preferences = player_preferences
	store = FcLocalContentStore.new(preferences.effective_content_root())
	store.definitions = attribute_definitions
	loader = FcContentLoader.new(store, attribute_definitions, starter_directory)
	refresh()


## Loads again from the content folder (after a publish, a rollback or a changed setting).
func refresh() -> FcContentLoadReport:
	if store.root_dir() != preferences.effective_content_root():
		store = FcLocalContentStore.new(preferences.effective_content_root())
		store.definitions = loader.definitions
		loader.store = store
	report = loader.load_active()
	if report.is_degraded() or not report.has_content():
		push_warning(report.summary())
	return report


## The loaded definitions (null only if not even the starter content could load).
func catalog() -> FcContentCatalog:
	return report.catalog


func rollback_to(release_id: String) -> FcContentResult:
	var r := loader.rollback_to(release_id)
	if r.is_ok():
		refresh()
	return r
