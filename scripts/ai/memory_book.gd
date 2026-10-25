class_name MemoryBook
extends RefCounted
## Privates Gedaechtnis je Unternehmen – erfahrungsbasierte Anpassung durch gespeicherten Kontext
## (keine Veraenderung von Modellgewichten). Zwei Bereiche:
##  - Ereignisse: was beobachtet, entschieden und tatsaechlich ausgefuehrt wurde (nur eigene Informationsquellen)
##  - Erfahrungen: aktualisierbare Zusammenhaenge mit Gueltigkeitsbereich, Art (tatsache/vermutung) und Vertrauen
## Die Engine fuehrt messbare Erfahrungen selbst (z. B. Auftragsergebnisse je Viertel, mit Stichprobengroesse);
## das Modell kann eigene Erfahrungen anlegen, aendern und verwerfen. An die API geht nur eine relevante Auswahl.

const MAX_EVENTS := 150
const MAX_EXPERIENCES := 40
const PROMPT_EXPERIENCES := 8
const PROMPT_EVENTS := 6

var sim
var books := {}          # Firma -> {"events": [], "experiences": [], "next": int}


func setup(simulation) -> void:
	sim = simulation
	for c in sim.companies:
		books[c.id] = {"events": [], "experiences": [], "next": 1}


func add_event(cid: int, quelle: String, inhalt: String, bereich: Array = []) -> void:
	var b: Dictionary = books[cid]
	b.events.append({"t": sim.game_min, "quelle": quelle, "inhalt": inhalt.left(200), "bereich": bereich, "art": "tatsache"})
	if b.events.size() > MAX_EVENTS:
		b.events.pop_front()


## Erfahrung anlegen oder (mit id) aktualisieren. Gibt die ID zurueck.
func upsert(cid: int, e: Dictionary, quelle: String) -> String:
	var b: Dictionary = books[cid]
	var id := str(e.get("id", ""))
	var entry: Dictionary = {}
	for x in b.experiences:
		if x.id == id:
			entry = x
	if entry.is_empty():
		id = "E%d" % b.next
		b.next += 1
		entry = {"id": id, "erstellt": sim.game_min, "belege": 0}
		b.experiences.append(entry)
	entry["inhalt"] = str(e.get("inhalt", entry.get("inhalt", ""))).left(220)
	var area = e.get("bereich", entry.get("bereich", []))
	entry["bereich"] = (area if area is Array else [str(area)]).map(func(x): return str(x).to_lower())
	entry["art"] = "vermutung" if str(e.get("art", entry.get("art", "vermutung"))) == "vermutung" else "tatsache"
	entry["vertrauen"] = clampf(float(e.get("vertrauen", entry.get("vertrauen", 0.5))), 0.0, 1.0)
	entry["quelle"] = quelle
	entry["aktualisiert"] = sim.game_min
	if e.has("belege"):
		entry["belege"] = int(e.belege)
	if b.experiences.size() > MAX_EXPERIENCES:
		b.experiences.sort_custom(func(x, y): return float(x.vertrauen) + float(x.aktualisiert) / 10000.0 > float(y.vertrauen) + float(y.aktualisiert) / 10000.0)
		b.experiences = b.experiences.slice(0, MAX_EXPERIENCES)
	return id


func forget(cid: int, id: String) -> bool:
	var b: Dictionary = books[cid]
	var n: int = b.experiences.size()
	b.experiences = b.experiences.filter(func(x): return x.id != id)
	return b.experiences.size() != n


## Engine-Erfahrung: Ergebnis abgeschlossener Auftraege je Abhol-Viertel (Stichprobe, Puenktlichkeit, Erloes je Einheit).
## Wenige Beobachtungen = geringes Vertrauen und Art "vermutung".
func record_contract(cid: int, k: Contract, on_time: bool, paid: float) -> void:
	var district: String = Catalog.DISTRICTS[sim.city.district_of(sim.city.building(k.pickup).road)].to_lower()
	var key := "auftraege:" + district
	var b: Dictionary = books[cid]
	var entry: Dictionary = {}
	for x in b.experiences:
		if x.get("schluessel", "") == key:
			entry = x
	var n := int(entry.get("n", 0)) + 1
	var ok_n := int(entry.get("puenktlich", 0)) + (1 if on_time else 0)
	var fail_n := int(entry.get("gescheitert", 0)) + (1 if paid <= 0.0 and not on_time else 0)
	var sum_pay := float(entry.get("summe_erloes", 0.0)) + paid
	var sum_tiles := float(entry.get("summe_strecke", 0.0)) + k.distance
	var text := "Aufträge ab %s: %d abgeschlossen, %d pünktlich, %d gescheitert, Ø Erlös %s je Auftrag, Ø %s je Tile Strecke." % [
		district.capitalize(), n, ok_n, fail_n, Catalog.money(sum_pay / n), Catalog.money(sum_pay / maxf(1.0, sum_tiles))]
	var id := upsert(cid, {"id": entry.get("id", ""), "inhalt": text, "bereich": [district, "auftraege"],
		"art": "tatsache" if n >= 3 else "vermutung", "vertrauen": minf(1.0, n / 6.0), "belege": n}, "engine")
	for x in b.experiences:
		if x.id == id:
			x["schluessel"] = key
			x["n"] = n
			x["puenktlich"] = ok_n
			x["gescheitert"] = fail_n
			x["summe_erloes"] = sum_pay
			x["summe_strecke"] = sum_tiles


## Relevante Auswahl fuer die Anfrage: Bereichs-Treffer zum aktuellen Kontext, Vertrauen und Aktualitaet.
func relevant(cid: int, context: Array) -> Dictionary:
	var b: Dictionary = books[cid]
	var ctx := context.map(func(x): return str(x).to_lower())
	var scored: Array = []
	for x in b.experiences:
		var hits := 0
		for tag in x.bereich:
			if tag in ctx:
				hits += 1
		var age: float = (sim.game_min - float(x.aktualisiert)) / 1440.0
		scored.append([hits * 2.0 + float(x.vertrauen) - minf(1.0, age * 0.3), x])
	scored.sort_custom(func(p, q): return p[0] > q[0])
	var exps: Array = scored.slice(0, PROMPT_EXPERIENCES).map(func(p): return {"id": p[1].id, "inhalt": p[1].inhalt,
		"bereich": p[1].bereich, "art": p[1].art, "vertrauen": snappedf(float(p[1].vertrauen), 0.01), "belege": p[1].get("belege", 0),
		"stand": Catalog.game_minutes_to_text(p[1].aktualisiert)})
	var evs: Array = b.events.slice(-PROMPT_EVENTS).map(func(e): return "%s [%s] %s" % [Catalog.game_minutes_to_text(e.t), e.quelle, e.inhalt])
	return {"erfahrungen": exps, "ereignisse": evs, "erfahrungen_gesamt": b.experiences.size()}


## Uebernahme in eine neue Partie (ausdrueckliche Einstellung): nur Erfahrungen, keine Ereignisse.
func export_experiences(cid: int) -> Array:
	return books[cid].experiences.map(func(x): return {"inhalt": x.inhalt, "bereich": x.bereich, "art": x.art,
		"vertrauen": x.vertrauen, "belege": x.get("belege", 0)})


func import_experiences(cid: int, items: Array) -> int:
	var n := 0
	for it in items:
		if it is Dictionary and str(it.get("inhalt", "")) != "":
			# Erfahrungen aus einer frueheren Partie gelten nur als Vermutung mit gedaempftem Vertrauen
			var e: Dictionary = it.duplicate()
			e["art"] = "vermutung"
			e["vertrauen"] = float(it.get("vertrauen", 0.5)) * 0.6
			e["bereich"] = (it.get("bereich", []) if it.get("bereich") is Array else []) + ["vorige_partie"]
			upsert(cid, e, "vorige Partie")
			n += 1
	return n


func to_dict() -> Dictionary:
	var out := {}
	for cid in books:
		out[str(cid)] = books[cid]
	return out


func from_dict(d: Dictionary) -> void:
	for cid in d:
		books[int(cid)] = d[cid]
		books[int(cid)].next = int(d[cid].next)
