class_name StreetCleaning
extends RefCounted
## Stadtreinigung, Sauberkeit je Viertel (Auftrag 22 Phase 2 Schritt 3). Baut auf Municipal (Betriebshof Abfallwirtschaft AW-01
## mit Kehrmaschine, Müllwerker) und Waste (überquellende Tonnen) und RoadCare (Straßenzellen) auf.
##  - Überquellende Tonnen (Waste.overflowing, Rest/Bio/Wertstoffe): der Abfall, der in die Straße fällt (Ueberschuss des
##    Fassungsvermögens, plus Grundabfall, falls die Tour die Tonne nicht erreicht), wird der Straßenzelle zugeordnet, in der
##    das Gebäude steht, und summiert sich dort als Straßenmüll.
##  - Sauberkeit je Viertel: Dreck = Straßenmüll im Viertel (je Straßenzelle via district_of) relativ zu einer Normmenge
##    (DIRTY_REF kg). Ein sauberes Viertel ist 0, ein ganz verschmutztes Viertel 1.
##  - Kehrmaschine: räumt die schmutzigste Straßenzelle je Stadt, nach Priorität (Viertel mit viel Dreck zuerst, dann nach
##    Entfernung). Sie verbraucht keine Ware; die Stadtkasse zahlt einen Sachkosten-Anteil pro geräumter Zelle.
##  - Wirkung: die Versorgungszufriedenheit (Contentment) sinkt um den Dreck im jeweiligen Viertel (Contentment._litter_of).
##  - Ohne Betriebshof (Einzelstadt, Küstenort) passiert nichts.

const DIRTY_REF := 40.0         # so viel Straßenmüll je Viertel entspricht "völlig verschmutzt" (1,0)
const OVERFLOW_K := 0.15        # Straßenmüll (kg) je kg Überquellung einer Tonne
const BASE_LITTER := 0.6        # Straßenmüll (kg) pro überquellender Tonne zusätzlich (der Rest bleibt auf dem Gehweg)
const CLEAN_KG := 30.0          # so viel Straßenmüll (kg) nimmt die Kehrmaschine je geräumter Zelle
const CLEAN_MIN := 40.0         # so lange (Spielminuten) arbeitet sie je Zelle
const CLEAN_AT := 0.15          # Zelle ab diesem Verschmutzungsgrad räumt die Kehrmaschine
const SPEED := 3.0
const COST_PER_CELL := 60.0     # Sachkosten (Wasser, Kehrbürste, Unterhalt) je geräumter Zelle, an die Kasse der Stadt

var sim
var dirt := {}             # Straßenzelle (Vector2i) -> Straßenmüll (kg)
var movers := {}           # Fahrzeug-ID -> Mover (nicht gespeichert)
var jobs := {}             # Fahrzeug-ID -> {town, cell, phase, until, task}
var stats := {"geraeumt": 0, "gesaeubert": 0.0}
var _last := 0.0


func setup(simulation) -> void:
	sim = simulation
	_last = sim.game_min


func enabled() -> bool:
	return sim != null and sim.municipal != null and sim.municipal.enabled()


# ------------------------------------------------------------------ Straßenmüll
## Taeglich: ueberquellende Tonnen lassen Abfall in der Straasse zurueck (Ueberschuss des Fassungsvermoegens + Grundabfall).
func _spawn(_day: int) -> void:
	if not enabled():
		return
	var W: Waste = sim.waste
	for bid in W.overflowing():
		var b: Dictionary = sim.city.building(bid)
		if b.is_empty() or not b.has("road"):
			continue
		var road: Vector2i = b.road
		var cap := W._cap_of("rest", bid) + W._cap_of("bio", bid) + W._cap_of("wert", bid)
		var level := W.bin_level("rest", bid) + W.bin_level("bio", bid) + W.bin_level("wert", bid)
		var over := maxf(0.0, level - cap)
		dirt[road] = float(dirt.get(road, 0.0)) + over * OVERFLOW_K + BASE_LITTER


## Verschmutzung eines Viertels 0..1: Straßenmüll der Straßenzellen dieses Viertels relativ zur Normmenge (DIRTY_REF kg).
func district_litter(district: int) -> float:
	var t := 0.0
	for cell in dirt:
		if sim.city.district_of(cell) == district:
			t += float(dirt[cell])
	return clampf(t / DIRTY_REF, 0.0, 1.0)


## Verschmutzung einer Straßenzelle 0..1 (Viertel, in dem die Zelle liegt).
func dirt_of(cell: Vector2i) -> float:
	return district_litter(sim.city.district_of(cell))


func on_road() -> Array:
	var out: Array = []
	for vid in jobs:
		if movers.has(vid):
			out.append({"vid": vid, "mover": movers[vid], "siren": jobs[vid].phase != "rueckfahrt"})
	return out


# ------------------------------------------------------------------ Kehrmaschine (Betriebshof Abfallwirtschaft)
func mover_of(vid: String) -> Mover:
	if not movers.has(vid):
		var M: Municipal = sim.municipal
		var mv := Mover.new()
		mv.speed = SPEED
		var f: Dictionary = M.facilities.get(str(M.vehicles[vid].facility), {})
		var home: Vector2i = sim.city.building(int(f.building)).road if not f.is_empty() else Vector2i.ZERO
		mv.pos = sim.city.tile_center(home)
		movers[vid] = mv
	return movers[vid]


func _sweepers(k: int) -> Array:
	var out: Array = []
	if not enabled():
		return out
	for f in sim.municipal.of_town(k, "abfall"):
		if str(f.code) != "AW-01" or f.status != "in_betrieb":
			continue
		for vid in f.vehicles:
			var v: Dictionary = sim.municipal.vehicles[vid]
			if str(v.type) == "Kehrmaschine" and v.status == "bereit" and int(v.driver) >= 0:
				out.append(vid)
	return out


## Die schmutzigste Straßenzelle der Stadt (Viertel mit viel Dreck zuerst, dann nach Entfernung); Vector2i(-1,-1) wenn sauber.
func _next_cell(k: int, from: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := CLEAN_AT
	var best_dist := 1 << 20
	var seen := {}
	for vid in jobs:
		seen[jobs[vid].cell] = true
	for cell in dirt:
		if seen.has(cell) or float(dirt[cell]) <= 0.0:
			continue
		if not sim.city.is_road(cell):
			continue
		if sim.towns.of_cell(cell) != k:
			continue
		var d := district_litter(sim.city.district_of(cell))
		if d < best_d:
			continue
		var dist: float = (cell - from).length_squared()
		if d > best_d + 0.0001 or (is_equal_approx(d, best_d) and dist < best_dist):
			best_d = d
			best_dist = dist
			best = cell
	return best


func update(dt: float) -> void:
	if not enabled():
		return
	var now: float = sim.game_min
	var mins := now - _last
	if mins < 1.0:
		_drive(dt)
		return
	var new_day := GameCalendar.day_of(now) != GameCalendar.day_of(_last)
	_last = now
	if new_day:
		_spawn(GameCalendar.day_of(now))
	for k in sim.towns.count():
		var home := _depot_home(k)
		if home.x < 0:
			continue
		var free: Array = _sweepers(k)
		while not free.is_empty():
			var cell := _next_cell(k, home)
			if cell.x < 0:
				break
			_start(free.pop_back(), k, cell)
	_progress(now)
	_drive(dt)


func _depot_home(k: int) -> Vector2i:
	if not enabled():
		return Vector2i(-1, -1)
	for f in sim.municipal.of_town(k, "abfall"):
		if str(f.code) == "AW-01" and f.status == "in_betrieb":
			return sim.city.building(int(f.building)).road
	return Vector2i(-1, -1)


func _start(vid: String, k: int, cell: Vector2i) -> void:
	var M: Municipal = sim.municipal
	var t: Dictionary = M.open_task(str(M.vehicles[vid].facility), "kehr", cell, 1, 1, [M.vehicles[vid].type])
	var r: Dictionary = M.dispatch(t.id, Callable(), [vid])
	if not r.ok:
		M.finish(t.id, str(r.msg))
		return
	jobs[vid] = {"town": k, "cell": cell, "phase": "anfahrt", "until": 0.0, "task": t.id}
	sim.route(mover_of(vid), cell)


func _progress(now: float) -> void:
	for vid in jobs.keys():
		var j: Dictionary = jobs[vid]
		match str(j.phase):
			"anfahrt":
				if mover_of(vid).arrived():
					j.phase = "arbeit"
					j.until = now + CLEAN_MIN
			"arbeit":
				if now >= float(j.until):
					_cleaned(j)
					j.phase = "rueckfahrt"
					sim.route(mover_of(vid), _depot_home(int(j.town)))
			"rueckfahrt":
				if mover_of(vid).arrived():
					sim.municipal.finish(str(j.task), "geräumt")
					jobs.erase(vid)


func _drive(dt: float) -> void:
	for vid in jobs:
		var mv := mover_of(vid)
		if not mv.arrived():
			mv.advance(dt, 1.0)


func _cleaned(j: Dictionary) -> void:
	var cell: Vector2i = j.cell
	var k := int(j.town)
	var got := minf(float(dirt.get(cell, 0.0)), CLEAN_KG)
	dirt[cell] = float(dirt.get(cell, 0.0)) - got
	if float(dirt[cell]) <= 0.5:
		dirt.erase(cell)
	var acct := Towns.account_of(k)
	var pay := minf(COST_PER_CELL, maxf(0.0, float(sim.economy.accounts.get(acct, 0.0))))
	if pay > 0.0:
		sim.economy.transfer(acct, "S0", pay)
	stats.geraeumt = int(stats.geraeumt) + 1
	stats.gesaeubert = float(stats.gesaeubert) + got
	sim.activity.add("stadt", k, "kehr", "%s räumt die Straße im %s" % [sim.towns.name_of(k), Catalog.DISTRICTS[sim.city.district_of(cell)]], "Straßenmüll gesammelt: %.0f kg" % got, cell)


# ------------------------------------------------------------------ Uebersicht, Speichern
func summary(k: int = -1) -> Dictionary:
	var ds: Dictionary = {}
	var total := 0.0
	for cell in dirt:
		if k >= 0 and sim.towns.of_cell(cell) != k:
			continue
		var d: int = sim.city.district_of(cell)
		ds[d] = maxf(float(ds.get(d, 0.0)), district_litter(d))
		total += float(dirt[cell])
	return {"abschnitte": dirt.size(), "dreck_kg": snappedf(total, 1.0), "viertel": ds, "im_einsatz": jobs.size(), "geraeumt": int(stats.geraeumt)}


func to_dict() -> Dictionary:
	var d := {}
	for cell in dirt:
		d[RoadCare.seg_id(cell)] = dirt[cell]
	return {"dirt": d, "stats": stats.duplicate(), "last": _last}


## Laden: laufende Fahrten werden beendet (die Kehrmaschine steht im Hof); der Straßenmüll bleibt liegen.
func from_dict(d: Dictionary) -> void:
	if d.is_empty():
		return
	dirt = {}
	for id in d.get("dirt", {}):
		var cell := RoadCare.parse_id(id)
		if cell.x >= 0 and sim.city.is_road(cell):
			dirt[cell] = float(d.dirt[id])
	stats = d.get("stats", stats)
	_last = float(d.get("last", sim.game_min))
	jobs.clear()
	movers.clear()
	for t in sim.municipal.tasks.values():
		if t.status == "unterwegs" and str(t.kind) == "kehr":
			sim.municipal.finish(t.id, "beim Laden beendet")
