## Supabase client over plain HTTPS: guest (anonymous) auth, optional Apple/Google link,
## cloud save sync and RPC calls. The game never needs this to be playable offline.
extends Node

signal status_changed(online: bool)
signal cloud_conflict(server: Dictionary)

const SESSION := "user://session.json"
const PUSH_EVERY := 120.0

var url := ""
var key := ""
var session := {}        # access_token, refresh_token, expires_at, user
var online := false
var _pushing := false

func configured() -> bool:
	return url != "" and key != ""

func _ready() -> void:
	var cfg = JSON.parse_string(FileAccess.get_file_as_string("res://config/backend.json")) if FileAccess.file_exists("res://config/backend.json") else null
	if cfg is Dictionary:
		url = str(cfg.get("supabase_url", "")).trim_suffix("/")
		key = str(cfg.get("supabase_anon_key", ""))
	if FileAccess.file_exists(SESSION):
		var s = JSON.parse_string(FileAccess.get_file_as_string(SESSION))
		if s is Dictionary: session = s
	Game.event.connect(func(n, _d): if n != "save_failed": Game.model.s["flags"]["cloud_dirty"] = true)
	var t := Timer.new()
	t.wait_time = PUSH_EVERY
	t.autostart = true
	t.timeout.connect(_periodic)
	add_child(t)
	if configured() and not _testing():
		connect_now()

func _testing() -> bool:
	return Game.save_path != "user://save.json"

func _periodic() -> void:
	if not configured(): return
	if not online: await connect_now()
	else:
		await process_outbox()
		if Game.model.s["flags"].get("cloud_dirty", false): await sync()

# ------------------------------------------------------------------ HTTP

## Returns {"code": int, "data": Variant}; code 0 = no connection.
func request(method: int, path: String, body: Variant = null, auth := true) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = 15.0
	add_child(http)
	var headers := ["apikey: " + key, "Content-Type: application/json"]
	if auth and session.has("access_token"):
		headers.append("Authorization: Bearer " + str(session["access_token"]))
	var err := http.request(url + path, headers, method, "" if body == null else JSON.stringify(body))
	if err != OK:
		http.queue_free()
		return {"code": 0, "data": null}
	var res: Array = await http.request_completed
	http.queue_free()
	var text: String = res[3].get_string_from_utf8()
	return {"code": int(res[1]) if int(res[0]) == HTTPRequest.RESULT_SUCCESS else 0, "data": JSON.parse_string(text) if text != "" else null}

func call_rpc(fn: String, args := {}) -> Dictionary:
	if not online: return {"code": 0, "data": {"error": "offline"}}
	var r := await request(HTTPClient.METHOD_POST, "/rest/v1/rpc/" + fn, args)
	if r["code"] == 401 and await _refresh():
		r = await request(HTTPClient.METHOD_POST, "/rest/v1/rpc/" + fn, args)
	if r["code"] == 0: _set_online(false)
	return r

func get_rows(table: String, query: String) -> Dictionary:
	if not online: return {"code": 0, "data": []}
	return await request(HTTPClient.METHOD_GET, "/rest/v1/%s?%s" % [table, query])

# ------------------------------------------------------------------ auth

func connect_now() -> bool:
	if not configured(): return false
	var ok := false
	if session.has("refresh_token"):
		ok = float(session.get("expires_at", 0)) > Time.get_unix_time_from_system() + 60 or await _refresh()
	if not ok:
		ok = await _sign_in_guest()
	_set_online(ok)
	if ok:
		await sync()
		await process_outbox()
		await claim_helps()
	return ok

func _sign_in_guest() -> bool:
	var r := await request(HTTPClient.METHOD_POST, "/auth/v1/signup", {"data": {}}, false)
	return _store_session(r)

func _refresh() -> bool:
	var r := await request(HTTPClient.METHOD_POST, "/auth/v1/token?grant_type=refresh_token", {"refresh_token": session.get("refresh_token", "")}, false)
	return _store_session(r)

func _store_session(r: Dictionary) -> bool:
	if r["code"] != 200 or not r["data"] is Dictionary or not r["data"].has("access_token"):
		return false
	session = r["data"]
	session["expires_at"] = Time.get_unix_time_from_system() + float(session.get("expires_in", 3600))
	var f := FileAccess.open(SESSION, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(session))
	return true

func _set_online(v: bool) -> void:
	if v != online:
		online = v
		status_changed.emit(v)

func is_guest() -> bool:
	return session.get("user", {}).get("is_anonymous", true)

func user_id() -> String:
	return str(session.get("user", {}).get("id", ""))

## Upgrade the guest account: opens the provider's sign-in page in the browser; the
## identity is linked to the SAME user id, so progress, wallet and listings are kept.
func link_identity(provider: String) -> String:
	var r := await request(HTTPClient.METHOD_GET, "/auth/v1/user/identities/authorize?provider=%s&skip_http_redirect=true" % provider)
	if r["code"] == 200 and r["data"] is Dictionary and r["data"].has("url"):
		OS.shell_open(r["data"]["url"])
		return ""
	return "link_failed"

## After the browser step: re-read the user to see if the identity is now linked.
func refresh_user() -> void:
	var r := await request(HTTPClient.METHOD_GET, "/auth/v1/user")
	if r["code"] == 200 and r["data"] is Dictionary:
		session["user"] = r["data"]
		_store_session({"code": 200, "data": session})

# ------------------------------------------------------------------ cloud save

func sync() -> void:
	if _pushing or not online: return
	_pushing = true
	var s: Dictionary = Game.model.s
	var base := int(s["flags"].get("cloud_rev", 0))
	var dirty: bool = s["flags"].get("cloud_dirty", true)
	var r := await call_rpc("load_game")
	if r["code"] == 200 and r["data"] is Dictionary:
		var server: Dictionary = r["data"]
		match CloudSync.decide(base, int(server.get("revision", 0)), dirty):
			"push": await _push(base)
			"pull": adopt(server)
			"conflict": cloud_conflict.emit(server)
	_pushing = false

func _push(base: int) -> void:
	var s: Dictionary = Game.model.s
	s["flags"]["cloud_dirty"] = false
	var r := await call_rpc("save_game", {"p_data": s, "p_base_revision": base})
	if r["code"] == 200 and r["data"] is Dictionary:
		if r["data"].get("ok", false):
			s["flags"]["cloud_rev"] = int(r["data"]["revision"])
		elif r["data"].get("conflict", false):
			s["flags"]["cloud_dirty"] = true
			cloud_conflict.emit(r["data"])
	else:
		s["flags"]["cloud_dirty"] = true

## Replace local progress with the cloud copy.
func adopt(server: Dictionary) -> void:
	var d := SaveCodec.decode(JSON.stringify(server["data"]))
	if d.is_empty(): return
	d["flags"]["cloud_rev"] = int(server["revision"])
	d["flags"]["cloud_dirty"] = false
	Game.set_model(GameModel.new(d))
	Game.save()

## Keep this device's progress: overwrite the cloud from the server's latest revision.
func keep_local(server: Dictionary) -> void:
	await _push(int(server["revision"]))

# ------------------------------------------------------------------ trading

## Sends pending deposits/collects. Same request id on retry = no duplicates.
func process_outbox() -> void:
	var m: GameModel = Game.model
	for op in m.s["outbox"].duplicate():
		var r: Dictionary
		if op["kind"] == "deposit":
			r = await call_rpc("deposit", {"p_request_id": op["id"], "p_items": op["items"], "p_coins": op["coins"]})
		else:
			r = await call_rpc("collect", {"p_request_id": op["id"]})
		if r["code"] == 0:
			return                                   # offline: keep for later
		m.finish_op(op["id"], r["data"] if r["code"] == 200 and r["data"] is Dictionary else {"error": err(r)})
	Game.save()

## Server error code from a PostgREST error body ("message" holds the raised text).
static func err(r: Dictionary) -> String:
	if r["code"] == 0: return "offline"
	if r["data"] is Dictionary:
		return str(r["data"].get("error", r["data"].get("message", "server_error")))
	return "server_error"

## Deposit (if needed) then run `fn`; returns "" or an error code.
func trade_call(fn: String, args: Dictionary) -> String:
	await process_outbox()
	var r := await call_rpc(fn, args)
	if r["code"] == 200 and not (r["data"] is Dictionary and r["data"].has("error")):
		return ""
	return err(r)

func collect_all() -> void:
	Game.model.queue_collect()
	await process_outbox()

func claim_helps() -> void:
	var r := await call_rpc("claim_helps")
	if r["code"] == 200 and r["data"] is Array:
		for h in r["data"]:
			Game.model.apply_help(int(h["plot"]), Game.now())
			Game.event.emit("helped", {"name": h["helper_name"]})
