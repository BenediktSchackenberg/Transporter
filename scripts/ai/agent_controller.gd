class_name AgentController
extends Node
## Steuert einen KI-Spieler: plant Anfragen (Intervall + gebuendelte Ereignisse), haelt Budgets ein,
## behandelt Fehler (Timeout, Rate Limit, ungueltiges JSON, Verbindungsabbruch), verhindert
## Doppelausfuehrung und schaltet bei anhaltenden Problemen in den sichtbar markierten Ersatzmodus.
## Jeder Spieler hat einen eigenen Controller mit eigenem Kontext und eigener Erinnerung.

signal decided(cid: int, summary: String, source: String)

const MAX_ACTIONS := 6
const MIN_EVENT_GAP := 6.0        # Echtzeit-Sekunden zwischen ereignisgetriebenen Anfragen
const STALE_GAME_MIN := 90.0      # aeltere Antworten werden verworfen
const STALE_GAME_MIN_OLLAMA := 1440.0  # lokales Modell braucht fuer grosse Prompts laenger; Aktionen werden erneut validiert
const FAIL_LIMIT := 3             # aufeinanderfolgende Fehler bis zum Ersatzmodus
const API_RETRY_IN_FALLBACK := 60.0

var sim: Simulation
var cid := 0
var config := {}                  # provider, base_url, model, interval, max_requests, max_tokens, fallback, ...
var adapter: LLMAdapter
var api_log: ApiLog
var active := false               # false = pausiert (keine neuen Anfragen, Antworten werden zurueckgestellt)
var remaining_real_min := 0.0
var memory_note := ""
var goal := ""                    # selbst formuliertes Ziel des Spielers (aus der Antwort)
var passive_streak := 0           # Entscheidungen in Folge ohne wirksame Aktion
var summaries: Array = []         # [{t, text, source}]
var stats := {"requests": 0, "ok": 0, "errors": 0, "invalid": 0, "tokens": 0, "actions_ok": 0, "actions_rejected": 0}
var status := "bereit"
var last_error := ""
var fallback_active := false
var real_time := 0.0
var speed := 1.0                  # aktuelle Simulationsgeschwindigkeit (die Veraltet-Grenze waechst mit ihr)

var _inflight := -1
var _inflight_obs_min := 0.0
var _inflight_sent := 0.0
var _abandoned := {}
var _applied := {}
var _next_req := 1
var _since := 1000.0
var _events: Array = []
var _backoff_until := 0.0
var _consecutive_fail := 0
var _last_obs_min := 0.0
var _api_retry_at := 0.0
var _deferred: Array = []
var _fallback_rng := RandomNumberGenerator.new()
var _perceived: Array = []        # Anlaesse der laufenden Entscheidung (fuer das Protokoll)
var _startup_at := 0.0
var _rapid_retry_count := 0


func setup(simulation: Simulation, company_id: int, cfg: Dictionary, logger: ApiLog) -> void:
	sim = simulation
	cid = company_id
	config = cfg
	_startup_at = float(company_id) * 3.0 if cfg.get("provider", "") == "ollama" else 0.0
	api_log = logger
	_fallback_rng.seed = hash(company_id * 7919 + sim.city.seed_value)
	adapter = LLMAdapter.create(cfg.get("provider", "demo"))
	adapter.config = cfg
	if adapter is DemoAdapter:
		adapter.personality = sim.company(cid).personality
		adapter.fault_rate = float(cfg.get("demo_fault_rate", 0.0))
		adapter.rng.seed = _fallback_rng.seed + 1
	add_child(adapter)
	adapter.completed.connect(handle_result)
	ApiLog.register_secret(str(cfg.get("api_key", "")))
	sim.agent_event.connect(_on_agent_event)


func is_demo() -> bool:
	return adapter is DemoAdapter


func _on_agent_event(company_id: int, text: String) -> void:
	if company_id == cid:
		_events.append("%s: %s" % [Catalog.game_minutes_to_text(sim.game_min), text])
		if _events.size() > 12:
			_events.pop_front()


func budget_left() -> bool:
	return stats.requests < int(config.get("max_requests", 300)) and stats.tokens < int(config.get("max_tokens", 400000))


func _process(delta: float) -> void:
	if not active or sim == null or sim.finished:
		return
	real_time += delta
	_since += delta
	while not _deferred.is_empty():
		var d: Array = _deferred.pop_front()
		handle_result(d[0], d[1])
	if _inflight >= 0:
		# Wachhund: falls der Adapter nie antwortet
		if real_time - _inflight_sent > float(config.get("timeout", 45.0)) + 5.0:
			_abandoned[_inflight] = true
			adapter.cancel()
			var id := _inflight
			_inflight = -1
			_on_failure(id, {"error": "Zeitüberschreitung (keine Antwort)"})
		return
	if real_time < _backoff_until:
		return
	if real_time < _startup_at:
		return
	var interval := float(config.get("interval", 20.0))
	var due := _since >= interval or (not _events.is_empty() and _since >= MIN_EVENT_GAP)
	if not due:
		return
	_since = 0.0
	if fallback_active and real_time < _api_retry_at:
		_run_fallback()
		return
	if not budget_left():
		status = "Budget erschöpft" + (" – Ersatzmodus" if config.get("fallback", true) else "")
		if config.get("fallback", true):
			_run_fallback()
		return
	_start_request()


func _start_request() -> void:
	var obs := ObservationBuilder.build(sim, cid, _events, _last_obs_min, remaining_real_min, goal, _hint())
	_perceived = _events.duplicate()
	_events.clear()
	_last_obs_min = sim.game_min
	var messages := [{"role": "system", "content": system_prompt()}, {"role": "user", "content": user_prompt(obs)}]
	_inflight = _next_req
	_next_req += 1
	_inflight_obs_min = sim.game_min
	_inflight_sent = real_time
	stats.requests += 1
	status = "wartet auf Antwort"
	adapter.observation = obs
	api_log.write({"type": "request", "player": cid, "req": _inflight, "game_time": sim.game_min,
		"provider": config.get("provider"), "model": config.get("model"), "messages": messages})
	adapter.send(_inflight, messages)


## Verarbeitet eine Adapter-Antwort. Oeffentlich fuer Tests.
func handle_result(req_id: int, r: Dictionary) -> void:
	if not active and sim != null and not sim.finished and _inflight == req_id:
		_deferred.append([req_id, r])   # pausiert: nach Fortsetzen verarbeiten
		return
	if _applied.has(req_id):
		api_log.write({"type": "duplicate_ignored", "player": cid, "req": req_id})
		return
	if _abandoned.has(req_id) or req_id != _inflight:
		api_log.write({"type": "late_ignored", "player": cid, "req": req_id})
		return
	_inflight = -1
	_applied[req_id] = true
	var usage: Dictionary = r.get("usage", {}) if r.get("usage") is Dictionary else {}
	stats.tokens += int(usage.get("total_tokens", 0))
	api_log.write({"type": "response", "player": cid, "req": req_id, "ok": r.get("ok", false),
		"content": r.get("content", ""), "error": r.get("error", ""), "usage": usage})
	if not r.get("ok", false):
		_on_failure(req_id, r)
		return
	var parsed := parse_response(str(r.get("content", "")))
	if not parsed.ok:
		stats.invalid += 1
		last_error = parsed.error
		status = "ungültige Antwort"
		sim.record_result(cid, "Deine letzte Antwort war ungültig (%s). Antworte nur mit dem JSON-Objekt." % parsed.error)
		sim.log_event("%s: ungültige KI-Antwort (%s)" % [sim.company(cid).player_name, parsed.error], "warn", cid)
		_consecutive_fail += 1
		_check_fallback()
		return
	var stale_limit := (STALE_GAME_MIN_OLLAMA if config.get("provider", "") == "ollama" else STALE_GAME_MIN) * maxf(speed, 1.0)
	if sim.game_min - _inflight_obs_min > stale_limit:
		last_error = "Antwort veraltet – verworfen"
		status = last_error
		sim.record_result(cid, "Deine letzte Antwort kam zu spät und wurde verworfen.")
		api_log.write({"type": "stale_discarded", "player": cid, "req": req_id,
			"age_game_min": sim.game_min - _inflight_obs_min, "limit_game_min": stale_limit})
		return
	stats.ok += 1
	_consecutive_fail = 0
	if fallback_active:
		fallback_active = false
		sim.log_event("%s: API wieder erreichbar – Ersatzmodus beendet." % sim.company(cid).player_name, "good", cid)
	status = "bereit"
	_apply(parsed, "r%d" % req_id, "KI")


func _on_failure(req_id: int, r: Dictionary) -> void:
	stats.errors += 1
	_consecutive_fail += 1
	last_error = str(r.get("error", "Fehler"))
	var wait := minf(60.0, 2.0 * pow(2.0, _consecutive_fail - 1))
	if r.has("retry_after"):
		wait = maxf(wait, float(r.retry_after))
	_backoff_until = real_time + wait
	status = "Fehler: %s (neuer Versuch in %d s)" % [last_error, int(wait)]
	api_log.write({"type": "failure", "player": cid, "req": req_id, "error": last_error})
	_check_fallback()


func _check_fallback() -> void:
	if _consecutive_fail >= FAIL_LIMIT and config.get("fallback", true) and not fallback_active:
		fallback_active = true
		_api_retry_at = real_time + API_RETRY_IN_FALLBACK
		sim.log_event("%s: API gestört – ERSATZMODUS (regelbasiert) aktiv." % sim.company(cid).player_name, "warn", cid)
	if fallback_active:
		status = "ERSATZMODUS (regelbasiert) – " + last_error
		if real_time >= _api_retry_at:
			_api_retry_at = real_time + API_RETRY_IN_FALLBACK


func _run_fallback() -> void:
	var obs := ObservationBuilder.build(sim, cid, _events, _last_obs_min, remaining_real_min, goal, _hint())
	_perceived = _events.duplicate()
	_events.clear()
	_last_obs_min = sim.game_min
	var d := RuleBrain.decide(obs, sim.company(cid).personality, _fallback_rng)
	var parsed := parse_response(JSON.stringify(d))
	_apply(parsed, "fb%d" % _next_req, "Ersatzmodus")
	_next_req += 1


const PASSIVE := ["wait", "send_message", "inspect_resource", "request_progress_report", "update_plan_step", "remember", "forget"]


## Gegen unbegruendetes Dauerwarten: nach zwei passiven Runden ein sachlicher Hinweis in der Beobachtung.
func _hint() -> String:
	if passive_streak < 2:
		return ""
	var free := sim.company_vehicles(cid).filter(func(v): return v.state == "idle" and v.stops.is_empty()).size()
	return "Du hast %d Entscheidungen in Folge nichts Wirksames ausgeführt. Freie Fahrzeuge: %d, unbekannte offene Aufträge: %d. Löhne, Miete und Abschreibung laufen weiter." % [
		passive_streak, free, sim.market.open_contracts().filter(func(k): return not sim.company(cid).known.has(k.id)).size()]


func _apply(parsed: Dictionary, key_prefix: String, source: String) -> void:
	var summary: String = parsed.summary
	if summary != "":
		summaries.append({"t": sim.game_min, "text": summary, "source": source})
		if summaries.size() > 20:
			summaries.pop_front()
		var who := sim.company(cid).player_name
		sim.log_event("%s%s: „%s“" % [who, " [ERSATZMODUS]" if source == "Ersatzmodus" else "", summary], "ai", cid)
		decided.emit(cid, summary, source)
	if parsed.memory != "":
		memory_note = parsed.memory.left(600)
	if parsed.goal != "":
		goal = parsed.goal
	var i := 0
	var effective := 0
	var actions: Array = parsed.actions
	if parsed.get("plan") is Dictionary and not parsed.plan.is_empty():
		var pa: Dictionary = parsed.plan.duplicate()
		pa["action"] = "set_plan"
		if not _same_plan(pa):
			actions = [pa] + actions   # Nur einen geaenderten Plan erneut festlegen
	var origin := "api" if source == "KI" else "fallback"
	sim.decisions.set_context(cid, _perceived, parsed.goal if parsed.get("goal", "") != "" else goal, summary)
	for a in actions:
		if not a is Dictionary:
			continue
		var actual: Dictionary = _ground_action(a)
		if str(actual.get("action", "")) == "set_plan" and _same_plan(actual):
			continue
		var res := sim.executor.execute(cid, actual, "p%d:%s:a%d" % [cid, key_prefix, i], origin)
		i += 1
		if res.ok:
			stats.actions_ok += 1
			if str(actual.get("action", "")) not in PASSIVE:
				effective += 1
		else:
			stats.actions_rejected += 1
			if config.get("provider", "") == "ollama":
				_events.append("Abgelehnte Aktion %s: %s. Prüfe die gültigen IDs in verfuegbare_aktionen und ändere den nächsten Versuch." % [str(actual.get("action", "")), str(res.msg)])
		api_log.write({"type": "action", "player": cid, "key": "%s:a%d" % [key_prefix, i - 1], "source": source,
			"action": actual, "original_action": a if actual != a else {}, "ok": res.ok, "msg": res.msg})
	sim.decisions.clear_context(cid)
	passive_streak = 0 if effective > 0 else passive_streak + 1
	if effective > 0 or _events.is_empty():
		_rapid_retry_count = 0
	elif config.get("provider", "") == "ollama" and _rapid_retry_count < 2:
		_rapid_retry_count += 1
		_since = maxf(_since, float(config.get("interval", 20.0)) - MIN_EVENT_GAP)
	for e in parsed.get("erfahrungen", []):
		if e is Dictionary:
			sim.memory.upsert(cid, e, "modell" if source == "KI" else "ersatzmodus")
	if summary != "":
		sim.memory.add_event(cid, "entscheidung", summary)
	sim.memory.add_event(cid, "ausfuehrung", "%d Aktionen ausgeführt, %d abgelehnt" % [effective, actions.size() - effective])


func _ground_action(a: Dictionary) -> Dictionary:
	var id := str(a.get("contract_id", ""))
	if id not in ["A_best_available", "best_available"]:
		return a
	var name := str(a.get("action", ""))
	var candidates: Array = []
	if name == "accept_contract":
		var c := sim.company(cid)
		if sim.executor.active_contracts(cid) >= c.contract_capacity():
			return a
		for k in sim.market.open_contracts():
			if not c.known.has(k.id) or c.reputation < k.min_rep or (k.exclusive_for >= 0 and k.exclusive_for != cid and k.exclusive_until > sim.game_min):
				continue
			if a.has("vehicle_id"):
				var v: FleetVehicle = sim.vehicles.get(int(a.vehicle_id))
				if v == null or v.owner != cid or not k.vehicle_ok(v.model):
					continue
			elif not sim.company_vehicles(cid).any(func(v): return k.vehicle_ok(v.model)):
				continue
			candidates.append(k)
	elif name in ["assign_vehicle", "assign_transport"]:
		var v: FleetVehicle = sim.vehicles.get(int(a.get("vehicle_id", -1)))
		if v == null or v.owner != cid:
			return a
		for k in sim.contracts.values():
			if k.owner == cid and k.status == "accepted" and k.vehicle_ok(v.model):
				candidates.append(k)
	if candidates.is_empty():
		return a
	candidates.sort_custom(func(x, y): return float(x.reward) / maxf(1.0, float(x.distance)) > float(y.reward) / maxf(1.0, float(y.distance)))
	var grounded := a.duplicate()
	grounded["contract_id"] = candidates[0].id
	return grounded


func _same_plan(a: Dictionary) -> bool:
	var p: Dictionary = sim.plans.current(cid)
	if p.is_empty() or p.get("status", "") != "aktiv" or str(p.get("ziel", "")) != str(a.get("ziel", "")):
		return false
	if str(p.get("nutzen", "")) != str(a.get("nutzen", "")) or str(p.get("risiken", "")) != str(a.get("risiken", "")):
		return false
	var steps: Array = a.get("schritte", []) if a.get("schritte", []) is Array else []
	if steps.size() != p.schritte.size():
		return false
	for i in steps.size():
		if not steps[i] is Dictionary or str(steps[i].get("id", "S%d" % (i + 1))) != str(p.schritte[i].id) \
				or str(steps[i].get("text", "")) != str(p.schritte[i].text) \
				or steps[i].get("aktion", {}) != p.schritte[i].get("aktion", {}) \
				or steps[i].get("abhaengig_von", []) != p.schritte[i].get("abhaengig_von", []):
			return false
	return true


## Extrahiert und prueft die JSON-Antwort. Toleriert Codebloecke und Begleittext.
static func parse_response(text: String) -> Dictionary:
	# Reasoning-Modelle (z. B. Qwen) schicken teils <think>…</think> vor dem JSON
	var s := RegEx.create_from_string("(?s)<think>.*?</think>").sub(text, "", true).strip_edges()
	var start := s.find("{")
	var end := s.rfind("}")
	if start < 0 or end <= start:
		return {"ok": false, "error": "kein JSON-Objekt gefunden"}
	var data = _parse_object(s.substr(start, end - start + 1))
	if data == null:
		# Abgeschnittene Antwort (Token-Limit): vollstaendige Aktionen vor dem Abbruch retten
		data = _salvage_truncated(s.substr(start))
	if not data is Dictionary:
		return {"ok": false, "error": "ungültiges JSON"}
	if not data.get("actions") is Array:
		return {"ok": false, "error": "Feld 'actions' (Array) fehlt"}
	var actions: Array = []
	for a in data.actions:
		if a is Dictionary:
			actions.append(a)
	return {"ok": true, "summary": str(data.get("summary", "")).left(240), "actions": actions.slice(0, MAX_ACTIONS),
		"memory": str(data.get("memory", "")) if data.get("memory") != null else "",
		"goal": str(data.get("goal", "")).left(120) if data.get("goal") != null else "",
		"plan": data.get("plan") if data.get("plan") is Dictionary else {},
		"erfahrungen": data.get("erfahrungen") if data.get("erfahrungen") is Array else []}


static func _parse_object(text: String):
	var j := JSON.new()
	if j.parse(text) != OK or not j.data is Dictionary:
		return null
	return j.data


## Schneidet hinter der letzten vollstaendigen Aktion ab und schliesst Array und Objekt.
static func _salvage_truncated(text: String):
	var pos := text.length()
	for _i in 30:
		pos = text.rfind("}", pos - 1)
		if pos < 0:
			return null
		for tail in ["]}", "}", "}]}"]:
			var d = _parse_object(text.substr(0, pos + 1) + tail)
			if d != null and d.get("actions") is Array:
				return d
	return null


func system_prompt() -> String:
	if config.get("provider", "") == "ollama":
		return _local_system_prompt()
	var c := sim.company(cid)
	var p: Dictionary = Catalog.PERSONALITIES.get(c.personality, Catalog.PERSONALITIES.kostenoptimierer)
	var schema := ""
	var all := ActionExecutor.all_schema()
	for name in all:
		var s: Dictionary = all[name]
		var params: Array = []
		for k in s.params:
			params.append("%s:%s" % [k, s.params[k]])
		schema += "- %s(%s): %s\n" % [name, ", ".join(params), s.desc]
	schema += "GEBÄUDETYPEN für place_building (Typ (BxH, Kosten ohne Baufirmen-Aufschlag, Bauzeit): Nutzen):\n" + Estate.catalog_text() + "\n"
	var custom := str(config.get("strategy", "")).strip_edges()
	return """Du bist %s, Inhaber(in) der Spedition „%s“ im Wirtschaftsspiel „Pixel Transport Rivals“. Du spielst gegen %d andere KI-Unternehmer in einer Retro-Pixelstadt.
Persönlichkeit: %s – %s%s

SPIELANWEISUNG: Du führst ein Transportunternehmen und willst diese Partie gewinnen. Entscheide selbstständig, welche verfügbaren Handlungen deine Gewinnchancen verbessern. Vergleiche Investitionen, Aufträge, Personal, Kooperationen und mögliche Angriffe auf Konkurrenten. Berücksichtige Kosten, Risiken und die verbleibende Spielzeit. Beobachte die erkennbaren Strategien deiner Gegner und reagiere darauf. Du darfst im Rahmen der Spielregeln täuschen, konkurrieren und sabotieren. Nutze ausschließlich die angebotenen Spielaktionen. Jede Handlung muss durch die Spielengine ausgeführt und bestätigt werden. Warte nur, wenn es dafür einen konkreten Grund gibt; Gespräche ersetzen keine Handlungen.

ZIEL: Gewinne die Partie und sieh deine Konkurrenten bankrott gehen. Ein zahlungsunfähiger Konkurrent (Insolvenz, Verwertung, Schließung) kann nicht gewinnen; wer am Ende zahlungsfähig ist und den höchsten kumulierten Nettogewinn hat, siegt. Mittel dazu sind besser wirtschaften, Aufträge und Personal wegnehmen, Preise drücken, Konkurrenten vom Kredit abschneiden und im Rahmen der Regeln auch Sabotage. Am Spielende den höchsten kumulierten Nettogewinn haben (Erlöse minus Treibstoff, Löhne, Miete, Reparaturen, Abschreibung %d %%/Tag, Zinsen, Strafen, Sabotagekosten usw.). Startkapital und Kredite sind KEIN Gewinn; Zinsen sind Aufwand. Gleichstand: Reputation, dann erledigte Aufträge.

REGELN (Kurzfassung):
- Aufträge annehmen (accept_contract) und Fahrzeugen zuweisen; Fahrzeug muss Kapazität/Kühlung/Schwerlast erfüllen und einen Fahrer haben. Pünktlich = volle Vergütung und +Reputation; je angefangene Stunde Verspätung −25 %%; >4 h über Frist = gescheitert mit 30 %% Vertragsstrafe.
- Bei Spielende werden überfällige Aufträge bestraft, unvollständige nicht bezahlt.
- Positionen sind Tile-Koordinaten [x, y]; Fahrstrecke ≈ |dx| + |dy| (ca. 2–3 Tiles pro Spielminute inkl. Ampeln). 4 Stellplätze pro Depot.
- Besuche (deine Figur läuft automatisch hin, Warteschlange bis 4): Aufträge sammeln an der Jobbörse (collect_contracts), Fahrer einstellen im Personalbüro, Fahrzeugkauf im Autohaus, Depot- und Büroeröffnung vor Ort. Alles andere geht per Disposition aus der Ferne.
- Du siehst nur Aufträge, die du gesammelt hast ("unbekannte_offene_auftraege" zählt den Rest). Internet im eigenen Büro: Stufe 1 = im Büro sammeln, Stufe 2 = von überall.
- Gleichzeitig laufende Aufträge sind begrenzt: 3 ohne Büro, +3 je Zentralenstufe, +2 je Filiale. Büros sind Investitionen (Abschreibung 1 %%/Tag) mit laufenden Kosten.
- Einen Spieler öffentlich ansprechen geht nur bei Begegnung; per Funk (private=true) oder Rundruf ("all") immer.
- PERSONAL: Fahrzeuge fahren nur mit einem eigenen Arbeiter am Steuer (assign_worker_task kind=fahren). Jeder Arbeiter tut immer nur eine Sache (fahren ODER reparieren ODER bewachen …) und braucht Zeit und Wege. Erschöpfte Arbeiter (≥90 %%) nehmen keine Aufgaben an. Arbeiter anwerben: recruit_worker – deine Figur geht hin, wer zuerst kommt, bekommt ihn. Vorarbeiter verteilen Aufgaben in ihrem Bereich, melden Störungen und dürfen im Rahmen ihrer Befugnisse Ersatz einteilen.
- RESSOURCEN sind knapp und für alle gleich sichtbar (ressourcen): Arbeitskräfte, Fahrzeugangebote beim Händler, Treibstoff an Tankstellen, Ersatzteile in Werkstätten. Ohne eigenen Treibstoffvorrat wird teuer nachgetankt. Reparatur vor Ort braucht Mechaniker + Ersatzteile, sonst Werkstatt/Abschleppen.
- PLANUNG: Halte einen eigenen strukturierten Plan (Feld "plan" oder set_plan): Ziel, Schritte mit optional hinterlegter Aktion, Abhängigkeiten, benötigte Mittel, erwarteter Nutzen, Risiken und Abbruchbedingungen. Führe Schritte mit execute_plan_step aus oder handle direkt. Meldet die Engine "neu_planen" (Abbruchbedingung, entfallene Voraussetzung, gescheiterter Schritt), überprüfe und ersetze den Plan. Bereits entstandene Kosten bleiben.
- GEDÄCHTNIS (erfahrungsbasierte Anpassung durch gespeicherten Kontext): "gedaechtnis" zeigt eine Auswahl deiner Erfahrungen (mit Belegen und Vertrauen) und letzter Ereignisse. Halte Erfahrungen aktuell (Antwortfeld "erfahrungen" oder remember/forget); unterscheide Tatsache und Vermutung, wenige Belege = geringes Vertrauen.
- EXPERIMENTE: Mit start_experiment kannst du begrenzte Vergleiche in der echten Simulation anlegen (z. B. Einzel- vs. Sammeltouren). Sie kosten echtes Geld und Zeit; entscheide selbst, ob sich der Erkenntnisgewinn lohnt. Wenige Beobachtungen = unsicheres Ergebnis.
- BETRIEBSHOF: Du startest auf einem leeren Grundstück (2 offene Stellplätze, 20 Lagerplätze, eine offene Ladefläche). Baue selbst: Büro (Firmensitz, Auftragskapazität), Stellplätze/Hallen (Flottengröße), Laderampen (parallele Abfertigung), Lager/Kühllager, Werkstatt, Tankstelle, Pausen-/Schulungsräume, Sicherheit, Waschplatz, vermietbare Büros (Mieteinnahmen). Bauvorschläge mit gültigen Positionen stehen in betriebshof.bauvorschlaege_xy_rot ([x, y, rot]); Engpässe (wartende Fahrzeuge, volle Lager) sind sichtbar. Grundstückserweiterung mit expand_plot.
- KOMBINIEREN: Fahrten bestehen aus Stopps (plan_tour): Teilmengen, Zwischenlager im eigenen Depot ('lager:<Depot-ID>', 60 Plätze), Umladen auf ein anderes Fahrzeug, Sammeltouren mit mehreren Aufträgen und Rückfahrten. Bezahlt wird ein Auftrag erst bei vollständiger Lieferung am Ziel.
- SABOTAGE an Fahrzeugen nur mit einem eigenen Arbeiter an einem gesichteten, stehenden Fremdfahrzeug. Ausgänge: Erfolg, Fehlschlag oder erwischt – dann ist dieser Arbeiter für die ganze Partie verloren (plus Bußgeld). Wachen, Zeugen und Sicherheitsstufe erhöhen das Risiko.
- 3 pünktliche Lieferungen für denselben Kunden machen ihn zum Stammkunden (exklusive, besser bezahlte Aufträge).
- STADT UND WETTER: "wetter" sind Modelldaten für Mainz (keine Wetterstation), für alle Unternehmen gleich; die Wetterzeit ist reale Zeit, die Spielzeit läuft schneller. Regen, Wind, Hitze, Kälte, Glätte und Nebel wirken als simulierte Spielereignisse: langsamere Fahrten, längeres Verladen im Freien (überdachte Plätze helfen), höheres Pannenrisiko ohne Wartung, veränderter Bedarf. "lage" listet aktive Ereignisse mit Ursache, Wirkung und Ende. Aufträge mit "kunde" stammen von benannten Kundenfiguren mit konkretem Anliegen; erledigte Anliegen kehren erst nach langer Pause wieder, unerledigte werden dringlicher und besser bezahlt.
- Nachrichten bewirken nichts Verbindliches. Besitz, Aufträge und Geld wechseln nur über offer_trade + accept_trade. Begrenztes Nachrichtenbudget – rede mit wirtschaftlichem Anlass, dann handle.
- Sabotage ist regelwidrig, kostet Geld, hat Abklingzeit und kann entdeckt werden (Bußgeld, Schadensersatz, Reputationsverlust, Paktbruch). Wirtschaftlicher Erfolg ist der Hauptweg zum Sieg.

AKTIONEN (Parameter, ? = optional):
%s
ANTWORTFORMAT: Antworte ausschließlich mit einem JSON-Objekt, ohne weiteren Text:
{"goal": "dein aktuelles Ziel in wenigen Worten", "plan": {optional: neuer Plan wie bei set_plan}, "erfahrungen": [optional: {id?, inhalt, bereich:[...], art, vertrauen}], "summary": "1–2 Sätze in Ich-Form auf Deutsch: was du tust und warum (nur für Zuschauer sichtbar)", "actions": [{"action": "...", ...}], "memory": "kurze Notiz für dich selbst, max. 400 Zeichen"}
Höchstens %d Aktionen. Verwende nur IDs aus der Beobachtung. Gib keine internen Gedankengänge aus.""" % [
		c.player_name, c.company_name, sim.companies.size() - 1, p.name, p.prompt,
		("\nZusätzliche Strategie-Vorgabe: " + custom) if custom != "" else "",
		int(Catalog.DEPRECIATION_PER_DAY * 100), schema, MAX_ACTIONS]


func user_prompt(obs: Dictionary) -> String:
	if config.get("provider", "") == "ollama":
		var recent: Array = summaries.slice(-2).map(func(s): return str(s.text))
		return "NOTIZ: %s\nLETZTE ENTSCHEIDUNGEN: %s\nBEOBACHTUNG:\n%s" % [memory_note.left(300), JSON.stringify(recent), JSON.stringify(ObservationBuilder.compact_for_local(obs))]
	var mem := ""
	for s in summaries.slice(-5):
		mem += "- %s: %s\n" % [Catalog.game_minutes_to_text(s.t), s.text]
	return "DEINE NOTIZ: %s\nDEINE LETZTEN ENTSCHEIDUNGEN:\n%s\nBEOBACHTUNG:\n%s" % [
		memory_note if memory_note != "" else "(leer)", mem if mem != "" else "(keine)\n", JSON.stringify(obs)]


func _local_system_prompt() -> String:
	var c := sim.company(cid)
	var p: Dictionary = Catalog.PERSONALITIES.get(c.personality, Catalog.PERSONALITIES.kostenoptimierer)
	var names := ["collect_contracts", "accept_contract", "assign_vehicle", "plan_tour", "assign_worker_task", "recruit_worker",
		"buy_vehicle", "sell_vehicle", "rent_depot", "cancel_depot", "build_office", "upgrade_office", "install_internet",
		"take_loan", "request_loan", "repay_loan", "repair_vehicle", "buy_supplies", "set_plan", "execute_plan_step", "wait"]
	var all := ActionExecutor.all_schema()
	var lines: Array = []
	for name in names:
		var params: Array = []
		for key in all[name].params:
			params.append("%s:%s" % [key, all[name].params[key]])
		lines.append("%s(%s)" % [name, ",".join(params)])
	var custom := str(config.get("strategy", "")).strip_edges()
	return """Du bist %s von %s. Persönlichkeit: %s. Ziel: höchster kumulierter Nettogewinn am Spielende. Kredit erhöht Bargeld, nicht Gewinn; Zinsen, Löhne und Fahrzeugabschreibung senken ihn. %s
Entscheide anhand der BEOBACHTUNG. Verwende ausschließlich exakte IDs aus markt, meine_auftraege, freie_depotstandorte, orte und verfuegbare_aktionen. Erfinde keine IDs, keine Platzhalter wie A_best_available. Wenn ein Auftrag nicht bekannt ist, collect_contracts. Fahrzeuge brauchen einen Fahrer: assign_worker_task mit kind='fahren', worker_id und vehicle_id. Vor Fahrzeugkauf prüfe passende bekannte Aufträge, freien Stellplatz, besetzbaren Fahrer, Bargeldreserve, Kreditangebot und Gewinnschwelle in mit_kredit. Kredit nur aufnehmen, wenn Kauf samt Fahrer und rechtzeitiger Auslastung plausibel ist. Bei Kredit: erst take_loan mit Betrag/Bank/Monaten, dann buy_vehicle mit offer_id. Ist die Flotte voll, prüfe rent_depot oder einen Büroumbau nur bei absehbarer Zusatznachfrage; Depotmiete läuft täglich. Angebote sind umkämpft und werden beim Kauf erneut geprüft. Warte nur mit Grund. Bei abgelehnter Aktion korrigiere die IDs oder Voraussetzungen; wiederhole nicht blind denselben Fehler. Ändere einen bestehenden Plan nur bei neuer Lage. Maximal %d Aktionen.
Häufige Aktionen: %s
Weitere Aktionen stehen in verfuegbare_aktionen und der Spielengine bereit. Antworte ausschließlich als JSON {"summary":"kurze Begründung in Ich-Form","goal":"Ziel","actions":[{"action":"..."}],"memory":"kurze Notiz"}. Kein Denktext.""" % [
		c.player_name, c.company_name, p.name, ("Zusatzstrategie: " + custom) if custom != "" else "", MAX_ACTIONS, "; ".join(lines)]


func to_dict() -> Dictionary:
	return {"memory_note": memory_note, "summaries": summaries, "stats": stats, "next_req": _next_req, "goal": goal,
		"passive_streak": passive_streak}


func from_dict(d: Dictionary) -> void:
	memory_note = d.memory_note
	summaries = d.summaries
	_next_req = int(d.get("next_req", 1))
	goal = str(d.get("goal", ""))
	passive_streak = int(d.get("passive_streak", 0))   # Idempotenzschluessel bleiben nach dem Laden eindeutig
	for k in d.stats:
		stats[k] = int(d.stats[k])


# ------------------------------------------------------------------ Testhilfen
func setup_for_test(simulation: Simulation, company_id: int) -> void:
	sim = simulation
	cid = company_id
	config = {"provider": "demo", "fallback": false}
	api_log = ApiLog.new()
	active = true


func begin_request_for_test() -> int:
	_inflight = _next_req
	_next_req += 1
	_inflight_obs_min = sim.game_min
	return _inflight


func abandon_for_test() -> void:
	_abandoned[_inflight] = true
	_inflight = -1
