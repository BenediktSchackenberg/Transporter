class_name PoliceService
extends RefCounted
## Polizei je Stadt (Auftrag 22 Phase 5, docs/INFRASTRUCTURE.md). Jede Stadt der Region hat eine Polizeiwache (Municipal PO-01,
## Startausstattung, Gebaeude police_station mit eigenem Bild, Beruf Polizist, Funkstreifenwagen "FuStW"). Einsaetze fahren
## sichtbar mit Blaulicht (Mover wie Rettungsdienst), Personal und Fahrzeug sind waehrend des Einsatzes gebunden (Municipal-Aufgabe):
##  - Festnahme: Ladendiebstaehle (PublicSafety) klaert die Wache der Wohnstadt des Taeters auf; die Aufklaerung je Tag haengt von
##    der Personalstaerke dieser Wache ab (solve_chance). Bei Festnahme faehrt der Streifenwagen zum Tatort/zur Wohnung.
##  - Verkehrsunfall: zufaellig auf einer Strasse der Stadt (bei Glaette/Nebel haeufiger); die Strasse ist gesperrt, bis die Polizei
##    den Unfall aufgenommen hat (Fahrzeuge planen um).
##  - Verkehrskontrolle: der Streifenwagen kontrolliert eine Stunde an einer Strasse; Firmenfahrzeuge in schlechtem Zustand
##    (unter 35 %) oder mit uebermuedetem Fahrer (ab 95) zahlen Bussgeld an die Stadt.
##  - Ruhestoerung: nachts (22-6 Uhr) an Kneipen und Discos; die Wache faehrt hin, ein Betrieb eines Unternehmens zahlt Bussgeld.
## Ohne Wache in der Stadt hilft die naechste Wache (laengere Anfahrt).

const CODE := "PO-01"
const VEHICLE := "FuStW"
const SPEED := 3.6
const TURNOUT := 2.0
const CREW := 2
const SOLVE_BASE := 0.1
const SOLVE_PER_OFFICER := 0.06
const SOLVE_MAX := 0.9
const ACCIDENT_P := 0.03               # je Stadt und Tag
const ACCIDENT_P_BAD := 0.09           # bei Glaette oder Nebel
const ACCIDENT_MIN := 40.0             # Unfallaufnahme vor Ort
const ACCIDENT_BLOCK_MAX := 600.0      # Sperrung haelt hoechstens so lange (falls keine Wache kommt)
const CHECK_P := 0.25                  # Verkehrskontrolle je Stadt und Tag
const CHECK_MIN := 60.0
const CHECK_RADIUS := 6
const CONDITION_LIMIT := 35.0
const TIRED_LIMIT := 95.0
const FINE_CONDITION := 150.0
const FINE_TIRED := 200.0
const NOISE_P := 0.05                  # je Kneipe/Disco und Nacht
const NOISE_MIN := 20.0
const NOISE_FINE := 300.0
const KEEP_DONE := 60

var sim
var missions := {}        # "P<n>" -> {id, kind, town, cell, station, task, vid, phase, t, status, ...}
var movers := {}          # Fahrzeug-ID -> Mover (nicht gespeichert)
var stats := {"festnahmen": 0, "unfaelle": 0, "kontrollen": 0, "bussgelder": 0, "bussgeld_eur": 0.0, "ruhestoerungen": 0}
var by_town := {}         # Stadt (str) -> {festnahmen, unfaelle, kontrollen, bussgelder, ruhestoerungen}
var random_events := true # Tests schalten Zufallsereignisse ab
var _next := 1
var _rng := RandomNumberGenerator.new()


func setup(simulation) -> void:
	sim = simulation
	if not enabled():
		return
	_rng.seed = hash([int(sim.city.seed_value), "polizei"])
	sim.day_changed.connect(on_day)


func enabled() -> bool:
	return sim != null and sim.towns != null and sim.towns.is_region() and sim.municipal != null


func station_of(k: int) -> Dictionary:
	for f in sim.municipal.of_town(k, "polizei"):
		if str(f.code) == CODE and f.status == "in_betrieb":
			return f
	return {}


## Aufklaerungschance je Tag und Gesuchtem: Grundwert plus Polizisten der Wache der Stadt (ohne Wache nur der Grundwert).
func solve_chance(k: int) -> float:
	var st := station_of(k)
	var n: int = sim.municipal.staff_count(st.id, "polizist") if not st.is_empty() else 0
	return clampf(SOLVE_BASE + SOLVE_PER_OFFICER * float(n), SOLVE_BASE, SOLVE_MAX)


func _tw(k: int) -> Dictionary:
	var key := str(k)
	if not by_town.has(key):
		by_town[key] = {"festnahmen": 0, "unfaelle": 0, "kontrollen": 0, "bussgelder": 0, "ruhestoerungen": 0}
	return by_town[key]


# ------------------------------------------------------------------ Einsaetze anlegen
func _mission(kind: String, k: int, cell: Vector2i, data: Dictionary = {}) -> Dictionary:
	var id := "P%d" % _next
	_next += 1
	var m := {"id": id, "kind": kind, "town": k, "cell": [cell.x, cell.y], "station": "", "task": "", "vid": "", "phase": "wartet",
		"t": sim.game_min, "alarm": sim.game_min, "status": "laufend"}
	m.merge(data)
	missions[id] = m
	_dispatch(m)
	return m


## Festnahme (von PublicSafety._arrest): Streifenwagen faehrt zum Tatort bzw. zur Wohnung.
func arrest_trip(k: int, cell: Vector2i, name: String) -> void:
	stats.festnahmen = int(stats.festnahmen) + 1
	_tw(k).festnahmen = int(_tw(k).festnahmen) + 1
	_mission("festnahme", k, cell, {"person": name})


## Verkehrsunfall auf einer Strasse der Stadt: Sperrung bis zur Unfallaufnahme.
func accident(k: int, cell: Vector2i = Vector2i(-1, -1)) -> Dictionary:
	if cell.x < 0:
		cell = _random_road(k)
		if cell.x < 0:
			return {}
	sim.nav.add_roadwork(cell, sim.game_min + ACCIDENT_BLOCK_MAX)
	stats.unfaelle = int(stats.unfaelle) + 1
	_tw(k).unfaelle = int(_tw(k).unfaelle) + 1
	sim.activity.add("stadt", -1, "polizei", "Verkehrsunfall in %s" % sim.towns.name_of(k), "Straße gesperrt, Polizei unterwegs", cell)
	sim.log_event("%s: Verkehrsunfall – Straße gesperrt bis zur Unfallaufnahme." % sim.towns.name_of(k), "warn")
	return _mission("unfall", k, cell)


func traffic_check(k: int, cell: Vector2i = Vector2i(-1, -1)) -> Dictionary:
	if cell.x < 0:
		cell = _random_road(k)
		if cell.x < 0:
			return {}
	stats.kontrollen = int(stats.kontrollen) + 1
	_tw(k).kontrollen = int(_tw(k).kontrollen) + 1
	return _mission("kontrolle", k, cell, {"checked": {}})


func noise_call(k: int, building_id: int) -> Dictionary:
	var b: Dictionary = sim.city.building(building_id)
	if b.is_empty():
		return {}
	stats.ruhestoerungen = int(stats.ruhestoerungen) + 1
	_tw(k).ruhestoerungen = int(_tw(k).ruhestoerungen) + 1
	return _mission("ruhestoerung", k, Vector2i(b.road), {"building": building_id})


func _random_road(k: int) -> Vector2i:
	var t: Dictionary = sim.towns.get_t(k)
	var c: Vector2i = sim.city.building(int(t.town_hall)).road if int(t.town_hall) >= 0 else Vector2i(t.center)
	for i in 40:
		var q := c + Vector2i(_rng.randi_range(-18, 18), _rng.randi_range(-18, 18))
		if sim.city.inside(q) and sim.city.is_road(q) and sim.city.town_of(q) == k and not sim.nav.is_blocked_road(q):
			return q
	return Vector2i(-1, -1)


# ------------------------------------------------------------------ Disposition und Ablauf
func _free_car(st: Dictionary) -> String:
	for vid in st.vehicles:
		var v: Dictionary = sim.municipal.vehicles[vid]
		if str(v.type) == VEHICLE and v.status == "bereit":
			return vid
	return ""


func _dispatch(m: Dictionary) -> void:
	var M: Municipal = sim.municipal
	var st := station_of(int(m.town))
	if st.is_empty() or _free_car(st) == "":   # Nachbarwache
		var target := Vector2i(int(m.cell[0]), int(m.cell[1]))
		var best_d := INF
		for f in M.facilities.values():
			if str(f.code) != CODE or f.status != "in_betrieb" or _free_car(f) == "":
				continue
			var d := Vector2(M._cell(f)).distance_to(Vector2(target))
			if d < best_d:
				best_d = d
				st = f
	if st.is_empty() or _free_car(st) == "":
		return   # bleibt "wartet"; update() versucht es erneut
	var t: Dictionary = M.open_task(st.id, "polizei_" + str(m.kind), Vector2i(int(m.cell[0]), int(m.cell[1])), 2, CREW, [VEHICLE], {"polizei": m.id})
	var r: Dictionary = M.dispatch(t.id)
	if not r.ok:
		M.finish(t.id, "nicht ausgerückt: " + str(r.msg))
		return
	m.station = st.id
	m.task = t.id
	m.vid = str(t.vehicles[0])
	m.phase = "ausruecken"
	m.t = sim.game_min + TURNOUT


func mover_of(vid: String) -> Mover:
	if not movers.has(vid):
		var M: Municipal = sim.municipal
		var mv := Mover.new()
		mv.speed = SPEED
		mv.pos = sim.city.tile_center(sim.city.building(M.building_of(str(M.vehicles[vid].facility))).road)
		movers[vid] = mv
	return movers[vid]


func update(dt: float) -> void:
	if missions.is_empty():
		return
	var now: float = sim.game_min
	for m in missions.values():
		if m.status != "laufend":
			continue
		match str(m.phase):
			"wartet":
				if now - float(m.t) >= 10.0:
					m.t = now
					_dispatch(m)
			"ausruecken":
				if now >= float(m.t):
					m.phase = "anfahrt"
					var to := Vector2i(int(m.cell[0]), int(m.cell[1]))
					var mv := mover_of(m.vid)
					if sim.nav.is_blocked_road(to):   # Unfallstelle selbst ist gesperrt: davor anhalten
						to = _beside(to)
					sim.route(mv, to)
			"anfahrt":
				var mv := mover_of(m.vid)
				if not mv.arrived():
					mv.advance(dt, 1.0)
				else:
					_on_scene(m, now)
			"vor_ort":
				if str(m.kind) == "kontrolle":
					_check_passing(m)
				if now >= float(m.t):
					_done_on_scene(m, now)
			"rueckfahrt":
				var mv := mover_of(m.vid)
				if not mv.arrived():
					mv.advance(dt, 1.0)
				else:
					m.status = "fertig"
					m.phase = "fertig"
					m["end"] = now
					sim.municipal.finish(m.task, "Polizei %s: %s" % [m.id, m.kind])
					_prune()


func _beside(c: Vector2i) -> Vector2i:
	for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
		var q: Vector2i = c + dv
		if sim.city.inside(q) and sim.city.is_road(q) and not sim.nav.is_blocked_road(q):
			return q
	return c


func _on_scene(m: Dictionary, now: float) -> void:
	m.phase = "vor_ort"
	var k := int(m.town)
	var cell := Vector2i(int(m.cell[0]), int(m.cell[1]))
	match str(m.kind):
		"festnahme":
			m.t = now + 10.0
		"unfall":
			m.t = now + ACCIDENT_MIN
		"kontrolle":
			m.t = now + CHECK_MIN
			sim.activity.add("stadt", -1, "polizei", "Verkehrskontrolle in %s" % sim.towns.name_of(k), "Zustand der Fahrzeuge und Lenkzeiten", cell)
		"ruhestoerung":
			m.t = now + NOISE_MIN
			_noise_fine(m)


func _done_on_scene(m: Dictionary, now: float) -> void:
	if str(m.kind) == "unfall":
		var cell := Vector2i(int(m.cell[0]), int(m.cell[1]))
		if sim.nav.roadworks.has(cell):
			sim.nav.roadworks[cell] = now   # Sperrung endet mit dem naechsten expire()
		sim.log_event("%s: Unfall aufgenommen, Straße wieder frei (%.0f Minuten nach dem Notruf)." % [sim.towns.name_of(int(m.town)), now - float(m.alarm)], "info")
	m.phase = "rueckfahrt"
	var mv := mover_of(m.vid)
	var M: Municipal = sim.municipal
	sim.route(mv, sim.city.building(M.building_of(str(M.vehicles[m.vid].facility))).road)


## Kontrolle: jedes Firmenfahrzeug, das waehrend der Kontrolle nahe vorbeikommt, wird einmal geprueft.
func _check_passing(m: Dictionary) -> void:
	var cell := Vector2i(int(m.cell[0]), int(m.cell[1]))
	var k := int(m.town)
	for v in sim.vehicles.values():
		if v.owner < 0 or m.checked.has(str(v.id)):
			continue
		var tl: Vector2i = v.tile()
		if absi(tl.x - cell.x) + absi(tl.y - cell.y) > CHECK_RADIUS:
			continue
		m.checked[str(v.id)] = true
		var why: Array = []
		var fine := 0.0
		if float(v.condition) < CONDITION_LIMIT:
			why.append("Fahrzeugzustand %d %%" % int(v.condition))
			fine += FINE_CONDITION
		var d = sim.driver_of(v)
		if d != null and float(d.fatigue) >= TIRED_LIMIT:
			why.append("Fahrer übermüdet")
			fine += FINE_TIRED
		if fine > 0.0:
			_fine(int(v.operator if v.operator >= 0 else v.owner), k, fine, "Verkehrskontrolle %s: %s" % [v.display_name(), ", ".join(why)])


func _noise_fine(m: Dictionary) -> void:
	var b: Dictionary = sim.city.building(int(m.building))
	var k := int(m.town)
	for biz in sim.biz.items.values():
		if int(biz.site) == int(m.building) and int(biz.owner) >= 0:
			_fine(int(biz.owner), k, NOISE_FINE, "Ruhestörung %s" % str(b.get("name", "")))
			return
	sim.activity.add("stadt", -1, "polizei", "Ruhestörung: %s" % str(b.get("name", "")), "Polizei mahnt zur Ruhe", Vector2i(b.road))


func _fine(cid: int, k: int, eur: float, why: String) -> void:
	var c = sim.company(cid)
	if c == null:
		return
	var pay := minf(eur, maxf(0.0, c.ledger.cash))
	if pay <= 0.0:
		return
	c.ledger.book("fines", -pay, true, why, sim.game_min, Towns.account_of(k))
	stats.bussgelder = int(stats.bussgelder) + 1
	stats.bussgeld_eur = float(stats.bussgeld_eur) + pay
	_tw(k).bussgelder = int(_tw(k).bussgelder) + 1
	sim.log_event("Polizei %s: Bußgeld %s für %s (%s)." % [sim.towns.name_of(k), Catalog.money(pay), c.company_name, why], "warn", cid)


# ------------------------------------------------------------------ Tag
func on_day(_day: int) -> void:
	if not random_events:
		return
	var bad: bool = sim.wx != null and (sim.wx.is_icy() or sim.wx.is_fog())
	for t in sim.towns.list:
		var k := int(t.id)
		if _rng.randf() < (ACCIDENT_P_BAD if bad else ACCIDENT_P):
			accident(k)
		if _rng.randf() < CHECK_P and not station_of(k).is_empty():
			traffic_check(k)
	for b in sim.city.buildings:   # Anzeigen aus der Nacht (Tageswechsel)
		if str(b.get("type", "")) in ["kneipe", "disco"] and _rng.randf() < NOISE_P:
			noise_call(sim.towns.of_building(int(b.id)), int(b.id))


func _prune() -> void:
	var done: Array = missions.values().filter(func(m): return m.status == "fertig")
	if done.size() <= KEEP_DONE:
		return
	done.sort_custom(func(a, b): return float(a.get("end", 0.0)) < float(b.get("end", 0.0)))
	for i in done.size() - KEEP_DONE:
		missions.erase(done[i].id)


func on_road() -> Array:
	var out: Array = []
	for m in missions.values():
		if m.status != "laufend" or m.phase in ["wartet", "ausruecken"] or not movers.has(m.vid):
			continue
		out.append({"vid": m.vid, "mover": movers[m.vid], "siren": m.phase in ["anfahrt"] and str(m.kind) != "kontrolle"})
	return out


func summary(k: int = -1) -> Dictionary:
	if k >= 0:
		var st := station_of(k)
		return {"wache": str(st.get("name", "")), "polizisten": sim.municipal.staff_count(st.id, "polizist") if not st.is_empty() else 0,
			"aufklaerung_tag": snappedf(solve_chance(k), 0.01), "einsaetze_laufend": missions.values().filter(func(m): return m.status == "laufend" and int(m.town) == k).size(),
			"zahlen": _tw(k).duplicate()}
	var out := {"gesamt": stats.duplicate()}
	for t in sim.towns.list:
		out[str(int(t.id))] = summary(int(t.id))
	return out


func to_dict() -> Dictionary:
	# Einsaetze laufen nach dem Laden nicht weiter (Fahrzeuge stehen in der Wache); Sperrungen gibt NavGrid frei
	return {"stats": stats, "by_town": by_town, "next": _next}


func from_dict(d: Dictionary) -> void:
	var st0: Dictionary = stats.duplicate()
	st0.merge(d.get("stats", {}), true)
	stats = st0
	by_town = d.get("by_town", {})
	_next = int(d.get("next", 1))
	missions = {}
