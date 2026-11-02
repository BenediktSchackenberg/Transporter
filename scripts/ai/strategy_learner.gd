class_name StrategyLearner
extends RefCounted
## Waehlt je Unternehmen eine Strategie (config/strategies.json) fuer einen Bewertungszeitraum, misst den wirtschaftlichen Erfolg
## (StrategyEvaluator) und waehlt danach meist die bisher beste, gelegentlich (EXPLORE) eine andere Strategie (Epsilon-Greedy-Bandit).
## Der Lerner aendert nur Parameter der Regel-KI (RuleBrain.decide); Sicherheitsregeln des ActionExecutor bleiben unberuehrt.
## Zeitraum: PERIOD_DAYS Spieltage, verlaengert bis MIN_CONTRACTS Auftraege vorliegen, hoechstens MAX_DAYS (dann Vertrauen "unsicher").

const CONFIG_PATH := "res://config/strategies.json"
const EXPLORE := 0.15
const PERIOD_DAYS := 5
const MAX_DAYS := 7
const MIN_UTIL_SAMPLES := 24      # so viele Fahrzeugstichproben, bevor die gemessene Auslastung Kaeufe sperren darf
const MIN_MODEL_DAYS := 3         # fruehestens nach so vielen Tagen darf ein Modell die Strategie wechseln
const START_BY_PERSONALITY := {"kostenoptimierer": "effizient", "wachstum": "wachstum", "netzwerker": "konservativ", "risikospieler": "wachstum"}
const FALLBACK := {
	"konservativ": {"cash_reserve_factor": 2.0, "min_expected_margin_ratio": 0.25, "fleet_purchase_utilization_min": 0.85},
	"wachstum": {"cash_reserve_factor": 1.5, "min_expected_margin_ratio": 0.0, "fleet_purchase_utilization_min": 0.0},
	"effizient": {"cash_reserve_factor": 1.8, "min_expected_margin_ratio": 0.22, "fleet_purchase_utilization_min": 0.90},
}

static var _profiles_cache := {}

var sim: Simulation
var enabled := true
var memory := StrategyMemory.new()
var state := {}                   # cid -> {current, start, acc, switched_day, locked, reason}
var rng := RandomNumberGenerator.new()


static func profiles() -> Dictionary:
	if _profiles_cache.is_empty():
		_profiles_cache = FALLBACK.duplicate(true)
		if FileAccess.file_exists(CONFIG_PATH):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
			if parsed is Dictionary and not parsed.is_empty():
				_profiles_cache = parsed
	return _profiles_cache


func setup(s: Simulation) -> void:
	sim = s
	rng.seed = int(s.rng.seed) + 7919
	for c in s.companies:
		_init_company(c)
	s.day_changed.connect(on_day)


func _init_company(c: Company) -> void:
	var id: String = START_BY_PERSONALITY.get(c.personality, "wachstum")
	if not profiles().has(id):
		id = str(profiles().keys()[0])
	state[c.id] = {"current": id, "start": StrategyEvaluator.snapshot(sim, c.id), "acc": {}, "switched_day": 0, "locked": false, "reason": ""}


## Feste Strategie (kein Lernen), z. B. fuer Vergleichspartien in der Arena.
func fix(cid: int, strategy_id: String) -> void:
	if profiles().has(strategy_id) and state.has(cid):
		state[cid].current = strategy_id
		state[cid].locked = true


func params_of(cid: int) -> Dictionary:
	if not enabled or not state.has(cid):
		return {}
	var p: Dictionary = profiles().get(state[cid].current, {}).duplicate()
	p["id"] = state[cid].current
	var acc: Dictionary = state[cid].acc
	if int(acc.get("vehicle_samples", 0)) >= MIN_UTIL_SAMPLES:
		p["utilization_now"] = float(acc.get("busy", 0)) / float(acc.vehicle_samples)
	return p


## Stuendliche Stichprobe fuer die Auslastung (von Simulation aufgerufen).
func sample() -> void:
	for cid in state:
		StrategyEvaluator.sample(sim, cid, state[cid].acc)


func on_day(day: int) -> void:
	if not enabled:
		return
	for cid in state:
		var st: Dictionary = state[cid]
		var c: Company = sim.company(cid)
		var days := day - int(st.start.day)
		if days < PERIOD_DAYS or not Standings.solvent(c):
			continue
		var done := int(c.stats.completed) - int(st.start.completed)
		if done >= StrategyMemory.MIN_CONTRACTS or days >= MAX_DAYS:
			_finish(cid, day, "", "")


## Zeitraum abschliessen, bewerten, speichern und die naechste Strategie waehlen (forced = vom Modell gewaehlt).
func _finish(cid: int, day: int, forced: String, reason: String) -> void:
	var st: Dictionary = state[cid]
	var rec := StrategyEvaluator.evaluate(sim, cid, st.current, st.start, st.acc)
	memory.add(cid, rec)
	var next: String = forced
	if next == "":
		next = st.current if st.locked else _choose(cid)
	if next != st.current:
		sim.log_event("%s wechselt die Strategie: %s -> %s (%s)." % [sim.company(cid).company_name, label_of(st.current), label_of(next), reason if reason != "" else "Bewertung der letzten %d Tage" % rec.days], "info", cid)
		st.switched_day = day
	st.reason = reason if reason != "" else _finding(cid, rec, next)
	st.current = next
	st.start = StrategyEvaluator.snapshot(sim, cid)
	st.acc = {}


## Strategie fuer den naechsten Zeitraum: zuerst jede einmal erproben, dann meist die beste, mit EXPLORE-Wahrscheinlichkeit eine andere.
func _choose(cid: int) -> String:
	var ids: Array = profiles().keys()
	for id in ids:
		if int(memory.aggregate(cid, id).zeitraeume) == 0:
			return id
	var best: String = ids[0]
	for id in ids:
		if float(memory.aggregate(cid, id).mittelwert) > float(memory.aggregate(cid, best).mittelwert):
			best = id
	if rng.randf() < EXPLORE:
		var others: Array = ids.filter(func(i): return i != best)
		return others[rng.randi() % others.size()]
	return best


func label_of(id: String) -> String:
	return str(profiles().get(id, {}).get("label", id))


## Erkenntnis aus Messwerten (keine erfundenen Gedanken): was der letzte Zeitraum ergab und wie es weitergeht.
func _finding(cid: int, rec: Dictionary, next: String) -> String:
	var agg: Dictionary = memory.aggregate(cid, rec.strategy)
	return "%s: %s je Spieltag bei %d Aufträgen, Auslastung %d %%, Leerfahrten %d %% (%s). Nächster Zeitraum: %s." % [label_of(rec.strategy),
		Catalog.money(float(rec.profit_per_day)), int(rec.contracts), int(float(rec.utilization) * 100.0), int(float(rec.empty_share) * 100.0), agg.vertrauen, label_of(next)]


## Wechsel durch ein Sprachmodell: nur eigene Firma, bekannte Strategie, frueestens nach MIN_MODEL_DAYS. Der laufende Zeitraum wird dabei bewertet.
func set_by_model(cid: int, id: String, reason: String) -> Dictionary:
	if not state.has(cid):
		return {"ok": false, "msg": "Unbekanntes Unternehmen."}
	if not profiles().has(id):
		return {"ok": false, "msg": "Unbekannte Strategie %s (möglich: %s)." % [id, ", ".join(profiles().keys())]}
	var st: Dictionary = state[cid]
	if id == st.current:
		return {"ok": false, "msg": "Die Strategie %s läuft bereits." % id}
	var day := GameCalendar.day_of(sim.game_min)
	if day - int(st.start.day) < MIN_MODEL_DAYS:
		return {"ok": false, "msg": "Die aktuelle Strategie läuft erst %d Tage; Bewertung frühestens nach %d." % [day - int(st.start.day), MIN_MODEL_DAYS]}
	st.locked = false
	_finish(cid, day, id, reason.left(200))
	memory.add_note(cid, day, reason)
	return {"ok": true, "msg": "Strategie auf %s gewechselt." % label_of(id)}


## Lernbericht fuer Beobachtung und Oberflaeche.
func summary_of(cid: int) -> Dictionary:
	if not state.has(cid):
		return {}
	var st: Dictionary = state[cid]
	var day := GameCalendar.day_of(sim.game_min)
	var ratings := {}
	var evaluated := 0
	for id in profiles():
		var a: Dictionary = memory.aggregate(cid, id)
		ratings[id] = {"zeitraeume": a.zeitraeume, "gewinn_je_tag": a.mittelwert, "auftraege": a.auftraege, "vertrauen": a.vertrauen}
		evaluated += 1 if int(a.zeitraeume) > 0 else 0
	return {"aktuell": st.current, "bezeichnung": label_of(st.current), "parameter": params_of(cid), "tage_im_zeitraum": day - int(st.start.day),
		"bewertet": evaluated, "bewertungen": ratings, "letzter_wechsel_tag": int(st.switched_day), "letzte_erkenntnis": str(st.reason),
		"zeitraeume_gesamt": memory.records.get(cid, []).size(), "vermutungen": memory.notes.get(cid, []).slice(-3),
		"regeln": "Messwerte stammen aus der Engine. Wechsel mit der Aktion set_strategy (frühestens nach %d Tagen). Sicherheitsregeln bleiben unverändert." % MIN_MODEL_DAYS}


func to_dict() -> Dictionary:
	var st := {}
	for cid in state:
		st[str(cid)] = state[cid]
	return {"enabled": enabled, "memory": memory.to_dict(), "state": st, "rng_state": str(rng.state)}


func from_dict(d: Dictionary) -> void:
	if d.is_empty():
		return
	enabled = bool(d.get("enabled", true))
	memory.from_dict(d.get("memory", {}))
	for k in d.get("state", {}):
		if state.has(int(k)):
			state[int(k)] = d.state[k]
	if d.has("rng_state"):
		rng.state = int(d.rng_state)
