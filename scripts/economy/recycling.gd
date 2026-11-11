class_name Recycling
extends RefCounted
## Recycling (Auftrag 20, Etappe 9, docs/PUBLIC_SERVICES.md). Ein Recyclinghof (RC-01, Municipal) sortiert die Wertstoffe seiner Stadt:
##  - Wertstoffmenge je Tag = Muell der Stadt (Einwohner x Waste.KG_PER_PERSON_DAY) x Recyclingquote (Waste.rate) + 15 % zusaetzlich
##    getrennter Abfall (vorher Restmuell; die Deponie fuellt sich langsamer). Verarbeitung bis zur Kapazitaet (t/Tag nach Personal).
##  - Stroeme: Papier 35 %, Glas 20 %, Kunststoff 20 %, Metall 10 %, Bioabfall 15 % -> Sekundaerrohstoffe als echte Ware im Warenbuch
##    (Altpapier, Altglas, Kunststoffgranulat, Stahlschrott, Kompost; je Einheit 100 kg) im Bestand des Recyclinghofs (Eigentum Stadt).
##  - Einmal je Woche faehrt der Wertstoffwagen sichtbar zum Grosslager: Stahlschrott geht in den Grosslagerbestand (Konto L0 zahlt den
##    Ankaufspreis an die Stadt; Stahlwerke kaufen ihn dort), die uebrigen Stoffe nimmt ein Verwerter ausserhalb ab (Ausfuhr X0 ->
##    Stadtkasse, Ausfuhrpreis laut Artikeldaten).

const FRACTIONS := {"altpapier": 0.35, "altglas": 0.20, "kunststoffgranulat": 0.20, "schrott": 0.10, "kompost": 0.15}
const EXTRA_SORTING := 0.15
const T_PER_STAFF := 1.0           # Tonnen je Tag und Mitarbeiter
const UNIT_T := 0.1                # 100 kg je Einheit
const TRIP_EVERY := 7
const SPEED := 3.0

var sim
var carry := {}          # "Stadt|Artikel" -> Bruchteil einer Einheit
var trips := {}          # Fahrzeug-ID -> {town, facility, phase, load}
var movers := {}
var stats := {"tonnen": 0.0, "umgeleitet_t": 0.0, "einheiten": {}, "erloes": 0.0, "an_grosslager": 0}
var _day := -1
var _day_done := {}      # Einrichtung-ID -> verarbeitete Tonnen des Tages (Kapazitaet bei realen Muellarten)


func setup(simulation) -> void:
	sim = simulation
	if sim.municipal != null and sim.municipal.enabled():
		sim.day_changed.connect(on_day)


func yards(k: int = -1) -> Array:
	return sim.municipal.facilities.values().filter(func(f): return f.code == "RC-01" and f.status == "in_betrieb" and (k < 0 or int(f.town) == k))


func capacity_t(f: Dictionary) -> float:
	return T_PER_STAFF * float(sim.municipal.staff_count(f.id))


func on_day(day: int) -> void:
	if day == _day:
		return
	_day = day
	_day_done = {}
	if sim.waste.real:   # echte Muellarten (Region): die Zulieferung kommt ueber deliver() mit dem Wertstoffwagen
		for f in yards():
			if day % TRIP_EVERY == 0:
				_start_trip(f)
		return
	for f in yards():
		var k := int(f.town)
		var tons := float(sim.citizens.population_of(k)) * Waste.KG_PER_PERSON_DAY / 1000.0
		var input := tons * (float(sim.waste.rate) + EXTRA_SORTING)
		var done := minf(input, capacity_t(f))
		var extra := minf(done, tons * EXTRA_SORTING)
		sim.waste.deposited = maxf(0.0, float(sim.waste.deposited) - extra)   # zusaetzlich getrennt statt auf die Deponie
		stats.tonnen = float(stats.tonnen) + done
		stats.umgeleitet_t = float(stats.umgeleitet_t) + extra
		for item in FRACTIONS:
			var key := "%d|%s" % [k, item]
			carry[key] = float(carry.get(key, 0.0)) + done * float(FRACTIONS[item]) / UNIT_T
			var n := int(carry[key])
			if n > 0:
				carry[key] = float(carry[key]) - n
				sim.stock.add(item, n, Towns.owner_of(k), int(f.building), "Recyclinghof %s" % f.name, sim.game_min)
				stats.einheiten[item] = int(stats.einheiten.get(item, 0)) + n
		if day % TRIP_EVERY == 0:
			_start_trip(f)


## Ablieferung der Wertstoffe (Bio + Wertstoffe) vom Wertstoffwagen (Waste.deliver_wert): sortiert nach den Stroemen,
## begrenzt auf die Tageskapazitaet des Hofs und legt die Sekundaerrohstoffe als echte Ware in den Hofbestand (Eigentum Stadt).
## Die Abfuhr rechnet Waste.deliver_wert separat ab; der Verwertungspreis kommt bei der woechentlichen Abholung (trip).
func deliver(k: int, kg: float) -> void:
	if kg <= 0.0:
		return
	var y: Array = yards(k)
	if y.is_empty():
		return   # kein Hof in Betrieb: Lieferung wird nicht entgegengenommen
	var f: Dictionary = y[0]
	var done := minf(kg / 1000.0, maxf(0.0, capacity_t(f) - float(_day_done.get(f.id, 0.0))))
	_day_done[f.id] = float(_day_done.get(f.id, 0.0)) + done
	if done <= 0.0:
		return
	stats.tonnen = float(stats.tonnen) + done
	# 40 % der angelieferten Menge ist Bio (Waste.BIO_OF_RECYCLED) und wird Kompost; der Rest laeuft ueber die Sortierstroeme
	var bio_sh := Waste.BIO_OF_RECYCLED
	for item in FRACTIONS:
		var share: float = float(FRACTIONS[item])
		if item == "kompost":
			share += bio_sh * (1.0 - float(FRACTIONS["kompost"]))
		var key := "%d|%s" % [k, item]
		carry[key] = float(carry.get(key, 0.0)) + done * share / UNIT_T
		var n := int(carry[key])
		if n > 0:
			carry[key] = float(carry[key]) - n
			sim.stock.add(item, n, Towns.owner_of(k), int(f.building), "Recyclinghof %s" % f.name, sim.game_min)
			stats.einheiten[item] = int(stats.einheiten.get(item, 0)) + n


func _start_trip(f: Dictionary) -> void:
	var M: Municipal = sim.municipal
	var vid := ""
	for v in f.vehicles:
		if str(M.vehicles[v].type) == "Wertstoffwagen" and M.vehicles[v].status == "bereit" and int(M.vehicles[v].driver) >= 0:
			vid = v
	if vid == "" or trips.has(vid):
		return
	var load := {}
	for item in FRACTIONS:
		var n: int = sim.stock.available(item, Towns.owner_of(int(f.town)), int(f.building))
		if n > 0:
			load[item] = n
	if load.is_empty():
		return
	M.vehicles[vid].status = "im_einsatz"
	trips[vid] = {"town": int(f.town), "facility": f.id, "phase": "hin", "load": load}
	sim.route(mover_of(vid), _hub_road(f))


func _hub_road(f: Dictionary) -> Vector2i:
	if sim.hub != null and sim.hub.enabled and sim.hub.loc >= 0:
		return sim.city.building(int(sim.hub.loc)).road
	return sim.city.building(int(f.building)).road


func mover_of(vid: String) -> Mover:
	if not movers.has(vid):
		var M: Municipal = sim.municipal
		var mv := Mover.new()
		mv.speed = SPEED
		mv.pos = sim.city.tile_center(sim.city.building(M.building_of(str(M.vehicles[vid].facility))).road)
		movers[vid] = mv
	return movers[vid]


func update(dt: float) -> void:
	for vid in trips.keys():
		var tr: Dictionary = trips[vid]
		var mv := mover_of(vid)
		if not mv.arrived():
			mv.advance(dt, 1.0)
			continue
		if tr.phase == "hin":
			_deliver(tr)
			tr.phase = "zurueck"
			sim.route(mv, sim.city.building(sim.municipal.building_of(str(tr.facility))).road)
		else:
			sim.municipal.vehicles[vid].status = "bereit"
			trips.erase(vid)


## Abladen: Stahlschrott ans Grosslager (L0 zahlt den Ankaufspreis), Rest an den Verwerter ausserhalb (Ausfuhr).
func _deliver(tr: Dictionary) -> void:
	var k := int(tr.town)
	var f: Dictionary = sim.municipal.facilities[tr.facility]
	var own := Towns.owner_of(k)
	var acct := Towns.account_of(k)
	var total := 0.0
	for item in tr.load:
		var n := mini(int(tr.load[item]), sim.stock.available(item, own, int(f.building)))
		if n <= 0:
			continue
		var hub_ok: bool = item == "schrott" and sim.hub != null and sim.hub.enabled and CentralHub.GOODS.has(item) and sim.hub.free_capacity() >= n
		var unit: float = sim.hub.buy_price(item) if hub_ok else float(Production.art(item).get("exportpreis", 0.0))
		var got: int = sim.stock.consume(item, n, own, int(f.building), "Abgabe Recyclinghof", sim.game_min)
		if hub_ok:
			sim.stock.add(item, got, CentralHub.ACCT, int(sim.hub.loc), "Ankauf Recyclinghof %s" % sim.towns.name_of(k), sim.game_min)
			sim.economy.transfer(CentralHub.ACCT, acct, unit * got)
			stats.an_grosslager = int(stats.an_grosslager) + got
		else:
			sim.economy.transfer("X0", acct, unit * got)
		total += unit * got
	stats.erloes = float(stats.erloes) + total
	sim.activity.add("stadt", -1, "stadt", "Wertstoffwagen %s liefert ab" % sim.towns.name_of(k), "Erlös %s" % Catalog.money(total), _hub_road(f))


func on_road() -> Array:
	var out: Array = []
	for vid in trips:
		if movers.has(vid):
			out.append({"vid": vid, "mover": movers[vid], "siren": false})
	return out


func summary(k: int = -1) -> Dictionary:
	var ys := yards(k)
	return {"recyclinghoefe": ys.map(func(f): return "%s: %.1f t/Tag" % [f.name, capacity_t(f)]), "gesamt": stats.duplicate(true)}


func to_dict() -> Dictionary:
	return {"carry": carry.duplicate(), "stats": stats.duplicate(true), "day": _day}


## Laden: laufende Fahrten enden (Ware bleibt im Recyclinghof, der Wagen steht im Hof).
func from_dict(d: Dictionary) -> void:
	if d.is_empty():
		return
	carry = d.get("carry", {})
	stats = d.get("stats", stats)
	_day = int(d.get("day", -1))
	for v in sim.municipal.vehicles.values():
		if str(v.type) == "Wertstoffwagen":
			v.status = "bereit"
