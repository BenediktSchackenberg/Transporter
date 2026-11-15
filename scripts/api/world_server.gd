class_name WorldServer
extends Node
## Weltschnittstelle des Eko-Modus (Protokoll nach Clawblox: join / observe / input ueber HTTP). Lauscht nur auf 127.0.0.1.
## Endpunkte: POST /join?name=, GET /observe, POST /input {"type", "data"}, POST /chat {"content"}, GET /chat/messages?after=&limit=,
## GET /api.md. Ausser /join und /api.md brauchen alle den Kopf X-Session. Antworten sind JSON (UTF-8), Verbindung wird danach geschlossen.

const API_DOC := "res://docs/EKO_API.md"
const MAX_REQUEST := 65536

var eko: EkoWorld
var port := 8790
var _server := TCPServer.new()
var _peers: Array = []              # [{peer, buf, since}]
var _sessions := {}                 # Token -> Name
var on_save: Callable                # Betreiber: Spielstand sichern (GameSession.save_game)
var operator_token := ""             # nur fuer den Betreiber (Datei user://eko_betreiber.txt), nie an Wesen weitergeben
## Identitaet (15.11.2026): Wer einen Namen zuerst beansprucht, bekommt einen geheimen Schluessel (einmalig in der Antwort von /join).
## Spaeteres /join unter diesem Namen nur mit Kopf X-Schluessel; gespeichert wird nur der SHA-256-Wert. Pro Wesen gilt nur die
## neueste Sitzung. "" = nicht dauerhaft speichern (Tests).
var keys_path := ""                  # im Spiel: user://eko_schluessel.json (setzt GameSession)
var _keys := {}                      # Name -> sha256(Schluessel)
var _keys_loaded := false
const DUPLICATE_MS := 3000
var _last_input := {}                # Name -> letzte Handlung (Typ + Daten)
var _last_input_ms := {}


func setup(world: EkoWorld, p: int = 8790) -> bool:
	eko = world
	port = p
	var err := _server.listen(port, "127.0.0.1")
	if err != OK:
		push_warning("Eko-Weltschnittstelle: Port %d belegt (Fehler %d)." % [port, err])
		return false
	print("EKO: Weltschnittstelle auf http://127.0.0.1:%d" % port)
	return true


func _exit_tree() -> void:
	_server.stop()


func _process(_delta: float) -> void:
	while _server.is_connection_available():
		_peers.append({"peer": _server.take_connection(), "buf": PackedByteArray(), "since": Time.get_ticks_msec()})
	for c in _peers.duplicate():
		var peer: StreamPeerTCP = c.peer
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED or Time.get_ticks_msec() - int(c.since) > 10000:
			_peers.erase(c)
			continue
		var n := peer.get_available_bytes()
		if n > 0:
			var got: Array = peer.get_partial_data(n)
			if got[0] == OK:
				c.buf.append_array(got[1])
		var req := _parse(c.buf)
		if req.is_empty():
			if c.buf.size() > MAX_REQUEST:
				_send(peer, 413, {"ok": false, "msg": "Anfrage zu gross."})
				_peers.erase(c)
			continue
		var res: Array = handle(str(req.method), str(req.path), req.query, req.headers, str(req.body))
		_send(peer, int(res[0]), res[1], str(res[2]) if res.size() > 2 else "application/json")
		_peers.erase(c)


## Vollstaendige Anfrage aus dem Puffer lesen, sonst {}.
func _parse(buf: PackedByteArray) -> Dictionary:
	var text := buf.get_string_from_utf8()
	var head_end := text.find("\r\n\r\n")
	if head_end < 0:
		return {}
	var lines := text.left(head_end).split("\r\n")
	var first := lines[0].split(" ")
	if first.size() < 2:
		return {"method": "BAD", "path": "", "query": {}, "headers": {}, "body": ""}
	var headers := {}
	for i in range(1, lines.size()):
		var k := lines[i].find(":")
		if k > 0:
			headers[lines[i].left(k).strip_edges().to_lower()] = lines[i].substr(k + 1).strip_edges()
	var head_bytes := text.left(head_end + 4).to_utf8_buffer().size()
	var length := int(headers.get("content-length", "0"))
	if buf.size() - head_bytes < length:
		return {}
	var body := buf.slice(head_bytes, head_bytes + length).get_string_from_utf8()
	var target := first[1]
	var query := {}
	var q := target.find("?")
	if q >= 0:
		for part in target.substr(q + 1).split("&", false):
			var kv := part.split("=", true, 1)
			query[kv[0].uri_decode()] = kv[1].uri_decode() if kv.size() > 1 else ""
		target = target.left(q)
	return {"method": first[0], "path": target, "query": query, "headers": headers, "body": body}


## Gibt [Status, Antwort (Dictionary/Array oder Text), Inhaltstyp] zurueck. Ohne Netzwerk testbar.
func handle(method: String, path: String, query: Dictionary, headers: Dictionary, body: String) -> Array:
	if path == "/api.md" and method == "GET":
		return [200, FileAccess.get_file_as_string(API_DOC), "text/markdown; charset=utf-8"]
	if path == "/betreiber/speichern" and method == "POST":   # Spielstand sichern, z. B. vor einem Neustart mit neuem Code
		if operator_token == "" or str(headers.get("x-betreiber", "")) != operator_token or not on_save.is_valid():
			return [403, {"ok": false, "msg": "Nur für den Betreiber."}]
		on_save.call()
		return [200, {"ok": true, "msg": "Spielstand gesichert."}]
	if path == "/betreiber/wesen" and method == "GET":   # Schwarm: welche Wesen gibt es, mit welcher Seele
		if operator_token == "" or str(headers.get("x-betreiber", "")) != operator_token:
			return [403, {"ok": false, "msg": "Nur für den Betreiber."}]
		return [200, eko.beings_info()]
	if path == "/betreiber/schluessel_zuruecksetzen" and method == "POST":   # verlorener Schluessel: Name wieder frei
		if operator_token == "" or str(headers.get("x-betreiber", "")) != operator_token:
			return [403, {"ok": false, "msg": "Nur für den Betreiber."}]
		_load_keys()
		_keys.erase(str(query.get("name", "")))
		_save_keys()
		return [200, {"ok": true, "msg": "Schlüssel zurückgesetzt."}]
	if path == "/join" and method == "POST":
		_load_keys()
		var want := str(query.get("name", "")).strip_edges().left(24)
		var key := str(headers.get("x-schluessel", ""))
		if _keys.has(want) and key.sha256_text() != str(_keys[want]):
			return [403, {"ok": false, "msg": "Der Name %s gehört bereits einem Wesen. Ohne dessen Schlüssel (Kopf X-Schluessel) kein Zutritt – wähle einen anderen Namen." % want}]
		var r := eko.join(want, str(query.get("art", "mensch")))
		if not bool(r.ok):
			return [400, r]
		var out := {"ok": true, "name": r.name, "hinweis": "Sende den Token im Kopf X-Session. Beschreibung: GET /api.md"}
		if not _keys.has(str(r.name)):
			var fresh := _random_hex(16)
			_keys[str(r.name)] = fresh.sha256_text()
			_save_keys()
			out["schluessel"] = fresh
			out["hinweis"] += " Bewahre den Schlüssel auf: Ohne ihn kannst du dich unter diesem Namen nicht wieder anmelden."
		for t in _sessions.keys():   # nur die neueste Sitzung je Wesen gilt
			if _sessions[t] == r.name:
				_sessions.erase(t)
		var token := _random_hex(16)
		_sessions[token] = r.name
		out["session"] = token
		return [200, out]
	var name := str(_sessions.get(str(headers.get("x-session", "")), ""))
	if name == "":
		return [401, {"ok": false, "msg": "Kopf X-Session fehlt oder ist ungueltig. Erst POST /join?name=DeinName."}]
	match [method, path]:
		["GET", "/observe"]:
			return [200, eko.observe(name)]
		["POST", "/input"]:
			var a = JSON.parse_string(body)
			if not (a is Dictionary) or not a.has("type"):
				return [400, {"ok": false, "msg": "Body muss JSON {\"type\": \"...\", \"data\": {...}} sein."}]
			var d = a.get("data", {})
			# Doppelschutz: dieselbe Handlung mit denselben Daten innerhalb von DUPLICATE_MS (z. B. Wiederholung nach Zeitueberschreitung)
			var key := str(a.type) + JSON.stringify(d)
			if str(a.type) not in ["Say", "Talk", "Inspect", "ZielStand", "Merke"] and key == str(_last_input.get(name, "")) 					and Time.get_ticks_msec() - int(_last_input_ms.get(name, 0)) < DUPLICATE_MS:
				return [409, {"ok": false, "status": "doppelt", "msg": "Diese Handlung hast du gerade eben schon geschickt. Prüfe erst das Ergebnis (observe), statt sie zu wiederholen."}]
			_last_input[name] = key
			_last_input_ms[name] = Time.get_ticks_msec()
			var r := eko.input(name, str(a.type), d if d is Dictionary else {})
			r["beobachtung"] = eko.observe(name)
			return [200 if bool(r.ok) else 400, r]
		["POST", "/chat"]:
			var c = JSON.parse_string(body)
			var r2 := eko.say(name, str(c.get("content", "")) if c is Dictionary else "")
			return [200 if bool(r2.ok) else 400, r2]
		["GET", "/chat/messages"]:
			return [200, eko.chat_after(str(query.get("after", "")), int(query.get("limit", "20")))]
	return [404, {"ok": false, "msg": "Unbekannter Endpunkt %s %s. Siehe GET /api.md." % [method, path]}]


func _random_hex(n: int) -> String:
	return Crypto.new().generate_random_bytes(n).hex_encode()


func _load_keys() -> void:
	if _keys_loaded:
		return
	_keys_loaded = true
	if keys_path != "" and FileAccess.file_exists(keys_path):
		var d = JSON.parse_string(FileAccess.get_file_as_string(keys_path))
		if d is Dictionary:
			_keys = d


func _save_keys() -> void:
	if keys_path == "":
		return
	var f := FileAccess.open(keys_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_keys))


func _send(peer: StreamPeerTCP, status: int, payload, ctype: String = "application/json") -> void:
	var body: PackedByteArray = (payload if payload is String else JSON.stringify(payload)).to_utf8_buffer()
	var reason: String = {200: "OK", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found", 409: "Conflict", 413: "Payload Too Large"}.get(status, "OK")
	var head := "HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [status, reason, ctype, body.size()]
	peer.put_data(head.to_utf8_buffer())
	peer.put_data(body)
	peer.disconnect_from_host()
