class_name DispatchAgent
extends Node
## Disponent mit Sprachmodell (Claude): nimmt kleinen lokalen Modellspielern die Auftragszuweisung ab.
## Die Regeln liefern nummerierte, gueltige Kandidaten (DispatchCandidates); das Modell waehlt nur Nummern, der
## ActionExecutor prueft jede Wahl. Bei API-Fehlern, ungueltiger Antwort oder erschoepftem Budget uebernimmt sofort die
## Regelwahl (sichtbar als Quelle "Regeln"/"Ersatzmodus"), die Fahrzeuge stehen also nie wegen des Modells still.
## Ein Aufruf deckt alle versorgten Firmen ab (eine Claude-Instanz, getrennter Kontext je Aufruf, kein Gedaechtnis).

signal decided(summary: String, source: String)

const FAIL_LIMIT := 3
const MAX_PICKS := 6

var sim: Simulation
var config := {}
var adapter: LLMAdapter
var api_log: ApiLog
var active := true
var eligible := {}                 # Firmen-ID -> true
var stats := {"requests": 0, "ok": 0, "errors": 0, "invalid": 0, "tokens": 0, "assigned": 0, "rejected": 0, "by_rules": 0}
var status := "bereit"
var last_error := ""
var fallback_active := false
var summaries: Array = []
var real_time := 0.0

var _since := 0.0
var _inflight := -1
var _inflight_sent := 0.0
var _pending: Array = []           # Kandidaten der laufenden Anfrage
var _next_req := 1
var _applied := {}
var _abandoned := {}
var _fail := 0
var _backoff_until := 0.0


func setup(simulation: Simulation, cfg: Dictionary, logger: ApiLog, company_ids: Array) -> void:
	sim = simulation
	config = cfg
	api_log = logger
	for id in company_ids:
		eligible[int(id)] = true
	var provider := str(cfg.get("provider", "demo"))
	if provider in ["demo", "regel"]:
		provider = "demo"
	else:
		adapter = LLMAdapter.create(provider)
		adapter.config = cfg
		add_child(adapter)
		adapter.completed.connect(handle_result)
		ApiLog.register_secret(str(cfg.get("api_key", "")))
	sim.dispatcher = self
	status = "regelbasiert" if adapter == null else "bereit"


## Uebernimmt der Disponent die Auftragszuweisung dieser Firma? Sonst arbeitet die Regel-Disposition des Spielers selbst.
func covers(cid: int) -> bool:
	return active and adapter != null and eligible.has(cid) and not fallback_active and budget_left()


func budget_left() -> bool:
	return stats.requests < int(config.get("max_requests", 400)) and stats.tokens < int(config.get("max_tokens", 600000))


func _process(delta: float) -> void:
	if not active or sim == null or sim.finished or adapter == null:
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
	if real_time < _backoff_until or _since < float(config.get("interval", 12.0)):
		return
	_since = 0.0
	think()


## Sammelt die Kandidaten aller versorgten Firmen.
func gather() -> Array:
	var groups: Array = []
	var nr := 1
	for cid in eligible:
		var c = sim.company(int(cid))
		if c == null or not c.is_active():
			continue
		var obs := ObservationBuilder.build(sim, int(cid), [], 0.0, 10.0)
		var b := DispatchCandidates.build(obs, nr)
		if b.candidates.is_empty():
			continue
		nr += b.candidates.size()
		groups.append({"company": int(cid), "name": c.company_name, "cash": int(c.ledger.cash), "reputation": int(c.reputation),
			"slots": b.slots_left, "vehicles": b.vehicles, "candidates": b.candidates})
	return groups


func think() -> void:
	var groups := gather()
	if groups.is_empty():
		return
	var all: Array = []
	for g in groups:
		for c in g.candidates:
			var e: Dictionary = c.duplicate()
			e["company"] = g.company
			all.append(e)
	if adapter == null or fallback_active or not budget_left():
		_apply_rules(all, "Ersatzmodus" if adapter != null else "Regeln")
		return
	_pending = all
	var messages := [{"role": "system", "content": system_prompt()}, {"role": "user", "content": user_prompt(groups)}]
	_inflight = _next_req
	_next_req += 1
	_inflight_sent = real_time
	stats.requests += 1
	status = "wartet auf Antwort"
	api_log.write({"type": "request", "player": "disponent", "req": _inflight, "game_time": sim.game_min, "provider": config.get("provider"), "model": config.get("model"), "messages": messages})
	adapter.send(_inflight, messages)


func handle_result(req_id: int, r: Dictionary) -> void:
	if _applied.has(req_id) or _abandoned.has(req_id) or req_id != _inflight:
		return
	_inflight = -1
	_applied[req_id] = true
	var usage: Dictionary = r.get("usage", {}) if r.get("usage") is Dictionary else {}
	stats.tokens += int(usage.get("total_tokens", 0))
	api_log.write({"type": "response", "player": "disponent", "req": req_id, "ok": r.get("ok", false), "content": r.get("content", ""), "error": r.get("error", ""), "usage": usage})
	if not r.get("ok", false):
		_on_failure(req_id, str(r.get("error", "Fehler")))
		return
	var parsed := parse_choice(str(r.get("content", "")))
	if not parsed.ok:
		stats.invalid += 1
		_on_failure(req_id, "ungültige Antwort (%s)" % parsed.error)
		return
	stats.ok += 1
	_fail = 0
	if fallback_active:
		fallback_active = false
		sim.log_event("Disponent: API wieder erreichbar – Ersatzmodus beendet.", "good")
	status = "bereit"
	_apply_choice(parsed.choice, parsed.reason, "KI")


## Antwort {"wahl":[1,4],"begruendung":"..."} lesen (auch mit Textrahmen oder Codeblock).
static func parse_choice(text: String) -> Dictionary:
	var a := text.find("{")
	var b := text.rfind("}")
	if a < 0 or b <= a:
		return {"ok": false, "error": "kein JSON"}
	var data = JSON.parse_string(text.substr(a, b - a + 1))
	if not data is Dictionary or not data.get("wahl") is Array:
		return {"ok": false, "error": "Feld 'wahl' fehlt"}
	var nums: Array = []
	for x in data.wahl:
		if x is float or x is int:
			nums.append(int(x))
		elif x is String and str(x).is_valid_int():
			nums.append(int(x))
	return {"ok": true, "choice": nums, "reason": str(data.get("begruendung", "")).left(300)}


func _on_failure(req_id: int, msg: String) -> void:
	stats.errors += 1
	_fail += 1
	last_error = msg
	_backoff_until = real_time + minf(60.0, 2.0 * pow(2.0, _fail - 1))
	status = "Fehler: %s" % msg
	api_log.write({"type": "failure", "player": "disponent", "req": req_id, "error": msg})
	if _fail >= FAIL_LIMIT and config.get("fallback", true) and not fallback_active:
		fallback_active = true
		sim.log_event("Disponent: API gestört – ERSATZMODUS (Regeln) aktiv.", "warn")
	if not _pending.is_empty():       # die Fahrzeuge duerfen nicht auf die API warten
		_apply_rules(_pending, "Ersatzmodus")
		_pending = []


func _apply_rules(cands: Array, source: String) -> void:
	var picks := DispatchCandidates.rule_pick(cands, MAX_PICKS)
	stats.by_rules += picks.size()
	_execute(cands, picks, source, "")


func _apply_choice(choice: Array, reason: String, source: String) -> void:
	_execute(_pending, choice, source, reason)
	_pending = []


func _execute(cands: Array, picks: Array, source: String, reason: String) -> void:
	var by_nr := {}
	for c in cands:
		by_nr[int(c.nr)] = c
	var used_v := {}
	var used_c := {}
	var done := 0
	for n in picks.slice(0, MAX_PICKS):
		var c = by_nr.get(int(n))
		if c == null or used_v.has(c.vehicle_id) or used_c.has(c.contract_id):
			stats.rejected += 1
			continue
		var kc: Contract = sim.contracts.get(str(c.contract_id))
		if kc == null or kc.status != "open":
			# Auftrag waehrend der Antwortzeit vergeben oder abgelaufen: naechstbester Kandidat fuer dasselbe Fahrzeug
			var alt = null
			for c2 in cands:
				var k2: Contract = sim.contracts.get(str(c2.contract_id))
				if int(c2.vehicle_id) == int(c.vehicle_id) and not used_c.has(c2.contract_id) and k2 != null and k2.status == "open":
					alt = c2
					break
			if alt != null:
				c = alt
				stats["substituted"] = int(stats.get("substituted", 0)) + 1
		used_v[c.vehicle_id] = true
		used_c[c.contract_id] = true
		var a := {"action": "accept_contract", "contract_id": c.contract_id, "vehicle_id": c.vehicle_id}
		var res: Dictionary = sim.executor.execute(int(c.company), a, "", "Disponent")
		if res.ok:
			stats.assigned += 1
			done += 1
		else:
			stats.rejected += 1
		api_log.write({"type": "action", "player": int(c.company), "source": "Disponent", "action": a, "ok": res.ok, "msg": res.msg})
	if done > 0:
		var text := "%d Zuweisung(en)%s" % [done, (": " + reason) if reason != "" else ""]
		summaries.append({"t": sim.game_min, "text": text, "source": source})
		if summaries.size() > 20:
			summaries.pop_front()
		sim.log_event("Disponent [%s]: %s" % [source, text.left(200)], "ai")
		decided.emit(text, source)


func system_prompt() -> String:
	return """Du bist der Disponent mehrerer Transportunternehmen in einem Wirtschaftsspiel. Für jedes Unternehmen siehst du freie Fahrzeuge und eine nummerierte Liste gültiger Zuweisungen (Fahrzeug -> Auftrag).
Ziel: möglichst viel Gewinn und pünktliche Lieferungen. Wähle je Fahrzeug höchstens eine Zuweisung und jeden Auftrag höchstens einmal. Gute Zuweisungen haben hohe Marge im Verhältnis zur Strecke und eine Frist mit Puffer. Strecken sind in Kacheln angegeben (keine Kilometer), Beträge in EUR. Angebote mit wenig Restlaufzeit (angebot_noch_min) verfallen bald: bei gleicher Güte zuerst wählen. Wähle nichts, wenn eine Zuweisung unwirtschaftlich ist (Marge klein oder negativ). Ein Unternehmen mit wenig Bargeld sollte kurze, sichere Aufträge bevorzugen; jede Firma hat nur die angegebene Zahl freier Auftragsplätze (slots).
Du darfst nur Nummern aus der Liste wählen; erfinde nichts.
ANTWORTFORMAT: Antworte ausschließlich mit einem JSON-Objekt ohne weiteren Text:
{"wahl": [Nummern der gewählten Zuweisungen], "begruendung": "ein Satz"}
Höchstens %d Nummern.""" % MAX_PICKS


func user_prompt(groups: Array) -> String:
	return "Lage der Unternehmen (JSON):\n" + JSON.stringify(groups) + "\nWähle jetzt."


func to_dict() -> Dictionary:
	return {"stats": stats, "summaries": summaries, "fallback": fallback_active}


func from_dict(d: Dictionary) -> void:
	stats = d.get("stats", stats)
	summaries = d.get("summaries", [])
	fallback_active = bool(d.get("fallback", false))
