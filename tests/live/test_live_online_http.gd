extends FcLiveTestCase
## The network executor's failure path (accounts milestone): a request to an address nothing listens on comes back as a plain
## "no answer" result, never a crash or a hang, and its temporary node is removed. There is no real server here, so the success path is
## not covered by an automated test.


func test_an_unreachable_address_gives_a_clear_error_result() -> void:
	var before := host.get_child_count()
	var result: Dictionary = await FcOnlineHttp.send(host, {"method": "POST", "url": "http://127.0.0.1:9/auth/v1/token", "headers": {"apikey": "x"}, "body": {"a": 1}})
	assert_eq(int(result["status"]), 0)
	assert_true(str(result["error"]) != "", "an error message")
	assert_eq(result["body"], {})
	assert_true("Could not reach" in FcSupabaseAuth.read_error(result), "the player-facing message")
	await frames(2)
	assert_eq(host.get_child_count(), before, "the request node is cleaned up")
