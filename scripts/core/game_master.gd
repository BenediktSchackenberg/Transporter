class_name GameMaster
extends RefCounted
## Spielleitung ("Marktmacher"): beobachtet alle Unternehmen und steuert die Nachfrage gezielt, damit keine Firma
## dauerhaft ohne passenden Auftrag dasteht (Angleichung statt Bevorzugung) und der Markt in Bewegung bleibt.
## Die Entscheidung trifft `decide` (reine Regeln, testbar, deterministisch). Ein Sprachmodell (siehe GameMasterAgent)
## darf nur zwischen den von den Regeln gelieferten, nummerierten Kandidaten waehlen; hier gelten harte Grenzen:
## je Lauf und je Spieltag begrenzte Zahl zusaetzlicher Auftraege, nie mehr als der vorhandene Markt aufnimmt.
## Standardmaessig aus (`enabled`), damit Tests und Wiederholungen unveraendert bleiben; das Spiel schaltet sie ein.

const PERIOD_MIN := 120.0            # Spielminuten zwischen zwei Laeufen
const MAX_PER_RUN := 3
const MAX_PER_DAY := 8
const MAX_DISTANCE := 90             # Wegstrecke (Kacheln) der Zusatzauftraege
const LOG_LIMIT := 60

var sim
var enabled := false
var log: Array = []                  # [{t, summary, actions:[...], source}]
var stats := {"runs": 0, "spawned": 0, "failed": 0, "skipped": 0}
var last_run := 0.0
var _day_index := -1
var _day_count := 0
## Von aussen setzbar (GameMasterAgent): erhaelt die Kandidaten und gibt die gewaehlten Indizes zurueck; leer = Regeln entscheiden.
var chooser: Callable = Callable()


func setup(simulation) -> void:
	sim = simulation


func minute_tick(now: float) -> void:
	if not enabled or sim == null or now - last_run < PERIOD_MIN:
		return
	last_run = now
	run(now)


## Ein Lauf: beobachten, entscheiden, ausfuehren, protokollieren.
func run(now: float) -> Dictionary:
	stats.runs += 1
	var day := int(now / 1440.0)
	if day != _day_index:
		_day_index = day
		_day_count = 0
	var obs := observe(now)
	var plan := decide(obs, MAX_PER_RUN, MAX_PER_DAY - _day_count)
	var source := "Regeln"
	if chooser.is_valid() and not plan.candidates.is_empty():
		var picked: Variant = chooser.call(obs, plan.candidates)
		if picked is Array:
			plan["actions"] = plan.candidates.filter(func(c): return int(c.nr) in picked).slice(0, MAX_PER_RUN)
			source = "Claude"
	var done: Array = []
	for a in plan.actions:
		if _day_count >= MAX_PER_DAY:
			break
		var k := spawn_for(int(a.company), str(a.need), now)
		if k != null:
			_day_count += 1
			stats.spawned += 1
			done.append({"company": a.company, "need": a.need, "contract": k.id, "reason": a.reason})
		else:
			stats.failed += 1
	if plan.actions.is_empty():
		stats.skipped += 1
	log.append({"t": snappedf(now, 1.0), "summary": plan.summary, "actions": done, "source": source})
	if log.size() > LOG_LIMIT:
		log = log.slice(-LOG_LIMIT)
	return plan


## Lage jedes aktiven Unternehmens, soweit sie fuer die Nachfragesteuerung noetig ist.
func observe(now: float) -> Dictionary:
	var open: Array = sim.market.open_contracts()
	var comps: Array = []
	for c in sim.companies:
		if not c.is_active():
			continue
		var specs: Array = []
		var idle := 0
		for v in sim.company_vehicles(c.id):
			specs.append(v.spec())
			if v.state == "idle" and v.stops.is_empty() and v.contract_id == "":
				idle += 1
		var fit := 0
		for k in open:
			if k.exclusive_for >= 0 and k.exclusive_for != c.id and now < k.exclusive_until:
				continue
			if fits(k, specs, float(c.reputation)):
				fit += 1
		comps.append({"id": c.id, "name": c.company_name, "vehicles": specs.size(), "idle": idle, "open_fit": fit,
			"has_cold": specs.any(func(s): return s.refrigerated), "has_heavy": specs.any(func(s): return s.heavy),
			"max_cap": specs.map(func(s): return int(s.capacity)).max() if not specs.is_empty() else 0,
			"cash": snappedf(c.ledger.cash, 1.0), "profit": snappedf(c.ledger.profit(), 1.0)})
	return {"time": now, "open_total": open.size(), "companies": comps}


## Passt der Auftrag zu mindestens einem der Fahrzeuge (Kapazitaet, Kuehlung, Schwerlast, Ruf, Entfernung)?
static func fits(k: Contract, specs: Array, reputation: float) -> bool:
	if reputation < k.min_rep or k.distance > MAX_DISTANCE:
		return false
	for s in specs:
		if s.capacity >= k.qty and (not k.needs_cold or s.refrigerated) and (not k.needs_heavy or s.heavy):
			return true
	return false


## Regelkern. Liefert {summary, candidates:[{nr, company, need, reason}], actions:[...]}.
## Wer Leerlauf hat und zu wenig passende offene Auftraege sieht, bekommt welche; ueberversorgte Firmen und
## der Marktfuehrer (hoechster Gewinn) nicht. Kandidaten sind absteigend nach Dringlichkeit nummeriert.
static func decide(obs: Dictionary, max_run: int, max_day_left: int) -> Dictionary:
	var comps: Array = obs.companies
	var cands: Array = []
	if comps.is_empty() or max_day_left <= 0:
		return {"summary": "Keine zusätzliche Nachfrage nötig.", "candidates": [], "actions": []}
	var leader := -1
	var best := -INF
	for c in comps:
		if float(c.profit) > best:
			best = float(c.profit)
			leader = int(c.id)
	var needy: Array = []
	for c in comps:
		var gap := int(c.idle) - int(c.open_fit)
		if gap <= 0 or int(c.vehicles) == 0:
			continue
		if int(c.id) == leader and comps.size() > 2 and float(c.profit) > 0.0:
			continue     # der Marktfuehrer wird nicht zusaetzlich bedient
		needy.append({"c": c, "gap": gap, "urgency": gap * 10.0 - float(c.profit) / 1000.0})
	needy.sort_custom(func(a, b): return a.urgency > b.urgency)
	var nr := 1
	for n in needy:
		var c: Dictionary = n.c
		var need := "kuehl" if c.has_cold and not c.has_heavy and int(c.idle) >= 1 and int(n.gap) >= 2 else ("schwer" if c.has_heavy and int(n.gap) >= 2 else "passend")
		for i in mini(int(n.gap), 2):
			cands.append({"nr": nr, "company": int(c.id), "need": need,
				"reason": "%s: %d Fahrzeug(e) im Leerlauf, nur %d passende offene Aufträge" % [c.name, int(c.idle), int(c.open_fit)]})
			nr += 1
	var actions: Array = cands.slice(0, mini(max_run, max_day_left))
	var summary := "Keine zusätzliche Nachfrage nötig." if actions.is_empty() else "Zusatzaufträge für %s." % ", ".join(actions.map(func(a): return "F%d" % int(a.company)))
	return {"summary": summary, "candidates": cands, "actions": actions}


## Erzeugt einen Auftrag, den ein Fahrzeug der Firma tragen kann; null, wenn keiner gefunden wurde.
func spawn_for(cid: int, need: String, now: float) -> Contract:
	var c = sim.company(cid)
	if c == null:
		return null
	var specs: Array = sim.company_vehicles(cid).map(func(v): return v.spec())
	for attempt in 30:
		var k: Contract = sim.market.spawn(now)
		if k == null:
			continue
		var ok := fits(k, specs, float(c.reputation))
		if ok and need == "kuehl":
			ok = k.needs_cold
		elif ok and need == "schwer":
			ok = k.needs_heavy
		if ok:
			return k
		sim.contracts.erase(k.id)    # unpassender Versuch: wieder entfernen
	return null


func to_dict() -> Dictionary:
	return {"enabled": enabled, "log": log.slice(-LOG_LIMIT), "stats": stats.duplicate(), "last_run": last_run, "day": _day_index, "day_count": _day_count}


func from_dict(d: Dictionary) -> void:
	if d.is_empty():
		return
	enabled = bool(d.get("enabled", false))
	log = d.get("log", [])
	stats = d.get("stats", stats)
	last_run = float(d.get("last_run", 0.0))
	_day_index = int(d.get("day", -1))
	_day_count = int(d.get("day_count", 0))
