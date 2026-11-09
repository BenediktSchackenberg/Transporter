class_name TalkAgent
extends Node
## Gespraechsregie mit Sprachmodell (Claude, Auftrag 12): bekommt einen Zug der RivalryTalk (Lage des Paares, letzte Zeilen,
## Persoenlichkeiten, nummerierte gueltige Reaktionen) und antwortet {text, richtung, wahl}. Das Modell formuliert den Satz
## und waehlt nur eine Nummer; die Simulation prueft die Wahl. Bei Fehlern, Zeitueberschreitung oder Budgetende
## entscheiden sofort die Regeln (RivalryTalk.fail_pending), das Spiel wartet nie auf die API.

const FAIL_LIMIT := 3

var sim: Simulation
var config := {}
var adapter: LLMAdapter
var api_log: ApiLog
var stats := {"requests": 0, "ok": 0, "errors": 0, "invalid": 0, "tokens": 0}
var status := "bereit"
var fallback_active := false
var real_time := 0.0

var _turn: Dictionary = {}
var _inflight := -1
var _inflight_sent := 0.0
var _next_req := 1
var _fail := 0


func setup(simulation: Simulation, cfg: Dictionary, logger: ApiLog) -> void:
	sim = simulation
	config = cfg
	api_log = logger
	adapter = LLMAdapter.create(str(cfg.get("provider", "anthropic")))
	adapter.config = cfg
	add_child(adapter)
	adapter.completed.connect(handle_result)
	ApiLog.register_secret(str(cfg.get("api_key", "")))
	sim.talk.turn_ready.connect(on_turn)
	sim.talk.use_model = true


func budget_left() -> bool:
	return stats.requests < int(config.get("max_requests", 300)) and stats.tokens < int(config.get("max_tokens", 400000))


func _process(delta: float) -> void:
	var _pt := Time.get_ticks_usec()
	_process_timed(delta)
	ProcTimer.add("gespraeche_ki", _pt)


func _process_timed(delta: float) -> void:
	real_time += delta
	if _inflight >= 0 and real_time - _inflight_sent > float(config.get("timeout", 45.0)):
		adapter.cancel()
		_inflight = -1
		_failure("Zeitüberschreitung")


func on_turn(turn: Dictionary) -> void:
	if fallback_active or not budget_left() or _inflight >= 0:
		sim.talk.fail_pending("Ersatzmodus" if fallback_active else ("Budget" if not budget_left() else "Modell beschäftigt"))
		return
	_turn = turn
	var messages := [{"role": "system", "content": system_prompt()}, {"role": "user", "content": user_prompt(turn)}]
	_inflight = _next_req
	_next_req += 1
	_inflight_sent = real_time
	stats.requests += 1
	status = "wartet auf Antwort"
	api_log.write({"type": "request", "player": "gespraechsregie", "req": _inflight, "game_time": sim.game_min, "model": config.get("model"), "messages": messages})
	adapter.send(_inflight, messages)


func handle_result(req_id: int, r: Dictionary) -> void:
	if req_id != _inflight:
		return
	_inflight = -1
	var usage: Dictionary = r.get("usage", {}) if r.get("usage") is Dictionary else {}
	stats.tokens += int(usage.get("total_tokens", 0))
	api_log.write({"type": "response", "player": "gespraechsregie", "req": req_id, "ok": r.get("ok", false), "content": r.get("content", ""), "error": r.get("error", ""), "usage": usage})
	if not r.get("ok", false):
		_failure(str(r.get("error", "Fehler")))
		return
	var p := parse(str(r.get("content", "")))
	if not p.ok:
		stats.invalid += 1
		_failure("ungültige Antwort (%s)" % p.error)
		return
	stats.ok += 1
	_fail = 0
	if fallback_active:
		fallback_active = false
	status = "bereit"
	sim.talk.resolve(int(_turn.get("id", -1)), int(p.wahl), str(p.text), "Claude")


## Antwort {"text": "...", "richtung": "...", "wahl": 3} lesen (auch mit Textrahmen oder Codeblock).
static func parse(text: String) -> Dictionary:
	var a := text.find("{")
	var b := text.rfind("}")
	if a < 0 or b <= a:
		return {"ok": false, "error": "kein JSON"}
	var data = JSON.parse_string(text.substr(a, b - a + 1))
	if not data is Dictionary or not data.has("wahl") or str(data.get("text", "")).strip_edges() == "":
		return {"ok": false, "error": "wahl oder text fehlt"}
	var w = data.wahl
	if w is String and str(w).is_valid_int():
		w = int(w)
	if not (w is int or w is float):
		return {"ok": false, "error": "wahl ist keine Zahl"}
	return {"ok": true, "wahl": int(w), "text": str(data.text).left(200), "richtung": str(data.get("richtung", ""))}


func _failure(msg: String) -> void:
	stats.errors += 1
	_fail += 1
	status = "Fehler: %s" % msg
	api_log.write({"type": "failure", "player": "gespraechsregie", "error": msg})
	if _fail >= FAIL_LIMIT and not fallback_active:
		fallback_active = true
		sim.log_event("Gesprächsregie: API gestört – Regeln sprechen.", "warn")
	sim.talk.fail_pending(msg)


func system_prompt() -> String:
	return """Du bist die Gesprächsregie eines Wirtschaftsspiels über rivalisierende Transportunternehmen in einer deutschen Stadt.
Du sprichst als die Person, die gerade am Zug ist, in einem einzigen kurzen Satz (höchstens 160 Zeichen) zum Gegenüber, öffentlich hörbar.
Bleib in der Persönlichkeit und im Tonfall, beziehe dich auf die letzten Vorfälle und Zeilen. Schau, in welche Richtung der Streit geht:
eskalieren, beruhigen oder zusammenarbeiten. Wähle genau eine Reaktion aus der nummerierten Liste; der Satz muss zur gewählten Tat passen.
Keine Beleidigungen unter der Gürtellinie, keine echten Personen, keine Drohungen mit Gewalt.
ANTWORTFORMAT: ausschließlich ein JSON-Objekt:
{"text": "der gesprochene Satz", "richtung": "eskalation|deeskalation|kooperation", "wahl": Nummer}"""


func user_prompt(turn: Dictionary) -> String:
	var me: Company = sim.company(int(turn.from))
	var other: Company = sim.company(int(turn.to))
	var person := func(c: Company) -> Dictionary:
		return {"name": c.player_name, "firma": c.company_name, "persoenlichkeit": Catalog.PERSONALITIES.get(c.personality, {}).get("prompt", ""),
			"ruf": int(c.reputation), "bargeld": int(c.ledger.cash)}
	var ctx := {"du": person.call(me), "gegenueber": person.call(other), "spannung": turn.spannung, "stufe": turn.stufe,
		"vorfaelle": sim.rivalry.summary_of(me.id).filter(func(r): return int(r.firma) == other.id).map(func(r): return r.vorfaelle),
		"letzte_zeilen": sim.talk.pair_lines(me.id, other.id, 6).map(func(l): return {"von": sim.company(int(l.from)).player_name, "text": l.text, "tat": l.art}),
		"reaktionen": turn.kandidaten}
	return "Lage (JSON):\n" + JSON.stringify(ctx) + "\nDu bist %s. Antworte jetzt." % me.player_name


func to_dict() -> Dictionary:
	return {"stats": stats, "fallback": fallback_active}
