class_name Businesses
extends RefCounted
## Betriebe der Unternehmer (Auftrag 14, docs/ENTREPRENEURS.md, Abschnitt 3). Die Company bleibt rechtliche und finanzielle
## Klammer; ein Betrieb ist eine wirtschaftliche Einheit an einem Standort (Transportbetrieb, spaeter Feld, Muehle, Baeckerei ...).
## Geld bucht weiterhin nur das Ledger der Company; der Betrieb ist dort eine Kostenstelle (Ledger.book(..., cc)). Ergebnisse je
## Betrieb sind deshalb Auswertungen derselben Buchungen und koennen nie doppelt zaehlen.
## Branchen kommen aus config/branches.json (eine Branche erscheint dort erst, wenn sie im Spiel funktioniert).

const CONFIG_PATH := "res://config/branches.json"
const STATES := ["geplant", "genehmigt", "im_bau", "eingerichtet", "betriebsbereit", "aktiv", "blockiert", "geschlossen", "verwertung"]
const RUNNING := ["betriebsbereit", "aktiv", "blockiert"]
const MAX_DECISIONS := 8

static var _cfg := {}

var sim
var items := {}          # "B<n>" -> Betrieb
var _next := 1


static func branches() -> Dictionary:
	if _cfg.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH)) if FileAccess.file_exists(CONFIG_PATH) else null
		var d: Dictionary = parsed if parsed is Dictionary else {}
		for k in d:
			if not str(k).begins_with("_"):
				_cfg[k] = d[k]
	return _cfg


func setup(simulation) -> void:
	sim = simulation


## Neuen Betrieb anlegen (Pruefung von Branche, Eigentum und Standort beim Aufrufer bzw. in found()).
func create(owner: int, branch: String, site: int, name: String = "", status: String = "aktiv") -> Dictionary:
	var spec: Dictionary = branches().get(branch, {})
	var id := "B%d" % _next
	_next += 1
	var b := {"id": id, "owner": owner, "branch": branch, "name": name if name != "" else "%s %s" % [spec.get("label", branch), sim.company(owner).company_name],
		"site": site, "status": status, "since": sim.game_min, "energy_kw": float(spec.get("strom_kw", 0.0)),
		"blockers": [], "decisions": [], "founded": sim.game_min}
	items[id] = b
	return b


func get_b(id: String) -> Dictionary:
	return items.get(id, {})


func of(cid: int, include_closed: bool = false) -> Array:
	return items.values().filter(func(b): return int(b.owner) == cid and (include_closed or b.status not in ["geschlossen"]))


## Erster laufender Betrieb einer Branche (z. B. der Transportbetrieb, dem Fahrzeuge und Fahrer zugeordnet sind).
func find(cid: int, branch: String) -> Dictionary:
	for b in of(cid):
		if b.branch == branch and b.status in RUNNING:
			return b
	return {}


func has_branch(cid: int, branch: String) -> bool:
	return not find(cid, branch).is_empty()


## Personal eines Betriebs: ausdruecklich zugeordnete Arbeiter; Arbeiter ohne Zuordnung gehoeren zum Standardbetrieb (Ledger.cost_center).
func staff_of(id: String) -> Array:
	var b := get_b(id)
	if b.is_empty():
		return []
	var default_id: String = sim.company(int(b.owner)).ledger.cost_center
	return sim.personnel.employed(int(b.owner)).filter(func(w): return w.business == id or (w.business == "" and id == default_id))


func set_status(id: String, status: String, reason: String = "") -> void:
	var b := get_b(id)
	if b.is_empty() or b.status == status:
		return
	b.status = status
	b.since = sim.game_min
	if reason != "":
		note(id, reason, "Betrieb")


## Blockadegrund setzen bzw. aufheben (konkreter Text, z. B. "Kein Strom: Netz ausgelastet").
func block(id: String, key: String, text: String) -> void:
	var b := get_b(id)
	if b.is_empty():
		return
	var blk: Array = b.blockers
	if not blk.any(func(x): return x.key == key):
		blk.append({"key": key, "text": text, "since": sim.game_min})
	if b.status == "aktiv":
		set_status(id, "blockiert", text)


func unblock(id: String, key: String) -> void:
	var b := get_b(id)
	if b.is_empty():
		return
	b.blockers = b.blockers.filter(func(x): return x.key != key)
	if b.blockers.is_empty() and b.status == "blockiert":
		set_status(id, "aktiv", "Blockade aufgehoben")


## Entscheidung bzw. Rueckmeldung mit Herkunft (KI, Regeln, Betrieb) fuer die Betriebsansicht.
func note(id: String, text: String, source: String) -> void:
	var b := get_b(id)
	if b.is_empty():
		return
	var d: Array = b.decisions
	d.append({"t": sim.game_min, "text": text.left(160), "source": source})
	if d.size() > MAX_DECISIONS:
		d.pop_front()


## Uebersicht fuer Oberflaeche und KI-Beobachtung: Ergebnis aus den Kostenstellen des Ledgers.
func summary_of(cid: int) -> Array:
	var L: Ledger = sim.company(cid).ledger
	var out: Array = []
	for b in of(cid, true):
		var rev := L.cc_revenue(b.id)
		var res := L.cc_profit(b.id)
		out.append({"id": b.id, "branche": b.branch, "name": b.name, "status": b.status, "standort": int(b.site),
			"personal": staff_of(b.id).size(), "umsatz": int(rev), "kosten": int(rev - res), "ergebnis": int(res),
			"strom_kw": float(b.energy_kw), "blockaden": b.blockers.map(func(x): return x.text),
			"letzte_entscheidung": b.decisions.back() if not b.decisions.is_empty() else {}})
	return out


## Transportbetrieb der Company; existiert keiner (Unternehmerstart), wird er am Hauptsitz eroeffnet (z. B. beim ersten Fahrzeugkauf).
## Ist noch keine Standard-Kostenstelle gesetzt, wird er es (dann gehoert das Personal ohne Zuordnung zu ihm).
func ensure_transport(cid: int, source: String) -> Dictionary:
	var b := find(cid, "transport")
	if not b.is_empty():
		return b
	var c = sim.company(cid)
	b = create(cid, "transport", int(c.depots[0]) if not c.depots.is_empty() else -1, "", "aktiv")
	if c.ledger.cost_center == "":
		c.ledger.cost_center = b.id
	note(b.id, "Transportbetrieb eröffnet (erstes Fahrzeug)", source)
	sim.log_event("%s eröffnet einen Transportbetrieb." % c.company_name, "info", cid)
	return b


## KI-Aktion found_business: Branche muss konfiguriert sein; Standort = Hauptsitz; Gruendungskosten als Investition (Buchwert) bzw.
## Verwaltungsaufwand. Transport: hoechstens ein Transportbetrieb je Unternehmer.
func found(cid: int, branch: String, reason: String) -> Dictionary:
	var spec: Dictionary = branches().get(branch, {})
	if spec.is_empty():
		return {"ok": false, "msg": "Unbekannte Branche '%s'. Verfügbar: %s" % [branch, ", ".join(branches().keys())]}
	var c = sim.company(cid)
	if c.depots.is_empty():
		return {"ok": false, "msg": "Kein Hauptsitz vorhanden."}
	if branch == "transport" and has_branch(cid, "transport"):
		return {"ok": false, "msg": "Es gibt bereits einen Transportbetrieb (%s)." % find(cid, "transport").id}
	var cost := float(spec.get("gruendungskosten", 0.0))
	if c.ledger.cash < cost:
		return {"ok": false, "msg": "Nicht genug Bargeld für die Gründung (%s)." % Catalog.money(cost)}
	if cost > 0.0:
		c.ledger.book("admin", -cost, true, "Gründung %s" % spec.label, sim.game_min)
	var b := create(cid, branch, int(c.depots[0]), "", "aktiv")
	if c.ledger.cost_center == "":
		c.ledger.cost_center = b.id
	note(b.id, "Gegründet: %s" % (reason if reason != "" else spec.label), "Unternehmer")
	sim.log_event("%s gründet %s." % [c.company_name, b.name], "info", cid)
	return {"ok": true, "msg": "%s gegründet (%s)." % [b.name, b.id], "ref": b.id}


func close(cid: int, id: String, reason: String) -> Dictionary:
	var b := get_b(id)
	if b.is_empty() or int(b.owner) != cid:
		return {"ok": false, "msg": "Betrieb %s gehört dir nicht." % id}
	if b.status in ["geschlossen", "verwertung"]:
		return {"ok": false, "msg": "Betrieb %s ist bereits %s." % [id, b.status]}
	var c = sim.company(cid)
	if b.branch == "transport":
		if not c.vehicle_ids.is_empty():
			return {"ok": false, "msg": "Erst alle Fahrzeuge verkaufen (noch %d)." % c.vehicle_ids.size()}
		if sim.contracts.values().any(func(k): return k.owner == cid and k.status in ["accepted", "assigned", "loading", "in_transit"]):
			return {"ok": false, "msg": "Es laufen noch Transportaufträge."}
	for w in staff_of(id):
		w.business = ""
	set_status(id, "geschlossen", reason if reason != "" else "Geschlossen")
	if c.ledger.cost_center == id:
		c.ledger.cost_center = ""
	sim.log_event("%s schließt %s." % [c.company_name, b.name], "warn", cid)
	return {"ok": true, "msg": "%s geschlossen." % b.name}


func assign(cid: int, worker_id: String, id: String) -> Dictionary:
	var b := get_b(id)
	if b.is_empty() or int(b.owner) != cid or b.status not in RUNNING:
		return {"ok": false, "msg": "Betrieb %s ist kein laufender eigener Betrieb." % id}
	var w = sim.personnel.workers.get(worker_id)
	if w == null or int(w.employer) != cid:
		return {"ok": false, "msg": "Mitarbeiter %s ist nicht bei dir angestellt." % worker_id}
	w.business = id
	return {"ok": true, "msg": "%s arbeitet jetzt für %s." % [w.name, b.name]}


## Knappe Betriebsliste fuer die KI-Beobachtung (Tokenbudget); Blockaden nur, wenn vorhanden.
func obs_of(cid: int) -> Array:
	var L: Ledger = sim.company(cid).ledger
	var out: Array = []
	for b in of(cid):
		var e := {"id": b.id, "branche": b.branch, "status": b.status, "personal": staff_of(b.id).size(), "ergebnis": int(L.cc_profit(b.id))}
		if not b.blockers.is_empty():
			e["blockaden"] = b.blockers.map(func(x): return x.text)
		out.append(e)
	return out


## Fuer die KI-Beobachtung: Branchen, die gegruendet werden koennen.
static func available() -> Array:
	var out: Array = []
	for k in branches():
		var s: Dictionary = branches()[k]
		out.append({"branche": k, "name": s.get("label", k), "gruendungskosten": float(s.get("gruendungskosten", 0.0)),
			"strom_kw": float(s.get("strom_kw", 0.0))})
	return out


## Alter Spielstand bzw. Speditionsstart: jede Company ohne Betrieb bekommt ihren bisherigen Transportbetrieb (Hof, Fahrzeuge,
## Personal, Auftraege bleiben unveraendert). Bisherige Summen der Kostenstelle "allgemein" gehoeren zu diesem Betrieb.
func migrate() -> int:
	var n := 0
	for c in sim.companies:
		if not of(c.id).is_empty() or c.depots.is_empty():   # geschlossene Betriebe eines Vorgaengers zaehlen nicht
			continue
		var b := create(c.id, "transport", int(c.depots[0]), "", "aktiv")
		var L: Ledger = c.ledger
		L.cost_center = b.id
		if L.cc_totals.has(Ledger.GENERAL):
			L.cc_totals[b.id] = L.cc_totals[Ledger.GENERAL]
			L.cc_totals.erase(Ledger.GENERAL)
		note(b.id, "Übernommen aus dem bisherigen Speditionsbetrieb", "Migration")
		n += 1
	return n


func to_dict() -> Dictionary:
	return {"items": items, "next": _next}


func from_dict(d: Dictionary) -> void:
	items = d.get("items", {})
	for b in items.values():
		b.owner = int(b.owner)
		b.site = int(b.site)
	_next = int(d.get("next", 1))
