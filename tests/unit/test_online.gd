extends FcTestCase
## Online foundations (Phase 6), all local: signing, accounts, the loopback server rules (signature, freshness, replay, rate limit,
## idempotency, whitelist, rollback, signed receipts), server-authoritative profiles, rating matchmaking, and server-decided matches that a
## claimed result is checked against by re-simulation.

var catalog: FcDynastyCatalog
var now_value: int
var server: FcOnlineServer
var session: Dictionary
var counter: int


func before_each() -> void:
	catalog = FcDynastyFixture.catalog()
	now_value = 1000000
	server = FcOnlineServer.new(catalog, "test-server-key")
	server.now = func() -> int: return now_value
	session = server.register("Maya Okoro", "Online Kings", "ONK")
	counter = 0


func _ask(command: String, params: Dictionary = {}, request_id: String = "") -> Dictionary:
	counter += 1
	return server.handle(FcOnlineServer.make_request(session, command, params, request_id, "n%d" % counter, now_value))


# --- crypto -------------------------------------------------------------------------------------------------------------------

func test_hmac_matches_a_known_vector_and_signatures_are_canonical() -> void:
	assert_eq(FcOnlineCrypto.hmac_hex("key", "The quick brown fox jumps over the lazy dog"), "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8")
	assert_eq(FcOnlineCrypto.sha256_hex("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
	assert_eq(FcOnlineCrypto.sign_dict("k", {"a": 1, "b": 2}), FcOnlineCrypto.sign_dict("k", {"b": 2, "a": 1}), "key order does not matter")
	assert_true(FcOnlineCrypto.sign_dict("k", {"a": 1}) != FcOnlineCrypto.sign_dict("k", {"a": 2}))
	var signed := {"a": 1}
	signed["sig"] = FcOnlineCrypto.sign_dict("k", signed)
	assert_true(FcOnlineCrypto.verify_dict("k", signed))
	assert_true(not FcOnlineCrypto.verify_dict("other", signed))
	signed["a"] = 2
	assert_true(not FcOnlineCrypto.verify_dict("k", signed), "a changed field breaks the signature")
	assert_eq(FcOnlineCrypto.new_key().length(), 64)
	assert_true(FcOnlineCrypto.new_key() != FcOnlineCrypto.new_key())


func test_account_names_are_validated() -> void:
	assert_true(FcOnlineAccount.create("Maya Okoro", 5).validate().is_empty())
	assert_true(not FcOnlineAccount.create("ab", 5).validate().is_empty(), "too short")
	assert_true(not FcOnlineAccount.create("x".repeat(21), 5).validate().is_empty(), "too long")
	assert_true(not FcOnlineAccount.create("bad<name>", 5).validate().is_empty(), "odd characters")
	assert_true(not server.register("a!", "T", "TT")["ok"])
	assert_true(str(session["account_id"]).begins_with("fca_"))
	assert_true(server.has_account(session["account_id"]))


# --- request rules ------------------------------------------------------------------------------------------------------------

func test_a_valid_request_is_answered_with_a_signed_receipt() -> void:
	var r := _ask("get_profile", {}, "req1")
	assert_true(r["ok"], str(r["message"]))
	assert_true(server.verify_receipt(r["receipt"]))
	assert_eq(r["receipt"]["account_id"], session["account_id"])
	assert_eq(r["receipt"]["result_hash"], FcOnlineCrypto.sha256_hex(FcOnlineCrypto.canonical(r["data"])))
	var forged: Dictionary = (r["receipt"] as Dictionary).duplicate()
	forged["revision"] = 99
	assert_true(not server.verify_receipt(forged), "an edited receipt is detected")


func test_unknown_accounts_bad_signatures_and_stale_requests_are_refused() -> void:
	var env := FcOnlineServer.make_request(session, "get_profile", {}, "", "x1", now_value)
	var wrong_account: Dictionary = env.duplicate(true)
	wrong_account["account_id"] = "fca_nobody"
	assert_eq(server.handle(wrong_account)["code"], "unknown_account")
	var tampered: Dictionary = env.duplicate(true)
	tampered["command"] = "buy_pack"
	assert_eq(server.handle(tampered)["code"], "bad_signature")
	var other := {"account_id": session["account_id"], "session_key": "0".repeat(64)}
	assert_eq(server.handle(FcOnlineServer.make_request(other, "get_profile", {}, "", "x2", now_value))["code"], "bad_signature", "a wrong key")
	assert_eq(server.handle(FcOnlineServer.make_request(session, "get_profile", {}, "", "x3", now_value - 500))["code"], "stale_request")
	assert_eq(server.handle(FcOnlineServer.make_request(session, "get_profile", {}, "", "x4", now_value + 500))["code"], "stale_request")
	assert_true(server.handle(env)["ok"], "the untouched original still works")


func test_a_replayed_envelope_is_refused() -> void:
	var env := FcOnlineServer.make_request(session, "get_profile", {}, "", "same-nonce", now_value)
	assert_true(server.handle(env)["ok"])
	assert_eq(server.handle(env)["code"], "replayed")
	var empty := FcOnlineServer.make_request(session, "get_profile", {}, "", "", now_value)
	assert_eq(server.handle(empty)["code"], "bad_nonce")


func test_only_whitelisted_commands_run() -> void:
	assert_eq(_ask("delete_everything")["code"], "unknown_command")
	assert_eq(_ask("set_balance", {"credits": 999999})["code"], "unknown_command", "a client cannot state its own balance")


func test_requests_are_rate_limited_and_the_bucket_refills() -> void:
	var refused := 0
	for i in 30:
		if _ask("get_profile")["code"] == "rate_limited":
			refused += 1
	assert_eq(refused, 30 - int(FcOnlineServer.RATE_CAPACITY))
	now_value += 5
	assert_true(_ask("get_profile")["ok"], "after a few seconds there are tokens again")


# --- authoritative actions ----------------------------------------------------------------------------------------------------

func test_a_retried_request_id_returns_the_same_answer_and_changes_nothing_twice() -> void:
	var before_games := server.profile_of(session["account_id"]).game_counter
	var first := _ask("play_quick_game", {"level_id": "easy"}, "game-1")
	assert_true(first["ok"], str(first["message"]))
	var revision := int(first["revision"])
	var again := _ask("play_quick_game", {"level_id": "easy"}, "game-1")
	assert_true(again["ok"] and bool(again.get("repeated", false)))
	assert_eq(again["data"], first["data"])
	assert_eq(server.profile_of(session["account_id"]).game_counter, before_games + 1, "played once")
	assert_eq(server.revision_of(session["account_id"]), revision)
	assert_true(not first["data"].has("box") and not first["data"].has("events"), "the client gets the facts, not the heavy replay")


func test_a_failed_command_changes_nothing() -> void:
	var before := server.profile_of(session["account_id"]).to_dict()
	var revision := server.revision_of(session["account_id"])
	var r := _ask("claim_goal", {"goal_id": "mastery_ten"}, "goal-1")
	assert_true(not r["ok"])
	assert_eq(r["code"], "not_done")
	assert_eq(server.profile_of(session["account_id"]).to_dict(), before)
	assert_eq(server.revision_of(session["account_id"]), revision)


func test_two_accounts_are_separate() -> void:
	var other := server.register("Jules Park", "Other Team", "OTH")
	assert_true(other["ok"])
	_ask("play_quick_game", {"level_id": "easy"}, "g")
	assert_eq(server.profile_of(other["account_id"]).game_counter, 0)
	var theirs := FcOnlineServer.make_request(other, "get_profile", {}, "", "o1", now_value)
	assert_eq(server.handle(theirs)["data"]["profile"]["team_name"], "Other Team")
	var crossed := FcOnlineServer.make_request({"account_id": session["account_id"], "session_key": other["session_key"]}, "get_profile", {}, "", "o2", now_value)
	assert_eq(server.handle(crossed)["code"], "bad_signature", "another account's key does not open this one")


# --- matchmaking and matches --------------------------------------------------------------------------------------------------

func test_matchmaking_pairs_close_ratings_and_widens_with_waiting() -> void:
	var m := FcOnlineMatchmaker.new()
	assert_true(m.join("a", 1000, 0))
	assert_true(not m.join("a", 1000, 0), "one place in the queue")
	m.join("b", 1090, 0)
	m.join("c", 1500, 0)
	var pairs := m.find_pairs(0)
	assert_eq(pairs.size(), 1)
	assert_eq([pairs[0][0]["account_id"], pairs[0][1]["account_id"]], ["a", "b"])
	assert_eq(m.size(), 1, "c waits")
	m.join("d", 1300, 10)
	assert_eq(m.find_pairs(10).size(), 0, "a gap of 200 against a window of 150 at once")
	assert_eq(m.find_pairs(60).size(), 1, "after a minute the window has widened")
	assert_true(not m.leave("nobody"))


func test_matchmaking_is_deterministic_and_seeds_come_from_the_server_key() -> void:
	var one := FcOnlineMatchmaker.new()
	var two := FcOnlineMatchmaker.new()
	for q in [one, two]:
		q.join("x", 1000, 0)
		q.join("y", 1010, 0)
		q.join("z", 1020, 0)
	assert_eq(one.find_pairs(0), two.find_pairs(0))
	assert_eq(FcOnlineMatchmaker.seed_for("k1", "m_000001"), FcOnlineMatchmaker.seed_for("k1", "m_000001"))
	assert_true(FcOnlineMatchmaker.seed_for("k1", "m_000001") != FcOnlineMatchmaker.seed_for("k2", "m_000001"), "another key, another seed")
	assert_true(FcOnlineMatchmaker.seed_for("k1", "m_000001") != FcOnlineMatchmaker.seed_for("k1", "m_000002"))


func test_a_match_is_decided_by_the_server_and_a_false_claim_is_caught() -> void:
	var other := server.register("Jules Park", "Other Team", "OTH")
	var matchmaker := FcOnlineMatchmaker.new()
	var r := server.play_match(session["account_id"], other["account_id"], matchmaker)
	assert_true(r["ok"], str(r["message"]))
	var result: Dictionary = r["result"]
	assert_true(int(result["score_a"]) != int(result["score_b"]))
	assert_eq(int(r["changes"]["a"]), -int(r["changes"]["b"]), "equal and opposite")
	assert_eq(server.profile_of(session["account_id"]).ladder["rating"], 1000 + int(r["changes"]["a"]))
	assert_eq(server.profile_of(other["account_id"]).ladder["rating"], 1000 + int(r["changes"]["b"]))
	for id in r["receipts"]:
		assert_true(server.verify_receipt(r["receipts"][id]))
	var honest := FcOnlineMatch.verify_claim(catalog, r["record"], {"score_a": result["score_a"], "score_b": result["score_b"]})
	assert_true(honest["valid"])
	var lie := FcOnlineMatch.verify_claim(catalog, r["record"], {"score_a": int(result["score_a"]) + 1, "score_b": result["score_b"]})
	assert_true(not lie["valid"])
	assert_eq(lie["result"], result, "the real result comes back")
	assert_eq(FcOnlineMatch.result_of(catalog, r["record"]), result, "the same record always gives the same result")
	assert_true(not server.play_match(session["account_id"], session["account_id"], matchmaker)["ok"], "not against oneself")
	assert_true(not server.play_match(session["account_id"], "fca_nobody", matchmaker)["ok"])
