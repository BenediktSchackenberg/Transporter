class_name TownHall
extends RefCounted
## Rathaus mit Personal (Auftrag 9, Etappe 1, siehe docs/TOWN_HALL.md). Das Personal sind Buerger mit Arbeitgeber "rathaus"
## (Lohn aus der Stadtkasse ueber Citizens). Der Buergermeister legt je Abteilung den Soll-Bestand fest; besetzt und entlassen
## wird zum Monatsende ueber den normalen Arbeitsmarkt. Die Zuordnung der Personen zu Abteilungen ist deterministisch
## (Buerger-ID, anteilig auf den tatsaechlichen Bestand), damit Speichern, Laden und Wiederholung exakt bleiben.

const DEPTS := {
	"verwaltung": {"label": "Verwaltung", "share": 0.45, "aufgabe": "Bauanträge und allgemeine Verwaltung"},
	"bauamt": {"label": "Bauamt", "share": 0.20, "aufgabe": "Bauanträge und Baugenehmigungen"},
	"strassen": {"label": "Straßenmeisterei", "share": 0.25, "aufgabe": "Straßenwartung (Etappe 4)"},
	"pruefdienst": {"label": "Prüfdienst", "share": 0.10, "aufgabe": "Prüfungen bei Firmen (Etappe 2)"},
}
const MAX_PER_ACTION := 5
const MIN_PER_DEPT := 1
const MAX_TOTAL := 120
const RESERVE_MONTHS := 6.0              # so viele Monatsgehaelter der neuen Kraefte muss die verfuegbare Stadtkasse decken
const PERMIT_DIVISOR := 5.2              # (Verwaltung + Bauamt) / 5,2 = Bearbeitungspunkte je Tag; entspricht bei Startverteilung dem frueheren "Beschaeftigte / 8"
const DEFAULT_WAGE := 15.0

var sim
var building := -1                       # Gebaeude-ID des Rathauses (-1 = kein Gebaeude)
var target := {}                         # Abteilung -> Soll-Bestand
var stats := {"hired": 0, "dismissed": 0, "refused": 0}


func setup(simulation) -> void:
	sim = simulation
	building = -1
	for b in sim.city.buildings:
		if b.role == "town_hall":
			building = int(b.id)
			break


## Startverteilung aus dem Grundbedarf des Arbeitgebers "rathaus" (groesster Rest, mindestens eine Kraft je Abteilung).
func ensure_targets() -> void:
	if not target.is_empty() or not sim.citizens.base_cap.has("rathaus"):
		return
	var total := maxi(int(sim.citizens.base_cap.rathaus), DEPTS.size() * MIN_PER_DEPT)
	target = _split(total, {})


func total_target() -> int:
	ensure_targets()
	var n := 0
	for d in target:
		n += int(target[d])
	return n


## Verteilt n Personen nach groesstem Rest auf die Abteilungen; weights leer = Anteile aus DEPTS, sonst Soll-Bestaende.
func _split(n: int, weights: Dictionary) -> Dictionary:
	var w := {}
	var sum := 0.0
	for d in DEPTS:
		w[d] = float(weights.get(d, DEPTS[d].share)) if not weights.is_empty() else float(DEPTS[d].share)
		sum += w[d]
	var out := {}
	var rest: Array = []
	var given := 0
	for d in DEPTS:
		var exact: float = float(n) * w[d] / maxf(0.0001, sum)
		out[d] = int(floor(exact))
		given += out[d]
		rest.append([exact - floor(exact), d])
	rest.sort_custom(func(a, b): return a[0] > b[0])
	var i := 0
	while given < n and not rest.is_empty():
		out[rest[i % rest.size()][1]] += 1
		given += 1
		i += 1
	return out


## Belegschaft: Buerger mit Arbeitgeber rathaus, nach ID sortiert, anteilig den Abteilungen zugeordnet.
func roster() -> Array:
	ensure_targets()
	var people: Array = sim.citizens.people.filter(func(p): return p.employer == "rathaus")
	people.sort_custom(func(a, b): return int(a.id) < int(b.id))
	var counts := _split(people.size(), target)
	var out: Array = []
	var idx := 0
	for d in DEPTS:
		for k in int(counts[d]):
			var p: Dictionary = people[idx]
			out.append({"id": int(p.id), "name": str(p.name), "dept": d, "wage": float(p.wage)})
			idx += 1
	return out


func staff(dept: String) -> int:
	ensure_targets()
	var n: int = sim.citizens.employed_count("rathaus")
	return int(_split(n, target).get(dept, 0)) if not target.is_empty() else 0


func staff_total() -> int:
	return sim.citizens.employed_count("rathaus")


## Bearbeitungspunkte je Tag fuer Bauantraege (Permits).
func permit_points() -> float:
	ensure_targets()
	return float(staff("verwaltung") + staff("bauamt")) / PERMIT_DIVISOR


func monthly_cost() -> float:
	var sum := 0.0
	for p in sim.citizens.people:
		if p.employer == "rathaus":
			sum += float(p.wage) * Citizens.HOURS_PER_MONTH
	return sum


func vacancies() -> int:
	return maxi(0, total_target() - staff_total())


## Einstellen: Soll-Bestand der Abteilung erhoehen. Besetzt wird zum Monatsende aus den Arbeitslosen.
func hire(dept: String, n: int, who: String = "") -> Dictionary:
	ensure_targets()
	if not DEPTS.has(dept):
		return _refuse("Unbekannte Abteilung '%s' (%s)." % [dept, ", ".join(DEPTS.keys())])
	if n < 1 or n > MAX_PER_ACTION:
		return _refuse("Anzahl muss zwischen 1 und %d liegen." % MAX_PER_ACTION)
	if total_target() + n > MAX_TOTAL:
		return _refuse("Das Rathaus darf höchstens %d Stellen haben (jetzt %d)." % [MAX_TOTAL, total_target()])
	var cost := float(n) * DEFAULT_WAGE * Citizens.HOURS_PER_MONTH
	var need := cost * RESERVE_MONTHS
	var free: float = sim.mayor.available_budget()
	if free < need:
		return _refuse("Die verfügbare Stadtkasse (%s) deckt keine %d Monatsgehälter der neuen Kräfte (%s) – Mehrkosten %s je Monat." % [
			Catalog.money(free), int(RESERVE_MONTHS), Catalog.money(need), Catalog.money(cost)])
	target[dept] = int(target[dept]) + n
	_sync()
	stats.hired += n
	return {"ok": true, "msg": "%d Stelle(n) in der Abteilung %s ausgeschrieben (Soll jetzt %d, besetzt %d). Besetzung zum Monatsende; Mehrkosten %s je Monat." % [
		n, DEPTS[dept].label, target[dept], staff(dept), Catalog.money(cost)]}


## Entlassen: Soll-Bestand senken; die Entlassung wirkt zum Monatsende (Arbeitsmarkt).
func dismiss(dept: String, n: int) -> Dictionary:
	ensure_targets()
	if not DEPTS.has(dept):
		return _refuse("Unbekannte Abteilung '%s' (%s)." % [dept, ", ".join(DEPTS.keys())])
	if n < 1 or n > MAX_PER_ACTION:
		return _refuse("Anzahl muss zwischen 1 und %d liegen." % MAX_PER_ACTION)
	if int(target[dept]) - n < MIN_PER_DEPT:
		return _refuse("Jede Abteilung braucht mindestens %d Kraft (%s hat Soll %d)." % [MIN_PER_DEPT, DEPTS[dept].label, target[dept]])
	target[dept] = int(target[dept]) - n
	_sync()
	stats.dismissed += n
	return {"ok": true, "msg": "%d Stelle(n) in der Abteilung %s gestrichen (Soll jetzt %d). Entlassung zum Monatsende." % [n, DEPTS[dept].label, target[dept]]}


func _refuse(msg: String) -> Dictionary:
	stats.refused += 1
	return {"ok": false, "msg": msg}


## Bedarf des Arbeitgebers "rathaus" im Arbeitsmarkt folgt dem Soll-Bestand.
func _sync() -> void:
	var t := total_target()
	sim.citizens.cap["rathaus"] = t
	sim.citizens.base_cap["rathaus"] = t


func summary() -> Dictionary:
	ensure_targets()
	var depts := {}
	for d in DEPTS:
		depts[d] = {"bezeichnung": DEPTS[d].label, "aufgabe": DEPTS[d].aufgabe, "soll": int(target.get(d, 0)), "ist": staff(d)}
	return {"gebaeude": sim.city.building(building).name if building >= 0 else "",
		"abteilungen": depts, "soll_gesamt": total_target(), "ist_gesamt": staff_total(), "offene_stellen": vacancies(),
		"kosten_monat": snappedf(monthly_cost(), 1.0), "bauantrag_kapazitaet_je_tag": snappedf(permit_points(), 0.1),
		"grenzen": {"max_je_aktion": MAX_PER_ACTION, "min_je_abteilung": MIN_PER_DEPT, "max_gesamt": MAX_TOTAL}}


func to_dict() -> Dictionary:
	return {"target": target.duplicate(), "stats": stats.duplicate()}


func from_dict(d: Dictionary) -> void:
	target = {}
	for k in d.get("target", {}):
		target[str(k)] = int(d.target[k])
	stats = d.get("stats", stats)
