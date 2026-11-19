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
const ACCT := "E0"                   # Auftrag 22 Phase 3: gemeinsame Kraftwerksgesellschaft der Staedte (Ausgleich in PowerGrid.settle)

var sim
var building := -1
var loaded_mwh := MWH_PER_ELEMENT
var pending: Array = []              # {due, n}: bestellte Elemente, Ankunft am Terminal
var maint_due := MAINT_DAYS
var stats := {"mwh": 0.0, "fuel_cost": 0.0, "crew": 0.0, "maintenance": 0.0, "emergency_kwh": 0.0, "emergency_cost": 0.0, "disposal": 0.0, "elements_used": 0}
var alarm := {}                       # {stufe, seit, ursache, sperre_bis, evakuiert, stabilisiert}
const EXCLUSION_RADIUS := 8
const RESPONSE_STABILIZE := 45000.0
const RESPONSE_EVACUATE := 20000.0


func setup(simulation) -> void:
	sim = simulation
	for b in sim.city.buildings:
		if b.role != "plot" and b.type == "factory" and b.id != sim.trader.bauhof and b.id != sim.city_depot.building:
			building = int(b.id)
			break
	if building < 0:
		building = int(sim.city_depot.building)
	sim.city.buildings[building].name = "Kernkraftwerk (Stadtwerke)"
	if str(sim.city.buildings[building].type) == "factory":
		sim.city.buildings[building].sprite = "nuclear_plant"
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
		if d.item == ITEM and d.buyer == "P0" and int(d.buyer_loc) == building and d.status in ["transport", "unterwegs"]:
			n += int(d.qty)
	return n


func maintenance_overdue() -> bool:
	return GameCalendar.day_of(sim.game_min) > maint_due


## Verfuegbare Leistung aus dem Kraftwerk (ohne Notstrom).
func available_kw(nominal: float) -> float:
	if GameCalendar.day_of(sim.game_min) < offline_until:
		return 0.0   # nach einem Stoerfall abgeschaltet
	if sim.eko != null and sim.eko.arms.condition_of(building) <= 0.0:
		return 0.0   # ein zerstoertes Kraftwerk muss erst wiederaufgebaut werden
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
		sim.economy.transfer(ACCT, "X0", cost)
		stats.emergency_kwh = float(stats.emergency_kwh) + emergency_kwh
		stats.emergency_cost = float(stats.emergency_cost) + cost


## Atomrisiko (Benedikt 15.11.: Kernkraftwerke haben Risiken): seltener Stoerfall, deutlich haeufiger bei ueberfaelliger Wartung.
## Stoerfall: Abschaltung, Reparatur an die Baufirmen, Zustimmung der Buergermeister sinkt (Buergerprotest). Schwerer Stoerfall
## (jeder fuenfte): lange Abschaltung, hohe Kosten, starker Protest. Waehrend der Abschaltung deckt teurer Notstrom die Luecke.
const INCIDENT_P := 0.002
const INCIDENT_P_OVERDUE := 0.02
var offline_until := -1
var incidents: Array = []        # {tag, schwer, kosten, tage}


func _incident_roll(day: int) -> void:
	if day < offline_until or (loaded_mwh <= 0.0 and fuel_elements() <= 0):
		return
	var r := RandomNumberGenerator.new()   # eigener Wurf je Tag: verschiebt nicht die Zufallsfolge der uebrigen Simulation
	r.seed = hash([int(sim.city.seed_value), day, "kernkraftwerk"])
	if r.randf() >= INCIDENT_P + (INCIDENT_P_OVERDUE if maintenance_overdue() else 0.0):
		return
	var severe: bool = r.randf() < 0.2
	var days: int = 30 if severe else r.randi_range(4, 10)
	var cost: float = 300000.0 if severe else 50000.0
	offline_until = day + days
	sim.economy.transfer(ACCT, "K0", cost)   # Reparatur und Sicherheitspruefung durch Baufirmen
	incidents.append({"tag": day + 1, "schwer": severe, "kosten": cost, "tage": days})
	for M in sim.towns.mayors:
		M.approval = maxf(0.0, float(M.approval) - (20.0 if severe else 8.0))
	sim.log_event(("SCHWERER STÖRFALL im Kernkraftwerk! %d Tage abgeschaltet, %s Kosten, Bürger protestieren." if severe else
		"Störfall im Kernkraftwerk: %d Tage abgeschaltet, %s Reparatur. Die Bürger sind beunruhigt.") % [days, Catalog.money(cost)], "bad")


## Ein Angriff fuehrt zuerst zur Sicherheitsabschaltung. Erst schwere, fortgesetzte Schaeden loesen eine regionale Katastrophe aus.
## Die Spielwerte bilden Risiko und Folgen ab, keine realen kerntechnischen Prozesse.
func attack_damage(condition: float, attacker: String) -> void:
	var day := GameCalendar.day_of(sim.game_min)
	var level := "abschaltung" if condition >= 60.0 else ("stoerfall" if condition >= 30.0 else "katastrophe")
	var rank := {"abschaltung": 1, "stoerfall": 2, "katastrophe": 3}
	if int(rank.get(alarm.get("stufe", ""), 0)) >= int(rank[level]):
		return
	var previous: String = str(alarm.get("stufe", ""))
	var shutdown := 3 if level == "abschaltung" else (12 if level == "stoerfall" else 45)
	offline_until = maxi(offline_until, day + shutdown)
	alarm = {"stufe": level, "seit": day, "ursache": attacker, "sperre_bis": day + (35 if level == "katastrophe" else 0),
		"evakuiert": false, "stabilisiert": false}
	var bd: Dictionary = sim.city.building(building)
	var at := Vector2i(int(bd.walk.x), int(bd.walk.y))
	if level == "abschaltung":
		sim.log_event("ALARM im Kernkraftwerk: Angriff durch %s, Sicherheitsabschaltung für mindestens %d Tage. Die Stadtwerke schalten auf Notstrom." % [attacker, shutdown], "warn")
		return
	if previous in ["", "abschaltung"]:
		sim.fire.ignite(building, "Angriff auf das Kernkraftwerk", "Industriebrand")
	if level == "stoerfall":
		sim.log_event("STÖRFALL im Kernkraftwerk nach Angriff durch %s: Feuerwehreinsatz, %d Tage Abschaltung und Stromengpass." % [attacker, shutdown], "bad")
		return
	# Ein schwerer Schaden legt die Umgebung still; die sichtbare Sperrzone trifft auch den Angreifer.
	sim.eko.arms.zones.append({"feld": [at.x, at.y], "radius": EXCLUSION_RADIUS, "bis_tag": day + 35, "quelle": "kraftwerk"})
	sim.eko.conflict.fires.append({"feld": [at.x, at.y], "left": 30.0, "staerke": 1.0})
	sim.eko.changed.emit()
	for mayor in sim.towns.mayors:
		mayor.approval = maxf(0.0, float(mayor.approval) - 18.0)
	sim.log_event("KATASTROPHE im Kernkraftwerk nach Angriff durch %s! Reaktor außer Betrieb, Evakuierung und Sperrzone um %d/%d für 35 Tage. Feuerwehr und Rettung sind alarmiert." % [attacker, at.x, at.y], "bad")


## Buergermeister entscheiden ueber Sofortschutz und Evakuierung; jede Massnahme ist einmalig und kostet die jeweilige Stadtkasse.
func respond(town: int, measure: String) -> Dictionary:
	if alarm.is_empty() or GameCalendar.day_of(sim.game_min) >= offline_until:
		return {"ok": false, "msg": "Kein laufender Kraftwerksnotfall."}
	if measure not in ["stabilisieren", "evakuieren"]:
		return {"ok": false, "msg": "Maßnahme stabilisieren oder evakuieren wählen."}
	if measure == "evakuieren" and str(alarm.stufe) != "katastrophe":
		return {"ok": false, "msg": "Evakuierung ist nur bei einer Sperrzone nötig."}
	var key := "stabilisiert" if measure == "stabilisieren" else "evakuiert"
	if bool(alarm.get(key, false)):
		return {"ok": false, "msg": "Maßnahme wurde bereits durchgeführt."}
	var cost := RESPONSE_STABILIZE if measure == "stabilisieren" else RESPONSE_EVACUATE
	if sim.towns.mayor(town).available_budget() < cost:
		return {"ok": false, "msg": "Für %s fehlen %s." % [measure, Catalog.money(cost)]}
	sim.economy.transfer(Towns.account_of(town), "K0" if measure == "stabilisieren" else "S0", cost)
	alarm[key] = true
	if measure == "stabilisieren":
		offline_until = maxi(GameCalendar.day_of(sim.game_min) + 3, offline_until - 8)
		if str(alarm.stufe) == "katastrophe":
			alarm.sperre_bis = maxi(GameCalendar.day_of(sim.game_min) + 10, int(alarm.sperre_bis) - 10)
			for zone in sim.eko.arms.zones:
				if str(zone.get("quelle", "")) == "kraftwerk":
					zone.bis_tag = int(alarm.sperre_bis)
	else:
		# Die sichtbaren Wesen verlassen die Sperrzone auf einem Fussweg zum naechsten sicheren Stadtzentrum.
		var site: Dictionary = sim.city.building(building)
		var center := Vector2i(int(site.walk.x), int(site.walk.y))
		for being in sim.eko.beings.values():
			if EkoWorld._dist(sim.eko.tile_of(being), center) > EXCLUSION_RADIUS:
				continue
			for t in sim.towns.list:
				if EkoWorld._dist(t.center, center) > EXCLUSION_RADIUS:
					var path: Array[Vector2i] = sim.nav.walk_path(sim.eko.tile_of(being), t.center)
					if not path.is_empty():
						being.mover.set_path(path)
						break
	sim.log_event("%s: Kraftwerksnotfall – %s für %s beschlossen." % [sim.towns.name_of(town), measure, Catalog.money(cost)], "good")
	return {"ok": true, "msg": "%s beauftragt (%s)." % [measure.capitalize(), Catalog.money(cost)]}


func _exclusion_day(day: int) -> void:
	var active: bool = not alarm.is_empty() and str(alarm.get("stufe", "")) == "katastrophe" and day < int(alarm.get("sperre_bis", 0))
	var site: Dictionary = sim.city.building(building)
	if site.is_empty():
		return
	var center := Vector2i(int(site.walk.x), int(site.walk.y))
	for biz in sim.biz.items.values():
		var bd: Dictionary = sim.city.building(int(biz.site))
		if bd.is_empty():
			continue
		var near := Vector2i(int(bd.walk.x), int(bd.walk.y)).distance_to(center) <= EXCLUSION_RADIUS
		if active and near:
			sim.biz.block(str(biz.id), "kraftwerk_sperrzone", "Kraftwerksnotfall: Betrieb in der Sperrzone")
		else:
			sim.biz.unblock(str(biz.id), "kraftwerk_sperrzone")


func on_day(day: int) -> void:
	if not alarm.is_empty() and day >= offline_until and day >= int(alarm.get("sperre_bis", 0)):
		alarm.clear()
	_incident_roll(day)
	_exclusion_day(day)
	sim.economy.transfer(ACCT, "H0", CREW_PER_DAY)   # Betriebsmannschaft
	stats.crew = float(stats.crew) + CREW_PER_DAY
	# Ankunft bestellter Elemente am Importterminal -> Spezialtransport zum Kraftwerk (echter Transportauftrag, Zahler P0)
	for p in pending.duplicate():
		if day >= int(p.due):
			p.n = _ship(int(p.n))
			if int(p.n) <= 0:
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
			sim.economy.transfer(ACCT, "T0", price)
			stats.maintenance = float(stats.maintenance) + price
			maint_due = day + MAINT_DAYS
			sim.log_event("Kraftwerk gewartet (%d Einheiten Stahl, %s)." % [MAINT_STEEL, Catalog.money(price)], "info")


func _ship(n: int) -> int:
	var port: int = int(sim.city_depot.port)
	var ip := float(Production.art(ITEM).get("importpreis", 0.0))
	# Heimische Brennelemente fahren als echte Fracht vom Werk zum Reaktor. Bis zur Ankunft bleiben sie beim Hersteller reserviert.
	var suppliers: Array = sim.prod.sellers(ITEM)
	suppliers.sort_custom(func(a, b): return float(a.price) < float(b.price))
	for supplier in suppliers:
		if n <= 0:
			break
		var q := mini(n, int(supplier.avail))
		var freight: float = sim.prod.freight(int(supplier.loc), building, ITEM, q)
		if sim.prod._deal("P0", building, "", supplier, ITEM, q, float(supplier.price), freight):
			var budget := float(supplier.price) * float(q) + freight
			sim.economy.transfer(ACCT, "P0", budget)
			stats.fuel_cost = float(stats.fuel_cost) + budget
			sim.log_event("Kernkraftwerk bestellt %d Brennelemente aus %s: Spezialtransport zum Reaktor ausgeschrieben." % [q, sim.company(int(supplier.cid)).company_name], "info")
			n -= q
	if n <= 0:
		return 0
	if sim.harbor.enabled and sim.harbor.available(ITEM) < n:   # Kuestenort: Brennstoff kommt mit dem naechsten Schiff
		sim.harbor.demand(ITEM, n - sim.harbor.available(ITEM))
		return n
	var freight: float = sim.prod.freight(port, building, ITEM, n)
	if sim.prod._deal("P0", building, "", {"biz": "", "acct": "X0", "cid": -1, "loc": port, "avail": n, "price": ip}, ITEM, n, ip, freight):
		var budget := ip * float(n) + freight
		sim.economy.transfer(ACCT, "P0", budget)   # Die gemeinsame Kraftwerksgesellschaft finanziert Einkauf und Fracht.
		stats.fuel_cost = float(stats.fuel_cost) + budget
		return 0
	return n


## Reststoffe: monatlich ein Teil kostenpflichtig zur externen Entsorgung (dokumentierter Abfallstrom).
func on_month(_m: int) -> void:
	var n := mini(DISPOSAL_PER_MONTH, sim.stock.qty(SPENT, "P0", building))
	if n > 0:
		sim.stock.consume(SPENT, n, "P0", building, "Entsorgung (extern)", sim.game_min)
		sim.economy.transfer(ACCT, "S0", DISPOSAL_COST * float(n))
		stats.disposal = float(stats.disposal) + DISPOSAL_COST * float(n)


func summary() -> Dictionary:
	return {"gebaeude": building, "brennstoff_mwh": snappedf(loaded_mwh, 0.1), "elemente_lager": fuel_elements(), "bestellt": ordered(),
		"wartung_faellig_tag": maint_due, "wartung_ueberfaellig": maintenance_overdue(), "reststoff": sim.stock.qty(SPENT, "P0", building), "reststoff_max": SPENT_CAP,
		"notstrom_kwh": int(stats.emergency_kwh), "notfall": alarm.duplicate(), "ausser_betrieb_bis_tag": offline_until}


func to_dict() -> Dictionary:
	return {"building": building, "loaded_mwh": loaded_mwh, "pending": pending, "maint_due": maint_due, "stats": stats, "offline_until": offline_until, "incidents": incidents, "alarm": alarm}


func from_dict(d: Dictionary) -> void:
	if d.is_empty():
		return
	var saved_building := int(d.get("building", building))
	if saved_building >= 0 and saved_building < sim.city.buildings.size() and str(sim.city.buildings[saved_building].type) == "factory":
		building = saved_building
	elif building != saved_building and building >= 0 and str(sim.city.buildings[building].type) == "factory":
		# Alte Wildnis-Spielstaende lagerten Brennstoff im Depot, weil dort noch kein Kraftwerk stand.
		for item in [ITEM, SPENT]:
			var amount: int = sim.stock.qty(item, "P0", saved_building)
			if amount > 0:
				sim.stock.move(item, amount, "P0", saved_building, "P0", building, "Kraftwerk am Großlager übernommen", sim.game_min)
	if building >= 0 and building < sim.city.buildings.size() and str(sim.city.buildings[building].type) == "factory":
		sim.city.buildings[building].sprite = "nuclear_plant"
	offline_until = int(d.get("offline_until", -1))
	incidents = d.get("incidents", [])
	alarm = d.get("alarm", {})
	loaded_mwh = float(d.get("loaded_mwh", loaded_mwh))
	pending = d.get("pending", [])
	maint_due = int(d.get("maint_due", maint_due))
	for k in d.get("stats", {}):
		stats[k] = d.stats[k]
