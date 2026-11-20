extends FcTestCase
## Dynasty foundation: profile, ledger, currencies, ownership, duplicates, atomic commit, save/load and migration.

const DIR := "user://test_dynasty"

var store: FcDynastyStore


func before_each() -> void:
	FcContentFixture.wipe(DIR)
	store = FcDynastyStore.new(DIR)


func after_each() -> void:
	FcContentFixture.wipe(DIR)


func _profile() -> FcDynastyProfile:
	return FcDynastyProfile.create("Harbor Kings", "hbk", 12345, "fcr_test")


func test_profile_creation_and_round_trip() -> void:
	var p := _profile()
	assert_eq(p.abbreviation, "HBK", "abbreviation upper-cased")
	assert_true(p.profile_id.begins_with("fcd_"), "stable profile id")
	assert_eq(p.profile_id, _profile().profile_id, "profile id is deterministic from the seed")
	FcDynastyEconomy.apply(p, "test", "x", {"credits": 500})
	FcDynastyCollection.grant_card(p, "card_a", 1, {"title": "A"}, "tx_000001")
	var again := FcDynastyProfile.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())))
	assert_eq(again.to_dict(), p.to_dict(), "a profile survives JSON unchanged")
	assert_eq(again.rng_seed, 12345, "seed kept (as text)")


func test_balances_never_go_negative() -> void:
	var p := _profile()
	FcDynastyEconomy.apply(p, "grant", "x", {"credits": 100})
	var r := FcDynastyEconomy.spend(p, "buy", "x", {"credits": 101})
	assert_true(not r.ok and r.code == "insufficient_funds", "overspending refused")
	assert_eq(p.balance("credits"), 100, "balance untouched by a refused spend")
	var multi := FcDynastyEconomy.apply(p, "mixed", "x", {"credits": -50, "tokens": -1})
	assert_true(not multi.ok, "one short currency refuses the whole transaction")
	assert_eq(p.balance("credits"), 100, "no partial change")
	assert_true(not FcDynastyEconomy.apply(p, "bad", "x", {"gold": 5}).ok, "unknown currency refused")


func test_requests_are_idempotent_and_ledger_numbers_are_stable() -> void:
	var p := _profile()
	var a := FcDynastyEconomy.apply(p, "grant", "x", {"credits": 10}, [], "req1")
	assert_eq(a.data["txn"]["txn_id"], "tx_000001", "first txn id")
	var prior := FcDynastyEconomy.previous(p, "req1")
	assert_eq(prior["txn_id"], "tx_000001", "a request id finds its transaction")
	assert_true(FcDynastyEconomy.previous(p, "other").is_empty(), "unknown request is empty")


func test_collection_keeps_editions_separate_and_counts_copies() -> void:
	var p := _profile()
	var first := FcDynastyCollection.grant_card(p, "reed_rookie", 1, {"overall": 78}, "tx_1")
	var second := FcDynastyCollection.grant_card(p, "reed_allstar", 1, {"overall": 93}, "tx_2")
	var dup := FcDynastyCollection.grant_card(p, "reed_rookie", 1, {"overall": 78}, "tx_3")
	assert_true(first["new"] and second["new"] and not dup["new"], "editions are separate cards; a repeat is a duplicate")
	assert_eq(p.quantity_of("reed_rookie"), 2, "copies counted")
	assert_eq(p.unique_owned(), 2, "two distinct cards")
	assert_eq(p.cards["reed_rookie"]["first_txn"], "tx_1", "history keeps the first transaction")


func test_convert_duplicate_and_mastery() -> void:
	var p := _profile()
	var cfg := FcDynastyConfig.build()
	FcDynastyCollection.grant_card(p, "c1", 1, {}, "t")
	assert_eq(FcDynastyCollection.convert_duplicate(p, cfg, "c1", "rare", "r1").code, "no_duplicate", "the only copy cannot be converted")
	FcDynastyCollection.grant_card(p, "c1", 1, {}, "t")
	var conv := FcDynastyCollection.convert_duplicate(p, cfg, "c1", "rare", "r2")
	assert_true(conv.ok, "converts a spare copy")
	assert_eq(p.balance("shards"), cfg.shards_for("rare"), "shards paid per config")
	assert_eq(p.quantity_of("c1"), 1, "one copy left")
	var again := FcDynastyCollection.convert_duplicate(p, cfg, "c1", "rare", "r2")
	assert_true(again.ok and again.data.get("repeated", false), "same request id is not applied twice")
	assert_eq(p.balance("shards"), cfg.shards_for("rare"), "no double payment")
	# mastery: needs a spare copy and shards
	FcDynastyCollection.grant_card(p, "c1", 1, {}, "t")
	FcDynastyEconomy.spend(p, "test", "x", {"shards": 10})
	var level := FcDynastyCollection.apply_mastery(p, cfg, "c1", "m1")
	assert_eq(level.code, "insufficient_funds", "mastery says shards are missing")
	assert_eq(p.quantity_of("c1"), 2, "a refused mastery keeps the duplicate")
	FcDynastyEconomy.apply(p, "test", "x", {"shards": 1000})
	var m := FcDynastyCollection.apply_mastery(p, cfg, "c1", "m2")
	assert_true(m.ok, "mastery with shards and a spare copy")
	assert_eq(int(p.cards["c1"]["mastery"]), 1, "mastery level raised")
	assert_eq(p.quantity_of("c1"), 1, "the duplicate was spent")


func test_session_commit_is_atomic() -> void:
	var s := FcDynastySession.new(_profile(), store, "one")
	var ok := s.commit(func() -> FcDynastyResult:
		return FcDynastyEconomy.apply(s.profile, "grant", "x", {"credits": 40}))
	assert_true(ok.ok and s.profile.balance("credits") == 40, "a successful change stays")
	var bad := s.commit(func() -> FcDynastyResult:
		FcDynastyEconomy.apply(s.profile, "grant", "x", {"credits": 1000})
		return FcDynastyResult.failure("nope", "failed after changing"))
	assert_true(not bad.ok, "failure reported")
	assert_eq(s.profile.balance("credits"), 40, "a failed operation is rolled back completely")
	var loaded := store.load_slot("one")
	assert_eq(int(loaded.data["profile"].balance("credits")), 40, "the disk matches memory")
	# a save that cannot happen undoes the change
	var broken := FcDynastySession.new(_profile(), FcDynastyStore.new("user://test_dynasty/bad slot/../x"), "bad slot!")
	var r := broken.commit(func() -> FcDynastyResult:
		return FcDynastyEconomy.apply(broken.profile, "grant", "x", {"credits": 5}))
	assert_true(not r.ok and r.code == "save_failed", "unsaveable change refused")
	assert_eq(broken.profile.balance("credits"), 0, "and undone")


func test_store_recovers_from_damage_and_rejects_newer_versions() -> void:
	var p := _profile()
	FcDynastyEconomy.apply(p, "grant", "x", {"credits": 7})
	assert_true(store.save("slot_a", p).ok, "save")
	p.balances["credits"] = 9
	assert_true(store.save("slot_a", p).ok, "second save keeps a backup")
	FcSafeFile.write_text(DIR.path_join("slot_a.dyn"), "garbage")
	var r := store.load_slot("slot_a")
	assert_true(r.ok and r.data["recovered_from"] == "backup", "recovers from the backup when the file is damaged")
	assert_eq(r.data["profile"].balance("credits"), 7, "backup holds the previous good save")
	assert_eq(store.load_slot("missing").code, "not_found", "missing slot")
	assert_eq(store.load_slot("Bad Slot").code, "invalid_slot", "bad slot name")
	var newer := FcDynastyStore.new(DIR)
	newer.current_version = 5
	assert_true(newer.save("slot_b", p).ok, "write a pretend newer file")
	assert_eq(store.load_slot("slot_b").code, "unsupported_version", "older game refuses newer data")
	assert_eq(store.list_slots(), ["slot_a", "slot_b"], "slots listed")


func test_migration_chain_runs_in_order() -> void:
	var old := FcDynastyStore.new(DIR)
	old.current_version = 1
	var p := _profile()
	assert_true(old.save("legacy", p).ok, "save as version 1")
	var newer := FcDynastyStore.new(DIR)
	newer.current_version = 2
	newer.migrator.register(1, func(d: Dictionary) -> Dictionary:
		var out := d.duplicate(true)
		out["team_name"] = "Migrated"
		return out)
	var r := newer.load_slot("legacy")
	assert_true(r.ok, "migrates a version 1 file")
	assert_eq(r.data["profile"].team_name, "Migrated", "the step ran")
	var missing := FcDynastyStore.new(DIR)
	missing.current_version = 3
	assert_eq(missing.load_slot("legacy").code, "migration_failed", "a missing step fails clearly")


func test_roster_round_trip() -> void:
	var r := FcDynastyRoster.new()
	r.slots[0] = "a"
	r.slots[12] = "z"
	r.minutes[3] = 1
	var back := FcDynastyRoster.from_dict(JSON.parse_string(JSON.stringify(r.to_dict())))
	assert_eq(back.to_dict(), r.to_dict(), "roster survives JSON")
	assert_eq(FcDynastyRoster.slot_name(0), "Starter PG", "slot names")
	assert_eq(FcDynastyRoster.slot_name(12), "Reserve", "reserve slot")
