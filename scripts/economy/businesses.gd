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
