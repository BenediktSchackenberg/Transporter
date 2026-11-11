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

const DISPATCHER_OWNED := ["accept_contract", "assign_transport", "assign_vehicle", "plan_tour", "assign_transport/plan_tour"]   # bei aktivem Disponenten dessen Aufgabe
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
var _dispatch_min := 0.0          # Spielminute der letzten Disposition ohne Modellaufruf
var speed := 1.0                  # aktuelle Simulationsgeschwindigkeit (die Veraltet-Grenze waechst mit ihr)

var _inflight := -1
var _inflight_obs_min := 0.0
var _latency_game := 0.0             # gleitender Mittelwert: Spielminuten von der Beobachtung bis zur Antwort
var _inflight_sent := 0.0
var _inflight_generation := 0
var _abandoned := {}
var _applied := {}
var _next_req := 1
var _since := 1000.0
var _events: Array = []
# KI-Postfach: Auftraege aus der Beobachtung bleiben fuer diesen Spieler vorgemerkt, bis seine Antwort da ist (das Modell braucht
# mehrere Spieltage; vorher waren fast alle angenommenen Auftraege bei Ankunft der Antwort weg). Aktionen fuer ein gerade gekauftes,
# noch nicht geliefertes Fahrzeug warten, bis es da ist.
const HOLD_MAX := 8                 # hoechstens so viele Auftraege je Anfrage vormerken
const HOLD_NO_VEHICLE := 4            # ohne machbares Angebot: so viele trotzdem vormerken
const HOLD_GAME_MIN := 600.0        # Obergrenze der Vormerkung (5 Spieltage), falls keine Antwort kommt
const AFTER_BUY_GAME_MIN := 1440.0  # Obergrenze; solange der Kaufbesuch der Figur noch aussteht, warten die Aktionen
var _held: Array = []
var _release_later: Array = []
var _after_buy: Array = []          # [{action, known: [Fahrzeug-IDs beim Kauf], until}]
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


## Lokales Ollama kostet nichts: keine Anfrage- und Tokengrenze (Benedikt 11.11.2026).
func budget_left() -> bool:
	if str(config.get("provider", "")) == "ollama":
		return true
	return stats.requests < int(config.get("max_requests", 300)) and stats.tokens < int(config.get("max_tokens", 400000))


func _process(delta: float) -> void:
	var _pt := Time.get_ticks_usec()
	ProcTimer.mark("firmen_ki", cid)
	ProcTimer.sub("-")
	_process_timed(delta)
	ProcTimer.add("firmen_ki", _pt)


func _process_timed(delta: float) -> void:
	if not active or sim == null or sim.finished:
		return
	real_time += delta
	if not _release_later.is_empty():
		_release_holds(_release_later)
		_release_later.clear()
	_since += delta
	while not _deferred.is_empty():
		var d: Array = _deferred.pop_front()
		handle_result(d[0], d[1])
	_dispatch_tick()
	_after_buy_tick()
	if _inflight >= 0:
		# Wachhund: falls der Adapter nie antwortet
		if real_time - _inflight_sent > adapter.timeout_s() + 5.0:   # Zeitgrenze des Adapters (IONOS laenger)
			_abandoned[_inflight] = true
			adapter.cancel()
			_release_holds(_held)
			_held.clear()
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
	ProcTimer.sub("KI: Beobachtung", cid)
	var t_obs := Time.get_ticks_usec()
	var obs := ObservationBuilder.build(sim, cid, _events, _last_obs_min, remaining_real_min, goal, _hint())
	_slow("beobachtung", t_obs)
	_perceived = _events.duplicate()
	_events.clear()
	_last_obs_min = sim.game_min
	ProcTimer.sub("KI: Anfrage senden", cid)
	var messages := [{"role": "system", "content": system_prompt()}, {"role": "user", "content": user_prompt(obs)}]
	_inflight = _next_req
	_next_req += 1
	_inflight_obs_min = sim.game_min
	_inflight_sent = real_time
	_inflight_generation = sim.company(cid).generation
	_hold_market(obs)
	stats.requests += 1
	status = "wartet auf Antwort"
	adapter.observation = obs
	api_log.write({"type": "request", "player": cid, "req": _inflight, "game_time": sim.game_min,
		"provider": config.get("provider"), "model": config.get("model"), "messages": messages})
	adapter.send(_inflight, messages)


## Verarbeitet eine Adapter-Antwort. Oeffentlich fuer Tests.
func handle_result(req_id: int, r: Dictionary) -> void:
	ProcTimer.sub("KI: Antwort verarbeiten", cid)
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
	_release_later = _held.duplicate()   # Vormerkungen gelten bis nach der Ausfuehrung dieser Antwort (Ende _apply bzw. naechstes Bild)
	_held.clear()
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
	# Antworten nach Partieende oder fuer eine inzwischen neu gegruendete Firma nicht mehr anwenden.
	if sim.finished or sim.company(cid).generation != _inflight_generation:
		api_log.write({"type": "session_ended_ignored", "player": cid, "req": req_id})
		return
	var age_now := sim.game_min - _inflight_obs_min
	_latency_game = age_now if _latency_game <= 0.0 else lerpf(_latency_game, age_now, 0.3)
	# Offene Modelle mit langer Denkphase (Ollama lokal, IONOS gehostet: Qwen ~2 min) bekommen die lange Frist - Partie 09.11.:
	# mit 90 Spielminuten wurden bei IONOS alle Antworten von Viktor verworfen. Aktionen werden bei der Ausfuehrung ohnehin neu geprueft.
	var stale_limit := (STALE_GAME_MIN_OLLAMA if config.get("provider", "") in DISPATCH_PROVIDERS else STALE_GAME_MIN) * maxf(speed, 1.0)
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
	var t_apply := Time.get_ticks_usec()
	_apply(parsed, "r%d" % req_id, "KI")
	_slow("antwort_ausfuehren", t_apply)


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
	ProcTimer.sub("KI: Ersatzmodus", cid)
	var obs := ObservationBuilder.build(sim, cid, _events, _last_obs_min, remaining_real_min, goal, _hint())
	_perceived = _events.duplicate()
	_events.clear()
	_last_obs_min = sim.game_min
	var d := RuleBrain.decide(obs, sim.company(cid).personality, _fallback_rng, sim.strategy.params_of(cid))
	var parsed := parse_response(JSON.stringify(d))
	_apply(parsed, "fb%d" % _next_req, "Ersatzmodus")
	_next_req += 1


## Regel-Disposition fuer Modellspieler mit offenen Modellen (lokal per Ollama oder gehostet bei IONOS): in der Partie vom 09.11.
## lief sie mit IONOS gar nicht, Fahrzeuge mit angenommenem Auftrag standen ohne Fahrer.
const DISPATCH_PROVIDERS := ["ollama", "ionos"]
func _dispatch_help_on() -> bool:
	return config.get("provider", "") in DISPATCH_PROVIDERS and bool(config.get("dispatch_help", true))


## Ruckler-Suche: KI-Verarbeitung im Hauptthread ueber 50 ms protokollieren (Spiel stockte am 09.11.)
func _slow(what: String, t0: int) -> void:
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	if ms > 50.0 and api_log != null:
		api_log.write({"type": "slow", "player": cid, "what": what, "ms": snappedf(ms, 0.1), "game_min": int(sim.game_min)})


const DISPATCH_EVERY_MIN := 60.0   # Spielminuten zwischen zwei Hofrunden der Disposition (Marktangebote verfallen nach 90-160 Minuten)


## Die Disposition wartet nicht auf das Modell: Marktangebote verfallen nach 90 bis 160 Spielminuten, eine Modellrunde dauert laenger.
## Steht ein Fahrzeug mit Fahrer ohne Auftrag still, uebernimmt sie in kurzem Takt die Annahme und Zuweisung (auch waehrend ein Modellaufruf laeuft).
func _dispatch_tick() -> void:
	if not _dispatch_help_on() or fallback_active:
		return
	if sim.game_min - _dispatch_min < DISPATCH_EVERY_MIN:
		return
	_dispatch_min = sim.game_min
	var idle: bool = sim.company_vehicles(cid).any(func(v): return v.state == "idle" and v.stops.is_empty() and v.contract_id == "")   # auch ohne Fahrer: die Regeln setzen einen ein (Partie 08.11.: Fahrzeug 27 Runden ohne Fahrer)
	if not idle:
		return
	# Gleiche Lage wie bei der letzten Hofrunde (dieselben Fahrzeuge stehen, keine neuen Auftraege, Kasse kaum veraendert): auslassen,
	# hoechstens DISPATCH_IDLE_MAX_MIN lang. Jede Runde baut eine volle Beobachtung (60-100 ms) - Partie 09.11.: 4 Firmen, stuendlich, Ruckler.
	var sig := _dispatch_signature()
	if sig == _dispatch_sig and sim.game_min - _dispatch_run_min < DISPATCH_IDLE_MAX_MIN:
		return
	_dispatch_sig = sig
	_dispatch_run_min = sim.game_min
	_run_dispatch_help()


const DISPATCH_IDLE_MAX_MIN := 240.0
var _dispatch_sig := ""
var _dispatch_run_min := -1.0e9


func _dispatch_signature() -> String:
	var c := sim.company(cid)
	var parts: Array = []
	for v in sim.company_vehicles(cid):
		parts.append("%d:%s:%s:%s" % [v.id, v.state, v.contract_id, "f" if sim.driver_of(v) != null else "-"])
	var known := 0
	for k in sim.market.open_contracts():
		if c.known.has(k.id):
			known += 1
	parts.append("k%d" % known)
	parts.append("g%d" % int(c.ledger.cash / 5000.0))
	return ",".join(parts)


const DISPATCH := ["accept_contract", "assign_transport", "assign_worker_task", "collect_contracts", "repair_vehicle", "buy_supplies",
	"schedule_refueling", "assign_foreman",
	# Aufbau des Betriebshofs (Plan aus der Regel-KI: Stellplatz, Büro, Lager, Werkstatt, Internet), damit der Hof nicht leer bleibt
	"set_plan", "execute_plan_step", "place_building", "build_office", "upgrade_building", "upgrade_office", "install_internet", "assign_building_staff"]


## Nur der Tagesbetrieb aus der Regel-KI: Auftraege annehmen und zuweisen, Fahrer einsetzen, reparieren, tanken.
func _run_dispatch_help() -> void:
	ProcTimer.sub("KI: Hofrunde", cid)
	var t_dp := Time.get_ticks_usec()
	var obs := ObservationBuilder.build(sim, cid, [], _last_obs_min, remaining_real_min, goal, "")
	_slow("disposition_beobachtung", t_dp)
	var d := RuleBrain.decide(obs, sim.company(cid).personality, _fallback_rng, sim.strategy.params_of(cid))
	# Fahrer anwerben gehoert zum Tagesbetrieb, solange ein eigenes Fahrzeug ohne Fahrer dasteht (sonst bleibt die Anwerbung beim Modell)
	var allowed: Array = DISPATCH + (["recruit_worker"] if sim.company_vehicles(cid).any(func(v): return sim.driver_of(v) == null) else [])
	d["actions"] = d.actions.filter(func(a): return str(a.get("action", "")) in allowed)
	if sim.dispatcher != null and sim.dispatcher.covers(cid):   # Auftragszuweisung macht der Claude-Disponent; die Regeln bleiben fuer Fahrer, Reparatur, Tanken und Hofaufbau
		d["actions"] = d.actions.filter(func(a): return str(a.get("action", "")) not in ["accept_contract", "assign_transport"] \
			or (str(a.get("action", "")) == "assign_transport" and sim.contracts.has(str(a.get("contract_id", ""))) and sim.contracts[str(a.contract_id)].internal != ""))   # eigene Materialtransporte bleiben bei den Regeln
	if d.actions.is_empty():
		return
	d["summary"] = ""
	d["goal"] = ""
	d["memory"] = ""
	var parsed := parse_response(JSON.stringify(d))
	# Rueckmeldungen und Zaehler gehoeren dem Modell: die Disposition soll sie weder beschoenigen noch verfaelschen
	var keep_events := _events.duplicate()
	var keep_retry := _rapid_retry_count
	var keep_streak := passive_streak
	_apply(parsed, "dp%d" % _next_req, "Disposition")
	_events = keep_events
	_rapid_retry_count = keep_retry
	passive_streak = keep_streak
	_next_req += 1
	stats["dispatch_help"] = int(stats.get("dispatch_help", 0)) + 1


const PASSIVE := ["wait", "send_message", "inspect_resource", "request_progress_report", "update_plan_step", "remember", "forget"]


## Gegen unbegruendetes Dauerwarten: nach zwei passiven Runden ein sachlicher Hinweis in der Beobachtung.
func _hint() -> String:
	if passive_streak < 2:
		return ""
	var free := sim.company_vehicles(cid).filter(func(v): return v.state == "idle" and v.stops.is_empty()).size()
	return "Du hast %d Entscheidungen in Folge nichts Wirksames ausgeführt. Freie Fahrzeuge: %d, unbekannte offene Aufträge: %d. Löhne, Miete und Abschreibung laufen weiter." % [
		passive_streak, free, sim.market.open_contracts().filter(func(k): return not sim.company(cid).known.has(k.id)).size()]


func _apply(parsed: Dictionary, key_prefix: String, source: String) -> void:
	ProcTimer.sub("KI: Aktionen ausfuehren", cid)
	# Fehlende Felder (z. B. wenn die Regel-KI abbrach) nicht als Laufzeitfehler: Standardwerte einsetzen
	for key in ["summary", "memory", "goal"]:
		if not parsed.get(key) is String:
			parsed[key] = ""
	if not parsed.get("actions") is Array:
		parsed["actions"] = []
	var summary: String = parsed.summary
	if summary != "":
		summaries.append({"t": sim.game_min, "text": summary, "source": source})
		if summaries.size() > 20:
			summaries.pop_front()
		var who := sim.company(cid).player_name
		sim.log_event("%s%s: „%s“" % [who, " [ERSATZMODUS]" if source == "Ersatzmodus" else "", summary], "ai", cid)
		if source == "KI" and cid < sim.avatars.size():
			sim.avatars[cid].say(summary.left(110), false)   # was sich die KI ueberlegt hat, sichtbar an der Figur
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
	var bought_pending := false
	for a in actions:
		if not a is Dictionary:
			continue
		var actual: Dictionary = _ground_action(a)
		if str(actual.get("action", "")) == "set_plan" and _same_plan(actual):
			continue
		if source == "KI" and str(actual.get("action", "")) in DISPATCHER_OWNED and sim.dispatcher != null and sim.dispatcher.covers(cid):
			# Auftragsannahme und -zuweisung macht der Claude-Disponent: nicht doppelt planen (frueher die haeufigste Ablehnung)
			stats["left_to_dispatcher"] = int(stats.get("left_to_dispatcher", 0)) + 1
			api_log.write({"type": "action", "player": cid, "key": "%s:a%d" % [key_prefix, i], "source": source, "action": actual, "ok": true,
				"msg": "übergangen: Aufträge verteilt der Disponent"})
			i += 1
			continue
		if _dispatch_help_on():
			sim.executor.auto_split[cid] = true
		if bought_pending and _needs_new_vehicle(actual):
			var kept := str(actual.get("contract_id", ""))
			if kept != "" and _release_later.has(kept):
				_release_later.erase(kept)   # Auftrag bleibt vorgemerkt, bis das Fahrzeug da ist
				var hk: Contract = sim.contracts.get(kept)
				if hk != null and hk.held_for == cid:
					hk.held_until = maxf(hk.held_until, sim.game_min + AFTER_BUY_GAME_MIN)
			else:
				kept = ""
			_after_buy.append({"action": actual, "known": sim.company_vehicles(cid).map(func(v): return v.id), "until": sim.game_min + AFTER_BUY_GAME_MIN,
				"key": "%s:a%d" % [key_prefix, i], "hold": kept})
			api_log.write({"type": "action", "player": cid, "key": "%s:a%d" % [key_prefix, i], "source": source, "action": actual, "ok": true,
				"msg": "wartet auf das gekaufte Fahrzeug"})
			i += 1
			continue
		var res := sim.executor.execute(cid, actual, "p%d:%s:a%d" % [cid, key_prefix, i], origin)
		if res.ok and bool(res.get("pending", false)) and str(actual.get("action", "")) == "buy_vehicle":
			bought_pending = true
		i += 1
		if res.ok:
			stats.actions_ok += 1
			if str(actual.get("action", "")) not in PASSIVE:
				effective += 1
		elif res.get("already", false):
			stats["already_planned"] = int(stats.get("already_planned", 0)) + 1   # Besuch laeuft schon: kein Fehler, kein Wiederholungsanstoss
		else:
			stats.actions_rejected += 1
			if config.get("provider", "") == "ollama":
				_events.append("Abgelehnte Aktion %s: %s. Prüfe die gültigen IDs in verfuegbare_aktionen und ändere den nächsten Versuch." % [str(actual.get("action", "")), str(res.msg)])
		api_log.write({"type": "action", "player": cid, "key": "%s:a%d" % [key_prefix, i - 1], "source": source,
			"action": actual, "original_action": a if actual != a else {}, "ok": res.ok, "msg": res.msg})
	sim.decisions.clear_context(cid)
	_release_holds(_release_later)
	_release_later.clear()
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
	# Kleine lokale Modelle scheitern oft an Pflichtangaben: blieb die Runde wirkungslos oder steht ein Fahrzeug still, setzt die Disposition (Regeln) die
	# Fahrzeuge und Arbeiter ein, damit sie nicht untaetig herumstehen. Eigene Strategie und Investitionen bleiben beim Modell.
	if source == "KI" and _dispatch_help_on():
		var idle_vehicle: bool = sim.company_vehicles(cid).any(func(v): return v.state == "idle" and v.stops.is_empty() and v.contract_id == "")
		if effective == 0 or idle_vehicle:   # auch wenn nur "abgewartet"-Aktionen gelangen, aber Fahrzeuge herumstehen
			_run_dispatch_help()


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
				or var_to_str(steps[i].get("aktion", {})) != var_to_str(p.schritte[i].get("aktion", {})) \
				or var_to_str(steps[i].get("abhaengig_von", [])) != var_to_str(p.schritte[i].get("abhaengig_von", [])):   # Modelle schicken teils Text statt Objekt (String != Dictionary war ein Skriptfehler)
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
- BETRIEBSABLAUF: Eine Investition braucht anschliessend Fahrer, Hofkontrolle, Ware, Lager und Kundenzustellung. Delegiere wiederkehrende Fracht mit create_transport_line. Die Engine fuehrt nur diesen erteilten Dauerauftrag aus; sie kauft und finanziert keine Fahrzeuge. betriebsablauf zeigt Linien, Engpaesse und echten Betriebsfunk. Reservierte Linienfahrzeuge nicht parallel verplanen. Nutze bei unverplanter Fracht request_transport_help, beantworte Anfragen mit quote_transport_help und verhandle/bestaetige konkrete Preise. Nachrichten allein ersetzen keine Annahme.
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
		"set_operations_policy", "create_transport_line", "pause_transport_line", "request_transport_help", "quote_transport_help", "offer_trade", "accept_trade", "reject_trade", "counter_offer", "take_loan", "request_loan", "repay_loan", "repair_vehicle", "buy_supplies", "set_plan", "execute_plan_step", "wait",
		"found_business", "explore_deposit", "request_mining", "build_access"]
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
Lege fuer wiederkehrende Fracht create_transport_line fest: Disposition teilt Fahrer ein, prueft den Lkw, holt Ware, schlaegt sie bei via_depot am eigenen Hof um und stellt zu. Prüfe betriebsablauf: Fahrer, Hofplatz, Lieferketten und Engpaesse gehoeren zu jeder Investition. Reservierte Linienfahrzeuge nicht parallel verplanen. Nutze request_transport_help und quote_transport_help fuer konkrete Fracht; accept_trade bestaetigt den Preis. Routine ist keine neue KI-Entscheidung.
Du bist UNTERNEHMER, nicht nur Spedition: Transport ist der Einstieg, Gewinn entsteht mit eigenen Betrieben. Prüfe in jeder Runde chancen (Lücken der Region mit Gründungskosten) und verfuegbare_branchen. Hast du Geld über der Reserve, gründe einen fehlenden Betrieb (found_business) oder beginne Bergbau (explore_deposit -> request_mining -> build_access -> found_business bergwerk; der Rohstoff speist Stahlwerk und Bau).
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
## Postfach: die Auftraege der Beobachtung fuer diesen Spieler vormerken (nicht fuer Fremde reservierte, hoechstens HOLD_MAX).
func _hold_market(obs: Dictionary) -> void:
	_release_holds(_held)
	_held.clear()
	var cands: Array = obs.get("markt", []).filter(func(x): return bool(x.get("machbar", true))).slice(0, HOLD_MAX)
	if cands.is_empty():
		# noch kein passendes Fahrzeug (z. B. erster Zug): Modelle kaufen oft eins und nehmen im selben Zug Auftraege an -
		# die ersten Angebote trotzdem vormerken, sonst sind sie weg, bis das Fahrzeug da ist
		cands = obs.get("markt", []).slice(0, HOLD_NO_VEHICLE)
	for m in cands:
		var k: Contract = sim.contracts.get(str(m.get("id", "")))
		if k == null or k.status != "open" or k.held_by_other(cid, sim.game_min):
			continue
		k.held_for = cid
		# so lange, wie das Modell zuletzt brauchte (+50 % und eine Spielstunde), mindestens HOLD_GAME_MIN, nie ueber die Lieferfrist
		k.held_until = minf(sim.game_min + maxf(HOLD_GAME_MIN, _latency_game * 1.5 + 60.0), k.deadline - 30.0)
		_held.append(k.id)


func _release_holds(ids: Array) -> void:
	for kid in ids:
		var k: Contract = sim.contracts.get(kid) if sim != null else null
		if k != null and k.held_for == cid:
			k.held_for = -1
			k.held_until = 0.0


## Bezieht sich die Aktion auf ein Fahrzeug, das der Firma (noch) nicht gehoert? (Modell hat die Nummer des gekauften Fahrzeugs geraten)
func _needs_new_vehicle(a: Dictionary) -> bool:
	if a.get("vehicle_id") == null:
		return false
	var vid := int(a.vehicle_id) if (a.vehicle_id is int or a.vehicle_id is float or str(a.vehicle_id).is_valid_int()) else -1
	var v: FleetVehicle = sim.vehicles.get(vid)
	return v == null or (v.owner != cid and v.operator != cid)


## Steht der Kaufbesuch der Figur noch aus (unterwegs oder eingereiht)?
func _buy_visit_pending() -> bool:
	if cid >= sim.avatars.size():
		return false
	var a: Avatar = sim.avatars[cid]
	for v in [a.pending] + a.queue:
		if v is Dictionary and v.has("action") and str(v.action.get("action", "")) == "buy_vehicle":
			return true
	return false


## Gekauftes Fahrzeug ist da: zurueckgehaltene Aktionen mit dessen Nummer ausfuehren; nach Ablauf verwerfen.
func _after_buy_tick() -> void:
	if _after_buy.is_empty():
		return
	ProcTimer.sub("KI: Nachkauf", cid)
	var keep: Array = []
	for item in _after_buy:
		var fresh: Array = sim.company_vehicles(cid).filter(func(v): return not item.known.has(v.id))
		if fresh.is_empty():
			var buying := _buy_visit_pending()
			if buying and sim.game_min < float(item.until):
				keep.append(item)
			else:
				_release_holds([item.get("hold", "")])
				api_log.write({"type": "action", "player": cid, "key": str(item.key) + ":spaet", "source": "Postfach", "action": item.action, "ok": false,
					"msg": "Fahrzeugkauf ist gescheitert (Angebot weg oder Geld fehlte) – zurückgehaltene Aktion verworfen" if not buying else "gekauftes Fahrzeug kam nicht rechtzeitig – Aktion verworfen"})
			continue
		var a: Dictionary = item.action.duplicate()
		a["vehicle_id"] = int(fresh[0].id)
		var res := sim.executor.execute(cid, a, "p%d:%s:nachkauf" % [cid, str(item.key)], "api")
		_release_holds([item.get("hold", "")])
		api_log.write({"type": "action", "player": cid, "key": str(item.key) + ":nachkauf", "source": "Postfach", "action": a, "ok": res.ok, "msg": res.msg})
	_after_buy = keep


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
	_inflight_sent = real_time
	_inflight_generation = sim.company(cid).generation
	return _inflight


func abandon_for_test() -> void:
	_abandoned[_inflight] = true
	_inflight = -1
