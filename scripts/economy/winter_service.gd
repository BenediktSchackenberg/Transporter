class_name WinterService
extends RefCounted
## Bauhof: Winterdienst und Flickarbeiten (Auftrag 20, Etappe 6, docs/PUBLIC_SERVICES.md). Baut auf Municipal (Bauhof BH-01 mit
## Personal, Streuwagen, Kipper) und RoadCare (Strassenabschnitte 16 x 16 mit Zustand) auf.
##  - Schnee: Bei Schneefall waechst die Schneehoehe je Abschnitt, Tauwetter (ueber 2 Grad, kein Schneefall) laesst ihn schmelzen.
##    Auf verschneiten Abschnitten (ab 30) gilt das Schnee-Tempo; geraeumte und gestreute Abschnitte fahren sich wie bei Regen.
##  - Raeumung nach Prioritaet: 1 Rettungswege (Abschnitte an Feuerwache, Rettungswache, Krankenhaus, Rathaus), 2 Hauptachsen
##    (viele Strassenfelder), 3 uebrige Strassen der Stadt. Der Streuwagen faehrt sichtbar von Abschnitt zu Abschnitt (15 Spielminuten
##    je Abschnitt) und verbraucht Streusalz aus dem Stadtlager; ohne Salz wird nur geraeumt (Wirkung halb so lange).
##  - Schlagloecher: Abschnitte unter 35 % Zustand. Der Kipper des Bauhofs flickt sie (60 Spielminuten, +25 Zustand, Asphaltmischung
##    aus dem Stadtlager, Kosten an die Dienstleister). Grundsanierung bleibt Sache des Buergermeisters (RoadCare.order).
##  - Ohne Bauhof oder ohne Personal geschieht nichts davon.

const SNOW_PER_MIN := 0.5          # Schneehoehe je Spielminute Schneefall (100 nach gut drei Spielstunden)
const MELT_PER_MIN := 0.3
const SNOWY := 30.0                # ab hier Schnee-Tempo
const CLEAR_MIN := 15.0            # Raeumen und Streuen je Abschnitt
const SALT_MIN := 360.0            # so lange haelt Streusalz neuen Schnee unter der Wirkungsschwelle
const SALT_T := 1                  # Streusalz je Abschnitt (t)
const POTHOLE := 35.0
const PATCH_MIN := 60.0
const PATCH_GAIN := 25.0
const PATCH_COST := 400.0          # Lohn und Geraet je Flickstelle (an S0)
const SPEED := 3.0

var sim
var snow := {}             # Abschnitt (Vector2i) -> Schneehoehe 0..100
var salted := {}           # Abschnitt -> gestreut bis Spielminute
var jobs := {}             # Fahrzeug-ID -> {kind: raeumen|flicken, town, seg, phase, until, queue: [Abschnitte]}
var movers := {}           # Fahrzeug-ID -> Mover (nicht gespeichert)
var stats := {"geraeumt": 0, "ohne_salz": 0, "geflickt": 0, "flickkosten": 0.0}
var order_log: Array = []  # [[Stadt, Abschnitt-ID, Prioritaet, Spielminute]] Reihenfolge der Raeumung (letzte 60)
var _last := 0.0


func setup(simulation) -> void:
	sim = simulation
	_last = sim.game_min


func enabled() -> bool:
	return sim != null and sim.municipal != null and sim.municipal.enabled()


# ------------------------------------------------------------------ Schnee und Fahrtempo
func snow_at(cell: Vector2i) -> float:
	return float(snow.get(RoadCare.seg_of(cell), 0.0))


## Ortsabhaengiges Fahrtempo bei Winterwetter: f = globaler Wetterfaktor.
func drive_factor(cell: Vector2i, f: float) -> float:
	if snow.is_empty():
		return f
	var seg := RoadCare.seg_of(cell)
	var s := float(snow.get(seg, 0.0))
	if s >= SNOWY:
		return minf(f, sim.wx.p("drive_snow"))
	if sim.wx.is_snow() or sim.wx.is_icy():
		return maxf(f, sim.wx.p("drive_rain"))   # geraeumt und gestreut
	return f


func cleared(seg: Vector2i) -> bool:
	return float(snow.get(seg, 0.0)) < SNOWY


func _weather(mins: float) -> void:
	var falling: bool = sim.wx.is_snow()
	var thaw: bool = not falling and float(sim.wx.cur.get("temp", 5.0)) > 2.0
	if not falling and snow.is_empty():
		return
	for seg in sim.road_care.cells:
		var s := float(snow.get(seg, 0.0))
		if falling:
			var rate := SNOW_PER_MIN * (0.2 if float(salted.get(seg, -1.0)) > sim.game_min else 1.0)
			s = minf(100.0, s + rate * mins)
		elif thaw:
			s = maxf(0.0, s - MELT_PER_MIN * mins)
		if s <= 0.0:
			snow.erase(seg)
		else:
			snow[seg] = s


# ------------------------------------------------------------------ Prioritaeten
## Raeumliste einer Stadt: verschneite Abschnitte nach Prioritaet (1 Rettungswege, 2 Hauptachsen, 3 Rest), innerhalb nach Entfernung.
func plan(k: int, from: Vector2i) -> Array:
	var prio := priorities(k)
	var out: Array = []
	for seg in prio:
		if not cleared(seg) and not _taken(seg):
			out.append(seg)
	out.sort_custom(func(a, b): return int(prio[a]) < int(prio[b]) or (int(prio[a]) == int(prio[b]) and
		(sim.road_care.cells[a] - from).length_squared() < (sim.road_care.cells[b] - from).length_squared()))
	return out


var _prio_cache := {}


func priorities(k: int) -> Dictionary:
	if _prio_cache.has(k):
		return _prio_cache[k]
	var RC: RoadCare = sim.road_care
	var vital := {}
	for f in sim.municipal.facilities.values():
		if f.code in ["FW-01", "RW-01", "KH-01"]:
			vital[RoadCare.seg_of(sim.city.building(int(f.building)).road)] = true
	var th := int(sim.towns.get_t(k).get("town_hall", -1))
	if th >= 0:
		vital[RoadCare.seg_of(sim.city.building(th).road)] = true
	var roads := _road_counts()
	var out := {}
	for seg in RC.cells:
		if sim.towns.of_cell(RC.cells[seg]) != k or not sim.towns.get_t(k).rect.has_point(RC.cells[seg]):
			continue   # Verbindungsstrassen ausserhalb des Ortes raeumt der Ort nicht
		out[seg] = 1 if vital.has(seg) else (2 if int(roads.get(seg, 0)) >= 20 else 3)
	_prio_cache[k] = out
	return out


var _roads := {}


## Strassenfelder je Abschnitt (einmal gezaehlt; Hauptachsen haben viele).
func _road_counts() -> Dictionary:
	if _roads.is_empty():
		for y in sim.city.size:
			for x in sim.city.size:
				var p := Vector2i(x, y)
				if sim.city.is_road(p):
					var seg := RoadCare.seg_of(p)
					_roads[seg] = int(_roads.get(seg, 0)) + 1
	return _roads


func _taken(seg: Vector2i) -> bool:
	return jobs.values().any(func(j): return j.seg == seg)


# ------------------------------------------------------------------ Bauhof-Fahrzeuge
func mover_of(vid: String) -> Mover:
	if not movers.has(vid):
		var M: Municipal = sim.municipal
		var mv := Mover.new()
		mv.speed = SPEED
		mv.pos = sim.city.tile_center(sim.city.building(M.building_of(str(M.vehicles[vid].facility))).road)
		movers[vid] = mv
	return movers[vid]


func _yards() -> Array:
	return sim.municipal.facilities.values().filter(func(f): return f.code == "BH-01" and f.status == "in_betrieb")


func _vehicle(f: Dictionary, vtype: String) -> String:
	for vid in f.vehicles:
		var v: Dictionary = sim.municipal.vehicles[vid]
		if str(v.type) == vtype and v.status == "bereit" and int(v.driver) >= 0:
			return vid
	return ""


func update(dt: float) -> void:
	if not enabled():
		return
	var now: float = sim.game_min
	var mins := now - _last
	if mins < 1.0:
		_drive(dt)
		return
	if GameCalendar.day_of(now) != GameCalendar.day_of(_last):
		_prio_cache.clear()   # neue Wachen, neue Abschnitte: Raeumplan taeglich neu
	_last = now
	_weather(mins)
	for f in _yards():
		var k := int(f.town)
		var home: Vector2i = sim.city.building(int(f.building)).road
		var plow := _vehicle(f, "Streuwagen")
		if plow != "" and (sim.wx.is_snow() or not snow.is_empty()):
			var q := plan(k, home)
			if not q.is_empty():
				_start(plow, f, "raeumen", q[0])
		var kip := _vehicle(f, "Kipper")
		if kip != "":
			var hole := _worst_pothole(k)
			if hole != Vector2i(-1, -1):
				_start(kip, f, "flicken", hole)
	_progress(now)
	_drive(dt)


func _worst_pothole(k: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	var worst := POTHOLE
	var RC: RoadCare = sim.road_care
	for seg in priorities(k):
		var c := float(RC.cond.get(seg, 100.0))
		if c < worst and not _taken(seg) and not RC.jobs.values().any(func(j): return j.status == "laufend" and j.seg == seg):
			worst = c
			best = seg
	return best


func _start(vid: String, f: Dictionary, kind: String, seg: Vector2i) -> void:
	var M: Municipal = sim.municipal
	var t: Dictionary = M.open_task(f.id, kind, sim.road_care.cells[seg], 2 if kind == "raeumen" else 1, 1, [M.vehicles[vid].type])
	var r: Dictionary = M.dispatch(t.id)
	if not r.ok:
		M.finish(t.id, str(r.msg))
		return
	jobs[vid] = {"kind": kind, "town": int(f.town), "seg": seg, "phase": "anfahrt", "until": 0.0, "task": t.id, "yard": f.id}
	sim.route(mover_of(vid), sim.road_care.cells[seg])


func _progress(now: float) -> void:
	var RC: RoadCare = sim.road_care
	for vid in jobs.keys():
		var j: Dictionary = jobs[vid]
		match str(j.phase):
			"anfahrt":
				if mover_of(vid).arrived():
					j.phase = "arbeit"
					j.until = now + (CLEAR_MIN if j.kind == "raeumen" else PATCH_MIN)
			"arbeit":
				if now >= float(j.until):
					if j.kind == "raeumen":
						_cleared(j)
						var q := plan(int(j.town), RC.cells[j.seg])
						if not q.is_empty():   # gleich weiter zum naechsten Abschnitt
							j.seg = q[0]
							j.phase = "anfahrt"
							sim.route(mover_of(vid), RC.cells[j.seg])
							continue
					else:
						_patched(j)
					j.phase = "rueckfahrt"
					sim.route(mover_of(vid), sim.city.building(sim.municipal.building_of(str(j.yard))).road)
			"rueckfahrt":
				if mover_of(vid).arrived():
					sim.municipal.finish(j.task, "%s erledigt" % j.kind)
					jobs.erase(vid)


func _drive(dt: float) -> void:
	for vid in jobs:
		var mv := mover_of(vid)
		if not mv.arrived():
			mv.advance(dt, 1.0)


func _cleared(j: Dictionary) -> void:
	var seg: Vector2i = j.seg
	snow.erase(seg)
	var D = sim.towns.depot(int(j.town))
	var got: int = sim.stock.consume("streusalz", SALT_T, D.owner(), D.building, "Winterdienst %s" % RoadCare.seg_id(seg), sim.game_min) if D.building >= 0 else 0
	salted[seg] = sim.game_min + (SALT_MIN if got >= SALT_T else SALT_MIN * 0.5)
	if got < SALT_T:
		stats.ohne_salz = int(stats.ohne_salz) + 1
	stats.geraeumt = int(stats.geraeumt) + 1
	order_log.append([int(j.town), RoadCare.seg_id(seg), int(priorities(int(j.town)).get(seg, 3)), sim.game_min])
	if order_log.size() > 60:
		order_log.pop_front()


func _patched(j: Dictionary) -> void:
	var RC: RoadCare = sim.road_care
	var seg: Vector2i = j.seg
	RC.cond[seg] = minf(100.0, float(RC.cond.get(seg, 0.0)) + PATCH_GAIN)
	var D = sim.towns.depot(int(j.town))
	if D.building >= 0:
		sim.stock.consume("asphalt", 1, D.owner(), D.building, "Flickarbeiten %s" % RoadCare.seg_id(seg), sim.game_min)
	sim.economy.transfer(Towns.account_of(int(j.town)), "S0", PATCH_COST)
	sim.public_sector.departments["Verkehr"] = float(sim.public_sector.departments.get("Verkehr", 0.0)) + PATCH_COST
	stats.geflickt = int(stats.geflickt) + 1
	stats.flickkosten = float(stats.flickkosten) + PATCH_COST
	sim.activity.add("stadt", -1, "reparatur", "Bauhof flickt Schlaglöcher (%s)" % RoadCare.seg_id(seg), "Zustand jetzt %d %%" % int(RC.cond[seg]), RC.cells[seg])


# ------------------------------------------------------------------ Anzeige, Uebersicht, Speichern
func on_road() -> Array:
	var out: Array = []
	for vid in jobs:
		if movers.has(vid):
			out.append({"vid": vid, "mover": movers[vid], "siren": jobs[vid].kind == "raeumen" and jobs[vid].phase != "rueckfahrt"})
	return out


func potholes() -> Array:
	var RC: RoadCare = sim.road_care
	return RC.cond.keys().filter(func(seg): return float(RC.cond[seg]) < POTHOLE)


func summary(k: int = -1) -> Dictionary:
	var pr := priorities(k) if k >= 0 else {}
	var snowy := snow.keys().filter(func(seg): return float(snow[seg]) >= SNOWY and (k < 0 or pr.has(seg)))
	return {"verschneit": snowy.size(), "rettungswege_verschneit": snowy.filter(func(seg): return int(pr.get(seg, 0)) == 1).size(),
		"schlagloecher": potholes().filter(func(seg): return k < 0 or pr.has(seg)).size(), "im_einsatz": jobs.size(), "gesamt": stats.duplicate()}


func to_dict() -> Dictionary:
	var s := {}
	for seg in snow:
		s[RoadCare.seg_id(seg)] = snow[seg]
	var sl := {}
	for seg in salted:
		sl[RoadCare.seg_id(seg)] = salted[seg]
	return {"snow": s, "salted": sl, "stats": stats.duplicate(), "last": _last}


## Laden: laufende Fahrten werden beendet (Fahrzeuge stehen im Bauhof); Schnee und Streusalz bleiben.
func from_dict(d: Dictionary) -> void:
	if d.is_empty():
		return
	for id in d.get("snow", {}):
		snow[RoadCare.parse_id(id)] = float(d.snow[id])
	for id in d.get("salted", {}):
		salted[RoadCare.parse_id(id)] = float(d.salted[id])
	stats = d.get("stats", stats)
	_last = float(d.get("last", sim.game_min))
	for t in sim.municipal.tasks.values():
		if t.status == "unterwegs" and t.kind in ["raeumen", "flicken"]:
			sim.municipal.finish(t.id, "beim Laden beendet")
