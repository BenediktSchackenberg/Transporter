class_name MayorAgent
extends Node
## Steuert die Buergermeister-Rolle. Eigener Kontext, eigenes Modell, eigener Schluessel und eigenes Anfrage-/Tokenbudget
## (oder der global konfigurierte Zugang, aber mit getrenntem Gespraech). Ohne Sprachmodell (provider "demo"/"regel") entscheidet
## `MayorBrain`; bei anhaltenden API-Fehlern oder erschoepftem Budget ebenfalls (sichtbar markierter Ersatzmodus).

signal decided(summary: String, source: String)

const FAIL_LIMIT := 3
const MAX_ACTIONS := 4

var sim: Simulation
var config := {}
var adapter: LLMAdapter
var api_log: ApiLog
var active := true
var stats := {"requests": 0, "ok": 0, "errors": 0, "invalid": 0, "tokens": 0, "actions_ok": 0, "actions_rejected": 0}
var status := "bereit"
var last_error := ""
var fallback_active := false
var summaries: Array = []
var real_time := 0.0

var _since := 0.0
var _inflight := -1
var _inflight_sent := 0.0
var _next_req := 1
var _applied := {}
var _abandoned := {}
var _fail := 0
var _backoff_until := 0.0


func setup(simulation: Simulation, cfg: Dictionary, logger: ApiLog) -> void:
	sim = simulation
	config = cfg
	api_log = logger
	var provider := str(cfg.get("provider", "demo"))
	if provider == "regel":
		provider = "demo"
	if provider != "demo":
		adapter = LLMAdapter.create(provider)
		adapter.config = cfg
		add_child(adapter)
		adapter.completed.connect(handle_result)
		ApiLog.register_secret(str(cfg.get("api_key", "")))
	sim.permits.mayor_attached = true
	status = "regelbasiert" if adapter == null else "bereit"


func uses_model() -> bool:
	return adapter != null


func budget_left() -> bool:
	return stats.requests < int(config.get("max_requests", 200)) and stats.tokens < int(config.get("max_tokens", 300000))


func _process(delta: float) -> void:
	if not active or sim == null or sim.finished:
		return
	real_time += delta
	_since += delta
	if _inflight >= 0:
		if real_time - _inflight_sent > float(config.get("timeout", 60.0)) + 5.0:
			_abandoned[_inflight] = true
			adapter.cancel()
			var id := _inflight
			_inflight = -1
			_on_failure(id, "Zeitüberschreitung (keine Antwort)")
		return
	if real_time < _backoff_until or _since < float(config.get("interval", 45.0)):
		return
	_since = 0.0
	think()


## Eine Entscheidungsrunde: mit Modell (asynchron) oder per Regeln.
func think() -> void:
	if adapter == null or fallback_active or not budget_left():
		if adapter != null and not budget_left():
			status = "Budget erschöpft – Ersatzmodus (regelbasiert)"
		_run_rules("Ersatzmodus" if adapter != null else "Regeln")
		return
	var obs := sim.mayor.indicators()
	var messages := [{"role": "system", "content": system_prompt()}, {"role": "user", "content": user_prompt(obs)}]
	_inflight = _next_req
	_next_req += 1
	_inflight_sent = real_time
	stats.requests += 1
	status = "wartet auf Antwort"
	api_log.write({"type": "request", "player": "buergermeister", "req": _inflight, "game_time": sim.game_min, "provider": config.get("provider"), "model": config.get("model"), "messages": messages})
	adapter.observation = obs
	adapter.send(_inflight, messages)


func handle_result(req_id: int, r: Dictionary) -> void:
	if _applied.has(req_id) or _abandoned.has(req_id) or req_id != _inflight:
		return
	_inflight = -1
	_applied[req_id] = true
	var usage: Dictionary = r.get("usage", {}) if r.get("usage") is Dictionary else {}
	stats.tokens += int(usage.get("total_tokens", 0))
	api_log.write({"type": "response", "player": "buergermeister", "req": req_id, "ok": r.get("ok", false), "content": r.get("content", ""), "error": r.get("error", ""), "usage": usage})
	if not r.get("ok", false):
		_on_failure(req_id, str(r.get("error", "Fehler")))
		return
	var parsed := AgentController.parse_response(str(r.get("content", "")))
	if not parsed.ok:
		stats.invalid += 1
		_on_failure(req_id, "ungültige Antwort (%s)" % parsed.error)
		return
	stats.ok += 1
	_fail = 0
	if fallback_active:
		fallback_active = false
		sim.log_event("Bürgermeister: API wieder erreichbar – Ersatzmodus beendet.", "good")
	status = "bereit"
	_apply(parsed, "KI")


func _on_failure(req_id: int, msg: String) -> void:
	stats.errors += 1
	_fail += 1
	last_error = msg
	_backoff_until = real_time + minf(60.0, 2.0 * pow(2.0, _fail - 1))
	status = "Fehler: %s" % msg
	api_log.write({"type": "failure", "player": "buergermeister", "req": req_id, "error": msg})
	if _fail >= FAIL_LIMIT and config.get("fallback", true) and not fallback_active:
		fallback_active = true
		sim.log_event("Bürgermeister: API gestört – ERSATZMODUS (regelbasiert) aktiv.", "warn")


func _run_rules(source: String) -> void:
	var d := MayorBrain.decide(sim.mayor.indicators())
	_apply(AgentController.parse_response(JSON.stringify(d)), source)


func _apply(parsed: Dictionary, source: String) -> void:
	var summary: String = parsed.summary
	if summary != "":
		summaries.append({"t": sim.game_min, "text": summary, "source": source})
		if summaries.size() > 20:
			summaries.pop_front()
		sim.log_event("Bürgermeister %s%s: „%s“" % [sim.mayor.name, " [%s]" % source if source != "KI" else "", summary.left(200)], "ai")
		decided.emit(summary, source)
	if parsed.memory != "":
		sim.mayor.remember(parsed.memory)
	for a in parsed.actions.slice(0, MAX_ACTIONS):
		var res := sim.mayor.execute(a)
		if res.ok:
			stats.actions_ok += 1
		else:
			stats.actions_rejected += 1
		api_log.write({"type": "action", "player": "buergermeister", "source": source, "action": a, "ok": res.ok, "msg": res.msg})


func system_prompt() -> String:
	var lines: Array = []
	for k in Mayor.SCHEMA:
		var s: Dictionary = Mayor.SCHEMA[k]
		var ps: Array = []
		for p in s.params:
			ps.append("%s:%s" % [p, s.params[p]])
		lines.append("- %s(%s): %s" % [k, ", ".join(ps), s.desc])
	return """Du bist die Bürgermeisterin bzw. der Bürgermeister einer Stadt in einem Wirtschaftsspiel. Du lenkst die Stadtentwicklung innerhalb der Spielregeln.
Ziel: bezahlbarer Wohnraum, Arbeitsplätze, solide Finanzen, zügige und regelkonforme Bauanträge, damit du wiedergewählt wirst (jährliche Wahl).
REGELN: Du darfst nur über städtische Grundstücke verfügen; private Rechte sind unantastbar. Große Vorhaben (Quartiere, Kosten über 30 000 EUR) braucht einen Ratsbeschluss mit drei Fraktionen (Wachstum, Soziales, Haushalt); die Engine zählt die Stimmen. Ohne Haushaltsmittel gibt es keine Projekte. Eine Ausweisung baut noch nichts: Grundstücke müssen vergeben, finanziert, erschlossen und bebaut werden. Bauanträge entscheidest du nach den benannten Voraussetzungen der Vorprüfung, nie nach Sympathie: Ablehnen nur wegen konkret fehlender Voraussetzungen, sonst genehmigen. Nutze nur IDs aus deiner Beobachtung.
AKTIONEN:
%s
ANTWORTFORMAT: Antworte ausschließlich mit einem JSON-Objekt ohne weiteren Text:
{"summary": "kurze Begründung deiner Entscheidung", "actions": [{"action": "...", ...}], "memory": "optionale Notiz für später"}
Jede Aktion hat die Felder genau so, wie oben angegeben, direkt in der Aktion (nicht verschachtelt), und möglichst ein Feld "reason". Höchstens %d Aktionen.""" % ["\n".join(lines), MAX_ACTIONS]


func user_prompt(obs: Dictionary) -> String:
	return "Aktuelle Lage der Stadt (JSON):\n" + JSON.stringify(obs) + "\nEntscheide jetzt."


func to_dict() -> Dictionary:
	return {"stats": stats, "summaries": summaries, "fallback": fallback_active}


func from_dict(d: Dictionary) -> void:
	stats = d.get("stats", stats)
	summaries = d.get("summaries", [])
	fallback_active = bool(d.get("fallback", false))
