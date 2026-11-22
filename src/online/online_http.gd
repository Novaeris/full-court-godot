class_name FcOnlineHttp
extends RefCounted
## Sends one request built by FcSupabaseAuth (or any {method, url, headers, body} dictionary) with Godot's own HTTPRequest, so no plugin
## is needed. It is the only place that touches the network. Returns {status, body, error}: `error` is "" when an answer came back (even
## an error status such as 401), and text when none did (offline, timed out, refused). Needs a Node in the scene tree to host the request.
##
## Not covered by an automated test against a real server (there is no project to call yet); the error path is tested against an address
## nothing listens on.

const TIMEOUT_SECONDS := 15.0
const METHODS := {"GET": HTTPClient.METHOD_GET, "POST": HTTPClient.METHOD_POST, "PATCH": HTTPClient.METHOD_PATCH, "PUT": HTTPClient.METHOD_PUT, "DELETE": HTTPClient.METHOD_DELETE}


static func send(host: Node, request: Dictionary) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT_SECONDS
	host.add_child(http)
	var headers: PackedStringArray = []
	for key in request.get("headers", {}):
		headers.append("%s: %s" % [str(key), str(request["headers"][key])])
	var method := str(request.get("method", "GET"))
	var body_text := "" if method == "GET" else JSON.stringify(request.get("body", {}))
	var started := http.request(str(request["url"]), headers, METHODS.get(method, HTTPClient.METHOD_GET), body_text)
	if started != OK:
		http.queue_free()
		return {"status": 0, "body": {}, "error": "the request could not start (code %d)" % started}
	var done: Array = await http.request_completed
	http.queue_free()
	if int(done[0]) != HTTPRequest.RESULT_SUCCESS:
		return {"status": 0, "body": {}, "error": "no answer (code %d)" % int(done[0])}
	var parsed = JSON.parse_string((done[3] as PackedByteArray).get_string_from_utf8())
	return {"status": int(done[1]), "body": parsed if parsed is Dictionary else {}, "error": ""}
