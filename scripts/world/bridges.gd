class_name Bridges
extends RefCounted
## Bruecken (Auftrag 15, Etappe D). Eine Bruecke ist ein staedtisches Bauprojekt (Mayor-Projekt kind "bruecke"): ausgeschrieben,
## von einer Baufirma gebaut, Material aus dem Stadtlager (Importe kommen per Schiff). Bis zur Abnahme bleiben die Wasserfelder
## gesperrt; erst danach werden sie Strasse und gehoeren zur Wegesuche. Bezahlt wird vom Unternehmer (private Zufahrt, Beitrag an
## die Stadt) oder aus der Stadtkasse (Buergermeister). Ueber das Meer wird nicht gebaut, nur ueber Fluesse und Seen.

signal bridge_opened(id: String)

## Varianten: Grundkosten, Kosten je Feld, Bautage (Grund + je Feld), Tragfaehigkeit in t, groesste Spannweite in Feldern, Material je Feld
const VARIANTS := {
	"holz": {"label": "Holzbrücke", "base": 4000.0, "cell": 1500.0, "days": 3, "days_cell": 1.0, "last_t": 12, "max_span": 4,
		"material": {"holz": 10, "verbindung": 6}},
	"stein": {"label": "Steinbrücke", "base": 8000.0, "cell": 3500.0, "days": 4, "days_cell": 1.5, "last_t": 40, "max_span": 8,
		"material": {"pflaster": 6, "kies": 6, "verbindung": 2}},
	"stahlbeton": {"label": "Stahlbetonbrücke", "base": 15000.0, "cell": 6000.0, "days": 4, "days_cell": 1.0, "last_t": 60, "max_span": 16,
		"material": {"betonfertigteil": 8, "kies": 6, "schotter": 4}},
}
const ORDER := ["holz", "stein", "stahlbeton"]
const PHASES := [["widerlager", 0.25], ["pfeiler", 0.5], ["fahrbahn", 0.8], ["gelaender", 0.95], ["abnahme", 1.0]]
const LOAD_MINE := 30            # Erzlaster brauchen eine tragfaehige Bruecke
const LOAD_TOWN := 10

var sim
var items := {}                  # "BR<n>" -> {id, cells: [[x, y]], ends: [[x, y], [x, y]], variant, cost, days, project, payer, access, status, day}
var _next := 1
var _sea := PackedByteArray()    # 1 = Meer (mit dem Kartenrand verbundenes Wasser)
var _cells := {}                 # Vector2i -> Bruecken-ID (Darstellung, Wegebau)


func setup(simulation) -> void:
	sim = simulation


## Wasser, das mit dem Kartenrand verbunden ist (Meer). Einmal berechnet; Bruecken entstehen nur ueber Fluss und See.
func is_sea(q: Vector2i) -> bool:
	if _sea.is_empty():
		_flood_sea()
	return _sea[sim.city.idx(q)] == 1


func _flood_sea() -> void:
	var city: CityData = sim.city
	var n := city.size
	_sea.resize(n * n)
	_sea.fill(0)
	for q in city.river:   # der Fluss muendet ins Meer, bleibt aber ueberbrueckbar: Flusszellen sperren die Flutung
		_sea[city.idx(q)] = 2
	var queue := PackedInt32Array()
	for k in n:
		for q in [Vector2i(k, 0), Vector2i(k, n - 1), Vector2i(0, k), Vector2i(n - 1, k)]:
			var i := city.idx(q)
			if city.ground[i] == CityData.G.WATER and _sea[i] == 0:
				_sea[i] = 1
				queue.append(i)
	var head := 0
	while head < queue.size():
		var i: int = queue[head]
		head += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = Vector2i(i % n, i / n) + d
			if not city.inside(q):
				continue
			var j := city.idx(q)
			if _sea[j] == 0 and city.ground[j] == CityData.G.WATER:
				_sea[j] = 1
				queue.append(j)


## Wasserabschnitte eines Weges (Zellen von der Lagerstaette zur Strasse) als Brueckenplaene. Ergebnis {ok, spans: [{cells, ends, variant, cost, days}], kosten, tage}.
func plan_spans(path: Array, need_t: int) -> Dictionary:
	var spans: Array = []
	var run: Array = []
	for k in path.size() + 1:
		var q: Vector2i = path[k] if k < path.size() else Vector2i(-1, -1)
		if k < path.size() and sim.city.g(q) == CityData.G.WATER:
			run.append(q)
			continue
		if run.is_empty():
			continue
		var before: Vector2i = path[k - run.size() - 1] if k - run.size() - 1 >= 0 else _road_next(run[0])
		var after: Vector2i = q if k < path.size() else _road_next(run[run.size() - 1])
		var v := pick_variant(run.size(), need_t)
		if v == "":
			return {"ok": false, "msg": "Das Gewässer ist an dieser Stelle %d Felder breit – zu weit für jede Brückenart (höchstens %d)." % [run.size(), int(VARIANTS.stahlbeton.max_span)]}
		spans.append({"cells": run.duplicate(), "ends": [before, after], "variant": v, "cost": cost_of(v, run.size()), "days": days_of(v, run.size())})
		run.clear()
	var total := 0.0
	var days := 0
	for s in spans:
		total += float(s.cost)
		days = maxi(days, int(s.days))
	return {"ok": true, "spans": spans, "kosten": total, "tage": days}


## Strassennachbar einer Zelle (Brueckenende direkt an der bestehenden Strasse).
func _road_next(q: Vector2i) -> Vector2i:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if sim.city.is_road(q + d):
			return q + d
	return q


## Guenstigste Variante, die Spannweite und Last schafft ("" = keine).
static func pick_variant(span: int, need_t: int) -> String:
	for v in ORDER:
		if span <= int(VARIANTS[v].max_span) and int(VARIANTS[v].last_t) >= need_t:
			return v
	return ""


static func cost_of(v: String, span: int) -> float:
	return snappedf(float(VARIANTS[v].base) + float(VARIANTS[v].cell) * span, 10.0)


static func days_of(v: String, span: int) -> int:
	return int(VARIANTS[v].days) + int(ceil(float(VARIANTS[v].days_cell) * span))


## Bruecke anlegen und als Stadtprojekt ausschreiben. payer: Firmen-ID (hat schon an die Stadt gezahlt) oder -1 (Stadtkasse).
func create(span: Dictionary, payer: int, access_id: String, by: String) -> Dictionary:
	var b := {"id": "BR%d" % _next, "cells": span.cells.map(func(c): return [c.x, c.y]), "ends": span.ends.map(func(c): return [c.x, c.y]),
		"variant": str(span.variant), "cost": float(span.cost), "days": int(span.days), "payer": payer, "access": access_id,
		"status": "ausgeschrieben", "day": GameCalendar.day_of(sim.game_min), "project": ""}
	_next += 1
	var mat := {}
	for it in VARIANTS[b.variant].material:
		mat[it] = int(VARIANTS[b.variant].material[it]) * b.cells.size()
	var prj: Dictionary = sim.towns.mayor(sim.towns.of_cell(Vector2i(int(b.cells[0][0]), int(b.cells[0][1])))).add_works_project("bruecke", b.id, float(b.cost), int(b.days), mat, "Brücke %s (%s)" % [b.id, by], str(span.get("award", "")))
	b.project = prj.id
	items[b.id] = b
	_index(b)
	var at := Vector2i(int(b.cells[0][0]), int(b.cells[0][1]))
	sim.log_event("%s: %s %s über %d Felder Wasser ausgeschrieben (%s, %s, etwa %d Bautage, trägt %d t). Gesperrt bis zur Abnahme." % [by,
		VARIANTS[b.variant].label, b.id, b.cells.size(), prj.id, Catalog.money(float(b.cost)), int(b.days), int(VARIANTS[b.variant].last_t)], "info", payer)
	sim.activity.add("stadt", payer, "bau", "%s %s ausgeschrieben" % [VARIANTS[b.variant].label, b.id], by, at)
	return b


## Baufortschritt (0..1) aus der Ausfuehrung der Baufirma.
func progress(b: Dictionary) -> float:
	if b.status == "freigegeben":
		return 1.0
	return minf(0.99, sim.construction.public_progress(str(b.project)))


func phase(b: Dictionary) -> String:
	if b.status == "freigegeben":
		return "freigegeben"
	var e: Dictionary = sim.construction.public.get(str(b.project), {})
	if e.is_empty():
		return "ausgeschrieben"
	if str(e.get("waiting", "")) != "":
		return "wartet"
	var p := progress(b)
	for ph in PHASES:
		if p < float(ph[1]):
			return str(ph[0])
	return "abnahme"


## Abnahme (von Construction._finish_public): Wasserfelder werden Fahrbahn und gehoeren zur Wegesuche.
func finish(id: String) -> void:
	var b: Dictionary = items.get(id, {})
	if b.is_empty() or b.status == "freigegeben":
		return
	b.status = "freigegeben"
	b["opened"] = GameCalendar.day_of(sim.game_min)
	_open(b)
	sim.log_event("%s %s abgenommen und freigegeben – Fahrzeuge dürfen jetzt darüber fahren." % [VARIANTS[b.variant].label, b.id], "good", int(b.payer))
	sim.activity.add("stadt", int(b.payer), "bau", "%s %s freigegeben" % [VARIANTS[b.variant].label, b.id], "Abnahme bestanden", Vector2i(int(b.cells[0][0]), int(b.cells[0][1])))
	sim.access.on_bridge_opened()
	sim.access.roads_built.emit(b.cells.map(func(a): return Vector2i(int(a[0]), int(a[1]))))   # Strassenkacheln an den Enden neu verbinden
	bridge_opened.emit(id)


func _open(b: Dictionary) -> void:
	var city: CityData = sim.city
	for a in b.cells:
		var q := Vector2i(int(a[0]), int(a[1]))
		var i := city.idx(q)
		if city.ground[i] == CityData.G.ROAD or city.building_at[i] >= 0:
			continue   # schon Strasse bzw. bebaut: nie unter ein Gebaeude legen
		city.ground[i] = CityData.G.ROAD
		city.blocked[i] = 0
		sim.nav.road.set_point_solid(q, false)
		sim.nav.walk.set_point_solid(q, false)
		sim.nav.walk.set_point_weight_scale(q, 4.0)
		city.road_count += 1


func is_bridge(q: Vector2i) -> bool:
	return _cells.has(q)


func _index(b: Dictionary) -> void:
	for a in b.cells:
		_cells[Vector2i(int(a[0]), int(a[1]))] = b.id


func running() -> int:
	return items.values().filter(func(b): return b.status != "freigegeben").size()


## Gewaehlte Brueckenart pruefen: schafft sie Spannweite und Last?
static func valid_variant(v: String, span: int, need_t: int) -> bool:
	return VARIANTS.has(v) and span <= int(VARIANTS[v].max_span) and int(VARIANTS[v].last_t) >= need_t


## Vorschlaege fuer den Buergermeister: freie staedtische Grundstuecke (keine Lagerstaetten), die nur ueber eine Bruecke erreichbar sind.
var _prop_day := -1
var _props: Array = []
func proposals(limit: int = 3) -> Array:
	var today := GameCalendar.day_of(sim.game_min)
	if today == _prop_day:
		return _props
	_prop_day = today
	_props = []
	if not sim.city.coastal():
		return _props
	var deposits: Dictionary = sim.prod._deposits
	var seen := 0
	for p in sim.parcels.search({"limit": 4000}):
		if p.state != "frei" or not Towns.is_public(str(p.owner)) or deposits.has(p.id) or bool(sim.parcels.utilities_of(p).strasse):
			continue
		if str(p.get("zone", "")) not in ["wohnen", "mischgebiet", "gewerbe"]:
			continue
		seen += 1
		if seen > 60:
			break
		var pl: Dictionary = sim.access.plan(p.id, LOAD_TOWN)
		if pl.ok and not pl.get("bruecken", []).is_empty():
			_props.append({"grundstueck": p.id, "zone": p.zone, "kosten": int(pl.kosten), "tage": int(pl.tage), "felder_wasser": pl.bruecken.reduce(func(s, x): return s + x.cells.size(), 0),
				"art": VARIANTS[pl.bruecken[0].variant].label})
	_props.sort_custom(func(x, y): return int(x.kosten) < int(y.kosten))
	_props = _props.slice(0, limit)
	return _props


func summary() -> Dictionary:
	return {"bruecken": items.values().map(func(b): return {"id": b.id, "art": VARIANTS[b.variant].label, "status": b.status, "phase": phase(b),
		"fortschritt": snappedf(progress(b), 0.01), "felder": b.cells.size(), "kosten": int(b.cost), "tragfaehigkeit_t": int(VARIANTS[b.variant].last_t),
		"projekt": b.project, "bezahlt_von": "Stadt" if int(b.payer) < 0 else "Firma %d" % int(b.payer)}),
		"im_bau": running(), "vorschlaege": proposals()}


func to_dict() -> Dictionary:
	return {"items": items.duplicate(true), "next": _next}


## Laden: abgenommene Bruecken wieder befahrbar machen (die Welt kommt aus dem Seed).
func from_dict(d: Dictionary) -> void:
	items = d.get("items", {}).duplicate(true)
	_next = int(d.get("next", 1))
	_cells.clear()
	for b in items.values():
		b.payer = int(b.payer)
		_index(b)
		if b.status == "freigegeben":
			_open(b)
