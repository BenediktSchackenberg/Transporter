class_name BusinessStages
extends RefCounted
## Gebaeudestufen der Unternehmerbetriebe (Auftrag 15, Etappe E, Abschnitt 10). Jede Stufe hat Aussehen (Name), Baukosten,
## Mindestpersonal und Wirkung auf Kapazitaet und laufenden Aufwand. Ausbau nur, wenn alle Voraussetzungen erfuellt sind:
##   Nachfrage (Kundschaft geht leer aus bzw. Foerderung wird abgesetzt), Geld, Personal, Strom (Netzreserve), Genehmigung
##   (Bauamt prueft Voraussetzungen), dann baut ein Bautrupp mit Material aus Bauhof/Hafen (Construction.add_company_works, Art "ausbau").
## Die neue Stufe gilt erst nach Fertigstellung. Stufe 1 ist der Gruendungszustand (Faktor 1, keine Aenderung bestehender Betriebe).

const STAGES := {
	"hotel": [
		{"name": "Strandpension", "zimmer": 10, "sprite": "hotel_pension"},
		{"name": "Strandhotel", "zimmer": 32, "sprite": "hotel_strand", "kosten": 36000.0, "personal": 3, "strom": 1.5},
		{"name": "Grandhotel", "zimmer": 80, "sprite": "hotel_grand", "kosten": 78000.0, "personal": 6, "strom": 2.5},
	],
	"baeckerei": [
		{"name": "Backstube"},
		{"name": "Bäckerei mit Café", "kosten": 16000.0, "personal": 3, "produktion": 1.3, "lager": 1.5, "kundschaft": 1.35, "strom": 1.4},
		{"name": "Großbäckerei", "kosten": 34000.0, "personal": 5, "produktion": 1.6, "lager": 2.0, "kundschaft": 1.7, "strom": 1.8},
	],
	"restaurant": [
		{"name": "Gasthaus", "plaetze": 40},
		{"name": "Restaurant mit Terrasse", "kosten": 18000.0, "personal": 3, "plaetze": 70, "kundschaft": 1.3, "strom": 1.4},
		{"name": "Hotel-Restaurant", "kosten": 38000.0, "personal": 5, "plaetze": 110, "kundschaft": 1.6, "strom": 1.8},
	],
	"bergwerk": [
		{"name": "Stollen"},
		{"name": "Schacht mit Förderturm", "kosten": 24000.0, "personal": 4, "produktion": 1.35, "lager": 1.5, "strom": 1.5},
		{"name": "Tiefbau mit Aufbereitung", "kosten": 50000.0, "personal": 6, "produktion": 1.7, "lager": 2.0, "strom": 2.0},
	],
}
const DEMAND_SHOP := 0.12      # Anteil abgewiesener/leer ausgegangener Kundschaft (gleitend), ab dem ein Ausbau lohnt
const DEMAND_MINE := 0.7       # Absatz/Foerderung (gleitend): die Foerderung wird abgenommen

var sim
var stats := {"ausbauten": 0}
var _spec_cache := {}


func setup(simulation) -> void:
	sim = simulation


static func has_stages(branch: String) -> bool:
	return STAGES.has(branch)


static func stage_of(b: Dictionary) -> int:
	return int(b.get("stufe", 1))


static func stage_def(b: Dictionary, stage: int = -1) -> Dictionary:
	var list: Array = STAGES.get(str(b.branch), [])
	var s := stage_of(b) if stage < 0 else stage
	return list[s - 1] if s >= 1 and s <= list.size() else {}


static func stage_name(b: Dictionary) -> String:
	return str(stage_def(b).get("name", ""))


## Branchenwerte mit der Wirkung der aktuellen Stufe (Rezept-Chargen, Foerderung, Lager). Stufe 1: unveraendert.
func spec_of(b: Dictionary) -> Dictionary:
	var base: Dictionary = Businesses.branches().get(b.branch, {})
	var s := stage_of(b)
	if s <= 1 or not STAGES.has(str(b.branch)):
		return base
	var key := "%s:%d" % [b.branch, s]
	if not _spec_cache.has(key):
		var d := stage_def(b)
		var spec: Dictionary = base.duplicate(true)
		var pf := float(d.get("produktion", 1.0))
		var lf := float(d.get("lager", 1.0))
		if spec.has("rezept"):
			for V in [spec.rezept] + spec.get("rezept_varianten", []):   # Varianten (Schlachthof Schwein/Rind) wachsen mit
				V.chargen_je_person_tag = int(round(float(V.chargen_je_person_tag) * pf))
				V.lager_max = int(round(float(V.lager_max) * lf))
		if spec.has("abbau"):
			spec.abbau.je_person_tag = int(round(float(spec.abbau.je_person_tag) * pf))
			spec.abbau.lager_max = int(round(float(spec.abbau.lager_max) * lf))
		_spec_cache[key] = spec
	return _spec_cache[key]


## Gewicht der Theke im gemeinsamen Kundentopf (groesserer Laden, Cafe, Terrasse).
static func customer_factor(b: Dictionary) -> float:
	return float(stage_def(b).get("kundschaft", 1.0))


## Sitzplaetze eines Restaurants (Kapazitaet je Tag); -1 = unbegrenzt.
static func seats(b: Dictionary) -> int:
	return int(stage_def(b).get("plaetze", -1))


# ------------------------------------------------------------------ Nachfrage
## Taeglich nach Produktion und Ladenverkauf: gleitender Nachfragedruck je Betrieb.
func on_day(_day: int) -> void:
	for b in sim.biz.items.values():
		if not STAGES.has(str(b.branch)) or b.status not in Businesses.RUNNING:
			continue
		var x := 0.0
		if b.branch == "hotel":
			x = sim.tourism.occupancy(str(b.id))
		elif b.branch == "bergwerk":
			x = clampf(float(b.get("sales_avg", 0.0)) / maxf(1.0, float(b.get("today", 0))), 0.0, 1.0) if int(b.get("today", 0)) > 0 else 0.0
		elif bool(b.get("counter", false)):
			var want := int(b.get("counter_customers", 0)) + int(b.get("counter_turned", 0))
			x = float(int(b.get("counter_lost", 0)) + int(b.get("counter_turned", 0))) / maxf(1.0, float(want))
		b["demand_avg"] = snappedf(float(b.get("demand_avg", 0.0)) * 0.8 + x * 0.2, 0.001)


# ------------------------------------------------------------------ Voraussetzungen
## Pruefung fuer die naechste Stufe: {moeglich, stufe, ziel, name, kosten, tage, gruende (fehlende Voraussetzungen)}.
func check(b: Dictionary) -> Dictionary:
	var list: Array = STAGES.get(str(b.branch), [])
	var s := stage_of(b)
	if list.is_empty():
		return {"moeglich": false, "gruende": ["keine Ausbaustufen für %s" % b.branch]}
	if s >= list.size():
		return {"moeglich": false, "stufe": s, "name": stage_name(b), "gruende": ["höchste Stufe erreicht"]}
	var nd: Dictionary = list[s]
	var cost := float(nd.kosten)
	var out := {"stufe": s, "name": stage_name(b), "ziel": s + 1, "ziel_name": nd.name, "kosten": int(cost), "tage": _days(cost), "gruende": []}
	if str(b.get("upgrading", "")) != "":
		out.gruende.append("Ausbau läuft bereits (%s)" % b.upgrading)
	if b.status not in Businesses.RUNNING:
		out.gruende.append("Betrieb läuft nicht (%s)" % b.status)
	var demand := float(b.get("demand_avg", 0.0))
	var need := DEMAND_MINE if b.branch == "bergwerk" else DEMAND_SHOP
	if demand < need:
		out.gruende.append("Nachfrage reicht nicht (%d %% statt %d %%)" % [int(demand * 100.0), int(need * 100.0)])
	var staff: int = sim.biz.staff_of(b.id).size()
	if staff < int(nd.personal):
		out.gruende.append("zu wenig Personal (%d von %d)" % [staff, int(nd.personal)])
	if sim.company(int(b.owner)).ledger.cash < cost:
		out.gruende.append("Geld fehlt (%s nötig)" % Catalog.money(cost))
	var extra := extra_kw(b)
	if extra > 0.0 and float(sim.grid.capacity) - float(sim.grid.last.get("bedarf", 0.0)) < extra:
		out.gruende.append("Stromnetz reicht nicht (+%d kW nötig, Netzausbau beim Bürgermeister)" % int(extra))
	out["moeglich"] = out.gruende.is_empty()
	return out


func extra_kw(b: Dictionary) -> float:
	var nd := stage_def(b, stage_of(b) + 1)
	var base := float(Businesses.branches().get(b.branch, {}).get("strom_kw", 0.0))
	return maxf(0.0, base * float(nd.get("strom", 1.0)) - float(b.energy_kw))


static func _days(cost: float) -> int:
	return int(clampf(4.0 + cost / 3000.0, 5.0, 24.0))


# ------------------------------------------------------------------ Ausbau
func upgrade(cid: int, biz_id: String, reason: String = "") -> Dictionary:
	var b: Dictionary = sim.biz.get_b(biz_id)
	if b.is_empty() or int(b.owner) != cid:
		return {"ok": false, "msg": "Betrieb %s gehört dir nicht." % biz_id}
	var ck := check(b)
	if not bool(ck.get("moeglich", false)):
		return {"ok": false, "msg": "Ausbau von %s nicht möglich: %s." % [b.name, "; ".join(ck.gruende)]}
	var cost := float(ck.kosten)
	var c = sim.company(cid)
	c.ledger.invest(cost, "K0")   # Bauauftrag: Geld liegt bei den Baufirmen bis zur Fertigstellung
	c.property_book += cost
	b["book"] = float(b.get("book", 0.0)) + cost
	b["equip"] = float(b.get("equip", 0.0)) + cost
	var w: Dictionary = sim.construction.add_company_works(cid, b, int(b.site), "ausbau", cost)
	w["upgrade"] = int(ck.ziel)
	b["upgrading"] = w.id
	var why := reason if reason != "" else "Nachfrage %d %%" % int(float(b.get("demand_avg", 0.0)) * 100.0)
	sim.biz.note(b.id, "Bauamt genehmigt Ausbau zu %s (%s); Auftrag %s an %s" % [ck.ziel_name, why, w.id, w.builder_name], "Unternehmer")
	sim.log_event("%s baut %s aus: %s → %s (%s, %s, etwa %d Tage)." % [c.company_name, b.name, ck.name, ck.ziel_name, Catalog.money(cost), w.builder_name, int(w.days)], "info", cid)
	return {"ok": true, "msg": "Ausbau zu %s beauftragt (%s, %s baut, etwa %d Tage). Die Stufe gilt nach Fertigstellung." % [ck.ziel_name, Catalog.money(cost), w.builder_name, int(w.days)], "ref": w.id}


## Vom Bausystem bei Fertigstellung eines Ausbauauftrags aufgerufen.
func finish(w: Dictionary) -> void:
	var b: Dictionary = sim.biz.get_b(str(w.biz))
	if b.is_empty():
		return
	b["stufe"] = int(w.upgrade)
	b.erase("upgrading")
	var base := float(Businesses.branches().get(b.branch, {}).get("strom_kw", 0.0))
	b.energy_kw = base * float(stage_def(b).get("strom", 1.0))
	if b.branch == "hotel":
		var site := int(b.site)
		sim.city.buildings[site].sprite = str(stage_def(b).get("sprite", "hotel_pension"))
		sim.events.buildings_added.emit([site])
	b["demand_avg"] = 0.0
	stats.ausbauten = int(stats.ausbauten) + 1
	sim.biz.note(b.id, "Ausbau fertig: jetzt %s" % stage_name(b), "Bau")
	sim.log_event("%s ist jetzt %s." % [b.name, stage_name(b)], "good", int(b.owner))


## Kurzinfo fuer Beobachtung und Detailkarte.
func obs(b: Dictionary) -> Dictionary:
	if not STAGES.has(str(b.branch)):
		return {}
	var ck := check(b)
	var e := {"stufe": stage_of(b), "stufe_name": stage_name(b), "nachfrage": snappedf(float(b.get("demand_avg", 0.0)), 0.01)}
	if ck.has("ziel"):
		e["ausbau"] = {"ziel": ck.ziel_name, "kosten": ck.kosten, "personal": int(stage_def(b, int(ck.ziel)).personal), "moeglich": ck.moeglich, "fehlt": ck.gruende}
	return e


func to_dict() -> Dictionary:
	return {"stats": stats}


func from_dict(d: Dictionary) -> void:
	stats = d.get("stats", stats)
