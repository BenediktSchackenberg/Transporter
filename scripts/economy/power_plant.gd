class_name PowerPlant
extends RefCounted
## Kommunales Kernkraftwerk (Auftrag 14, Etappe 4; docs/ENTREPRENEURS.md Abschnitt 8). Eigentuemer ist die Stadt (Stadtwerke, Konto P0),
## die Betriebsleitung handelt im Rahmen des Budgets selbst. Abstrakte Spielebene, keine realen kerntechnischen Ablaeufe.
##
## Brennstoff: Brennelemente (Import ueber das Importterminal mit Lieferzeit, Spezialtransport als echter Transportauftrag, Zahler P0).
##   Ein geladenes Element liefert MWH_PER_ELEMENT; ist es aufgebraucht, wird das naechste aus dem Lager geladen und das alte wird
##   Reststoff (abgebranntes Element) im begrenzten Abklinglager; monatlich geht ein Teil kostenpflichtig zur externen Entsorgung.
## Betrieb: Mannschaft (Lohn je Tag an Haushalte), Wartung alle MAINT_DAYS mit Stahl vom Bauhof; ueberfaellige Wartung halbiert die Leistung.
## Engpass: Ohne Brennstoff liefert das Kraftwerk nichts; der Netzbetreiber kauft dann begrenzt teuren Notstrom von aussen (X0).
## Start: Anfangsbestand an Brennelementen und ein geladenes Element (kein Startstillstand).

const ITEM := "brennelement"
const SPENT := "reststoff_brennelement"
const MWH_PER_ELEMENT := 250.0
const START_STOCK := 2
const REORDER_AT := 1                # Elemente im Lager (inkl. bestellter) -> nachbestellen
const ORDER_QTY := 2
const LEAD_DAYS := 5                 # Lieferzeit bis zum Importterminal
const CREW_PER_DAY := 300.0          # Betriebsmannschaft (an Haushalte H0)
const MAINT_DAYS := 30
const MAINT_STEEL := 10              # Einheiten Stahl je Wartung (vom Bauhof)
const SPENT_CAP := 6                 # Abklinglager
const DISPOSAL_PER_MONTH := 2
const DISPOSAL_COST := 3000.0
const EMERGENCY_KW := 800.0          # Notstrom von aussen
const EMERGENCY_EUR_KWH := 0.45

var sim
var building := -1
var loaded_mwh := MWH_PER_ELEMENT
var pending: Array = []              # {due, n}: bestellte Elemente, Ankunft am Terminal
var maint_due := MAINT_DAYS
var stats := {"mwh": 0.0, "fuel_cost": 0.0, "crew": 0.0, "maintenance": 0.0, "emergency_kwh": 0.0, "emergency_cost": 0.0, "disposal": 0.0, "elements_used": 0}


func setup(simulation) -> void:
	sim = simulation
	for b in sim.city.buildings:
		if b.role != "plot" and b.type == "factory" and b.id != sim.trader.bauhof and b.id != sim.city_depot.building:
			building = int(b.id)
			break
	if building < 0:
		building = int(sim.city_depot.building)
	sim.city.buildings[building].name = "Kernkraftwerk (Stadtwerke)"
	sim.stock.add(ITEM, START_STOCK, "P0", building, "Anfangsbestand der Stadtwerke", 0.0)
	sim.day_changed.connect(on_day)
	sim.month_changed.connect(on_month)


func fuel_elements() -> int:
	return sim.stock.qty(ITEM, "P0", building)


func ordered() -> int:
	var n := 0
	for p in pending:
		n += int(p.n)
	for d in sim.prod.deals.values():
		if d.item == ITEM and d.status in ["transport", "unterwegs"]:
			n += int(d.qty)
	return n


func maintenance_overdue() -> bool:
	return GameCalendar.day_of(sim.game_min) > maint_due


## Verfuegbare Leistung aus dem Kraftwerk (ohne Notstrom).
func available_kw(nominal: float) -> float:
	if loaded_mwh <= 0.0 and fuel_elements() <= 0:
		return 0.0
	return nominal * (0.5 if maintenance_overdue() else 1.0)


## Erzeugung eines Tages: `kwh` aus dem Kraftwerk zehrt den Brennstoff auf; `emergency_kwh` wird teuer von aussen bezogen.
func generate(kwh: float, emergency_kwh: float) -> void:
	var mwh := kwh / 1000.0
	stats.mwh = float(stats.mwh) + mwh
	loaded_mwh -= mwh
	while loaded_mwh <= 0.0 and fuel_elements() > 0 and sim.stock.qty(SPENT, "P0", building) < SPENT_CAP:
		sim.stock.consume(ITEM, 1, "P0", building, "Brennelement geladen", sim.game_min)
		sim.stock.add(SPENT, 1, "P0", building, "Abgebranntes Element (Abklinglager)", sim.game_min)
		loaded_mwh += MWH_PER_ELEMENT
		stats.elements_used = int(stats.elements_used) + 1
	loaded_mwh = maxf(loaded_mwh, 0.0)
	if emergency_kwh > 0.0:
		var cost := emergency_kwh * EMERGENCY_EUR_KWH
		sim.economy.transfer("P0", "X0", cost)
		stats.emergency_kwh = float(stats.emergency_kwh) + emergency_kwh
		stats.emergency_cost = float(stats.emergency_cost) + cost


func on_day(day: int) -> void:
	sim.economy.transfer("P0", "H0", CREW_PER_DAY)   # Betriebsmannschaft
	stats.crew = float(stats.crew) + CREW_PER_DAY
	# Ankunft bestellter Elemente am Importterminal -> Spezialtransport zum Kraftwerk (echter Transportauftrag, Zahler P0)
	for p in pending.duplicate():
		if day >= int(p.due):
			_ship(int(p.n))
			pending.erase(p)
	if fuel_elements() + ordered() <= REORDER_AT:
		pending.append({"due": day + LEAD_DAYS, "n": ORDER_QTY})
		sim.log_event("Stadtwerke bestellen %d Brennelemente (Lieferzeit %d Tage)." % [ORDER_QTY, LEAD_DAYS], "info")
	# Wartung mit Stahl vom Bauhof
	if day >= maint_due:
		var T: Trader = sim.trader
		if T.stock_of("stahl") >= MAINT_STEEL:
			var price := T.price("stahl", MAINT_STEEL)
			sim.stock.consume("stahl", MAINT_STEEL, "T0", T.bauhof, "Wartung Kraftwerk", sim.game_min)
			sim.economy.transfer("P0", "T0", price)
			stats.maintenance = float(stats.maintenance) + price
			maint_due = day + MAINT_DAYS
			sim.log_event("Kraftwerk gewartet (%d Einheiten Stahl, %s)." % [MAINT_STEEL, Catalog.money(price)], "info")


func _ship(n: int) -> void:
	var port: int = int(sim.city_depot.port)
	var ip := float(Production.art(ITEM).get("importpreis", 0.0))
	sim.prod._deal("P0", building, "", {"biz": "", "acct": "X0", "cid": -1, "loc": port, "avail": n, "price": ip}, ITEM, n, ip, sim.prod.freight(port, building, ITEM, n))
	stats.fuel_cost = float(stats.fuel_cost) + ip * float(n)


## Reststoffe: monatlich ein Teil kostenpflichtig zur externen Entsorgung (dokumentierter Abfallstrom).
func on_month(_m: int) -> void:
	var n := mini(DISPOSAL_PER_MONTH, sim.stock.qty(SPENT, "P0", building))
	if n > 0:
		sim.stock.consume(SPENT, n, "P0", building, "Entsorgung (extern)", sim.game_min)
		sim.economy.transfer("P0", "S0", DISPOSAL_COST * float(n))
		stats.disposal = float(stats.disposal) + DISPOSAL_COST * float(n)


func summary() -> Dictionary:
	return {"gebaeude": building, "brennstoff_mwh": snappedf(loaded_mwh, 0.1), "elemente_lager": fuel_elements(), "bestellt": ordered(),
		"wartung_faellig_tag": maint_due, "wartung_ueberfaellig": maintenance_overdue(), "reststoff": sim.stock.qty(SPENT, "P0", building), "reststoff_max": SPENT_CAP,
		"notstrom_kwh": int(stats.emergency_kwh)}


func to_dict() -> Dictionary:
	return {"building": building, "loaded_mwh": loaded_mwh, "pending": pending, "maint_due": maint_due, "stats": stats}


func from_dict(d: Dictionary) -> void:
	if d.is_empty():
		return
	building = int(d.get("building", building))
	loaded_mwh = float(d.get("loaded_mwh", loaded_mwh))
	pending = d.get("pending", [])
	maint_due = int(d.get("maint_due", maint_due))
	for k in d.get("stats", {}):
		stats[k] = d.stats[k]
