class_name RoadCare
extends RefCounted
## Strassenwartung und Bautrupps (Auftrag 9, Etappe 4, docs/TOWN_HALL.md).
## Die Strassen sind in Abschnitte zu 16 x 16 Feldern geteilt. Jeder Abschnitt hat einen Zustand (0-100), der taeglich sinkt: Grundverschleiss,
## Verkehr (Fahrzeugsekunden im Verhaeltnis zum Mittel), Frost und Regen. Unter 50 % fahren Fahrzeuge dort langsamer und haben mehr Pannen
## (mild, Annahme 2). Der Buergermeister laesst Abschnitte instand setzen: in Eigenleistung durch die Strassenmeisterei (Zahl der Trupps aus
## dem Personal) oder durch eine Baufirma (teurer, schneller). Waehrend der Arbeiten steht am Arbeitsort eine Spur weniger zur Verfuegung,
## und ein Bautrupp mit Absperrung ist auf der Karte zu sehen (SiteView).

const SEG := 16
const DECAY_BASE := 0.005                # Punkte je Tag ohne Verkehr (ruhige Strassen halten Jahre)
const DECAY_TRAFFIC := 0.04              # Punkte je Tag bei mittlerem Verkehr (hoechstens das Vierfache: Hauptachsen nach rund einem halben Jahr unter 50 %)
const FROST := 2.0                       # Faktor bei Frost
const RAIN := 0.05                       # zusaetzlich bei Regen
const BAD := 50.0                        # darunter Wirkung auf Tempo und Pannen
const SLOW_MAX := 0.3                    # hoechster Tempoverlust (Zustand 0)
const MODES := {
	"eigen": {"label": "Straßenmeisterei", "cost": 1500.0, "days": 3},
	"firma": {"label": "Baufirma", "cost": 8000.0, "days": 2},
}
const STAFF_PER_CREW := 4                # Kraefte der Strassenmeisterei je Bautrupp
const MAX_FIRM_JOBS := 2

var sim
var cells := {}                          # Abschnitt (Vector2i) -> Arbeitsort (Strassenzelle nahe der Mitte)
var cond := {}                           # Abschnitt -> Zustand 0..100
var usage := {}                          # Abschnitt -> Fahrzeugsekunden heute
var road_count := {}                     # Abschnitt -> Strassenfelder (Hauptachsen fuer den Winterdienst)
var jobs := {}                           # "S<n>" -> {id, seg, cell, mode, start, end, cost, status}
var works := {}                          # Strassenzelle -> Auftrags-ID (laufende Arbeiten)
var stats := {"repairs": 0, "spent": 0.0}
var _next := 1
var _day := -1


func setup(simulation) -> void:
	sim = simulation
	cells.clear()
	cond.clear()
	road_count.clear()
	var best := {}
	var C = sim.city
	for y in C.size:
		for x in C.size:
			var p := Vector2i(x, y)
			if not C.is_road(p):
				continue
			var seg := Vector2i(x / SEG, y / SEG)
			road_count[seg] = int(road_count.get(seg, 0)) + 1
			var mid := Vector2(seg.x * SEG + SEG / 2, seg.y * SEG + SEG / 2)
			var d := Vector2(p).distance_squared_to(mid)
			if not best.has(seg) or d < float(best[seg]):
				best[seg] = d
				cells[seg] = p
	for seg in cells:
		cond[seg] = 70.0 + 30.0 * float(absi(hash(Vector3i(seg.x, seg.y, int(C.seed_value)))) % 1000) / 1000.0   # Startzustand 70-100 %
	_day = GameCalendar.day_of(sim.game_min)


static func seg_of(cell: Vector2i) -> Vector2i:
	return Vector2i(cell.x / SEG, cell.y / SEG)


static func seg_id(seg: Vector2i) -> String:
	return "A%d_%d" % [seg.x, seg.y]


static func parse_id(id: String) -> Vector2i:
	var parts := id.trim_prefix("A").split("_")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i(-1, -1)
	return Vector2i(int(parts[0]), int(parts[1]))


func condition_at(cell: Vector2i) -> float:
	return float(cond.get(seg_of(cell), 100.0))


## Tempofaktor (0,7..1) aus dem Strassenzustand.
func factor(cell: Vector2i) -> float:
	var c := condition_at(cell)
	return 1.0 if c >= BAD else 1.0 - SLOW_MAX * (BAD - c) / BAD


## Faktor auf die Pannenwahrscheinlichkeit (1..2).
func breakdown_factor(cell: Vector2i) -> float:
	var c := condition_at(cell)
	return 1.0 if c >= BAD else 1.0 + (BAD - c) / BAD


## Verschleiss durch Verkehr: je Simulationsschritt eines fahrenden Fahrzeugs.
func wear(cell: Vector2i, dt: float) -> void:
	var seg := seg_of(cell)
	usage[seg] = float(usage.get(seg, 0.0)) + dt


func under_works(cell: Vector2i) -> bool:
	return works.has(cell)


func on_day(day: int) -> void:
	if day == _day:
		return
	_day = day
	var mean := 0.0
	for u in usage.values():
		mean += float(u)
	mean = mean / maxf(1.0, float(usage.size()))
	var frost: bool = sim.wx.cur.has("temp") and float(sim.wx.cur.temp) <= 0.0
	var rain: bool = sim.wx.cur.has("cond") and sim.wx.is_rain()
	for seg in cond:
		if jobs.values().any(func(j): return j.status == "laufend" and j.seg == seg):
			continue
		var rel := minf(4.0, float(usage.get(seg, 0.0)) / mean) if mean > 0.0 else 0.0
		var loss := (DECAY_BASE + DECAY_TRAFFIC * rel) * (FROST if frost else 1.0) + (RAIN if rain else 0.0)
		cond[seg] = maxf(0.0, float(cond[seg]) - loss)
	usage.clear()
	for j in jobs.values():
		if j.status == "laufend" and day >= int(j.end):
			_finish(j)


func crews() -> int:
	return maxi(1, sim.town_hall.staff("strassen") / STAFF_PER_CREW)


func running(mode: String) -> int:
	return jobs.values().filter(func(j): return j.status == "laufend" and j.mode == mode).size()


## Instandsetzung eines Abschnitts anordnen (Buergermeister). mode eigen | firma.
func order(id: String, mode: String, by: String = "") -> Dictionary:
	var seg := parse_id(id)
	if not cells.has(seg):
		return {"ok": false, "msg": "Unbekannter Straßenabschnitt '%s' (siehe obs.strassen.schlechteste)." % id}
	if not MODES.has(mode):
		return {"ok": false, "msg": "Ausführung muss eigen (Straßenmeisterei) oder firma (Baufirma) sein."}
	if jobs.values().any(func(j): return j.status == "laufend" and j.seg == seg):
		return {"ok": false, "msg": "Am Abschnitt %s wird schon gearbeitet." % id}
	if mode == "eigen" and running("eigen") >= crews():
		return {"ok": false, "msg": "Alle %d Bautrupps der Straßenmeisterei sind im Einsatz (mehr Personal über hire_staff strassen oder Baufirma beauftragen)." % crews()}
	if mode == "firma" and running("firma") >= MAX_FIRM_JOBS:
		return {"ok": false, "msg": "Höchstens %d Baufirmen-Aufträge gleichzeitig." % MAX_FIRM_JOBS}
	var cost := float(MODES[mode].cost)
	var M: Mayor = sim.towns.mayor(sim.towns.of_cell(cells[seg]))   # Wartungszustaendigkeit: Verwaltungsgebiet des Abschnitts
	if M.available_budget() < cost:
		return {"ok": false, "msg": "Verfügbare Stadtkasse (%s) reicht nicht für %s." % [Catalog.money(M.available_budget()), Catalog.money(cost)]}
	sim.economy.transfer(M.acct(), "S0", cost)   # Material bzw. Werklohn der Baufirma
	stats.spent += cost
	var today := GameCalendar.day_of(sim.game_min)
	var j := {"id": "S%d" % _next, "seg": seg, "cell": cells[seg], "mode": mode, "start": today, "end": today + int(MODES[mode].days), "cost": cost,
		"status": "laufend", "before": snappedf(float(cond[seg]), 0.1)}
	_next += 1
	jobs[j.id] = j
	works[j.cell] = j.id
	var msg := "Instandsetzung Straßenabschnitt %s (Zustand %.0f %%) durch %s, %d Tage, %s; eine Spur gesperrt." % [id, float(cond[seg]), MODES[mode].label, int(MODES[mode].days), Catalog.money(cost)]
	sim.log_event(msg, "info")
	sim.activity.add("buergermeister", -1, "stadt", "Bautrupp %s: Abschnitt %s" % [MODES[mode].label, id], by, j.cell)
	sim.fleet.send_crew(j.cell, GameCalendar.day_start(int(j.end)), str(MODES[mode].label))
	return {"ok": true, "msg": msg, "ref": j.id}


func _finish(j: Dictionary) -> void:
	j.status = "fertig"
	cond[j.seg] = 100.0
	sim.city_depot.add_materials(CityDepot.MATERIAL_ROAD, "Aufbruch Straßenabschnitt %s" % seg_id(j.seg))
	works.erase(j.cell)
	stats.repairs += 1
	sim.log_event("Straßenabschnitt %s instand gesetzt (%s)." % [seg_id(j.seg), MODES[j.mode].label], "good")
	if jobs.size() > 40:
		for id in jobs.keys():
			if jobs[id].status == "fertig":
				jobs.erase(id)
				break


## Bautrupp fuer die Anzeige (gleiches Format wie Construction.crew_of).
func crew_of(j: Dictionary) -> Dictionary:
	var own: bool = j.mode == "eigen"
	return {"phase": "strasse", "role": "Straßenbau", "foreman": 1, "workers": 3 if own else 4, "operators": 1, "gear": ["lkw"] if own else ["bagger", "lkw"],
		"working": true, "people": 5 if own else 6, "builder": MODES[j.mode].label}


func mean_condition() -> float:
	var s := 0.0
	for v in cond.values():
		s += float(v)
	return s / maxf(1.0, float(cond.size()))


func summary() -> Dictionary:
	var segs: Array = cond.keys()
	segs.sort_custom(func(a, b): return float(cond[a]) < float(cond[b]) or (float(cond[a]) == float(cond[b]) and seg_id(a) < seg_id(b)))
	var worst: Array = []
	for seg in segs:
		if worst.size() >= 6:
			break
		if jobs.values().any(func(j): return j.status == "laufend" and j.seg == seg):
			continue
		worst.append({"abschnitt": seg_id(seg), "x": cells[seg].x, "y": cells[seg].y, "zustand": snappedf(float(cond[seg]), 0.1)})
	var below := segs.filter(func(s): return float(cond[s]) < BAD).size()
	return {"abschnitte": cond.size(), "mittlerer_zustand": snappedf(mean_condition(), 0.1), "unter_50_prozent": below, "schlechteste": worst,
		"bautrupps_eigen": crews(), "bautrupps_frei": maxi(0, crews() - running("eigen")), "baufirmen_frei": maxi(0, MAX_FIRM_JOBS - running("firma")),
		"laufend": jobs.values().filter(func(j): return j.status == "laufend").map(func(j): return {"id": j.id, "abschnitt": seg_id(j.seg), "ausfuehrung": j.mode, "fertig_tag": j.end}),
		"kosten": {"eigen": MODES.eigen.cost, "firma": MODES.firma.cost}, "instandsetzungen": int(stats.repairs)}


func to_dict() -> Dictionary:
	var c := {}
	for seg in cond:
		c[seg_id(seg)] = snappedf(float(cond[seg]), 0.01)
	var js := {}
	for id in jobs:
		var j: Dictionary = jobs[id].duplicate()
		j.seg = seg_id(j.seg)
		j.cell = [j.cell.x, j.cell.y]
		js[id] = j
	return {"cond": c, "jobs": js, "stats": stats.duplicate(), "next": _next}


func from_dict(d: Dictionary) -> void:
	if d.is_empty():
		return
	for k in d.get("cond", {}):
		var seg := parse_id(str(k))
		if cells.has(seg):
			cond[seg] = float(d.cond[k])
	jobs = {}
	works = {}
	for id in d.get("jobs", {}):
		var j: Dictionary = d.jobs[id]
		j.seg = parse_id(str(j.seg))
		j.cell = Vector2i(int(j.cell[0]), int(j.cell[1]))
		j.start = int(j.start)
		j.end = int(j.end)
		jobs[str(id)] = j
		if j.status == "laufend":
			works[j.cell] = str(id)
	stats = d.get("stats", stats)
	_next = int(d.get("next", 1))
