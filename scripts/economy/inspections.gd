class_name Inspections
extends RefCounted
## Gezielte Pruefungen durch den Pruefdienst des Rathauses (Auftrag 9, Etappe 2, docs/TOWN_HALL.md). Der Buergermeister ordnet sie an
## (`order_inspection`); die monatliche Zufallspruefung der Ertragsteuer (`PublicSector`) bleibt als Grundrauschen.
## Grenzen: Kapazitaet des Pruefdienstes je Monat, Sperrfrist je Firma, Bussgeld hoechstens das Bargeld. Ein Fehlverdacht (Pruefung
## ohne Befund) kostet Zustimmung. Jede Pruefung steht im Ereignisprotokoll (fuer die betroffene Firma sichtbar) und auf der Karte.

const KINDS := {
	"lohnsteuer": "Steuern und Löhne: offene Ertragsteuer und nicht gezahlte Löhne",
	"arbeitssicherheit": "Arbeitssicherheit: erschöpfte oder kranke Beschäftigte im Einsatz",
	"fahrzeuge": "Fahrzeuge: Verkehrssicherheit (Zustand unter 40 %)",
}
const PER_INSPECTOR := 2                 # Pruefungen je Pruefer und Monat
const BLOCK_DAYS := 10                   # Sperrfrist je Firma (Spieltage)
const FINE_WORKER := 300.0               # je erschoepftem (Ermuedung >= 90) oder krankem (Gesundheit < 50) Beschaeftigten
const FINE_VEHICLE := 400.0              # je Fahrzeug mit Zustand unter VEHICLE_MIN
const FINE_WAGES := 0.10                 # Zuschlag auf nicht gezahlte Loehne
const VEHICLE_MIN := 40.0
const FALSE_SUSPICION := 1.5             # Zustimmungsverlust bei Pruefung ohne Befund

var sim
var records: Array = []                  # {day, month, cid, kind, findings: [...], fine, conditions: [...]}
var used := {}                           # Monat -> Zahl der angeordneten Pruefungen


func setup(simulation) -> void:
	sim = simulation


func _today() -> int:
	return GameCalendar.day_of(sim.game_min)


func _month() -> int:
	return _today() / 30


func capacity() -> int:
	return maxi(1, sim.town_hall.staff("pruefdienst") * PER_INSPECTOR)


func remaining() -> int:
	return maxi(0, capacity() - int(used.get(_month(), 0)))


func last_day(cid: int) -> int:
	for i in range(records.size() - 1, -1, -1):
		if int(records[i].cid) == cid:
			return int(records[i].day)
	return -100000


## Anordnung durch den Buergermeister. Gibt {ok, msg, befund} zurueck.
func order(cid: int, kind: String, by: String = "") -> Dictionary:
	var c: Company = sim.company(cid)
	if c == null:
		return {"ok": false, "msg": "Unbekannte Firma %d." % cid}
	if not KINDS.has(kind):
		return {"ok": false, "msg": "Unbekannte Prüfart '%s' (%s)." % [kind, ", ".join(KINDS.keys())]}
	if remaining() <= 0:
		return {"ok": false, "msg": "Der Prüfdienst ist diesen Monat ausgelastet (%d Prüfungen; mehr Prüfer über hire_staff pruefdienst)." % capacity()}
	var since := _today() - last_day(cid)
	if since < BLOCK_DAYS:
		return {"ok": false, "msg": "%s wurde vor %d Tagen geprüft; Sperrfrist %d Tage." % [c.company_name, since, BLOCK_DAYS]}
	used[_month()] = int(used.get(_month(), 0)) + 1
	var rec := _inspect(c, kind)
	var txt := "Prüfung (%s) bei %s: %s" % [kind, c.company_name, ("Befund: " + "; ".join(rec.findings) + ", Bußgeld " + Catalog.money(float(rec.fine))) if not rec.findings.is_empty() else "ohne Beanstandung"]
	if rec.findings.is_empty():
		sim.mayor.approval = maxf(0.0, sim.mayor.approval - FALSE_SUSPICION)
		txt += " – Fehlverdacht kostet Zustimmung"
	sim.log_event(txt, "warn" if not rec.findings.is_empty() else "info", cid)
	sim.activity.add("buergermeister", cid, "stadt", "Prüfdienst bei %s (%s)" % [c.company_name, kind], by, sim.depot_road(cid))
	return {"ok": true, "msg": txt, "befund": rec}


func _inspect(c: Company, kind: String) -> Dictionary:
	var findings: Array = []
	var conditions: Array = []
	var fine := 0.0
	match kind:
		"lohnsteuer":
			var audit: Dictionary = sim.public_sector.audit(c, _month())   # Ertragsteuer nachfordern, Zuschlag bucht PublicSector
			if float(audit.arrears) > 0.01:
				findings.append("Ertragsteuer offen %s (nachgefordert)" % Catalog.money(float(audit.arrears)))
				fine += float(audit.fine)
			if c.ledger.payables > 1.0:
				findings.append("Löhne nicht gezahlt %s" % Catalog.money(c.ledger.payables))
				conditions.append("Lohnrückstand begleichen")
				fine += _fine(c, c.ledger.payables * FINE_WAGES, "Prüfung: Lohnrückstand")
		"arbeitssicherheit":
			var bad: Array = sim.personnel.employed(c.id).filter(func(w): return w.fatigue >= 90.0 or w.health < 50.0)
			if not bad.is_empty():
				findings.append("%d Beschäftigte erschöpft oder krank im Einsatz (%s)" % [bad.size(), ", ".join(bad.slice(0, 3).map(func(w): return w.name))])
				conditions.append("Ruhezeiten einhalten, Kranke freistellen")
				fine += _fine(c, FINE_WORKER * bad.size(), "Prüfung: Arbeitssicherheit")
		"fahrzeuge":
			var bad_v: Array = []
			for vid in c.vehicle_ids:
				var v = sim.vehicles.get(vid)
				if v != null and v.condition < VEHICLE_MIN:
					bad_v.append(v)
			if not bad_v.is_empty():
				findings.append("%d Fahrzeuge nicht verkehrssicher (%s)" % [bad_v.size(), ", ".join(bad_v.slice(0, 3).map(func(v): return "#%d %.0f %%" % [v.id, v.condition]))])
				conditions.append("Fahrzeuge instand setzen (repair_vehicle)")
				fine += _fine(c, FINE_VEHICLE * bad_v.size(), "Prüfung: Fahrzeugsicherheit")
	var rec := {"day": _today(), "month": _month(), "cid": c.id, "kind": kind, "findings": findings, "fine": snappedf(fine, 0.01), "conditions": conditions}
	records.append(rec)
	if records.size() > 60:
		records.pop_front()
	return rec


## Bussgeld hoechstens bis zum Bargeld (an die Stadtkasse ueber die Buchungskategorie fines).
func _fine(c: Company, amount: float, note: String) -> float:
	var pay := minf(amount, maxf(0.0, c.ledger.cash))
	if pay > 0.01:
		c.ledger.book("fines", -pay, true, note, sim.game_min)
	return pay


## Beobachtung fuer den Buergermeister: Kapazitaet, Sperrfristen und oeffentlich sichtbare Auffaelligkeiten je Firma
## (Zustand der Fahrzeuge auf der Strasse, erschoepfte Beschaeftigte, Pannen) – keine Akteneinsicht vor der Pruefung.
func summary() -> Dictionary:
	var firms: Array = []
	for c in sim.companies:
		var cond := 0.0
		var nv := 0
		for vid in c.vehicle_ids:
			var v = sim.vehicles.get(vid)
			if v != null:
				cond += v.condition
				nv += 1
		var tired: int = sim.personnel.employed(c.id).filter(func(w): return w.fatigue >= 90.0).size()
		var since := _today() - last_day(c.id)
		firms.append({"firma": c.id, "name": c.company_name, "fahrzeugzustand_mittel": snappedf(cond / maxf(1.0, nv), 1.0), "erschoepfte_beschaeftigte": tired,
			"tage_seit_pruefung": since if since < 100000 else -1, "gesperrt": since < BLOCK_DAYS})
	return {"kapazitaet_monat": capacity(), "frei_diesen_monat": remaining(), "sperrfrist_tage": BLOCK_DAYS, "arten": KINDS, "firmen": firms,
		"letzte": records.slice(-5).map(func(r): return {"tag": r.day, "firma": r.cid, "art": r.kind, "befunde": r.findings.size(), "bussgeld": r.fine})}


func to_dict() -> Dictionary:
	return {"records": records.duplicate(true), "used": used.duplicate()}


func from_dict(d: Dictionary) -> void:
	records = d.get("records", [])
	for r in records:
		r.day = int(r.day)
		r.cid = int(r.cid)
		r.month = int(r.month)
	used = {}
	for k in d.get("used", {}):
		used[int(k)] = int(d.used[k])
