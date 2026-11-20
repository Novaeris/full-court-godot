class_name FcDynastyEnv
extends RefCounted
## Test helper: a fixture catalog plus an open Dynasty session with the starter collection and an automatic lineup.

const DIR := "user://test_dynasty_play"

var catalog: FcDynastyCatalog
var store: FcDynastyStore
var session: FcDynastySession


static func make(seed_value: int = 777) -> FcDynastyEnv:
	var e := FcDynastyEnv.new()
	FcSafeFile.remove_tree(DIR)
	FcDynastyFixture.wipe()
	e.catalog = FcDynastyFixture.catalog()
	e.store = FcDynastyStore.new(DIR)
	var profile := FcDynastyProfile.create("Test Kings", "TKG", seed_value, e.catalog.release_id())
	e.session = FcDynastySession.new(profile, e.store, "env")
	var cat := e.catalog
	var s := e.session
	var made := s.commit(func() -> FcDynastyResult:
		var g := FcDynastyOnboarding.grant_starter(s.profile, cat)
		FcDynastyLineup.auto_fill(s.profile, cat)
		return g)
	if not made.ok:
		push_error("env setup failed: %s" % made.message)
	return e


func profile() -> FcDynastyProfile:
	return session.profile


## Gives currency through the ledger (a test-only stand-in for earning it).
func fund(currency: String, amount: int) -> void:
	session.commit(func() -> FcDynastyResult: return FcDynastyEconomy.apply(session.profile, "test_grant", "test", {currency: amount}))


## Gives one copy of a card the way a reward would.
func give(card_id: String) -> void:
	session.commit(func() -> FcDynastyResult:
		var t := FcDynastyEconomy.apply(session.profile, "test_grant", card_id, {}, [card_id])
		FcDynastyCollection.grant_card(session.profile, card_id, 1, catalog.snapshot_of(card_id), t.data["txn"]["txn_id"])
		return t)


static func cleanup() -> void:
	FcSafeFile.remove_tree(DIR)
	FcDynastyFixture.wipe()
