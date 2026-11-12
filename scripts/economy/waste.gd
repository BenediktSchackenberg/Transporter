class_name Waste
extends RefCounted
## Muellabfuhr, Recycling und Mehrweg (Auftrag 5, Abschnitt 12; Auftrag 22 Phase 1, docs/INFRASTRUCTURE.md).
## Jedes bewohnte Haus und jeder Laden hat eine Tonne mit Fuellstand (kg). Taeglich kommt der Abfall der Einwohner der jeweiligen Stadt
## (Einwohner x KG_PER_PERSON_DAY, verteilt nach bewohnten Wohnungen) und die Verpackung der Kassenverkaeufe (auf die Laeden) hinein.
## Die Muellabfuhr jeder Stadt faehrt vom Rathaus aus Touren zu den vollsten Tonnen; erst beim Halt wird die Tonne wirklich geleert.
## Volle Wagen fahren zur gemeinsamen Deponie der Region, wo die Waage die Menge je Stadt erfasst: Wertstoffe (Recyclingquote) werden
## verkauft, der Rest wird abgelagert. Abholung und Ablagerung zahlt die Kasse der liefernden Stadt (an den Entsorger S0), die Gebuehr
## am Monatsende die Haushalte (H0) an ihre Stadt. Ueberquellende Tonnen senken die Versorgungszufriedenheit. Ist die Deponie zu
## EXPAND_AT gefuellt, wird sie erweitert; die Kosten teilen sich die Staedte nach ihren gewogenen Mengen.
## Mehrwegflaschen (siehe Retail: Pfand, Leergut, Wiederbefuellung) sparen Verpackungsabfall und erhoehen die Recyclingquote.

const KG_PER_PERSON_DAY := 0.9
const KG_PER_SALE := 0.35               # Verpackung je Kassenverkauf (Einheit)
const COLLECT_COST := 55.0              # EUR je Tonne Abholung
const DISPOSAL_COST := 70.0             # EUR je Tonne Restmuell
const RECYCLE_INCOME := 30.0            # EUR je Tonne Wertstoff
const BASE_RECYCLING := 0.35
const MEHRWEG_BONUS := 0.25             # zusaetzliche Quote bei vollstaendiger Mehrwegnutzung
const FEE_MARKUP := 1.1                 # Gebuehr = erwartete Kosten + 10 %
## Muellarten (Auftrag 22 Phase 2 Schritt 2): der Gesamtabsatz eines Gebaeudes wird in drei getrennte Toenen aufgeteilt.
## Rest (1-rate) geht zur Deponie, der recyclebare Teil (rate) geht real zum Recyclinghof: davon BIO_OF_RECYCLED Bio (-> Kompost),
## der Rest Wertstoffe (-> Sortierung). rate ist die effektive Recyclingquote (Mehrweg erhoht sie).
const BIO_OF_RECYCLED := 0.4
const WERT_TONS := 1.0                  # Ladekapazitaet eines Wertstoffwagens (t)
## Deponie und Muellabfuhr (sichtbar): Restmuell geht auf die gemeinsame Deponie, Muellwagen fahren Touren zu vollen Tonnen.
const LANDFILL_CAPACITY := 800.0        # Tonnen bis zur vollen Deponie beim Start (Spielwert)
const START_FILL := 0.25                # bestehende Deponie beim Start
const TRUCK_TONS := 2.0                 # Ladekapazitaet eines Muellwagens (t)
const TRIP_DAYS := 5.0                  # typische Tourdauer mit voller Ladung inkl. Fahrt zur Deponie (gemessen 2-9 Tage, tests/probe_waste.gd)
const MAX_TRUCKS := 8                   # hoechstens so viele Muellwagen je Stadt
const STOPS := 60                       # Halte je Tour (bis die Ladung voll ist)
const BIN_DAYS := 7.0                   # eine Tonne fasst den Abfall von so vielen Tagen
const WERT_DAYS := 4.0                  # Bio-/Wertstofftonnen werden oefters geleert (Wertstoffwirtschaft)
const MIN_BIN_KG := 20.0
const COLLECT_AT := 0.6                 # Tonnen ab diesem Fuellstand werden angefahren
const MIN_LOAD := 0.3                   # eine Tour startet ab diesem Anteil der Ladekapazitaet ...
const URGENT := 0.95                    # ... oder wenn die vollste Tonne so voll ist (kleine Orte: etwa woechentlich)
const EXPAND_AT := 0.8                  # Deponie-Erweiterung ab diesem Fuellstand
const EXPAND_T := 600.0
const EXPAND_COST := 90000.0
const EXPAND_DAYS := 20
const SCALE_LOG := 40                   # so viele Waegungen bleiben im Waagebuch
## Muellverbrennung (Auftrag 22 Phase 2 Schritt 4): hat die Deponie IV_BUILD_T neuen Restmuell (ohne Startfuellung) gesammelt,
## beschliesst die Region eine gemeinsame Verbrennungsanlage neben der Deponie (Municipal MV-01, Kosten nach Abfallmengen).
## Ab der Inbetriebnahme faehrt der Muellwagen weiter dorthin: 90 % des Restmuells wird verbrannt (Strom ins Netz, kein
## Brennstoff, der Muell ist ohnehin da), nur IV_ASH landet als Asche auf der Deponie; die Stadt zahlt einen Verarbeitungstarif.
const IV_BUILD_T := 5.0                # Tonnen neuer Restmuell (ohne Startfuellung), bis die Region die Verbrennungsanlage beschliesst (gemessen: ~0,1 t/Tag real angeliefert, tests/probe_waste.gd)
const IV_DAYS := 25                     # Bauzeit
const IV_ASH := 0.10                    # Anteil des Restmülls, der als Asche deponiert wird
const IV_KWH_PER_T := 500.0             # Stromausbeute je verbrannter Tonne Restmüll
const IV_PROC_PER_T := 25.0             # Verarbeitungstarif je Tonne (statt der vollen Deponiegebühr)

var sim: Simulation
var month := {"tons": 0.0, "recycled": 0.0, "cost": 0.0, "income": 0.0}
var total := {"tons": 0.0, "recycled": 0.0, "cost": 0.0, "income": 0.0, "fees": 0.0}
var rate := BASE_RECYCLING
var last_month := {}
var _units_seen := 0
var _unpaid := 0.0                      # aufgelaufene Kosten, die der Stadtkasse noch zu begleichen sind (nur bei leerer Kasse)
var landfill_pid := ""                  # Parzelle der Deponie
var landfill_cells := {}                # Zelle -> Formfaktor 0..1 (Rand niedrig, Mitte hoch)
var landfill_road := Vector2i(-1, -1)   # Zufahrt (Abladestelle)
var deposited := 0.0                    # abgeladener Restmuell (t), bestimmt die Hoehe des Muellbergs
var tours := 0
var capacity := LANDFILL_CAPACITY      # Fassungsvermoegen der Deponie (t), waechst mit jeder Erweiterung
var bins := {}                          # Gebaeude-ID -> Fuellstand (kg), Restmuell
var bio := {}                           # Gebaeude-ID -> Fuellstand (kg), Bioabfall (Auftrag 22 Phase 2 Schritt 2)
var wert := {}                          # Gebaeude-ID -> Fuellstand (kg), Wertstoffe (Auftrag 22 Phase 2 Schritt 2)
var bin_rate := {}                      # Gebaeude-ID -> kg Restmuell je Tag (taeglich neu berechnet, nicht gespeichert)
var bio_rate := {}                      # Gebaeude-ID -> kg Bio je Tag (taeglich neu berechnet, nicht gespeichert)
var wert_rate := {}                     # Gebaeude-ID -> kg Wertstoffe je Tag (taeglich neu berechnet, nicht gespeichert)
var by_town := {}                       # Stadt -> {"month": {...}, "total": {...}} wie month/total
var scale_log: Array = []               # Waagebuch [{tag, stadt, t, rest}]
var expansion := {}                     # laufende Erweiterung {start, fertig, t, kosten}
var expansions := 0
var overflow_days := 0                  # Summe ueberquellender Tonnen je Tag (Kennzahl)
var _planned := {}                      # Gebaeude-ID -> true, Tonne ist einer laufenden Tour zugeteilt (nicht gespeichert)
var real := false                       # Region: Muellarten real (Rest -> Deponie, Bio+Wertstoffe -> Recyclinghof). Kuestenort: altes Pauschal-Modell.
var tours_wert := 0                     # Wertstofftouren (Auftrag 22 Phase 2 Schritt 2)
var iv_building := 0                    # Baubeginn der Verbrennungsanlage (Tag), 0 = kein Bau
var iv_fertig := 0                      # Inbetriebnahme-Tag der Verbrennungsanlage, 0 = keine gebaut
var iv_retry := 0                       # naechster Versuch, einen Bauplatz neben der Deponie zu finden
var iv_fac := ""                        # Einrichtung MV-01 (Municipal)
var iv_new_t := 0.0                     # neu abgelagerter Restmuell seit Spielanfang (t) – Ausloesekriterium, die Startfuellung zaehlt nicht
var iv_stats := {"t": 0.0, "ash": 0.0, "kwh": 0.0, "erloes": 0.0}   # Verbrennungsleistung gesamt (Erloes deckt den Betrieb)
var _iv_acc := {"t": 0.0, "ash": 0.0, "kwh": 0.0}    # Tagesakkumulation (waelt am Tagesende in iv_last um)
var iv_last := {"t": 0.0, "ash": 0.0, "kwh": 0.0, "day": -1}   # letzter abgeschlossener Tag (Grundlage fuer Netzanschluss)
var _iv_site := {}   # gefundener Bauplatz (rect, parcel), bis zur Errichtung


func setup(s: Simulation) -> void:
	sim = s
	real = sim.municipal != null and sim.municipal.enabled()   # Region: echte Muellarten, sonst Pauschal-Modell
	s.day_changed.connect(on_day)
	s.month_changed.connect(on_month)
	deposited = LANDFILL_CAPACITY * START_FILL
	_build_landfill()


## Deponie auf einer freien Parzelle am Stadtrand (nicht auf Lagerstaetten), deterministisch aus dem Stadtsamen. Die Flaeche ist nicht
## begehbar und nicht bebaubar; die Zufahrt ist die naechste Strassenzelle.
func _build_landfill() -> void:
	var city: CityData = sim.city
	var best := {}
	var best_h := INF
	for p in sim.parcels.items.values():
		if p.state != "frei" or not sim.parcels.is_buildable(p) or int(p.area) < 60 or sim.prod._deposits.has(p.id):
			continue
		if not bool(sim.parcels.utilities_of(p).strasse):
			continue
		if not city.coastal() and not sim.prod._outskirts(p):
			continue
		var h := float(absi(hash([city.seed_value, p.id, "deponie"])) % 100000)
		if city.coastal():   # Kuestenort: an der Ortsgrenze, so weit wie moeglich vom Hafen (Strassen gibt es nur im Ort)
			h = -Vector2(float(p.rect[0]), float(p.rect[1])).distance_to(Vector2(city.building(city.start_depots[0]).road)) if not city.start_depots.is_empty() else h
		if h < best_h:
			best_h = h
			best = p
	if best.is_empty():
		return
	landfill_pid = best.id
	var r := Rect2i(int(best.rect[0]), int(best.rect[1]), int(best.rect[2]), int(best.rect[3]))
	var mid := Vector2(r.position) + Vector2(r.size) * 0.5
	var far := Vector2(r.size).length() * 0.5
	var bestd := 999
	for y in range(r.position.y - 3, r.end.y + 3):
		for x in range(r.position.x - 3, r.end.x + 3):
			var q := Vector2i(x, y)
			if city.inside(q) and city.is_road(q):
				var d := int(Vector2(q).distance_to(mid))
				if d < bestd:
					bestd = d
					landfill_road = q
	for y in range(r.position.y + 1, r.end.y - 1):
		for x in range(r.position.x + 1, r.end.x - 1):
			var c := Vector2i(x, y)
			if city.building_at[city.idx(c)] >= 0 or city.is_road(c) or city.g(c) == CityData.G.WATER:
				continue
			landfill_cells[c] = clampf(1.0 - Vector2(c).distance_to(mid) / far, 0.15, 1.0)
	best.state = "privat_gehalten"
	best.use = "deponie"
	for c in landfill_cells:
		city.blocked[city.idx(c)] = 1
		sim.nav.walk.set_point_solid(c, true)
	city.trees = city.trees.filter(func(t): return not landfill_cells.has(t[0]))


func fill_share() -> float:
	return clampf(deposited / capacity, 0.0, 1.0)


func bin_capacity(bid: int) -> float:
	return maxf(MIN_BIN_KG, float(bin_rate.get(bid, 0.0)) * BIN_DAYS)


## Fassungsvermoegen einer Tonne: Restmuell fasst BIN_DAYS, Bio- und Wertstofftonne WERT_DAYS (ofterer Leerzyklus).
func _cap_of(stream: String, bid: int) -> float:
	var rt: Dictionary = {"rest": bin_rate, "bio": bio_rate, "wert": wert_rate}.get(stream, bin_rate)
	return maxf(MIN_BIN_KG, float(rt.get(bid, 0.0)) * (BIN_DAYS if stream == "rest" else WERT_DAYS))


## Inhalt (kg) eines Abfallstroms; bid = -1 bedeutet "Summe ueber alle Gebaeude".
func bin_level(stream: String, bid: int) -> float:
	if bid >= 0:
		return float({"rest": bins, "bio": bio, "wert": wert}.get(stream, bins).get(bid, 0.0))
	var out := 0.0
	for b in {"rest": bins, "bio": bio, "wert": wert}.get(stream, bins):
		out += float(b)
	return out


## Tonnen, die ueber ihr Fassungsvermoegen gefuellt sind (Stadt k oder alle), ueber alle drei Muellarten (Rest, Bio, Wertstoffe).
func overflowing(k: int = -1) -> Array:
	return bins.keys().filter(func(bid): return float(bins[bid]) > _cap_of("rest", bid) and (k < 0 or sim.towns.of_building(bid) == k)) \
		+ bio.keys().filter(func(bid): return float(bio[bid]) > _cap_of("bio", bid) and (k < 0 or sim.towns.of_building(bid) == k)) \
		+ wert.keys().filter(func(bid): return float(wert[bid]) > _cap_of("wert", bid) and (k < 0 or sim.towns.of_building(bid) == k))


## Anteil ueberquellender Tonnen (0..1) fuer die Versorgungszufriedenheit; Nenner = alle Toenen aller drei Muellarten.
func overflow_share() -> float:
	var n := bins.size() + bio.size() + wert.size()
	return float(overflowing().size()) / maxf(1.0, float(n))


## Abfall des Tages in die Toenen: Einwohner je Stadt verteilt nach bewohnten Wohnungen, Verpackung auf die geoeffneten Laeden.
## Ohne bewohnte Wohnung landet der Abfall der Stadt in der Tonne am Rathaus. Der Gesamtabsatz wird in die drei Muellarten
## (Rest, Bio, Wertstoffe) aufgeteilt (Auftrag 22 Phase 2 Schritt 2). Gibt die erzeugte Gesamtmenge (t) zurueck.
func _produce() -> float:
	var weights := {}   # Stadt -> {Gebaeude-ID: Wohnungen}
	for u in sim.housing.units.values():
		if str(u.get("tenant", "")) == "":
			continue
		var bid := int(u.building)
		var k: int = sim.towns.of_building(bid)
		if not weights.has(k):
			weights[k] = {}
		weights[k][bid] = int(weights[k].get(bid, 0)) + 1
	bin_rate = {}
	bio_rate = {}
	wert_rate = {}
	var made := 0.0
	for k in sim.towns.count():
		var kg := float(sim.citizens.population_of(k)) * KG_PER_PERSON_DAY
		var w: Dictionary = weights.get(k, {})
		if w.is_empty():
			var th := int(sim.towns.get_t(k).get("town_hall", -1))
			if th < 0 or kg <= 0.0:
				continue
			w = {th: 1}
		var sum := 0
		for bid in w:
			sum += int(w[bid])
		for bid in w:
			_put(bid, kg * float(w[bid]) / float(sum))
		made += kg
	var units: int = int(sim.retail.stats.units)
	var pack := float(units - _units_seen) * KG_PER_SALE
	_units_seen = units
	var shops: Array = sim.retail.shops.values().filter(func(s): return s.status == "offen")
	if pack > 0.0 and not shops.is_empty():
		for s in shops:
			_put(int(s.building), pack / float(shops.size()))
		made += pack
	return made / 1000.0


## Gesammelter Abfall (kg) eines Gebaeudes in die drei getrennten Toenen verteilen (Auftrag 22 Phase 2 Schritt 2):
## Rest (1-rate), Bio (rate * BIO_OF_RECYCLED) und Wertstoffe (der Rest). Ohne realen Abfallstrom (Einzel-/Kuestenwelt)
## bleibt der Bestand, wie bisher: alles in der Restmuelltone, die Waage berechnet die Restmenge aus der Recyclingquote.
func _put(bid: int, kg: float) -> void:
	if not real:
		bins[bid] = float(bins.get(bid, 0.0)) + kg
		bin_rate[bid] = float(bin_rate.get(bid, 0.0)) + kg
		return
	var rec := clampf(rate, 0.0, 1.0)
	bins[bid] = float(bins.get(bid, 0.0)) + kg * (1.0 - rec)
	bin_rate[bid] = float(bin_rate.get(bid, 0.0)) + kg * (1.0 - rec)
	bio[bid] = float(bio.get(bid, 0.0)) + kg * rec * BIO_OF_RECYCLED
	bio_rate[bid] = float(bio_rate.get(bid, 0.0)) + kg * rec * BIO_OF_RECYCLED
	var wert_kg := kg * rec * (1.0 - BIO_OF_RECYCLED)
	if wert_kg > 0.0:
		wert[bid] = float(wert.get(bid, 0.0)) + wert_kg
		wert_rate[bid] = float(wert_rate.get(bid, 0.0)) + wert_kg


func _dist(a: int, sb: Dictionary) -> int:
	var b: Dictionary = sim.city.building(a)
	return absi(int(b.x) - int(sb.x)) + absi(int(b.y) - int(sb.y))


## Muellwagen der Stadt k: so viele, dass der Tagesabfall (Haushalte und Verpackung) bei typischer Tourdauer abgefahren wird (+30 % Reserve).
func trucks_for(k: int) -> int:
	var need := _trucks_needed(k)
	var crews := crews_of(k)
	return need if crews < 0 else mini(need, crews)


## Betriebshof der Abfallwirtschaft (Municipal AW-01) der Stadt k, sonst {} (dann holt ein Entsorger gegen Gebuehr ab, Wagen vom Rathaus).
func depot_of(k: int) -> Dictionary:
	if sim.municipal == null or not sim.municipal.enabled():
		return {}
	for f in sim.municipal.of_town(k, "abfall"):
		if str(f.code) == "AW-01" and f.status == "in_betrieb":
			return f
	return {}


## Einsatzbereite Muellwagen mit voller Besatzung (Fahrer + 2 Lader = Vehicles.crew) am Betriebshof; -1 ohne Betriebshof.
func crews_of(k: int) -> int:
	var f := depot_of(k)
	if f.is_empty():
		return -1
	var M: Municipal = sim.municipal
	var trucks: int = f.vehicles.filter(func(v): return str(M.vehicles[v].type) == "Müllwagen" and M.vehicles[v].status != "ausser_dienst" and int(M.vehicles[v].driver) >= 0).size()
	return mini(trucks, M.staff_count(f.id, "muellwerker") / int(Municipal.VEHICLES["Müllwagen"].crew))


## Reicht der Fuhrpark nicht und ist Personal fuer einen weiteren Wagen da, kauft die Stadt einen Muellwagen (Kasse -> Hersteller X0).
func _fleet_upkeep(k: int) -> void:
	var f := depot_of(k)
	if f.is_empty():
		return
	var M: Municipal = sim.municipal
	var n: int = f.vehicles.filter(func(v): return str(M.vehicles[v].type) == "Müllwagen").size()
	var price := float(Municipal.VEHICLES["Müllwagen"].price)
	var acct := Towns.account_of(k)
	if _trucks_needed(k) <= n or n >= MAX_TRUCKS or M.staff_count(f.id, "muellwerker") < (n + 1) * int(Municipal.VEHICLES["Müllwagen"].crew) 			or float(sim.economy.accounts.get(acct, 0.0)) < 2.0 * price:
		return
	sim.economy.transfer(acct, "X0", price)
	var v := M.add_vehicle(f.id, "Müllwagen")
	sim.activity.add("stadt", -1, "kauf", "%s kauft einen Müllwagen" % sim.towns.name_of(k), "%s · %s" % [v.label, Catalog.money(price)], sim.city.building(int(f.building)).road)


## Bedarf an Muellwagen der Stadt k (ohne Ruecksicht auf Fuhrpark und Personal).
func _trucks_needed(k: int) -> int:
	var kg := 0.0
	for bid in bin_rate:
		if sim.towns.of_building(bid) == k:
			kg += float(bin_rate[bid])
	var t_day := kg / 1000.0
	return clampi(ceili(t_day * TRIP_DAYS / TRUCK_TONS * 1.3), 1, MAX_TRUCKS)


## Tonne der Stadt k im Abfallstrom `stream` (rest|wert) voll genug fuer die Abfuhr und noch keiner Tour zugeteilt?
func _due(stream: String, bid: int, k: int) -> bool:
	if _planned.has(bid) or sim.towns.of_building(bid) != k or sim.city.building(bid).is_empty():
		return false
	return _stream_level(stream, bid) >= COLLECT_AT * _stream_cap(stream, bid)


## Inhalt (kg) und Fassungsvermoegen der Tonne im Strom `stream`: rest = Resttonne, wert = Wertstofftonnen (Bio + Wertstoffe).
func _stream_level(stream: String, bid: int) -> float:
	if stream == "rest":
		return float(bins.get(bid, 0.0))
	return float(bio.get(bid, 0.0)) + float(wert.get(bid, 0.0))


func _stream_cap(stream: String, bid: int) -> float:
	if stream == "rest":
		return bin_capacity(bid)
	return _cap_of("bio", bid) + _cap_of("wert", bid)


## Touren je Stadt: die vollste Tonne ist der erste Halt; von dort faehrt der Wagen jeweils die naechstgelegene volle Tonne an,
## bis die Ladung voll ist (Nachbarschaftsroute statt Zickzack; die Fahrt lohnt sich nur mit voller Ladung).
## Restmuell faehrt zur Deponie (stream "rest"); Bio und Wertstoffe fahren gemeinsam zur Wertstoffsammlung (stream "wert")
## und werden am Recyclinghof sortiert (Auftrag 22 Phase 2 Schritt 2).
func _dispatch() -> void:
	if landfill_road.x < 0:
		return
	for k in sim.towns.count():
		_dispatch_stream(k, "rest")
		if real:
			_dispatch_stream(k, "wert")


func _dispatch_stream(k: int, stream: String) -> void:
	var dest: Vector2i = landfill_road
	var tons: float = TRUCK_TONS
	if stream == "wert":
		var y := yard_of(k)
		if y.is_empty():
			return
		dest = sim.city.building(int(y.building)).road
		tons = WERT_TONS
	var cand: Array = (bins.keys() if stream == "rest" else wert.keys()).filter(func(bid): return _due(stream, bid, k))
	cand.sort_custom(func(a, b): return _stream_level(stream, a) / _stream_cap(stream, a) > _stream_level(stream, b) / _stream_cap(stream, b))
	while not cand.is_empty():
		var seed_b: Dictionary = sim.city.building(cand[0])
		var pool: Array = cand.duplicate()
		var stops: Array = []
		var kg := 0.0
		var at: Dictionary = seed_b
		while not pool.is_empty() and stops.size() < STOPS:
			var here: Dictionary = at
			var bid: int = pool.reduce(func(best, x): return x if _dist(x, here) < _dist(best, here) else best, pool[0])
			if not stops.is_empty() and kg + _stream_level(stream, bid) > tons * 1000.0:
				break
			pool.erase(bid)
			at = sim.city.building(bid)
			stops.append({"road": at.road, "building": bid})
			kg += _stream_level(stream, bid)
		if kg < MIN_LOAD * tons * 1000.0 and _stream_level(stream, cand[0]) < URGENT * _stream_cap(stream, cand[0]):
			break   # lohnt die Fahrt noch nicht und keine Tonne droht ueberzulaufen
		var dep := depot_of(k)
		var home: Vector2i = sim.city.building(int(dep.building)).road if not dep.is_empty() else Vector2i(-1, -1)
		var label := "Wertstoffsammlung %s %d" % [sim.towns.name_of(k), tours_wert + 1] if stream == "wert" \
			else "%s Tour %d" % [str(dep.name) if not dep.is_empty() else "Müllabfuhr " + sim.towns.name_of(k), tours + 1]
		if not sim.fleet.send_garbage(stops, dest, tons, label, k, home, stream):
			break
		if stream == "wert":
			tours_wert += 1
		else:
			tours += 1
		for st in stops:
			_planned[int(st.building)] = true
			cand.erase(int(st.building))


## Recyclinghof (RC-01) der Stadt k, sonst {} (dann bleibt der Wertstoffstrom in der Tour-Liste und wird nicht abgeholt).
func yard_of(k: int) -> Dictionary:
	if sim.municipal == null or not sim.municipal.enabled():
		return {}
	for f in sim.municipal.of_town(k, "recycling"):
		if str(f.code) == "RC-01" and f.status == "in_betrieb":
			return f
	return {}


## Halt eines Muellwagens: Resttonne leeren, hoechstens room_kg. Gibt die geladenen kg zurueck.
func empty_bin(bid: int, room_kg: float) -> float:
	_planned.erase(bid)
	var take := minf(float(bins.get(bid, 0.0)), maxf(0.0, room_kg))
	if take > 0.0:
		bins[bid] = float(bins[bid]) - take
	return take


## Halt des Wertstoffwagens: Bio- und Wertstofftonne am Haus leeren (proportional zum Füllstand), zusammen hochstens room_kg.
func empty_wert(bid: int, room_kg: float) -> float:
	_planned.erase(bid)
	var b := float(bio.get(bid, 0.0))
	var w := float(wert.get(bid, 0.0))
	var tot := b + w
	if tot <= 0.0:
		return 0.0
	var take := minf(tot, maxf(0.0, room_kg))
	var sh := take / tot
	bio[bid] = float(bio[bid]) - b * sh
	wert[bid] = float(wert[bid]) - w * sh
	if float(bio[bid]) < 0.0:
		bio[bid] = 0.0
	if float(wert[bid]) < 0.0:
		wert[bid] = 0.0
	return take


## Wagen voll oder Tour abgebrochen: zugeteilte Tonnen wieder freigeben.
func release(bids: Array) -> void:
	for bid in bids:
		_planned.erase(int(bid))


## Abladen der Wertstoffe am Recyclinghof (Bio + Wertstoffe): die Stadt liefert ab, der Hof sortiert (Recycling.deliver)
## und rechnet die Abfuhr und den Sortierwert ab. Geld und Waren bleiben erhalten.
func deliver_wert(k: int, tons: float) -> void:
	if tons <= 0.0:
		return
	var acct := Towns.account_of(k)
	# eigene Wertstoffwirtschaft: Abholung durch den Betriebshof (Loehne/Fahrzeuge ueber Municipal), sonst Entsorger S0
	var cost := (0.0 if not depot_of(k).is_empty() else tons * COLLECT_COST)
	var pay := minf(cost, maxf(0.0, float(sim.economy.accounts.get(acct, 0.0))))
	if pay > 0.0:
		sim.economy.transfer(acct, "S0", pay)
	_unpaid += cost - pay
	if sim.recycling != null:
		sim.recycling.deliver(k, tons * 1000.0)
	var tk: Dictionary = _town_stats(k)
	for d in [month, total, tk.month, tk.total]:
		d.tons = float(d.tons) + tons
		d.cost = float(d.cost) + pay
	scale_log.append({"tag": GameCalendar.day_of(sim.game_min), "stadt": k, "t": tons, "rest": 0.0, "art": "wert"})
	if scale_log.size() > SCALE_LOG:
		scale_log = scale_log.slice(-SCALE_LOG)


## Waage der Deponie: Menge der Stadt k erfassen und Kosten der Stadtkasse buchen.
## Ohne eigene Wertstoffwirtschaft (Einzel-/Kuestenwelt): wie bisher, Wertstoffe laufen pauschal ueber die Recyclingquote.
## Eigene Wertstoffwirtschaft (real): hier landen nur die Reststoffe; Bio/Wertstoffe gehen ueber deliver_wert zum Hof.
## Muellverbrennung (Schritt 4): in Betrieb verbrannt die Anlage den Restmuell (Strom, Asche), nur die Asche wird deponiert.
func weigh_in(k: int, tons: float) -> void:
	if tons <= 0.0:
		return
	if not real:
		var recycled := tons * rate
		var residual := tons - recycled
		deposited += residual
		var acct := Towns.account_of(k)
		# eigener Betriebshof: Abholung leisten Muellwerker und Fuhrpark der Stadt (Loehne/Fahrzeugkosten ueber Municipal), sonst Entsorger S0
		var cost := (0.0 if not depot_of(k).is_empty() else tons * COLLECT_COST) + residual * DISPOSAL_COST
		var income := recycled * RECYCLE_INCOME
		var pay := minf(cost, maxf(0.0, float(sim.economy.accounts.get(acct, 0.0))))
		sim.economy.transfer(acct, "S0", pay)            # Entsorger holt ab und behandelt
		_unpaid += cost - pay
		sim.economy.transfer("X0", acct, income)         # Wertstoffe gehen in den Verkauf
		var tk: Dictionary = _town_stats(k)
		for d in [month, total, tk.month, tk.total]:
			d.tons = float(d.tons) + tons
			d.recycled = float(d.recycled) + recycled
			d.cost = float(d.cost) + pay
			d.income = float(d.income) + income
		scale_log.append({"tag": GameCalendar.day_of(sim.game_min), "stadt": k, "t": tons, "rest": residual})
		if scale_log.size() > SCALE_LOG:
			scale_log = scale_log.slice(-SCALE_LOG)
		return
	# real: reine Restmüll-Waage; die Wertstoffe sind schon im Hof verbucht
	var burn := _iv_burn(k, tons)
	var ash := tons if burn <= 0.0 else tons * IV_ASH   # ohne Anlage: alles deponiert; mit Anlage: nur die Asche
	deposited += ash
	iv_new_t += ash
	var acct2 := Towns.account_of(k)
	var cost2 := (0.0 if not depot_of(k).is_empty() else tons * COLLECT_COST) + ash * DISPOSAL_COST + burn * IV_PROC_PER_T
	var pay2 := minf(cost2, maxf(0.0, float(sim.economy.accounts.get(acct2, 0.0))))
	sim.economy.transfer(acct2, "S0", pay2)
	_unpaid += cost2 - pay2
	var tk2: Dictionary = _town_stats(k)
	for d in [month, total, tk2.month, tk2.total]:
		d.tons = float(d.tons) + tons
		d.cost = float(d.cost) + pay2
	scale_log.append({"tag": GameCalendar.day_of(sim.game_min), "stadt": k, "t": tons, "rest": ash, "verbrannt": burn})
	if scale_log.size() > SCALE_LOG:
		scale_log = scale_log.slice(-SCALE_LOG)


## Muellverbrennung (Schritt 4): in Betrieb wird der angelieferte Restmuell verbrannt (Strom IV_KWH_PER_T je Tonne, kein
## Brennstoff, der Muell ist ohnehin da). Der Stromerlös (kwh * Tarif) wird in iv_stats.erloes gefuehrt; die Leistung selbst fliest
## ueber iv_available_kw() ins Netz (PowerGrid._allocate), wo sie Notstrom-Bezug verdrangt. Die Menge wird je Tag akkumuliert
## und von _iv_daily in iv_last gewaellt (Netzanschluss, Anzeige).
func _iv_burn(k: int, tons: float) -> float:
	if not _iv_on():
		return 0.0
	var kwh := tons * IV_KWH_PER_T
	_iv_acc.t = float(_iv_acc.t) + tons
	_iv_acc.ash = float(_iv_acc.ash) + tons * IV_ASH
	_iv_acc.kwh = float(_iv_acc.kwh) + kwh
	iv_stats.t = float(iv_stats.t) + tons
	iv_stats.ash = float(iv_stats.ash) + tons * IV_ASH
	iv_stats.kwh = float(iv_stats.kwh) + kwh
	iv_stats.erloes = float(iv_stats.erloes) + kwh * sim.grid.tariff
	return tons


## Anlage ist gebaut und in Betrieb (MV-01, ab dem Inbetriebnahmetag)?
func _iv_on() -> bool:
	return iv_fertig > 0 and GameCalendar.day_of(sim.game_min) >= iv_fertig and _iv_fac() != {}


func _iv_fac() -> Dictionary:
	if iv_fac == "" or sim.municipal == null:
		return {}
	return sim.municipal.facilities.get(iv_fac, {})


## Netzanschluss der Verbrennungsanlage (kW) aus dem letzten abgeschlossenen Tag (iv_last); 0 ohne Anlage.
func iv_available_kw() -> float:
	if iv_fertig == 0 or not _iv_fac().has("building") or int(iv_last.day) < 0:
		return 0.0
	return float(iv_last.kwh) / (GameCalendar.day_game_min / 60.0)


## Tageslauf der Verbrennung (am Tagesende, nach Abfuhr und Erweiterung): bei IV_BUILD_T Restmuell beschliesst die Region
## den Bau, der Bauplatz wird neben der Deponie gesucht, nach IV_DAYS wird die Anlage in Betrieb genommen; der abgelaufene
## Tag wird zuletzt in iv_last gewaellt (Netzanschluss und Anzeige), auch nachdem sie laeuft.
func _iv_daily(day: int) -> void:
	if iv_fertig > 0 and day >= iv_fertig:
		if iv_building > 0:   # Inbetriebnahme melden
			iv_building = 0
			sim.log_event("Die Müllverbrennungsanlage ist in Betrieb: 90 %% des Restmülls werden verbrannt (Strom %d kWh/t), Asche bleibt auf der Deponie." % int(IV_KWH_PER_T), "good")
	elif iv_building > 0 and iv_fertig == 0:   # beschlossen: Bauplatz neben der Deponie suchen und errichten
		if _iv_find_site():
			_iv_build(day)
		elif day >= iv_retry:
			iv_retry = day + 7
			sim.log_event("Noch kein freies städtisches Grundstück neben der Deponie für die Müllverbrennungsanlage – die Suche wird in 7 Tagen wiederholt.", "warn")
	elif real and iv_new_t >= IV_BUILD_T:
		_iv_building(day)
	if day > int(iv_last.day):   # Vortag abschliessen (Menge fuer Netzanschluss und Anzeige; auch nach Spruengen)
		iv_last = {"t": float(_iv_acc.t), "ash": float(_iv_acc.ash), "kwh": float(_iv_acc.kwh), "day": day - 1}
		_iv_acc = {"t": 0.0, "ash": 0.0, "kwh": 0.0}


## Baubeschluss der Region (Kassenanteil nach den bisher gewogenen Mengen; S0 als Trägerschaftskonto): die Anlage soll
## neben der Deponie entstehen; den Bauplatz findet _iv_daily, errichtet wird sofort danach.
func _iv_building(day: int) -> void:
	if sim.municipal == null or not sim.municipal.enabled():
		return
	iv_building = day
	iv_retry = day
	sim.log_event("Die Region beschließt eine gemeinsame Müllverbrennungsanlage neben der Deponie (%s, Bauzeit %d Tage; Kosten nach den Abfallmengen der Städte)." % [
		Catalog.money(float(Municipal.TYPES["MV-01"].cost)), IV_DAYS], "info")


## Bauplatz neben der Deponie: das freie städtische Grundstück im Umkreis der Deponie mit Straßenanschluss, das der
## Deponieflaeche am naechsten ist (5x4 Felder). Findet einen: true (in _iv_site).
func _iv_find_site() -> bool:
	_iv_site = {}
	if landfill_cells.is_empty():
		return false
	var rect := Rect2i(landfill_cells.keys()[0], landfill_cells.keys()[0] + Vector2i(1, 1))
	for c in landfill_cells:
		var r2 := Rect2i(c, c + Vector2i(1, 1))
		rect = Rect2i(Vector2i(mini(rect.position.x, r2.position.x), mini(rect.position.y, r2.position.y)),
			Vector2i(maxi(rect.end.x, r2.end.x) - rect.position.x, maxi(rect.end.y, r2.end.y) - rect.position.y))
	var W: int = int(CityGenerator.TYPES["incineration_plant"][1])
	var H: int = int(CityGenerator.TYPES["incineration_plant"][2])
	var best := 1 << 30
	for p in sim.parcels.items.values():
		if p.state != "frei" or not Towns.is_public(str(p.owner)) or int(p.area) < W * H:
			continue
		if not sim.parcels.is_buildable(p) or str(p.zone) in ["korridor", "industrie"]:
			continue
		var pr := Rect2i(int(p.rect[0]), int(p.rect[1]), int(p.rect[2]), int(p.rect[3]))
		if pr.size.x < W or pr.size.y < H or _gap(pr, rect) > 16:
			continue
		for y in range(pr.position.y, pr.end.y - H + 1):
			for x in range(pr.position.x, pr.end.x - W + 1):
				var r := Rect2i(x, y, W, H)
				if not sim.civic._cells_free(r) or not sim.civic._touches_road(r):
					continue
				var d: int = _gap(r, rect)
				if d < best:
					best = d
					_iv_site = {"rect": [r.position.x, r.position.y, W, H], "parcel": str(p.id)}
	if _iv_site.is_empty():
		return false
	_iv_site["costs"] = _iv_shares()
	return true


## Naechster Abstand (in Feldern) zwischen zwei Rechtecken: 0, wenn sie sich beruehren oder ueberlappen, sonst der
## Lueckenschmalste Abstand (Godot hat fuer Rechtecke keine distance_to-Methode).
static func _gap(a: Rect2i, b: Rect2i) -> int:
	var gx := maxi(0, maxi(b.position.x - a.end.x, a.position.x - b.end.x))
	var gy := maxi(0, maxi(b.position.y - a.end.y, a.position.y - b.end.y))
	return maxi(gx, gy)


## Baupreis je Stadt nach den bisher gewogenen Mengen (Kassenanteil; S0 als Trägerschaftskonto).
func _iv_shares() -> Dictionary:
	var out := {}
	var sum := 0.0
	for k in sim.towns.count():
		out[str(k)] = float(_town_stats(k).total.tons)
		sum += float(out[str(k)])
	for k in out:
		out[str(k)] = float(out[k]) / sum if sum > 0.0 else 1.0 / float(out.size())
	return out


## Gebäude errichten (Gebäude- und Grundstücksstatus wie bei den Diensten), Einrichtung MV-01 registrieren; nach IV_DAYS
## in Betrieb. Die Kassen der Städte zahlen ihren Anteil des Baupreises (S0 als Trägerschaftskonto).
func _iv_build(day: int) -> void:
	var r := Rect2i(int(_iv_site.rect[0]), int(_iv_site.rect[1]), int(_iv_site.rect[2]), int(_iv_site.rect[3]))
	var b: Dictionary = sim.events._add_building("incineration_plant", r, "Müllverbrennungsanlage")
	if b.is_empty():
		return
	var p: Dictionary = sim.parcels.parcel(str(_iv_site.parcel))
	if not p.is_empty():
		p.state = "bebaut"
		p.use = "incineration_plant"
		p.building = int(b.id)
		sim.parcels.touch(str(p.id))
	var k := 0
	for t in sim.towns.list:   # Trägerstadt: die Abfallmeiste (Name/Lage der Anlage)
		if sim.citizens.population_of(int(t.id)) > sim.citizens.population_of(k):
			k = int(t.id)
	var f: Dictionary = sim.municipal.register(k, "MV-01", int(b.id))
	if f.is_empty():
		return
	var shares: Dictionary = _iv_site.get("costs", _iv_shares())
	f["shares"] = shares
	f.owner = "region"
	var cost := float(Municipal.TYPES["MV-01"].cost)
	var parts: Array = []
	for sk in shares:
		var part := cost * float(shares[sk])
		var acct := Towns.account_of(int(sk))
		var pay := minf(part, maxf(0.0, float(sim.economy.accounts.get(acct, 0.0))))
		sim.economy.transfer(acct, "S0", pay)
		_unpaid += part - pay
		parts.append("%s %s" % [sim.towns.name_of(int(sk)), Catalog.money(part)])
	iv_fac = str(f.id)
	iv_fertig = day + IV_DAYS
	sim.events.buildings_added.emit([b.id])
	sim.log_event("%s errichtet die Müllverbrennungsanlage am Deponiestrand (fertig in %d Tagen; Baukosten: %s)." % [sim.towns.name_of(k), IV_DAYS, ", ".join(parts)], "info")


func _town_stats(k: int) -> Dictionary:
	var key := str(k)
	if not by_town.has(key):
		by_town[key] = {"month": {"tons": 0.0, "recycled": 0.0, "cost": 0.0, "income": 0.0}, "total": {"tons": 0.0, "recycled": 0.0, "cost": 0.0, "income": 0.0, "fees": 0.0}}
	return by_town[key]


## Erweiterung der Deponie: Start ab EXPAND_AT Fuellstand, Kosten nach den bisher gewogenen Mengen je Stadt, fertig nach EXPAND_DAYS.
func _check_expansion(day: int) -> void:
	if not expansion.is_empty():
		if day >= int(expansion.fertig):
			capacity += float(expansion.t)
			expansions += 1
			sim.log_event("Deponie erweitert: Fassungsvermögen jetzt %.0f t (Füllstand %d %%)." % [capacity, roundi(fill_share() * 100.0)], "info")
			expansion = {}
		return
	if fill_share() < EXPAND_AT:
		return
	var shares := {}
	var sum := 0.0
	for k in sim.towns.count():
		shares[k] = float(_town_stats(k).total.tons)
		sum += float(shares[k])
	var parts: Array = []
	for k in shares:
		var part := EXPAND_COST * (float(shares[k]) / sum if sum > 0.0 else 1.0 / float(shares.size()))
		var acct := Towns.account_of(k)
		var pay := minf(part, maxf(0.0, float(sim.economy.accounts.get(acct, 0.0))))
		sim.economy.transfer(acct, "S0", pay)
		_unpaid += part - pay
		parts.append("%s %s" % [sim.towns.name_of(k), Catalog.money(part)])
	expansion = {"start": day, "fertig": day + EXPAND_DAYS, "t": EXPAND_T, "kosten": EXPAND_COST}
	sim.log_event("Deponie zu %d %% voll – Erweiterung um %.0f t beginnt (fertig in %d Tagen; Kosten nach Liefermengen: %s)." % [
		roundi(fill_share() * 100.0), EXPAND_T, EXPAND_DAYS, ", ".join(parts)], "warn")


## Anteil der Getraenkeflaschen, die als Mehrweg zurueckkommen (0..1).
func mehrweg_share() -> float:
	var sold := int(sim.retail.stats.bottles_sold)
	return 0.0 if sold <= 0 else clampf(float(sim.retail.stats.bottles_returned) / float(sold), 0.0, 1.0)


func on_day(day: int) -> void:
	rate = BASE_RECYCLING + MEHRWEG_BONUS * mehrweg_share()
	var first := bins.is_empty()
	_produce()
	for k in sim.towns.count():
		_fleet_upkeep(k)
	if first:   # Spielbeginn: die Tonnen sind unterschiedlich voll (wie die vorhandene Deponie), damit die Abfuhr gleich Arbeit hat
		for bid in bins:
			bins[bid] = float(bins[bid]) + bin_capacity(bid) * float(absi(hash([sim.city.seed_value, bid, "tonne"])) % 80) / 100.0
		if real:
			for bid in bio:
				bio[bid] = float(bio[bid]) + _cap_of("bio", bid) * float(absi(hash([sim.city.seed_value, bid, "bio"])) % 80) / 100.0
			for bid in wert:
				wert[bid] = float(wert[bid]) + _cap_of("wert", bid) * float(absi(hash([sim.city.seed_value, bid, "wert"])) % 80) / 100.0
	_dispatch()
	overflow_days += overflowing().size()
	_check_expansion(day)
	_iv_daily(day)


func on_month(_m: int) -> void:
	# Gebuehr je Stadt: die Haushalte tragen die Kosten des abgelaufenen Monats (plus Aufschlag), abzueglich Wertstofferloes
	var due_all := 0.0
	for key in by_town:
		var tm: Dictionary = by_town[key].month
		var due: float = maxf(0.0, (float(tm.cost) - float(tm.income)) * FEE_MARKUP)
		if due > 0.0:
			sim.economy.transfer("H0", Towns.account_of(int(key)), due)
			by_town[key].total.fees = float(by_town[key].total.fees) + due
			due_all += due
		by_town[key].month = {"tons": 0.0, "recycled": 0.0, "cost": 0.0, "income": 0.0}
	total.fees += due_all
	last_month = month.duplicate()
	last_month["fee"] = due_all
	last_month["quote"] = float(month.recycled) / maxf(0.001, float(month.tons))
	last_month["ueberquellend"] = overflowing().size()
	sim.log_event("Müllabfuhr: %.1f t gewogen, Recyclingquote %d %% (Mehrweg %d %%), Gebühr %s, %d Tonnen quellen über." % [float(month.tons),
		roundi(float(last_month.quote) * 100.0), roundi(mehrweg_share() * 100.0), Catalog.money(due_all), int(last_month.ueberquellend)], "info")
	month = {"tons": 0.0, "recycled": 0.0, "cost": 0.0, "income": 0.0}


func to_dict() -> Dictionary:
	var b := {}
	var b2 := {}
	var b3 := {}
	for bid in bins:
		b[str(bid)] = bins[bid]
	for bid in bio:
		b2[str(bid)] = bio[bid]
	for bid in wert:
		b3[str(bid)] = wert[bid]
	return {"month": month, "total": total, "rate": rate, "last": last_month, "units_seen": _units_seen, "unpaid": _unpaid, "deposited": deposited, "tours": tours,
		"capacity": capacity, "bins": b, "bio": b2, "wert": b3, "by_town": by_town.duplicate(true), "scale_log": scale_log.duplicate(true), "expansion": expansion.duplicate(),
		"expansions": expansions, "overflow_days": overflow_days, "iv_building": iv_building, "iv_fertig": iv_fertig, "iv_retry": iv_retry, "iv_new_t": iv_new_t,
		"iv_fac": iv_fac, "iv_stats": iv_stats.duplicate(), "iv_last": iv_last.duplicate()}


func from_dict(d: Dictionary) -> void:
	if d.is_empty():
		return
	for k in d.get("month", {}):
		month[k] = float(d.month[k])
	for k in d.get("total", {}):
		total[k] = float(d.total[k])
	rate = float(d.get("rate", BASE_RECYCLING))
	last_month = d.get("last", {})
	_units_seen = int(d.get("units_seen", 0))
	_unpaid = float(d.get("unpaid", 0.0))
	deposited = float(d.get("deposited", deposited))
	tours = int(d.get("tours", 0))
	capacity = float(d.get("capacity", LANDFILL_CAPACITY))
	bins = {}
	for key in d.get("bins", {}):
		bins[int(key)] = float(d.bins[key])
	bio = {}
	for key in d.get("bio", {}):
		bio[int(key)] = float(d.bio[key])
	wert = {}
	for key in d.get("wert", {}):
		wert[int(key)] = float(d.wert[key])
	by_town = d.get("by_town", {})
	scale_log = d.get("scale_log", [])
	expansion = d.get("expansion", {})
	expansions = int(d.get("expansions", 0))
	overflow_days = int(d.get("overflow_days", 0))
	iv_building = int(d.get("iv_building", 0))
	iv_fertig = int(d.get("iv_fertig", 0))
	iv_retry = int(d.get("iv_retry", 0))
	iv_fac = str(d.get("iv_fac", ""))
	iv_new_t = float(d.get("iv_new_t", 0.0))
	for k in d.get("iv_stats", {}):
		iv_stats[k] = float(d.iv_stats[k])
	iv_last = d.get("iv_last", iv_last)
	_iv_site = {}
	_planned = {}   # Muellwagen werden nicht gespeichert: laufende Touren entfallen, die Tonnen bleiben voll und werden neu angefahren
