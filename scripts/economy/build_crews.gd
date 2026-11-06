class_name BuildCrews
extends RefCounted
## Bautrupps (Auftrag von Benedikt, 06.11.2026): jede Baufirma hat so viele Trupps wie Kapazitaet (Unternehmer-Baufirmen: je drei
## zugeordnete Leute ein Trupp). Ein Trupp baut immer nur ein Vorhaben. Ablauf: Bauhof -> Lager (Material laden) -> Baustelle (bauen)
## -> bei Bedarf erneut Material holen -> fertig -> zurueck zum Bauhof. Privatbauten holen beim Bauhof (T0), sonst im Hafenlager (X0);
## Stadtprojekte holen ihr reserviertes Material im Stadtlager. Gebaut wird nur, wenn der Trupp vor Ort ist.
## Die Logik laeuft ueber Spielzeit (Fahrtdauer aus der Entfernung), damit Tageslaeufe ohne Einzelschritte stimmen; sichtbar faehrt
## je Trupp ein Baukolonnen-Fahrzeug des Stadtfuhrparks (Art "kolonne").

const MIN_PER_CELL := 0.4          # Fahrtdauer je Feld (Spielminuten)
const MIN_TRIP := 6.0
const MAX_TRIP := 90.0
const LOAD_MIN := 20.0             # Laden im Lager
const RETRY_MIN := 60.0            # fehlt Material, erneut nachsehen

var sim
var crews := {}                    # "T<n>" -> {id, builder, name, home: [x, y], state, job: {kind, id}, site: [x, y], at: [x, y], next: Minute, delivery, src, note}
var _next := 1
var _vehicles := {}                # Trupp-ID -> Fahrzeug im Stadtfuhrpark (nur Darstellung)
var stats := {"fahrten": 0, "hafen": 0, "fertig": 0}


func setup(simulation) -> void:
	sim = simulation


# ------------------------------------------------------------------ Bestand
## Trupps je Baufirma an die Kapazitaet anpassen (nur freie Trupps werden aufgeloest).
func sync() -> void:
	var C = sim.construction
	for bid in C.builders:
		var b: Dictionary = C.builders[bid]
		var want: int = int(b.capacity) if b.status == "aktiv" else 0
		var mine: Array = crews.values().filter(func(t): return t.builder == bid)
		var n := mine.size()
		while n < want:
			var t := {"id": "T%d" % _next, "builder": bid, "name": "%s Trupp %d" % [b.name, n + 1], "home": _arr(_home_of(bid)), "state": "frei",
				"job": {}, "site": [], "at": _arr(_home_of(bid)), "next": 0.0, "delivery": "", "src": "", "note": ""}
			_next += 1
			crews[t.id] = t
			n += 1
		for t in mine:
			if n <= want:
				break
			if t.state == "frei":
				_drop_vehicle(t.id)
				crews.erase(t.id)
				n -= 1


## Heimat: staedtische Baufirmen am Bauhof, Unternehmer-Baufirmen am Hauptsitz.
func _home_of(bid: String) -> Vector2i:
	var b: Dictionary = sim.construction.builders.get(bid, {})
	if b.has("company"):
		return sim.depot_road(int(b.company))
	var yard: Dictionary = sim.city.building(int(sim.trader.bauhof))
	return yard.road if not yard.is_empty() else sim.fleet.depot_road()


# ------------------------------------------------------------------ Zuteilung
## Vorhaben, die einen Trupp brauchen: [{kind, id, builder, site}] (privat: Erschliessung und Bau ab Baubeginn; Stadt: laufend mit Material).
func demand() -> Array:
	var C = sim.construction
	var today := GameCalendar.day_of(sim.game_min)
	var out: Array = []
	for pr in C.projects.values():
		if pr.status in ["erschliessung", "im_bau"] and today >= int(pr.start) and str(pr.get("builder", "")) != "":
			out.append({"kind": "bp", "id": pr.id, "builder": pr.builder})
	for pid in C.public:
		var e: Dictionary = C.public[pid]
		if e.status == "laufend" and today >= int(e.start) and sim.city_depot.project_complete(str(pid)):
			out.append({"kind": "pub", "id": pid, "builder": e.builder})
	return out


func crew_for(kind: String, id: String) -> Dictionary:
	for t in crews.values():
		if not t.job.is_empty() and t.job.kind == kind and t.job.id == id:
			return t
	return {}


## Ist der Trupp des Vorhabens auf der Baustelle und arbeitet?
func on_site(kind: String, id: String) -> bool:
	var t := crew_for(kind, id)
	return not t.is_empty() and t.state == "bauen"


## Vorhaben ohne Trupp (Baunachfrage): fuer die Beobachtung der Unternehmer und die Anzeige.
func waiting() -> Array:
	return demand().filter(func(d): return crew_for(d.kind, d.id).is_empty())


func _assign() -> void:
	for d in waiting():
		var free: Array = crews.values().filter(func(t): return t.builder == d.builder and t.state == "frei")
		if free.is_empty():
			continue
		var t: Dictionary = free[0]
		t.job = {"kind": d.kind, "id": d.id}
		t.site = _arr(_site_of(d.kind, d.id))
		t.note = ""
		_log(t, "übernimmt %s" % _job_label(t))
		_next_step(t, sim.game_min)


# ------------------------------------------------------------------ Ablauf
## Zustandswechsel bis zur aktuellen Spielzeit nachholen (auch bei Tageslaeufen ohne Einzelschritte).
func tick(now: float) -> void:
	for t in crews.values():
		var guard := 0
		while t.state != "frei" and t.state != "bauen" and float(t.next) <= now and guard < 8:
			guard += 1
			_arrive(t, float(t.next))
		if t.state == "bauen":
			_check_building(t, now)


func on_day(_day: int) -> void:
	sync()
	tick(sim.game_min)
	_assign()


## Ankunft am Ziel des aktuellen Abschnitts.
func _arrive(t: Dictionary, at_min: float) -> void:
	match str(t.state):
		"zum_lager":
			t.at = t.lager
			t.state = "laden"
			t.next = at_min + LOAD_MIN
		"laden":
			if not _load(t):
				t.state = "wartet_material"
				t.next = at_min + RETRY_MIN
				return
			_drive(t, _v(t.site), "zur_baustelle", at_min)
		"wartet_material":
			t.state = "laden"
			t.next = at_min
		"zur_baustelle":
			t.at = t.site
			_unload(t)
			t.state = "bauen"
			_log(t, "baut an %s" % _job_label(t))
		"rueckfahrt":
			t.at = t.home
			t.state = "frei"
			t.job = {}
			t.site = []
			_drop_vehicle(t.id)


## Naechster Schritt nach einer Zuteilung oder wenn auf der Baustelle Material fehlt.
func _next_step(t: Dictionary, now: float) -> void:
	var need := _material_need(t)
	if need.is_empty():
		_drive(t, _v(t.site), "zur_baustelle", now)
		return
	t.delivery = str(need.get("delivery", ""))
	t.src = str(need.src)
	t.lager = _arr(need.at)
	_drive(t, need.at, "zum_lager", now)


## Bauen: fehlt fuer die naechste Phase Material, faehrt der Trupp zum Lager; ist das Vorhaben fertig, zurueck zum Bauhof.
func _check_building(t: Dictionary, now: float) -> void:
	if not _job_active(t):
		stats.fertig += 1
		_log(t, "fertig mit %s, fährt zurück zum Bauhof" % _job_label(t))
		t.note = ""
		_drive(t, _v(t.home), "rueckfahrt", now)
		return
	if t.job.kind == "bp" and not _material_need(t).is_empty():
		_next_step(t, now)


func _job_active(t: Dictionary) -> bool:
	if t.job.kind == "bp":
		var pr: Dictionary = sim.construction.projects.get(t.job.id, {})
		return not pr.is_empty() and pr.status in ["erschliessung", "im_bau"]
	var e: Dictionary = sim.construction.public.get(t.job.id, {})
	return not e.is_empty() and e.status == "laufend"


## Was muss geholt werden? Privat: offene Lieferung der laufenden Phase (Bauhof, sonst Hafen); Stadt: einmal das reservierte Material.
func _material_need(t: Dictionary) -> Dictionary:
	if t.job.kind == "pub":
		var e: Dictionary = sim.construction.public[t.job.id]
		if bool(e.get("crew_loaded", false)):
			return {}
		return {"src": "stadtlager", "at": sim.city.building(sim.city_depot.building).road}
	var pr: Dictionary = sim.construction.projects[t.job.id]
	if pr.status != "im_bau":
		return {}
	var ph: Dictionary = Construction.PHASES[clampi(int(pr.phase), 0, Construction.PHASES.size() - 1)]
	if not pr.mats.has(ph.id) or pr.mats[ph.id].ready:
		return {}
	sim.construction.order_phase_material(pr, ph.id)
	var d: Dictionary = {}
	for x in sim.construction.deliveries.values():
		if x.project == pr.id and x.phase == ph.id and x.status in ["offen", "unterwegs"]:
			d = x
	if d.is_empty() or d.status == "unterwegs" and str(d.get("carrier", "")) != t.id:
		return {}   # eine Transportfirma bringt es gerade
	var src: String = sim.construction.material_source(d)
	if src == "hafen":
		return {"delivery": d.id, "src": "hafen", "at": sim.city.building(sim.harbor.building).road}
	return {"delivery": d.id, "src": "bauhof", "at": sim.city.building(int(sim.trader.bauhof)).road}


func _load(t: Dictionary) -> bool:
	if t.job.kind == "pub":
		var e: Dictionary = sim.construction.public[t.job.id]
		e["crew_loaded"] = true
		t.note = "Material aus dem Stadtlager geladen"
		return true
	var d: Dictionary = sim.construction.deliveries.get(str(t.delivery), {})
	if d.is_empty() or d.status == "geliefert":
		return true
	var r: Dictionary = sim.construction.crew_load(d, str(t.src), str(t.id))
	t.note = str(r.msg)
	if r.ok and t.src == "hafen":
		stats.hafen += 1
	return r.ok


func _unload(t: Dictionary) -> void:
	if t.job.kind == "bp" and str(t.delivery) != "":
		var d: Dictionary = sim.construction.deliveries.get(str(t.delivery), {})
		if not d.is_empty() and d.status == "unterwegs":
			sim.construction.crew_unload(d)
		t.delivery = ""


func _drive(t: Dictionary, to: Vector2i, state: String, now: float) -> void:
	var from := _v(t.at)
	var cells := absi(to.x - from.x) + absi(to.y - from.y)
	t.state = state
	t.next = now + clampf(MIN_TRIP + MIN_PER_CELL * float(cells), MIN_TRIP, MAX_TRIP)
	stats.fahrten += 1
	_show(t, from, to)


# ------------------------------------------------------------------ Orte
func _site_of(kind: String, id: String) -> Vector2i:
	if kind == "bp":
		var pr: Dictionary = sim.construction.projects[id]
		return nearest_road(_parcel_center(str(pr.parcel)))
	var prj: Dictionary = sim.mayor.projects.get(id, {})
	match str(prj.get("kind", "")):
		"zufahrt":
			var j: Dictionary = sim.access.jobs.get(str(prj.ref), {})
			if not j.is_empty():
				return nearest_road(sim.access._head(j))
		"bruecke":
			var b: Dictionary = sim.bridges.items.get(str(prj.bridge), {})
			if not b.is_empty():
				return nearest_road(Vector2i(int(b.ends[1][0]), int(b.ends[1][1])))
	if not prj.get("parcels", []).is_empty():
		return nearest_road(_parcel_center(str(prj.parcels[0])))
	return sim.fleet.depot_road()


func _parcel_center(pid: String) -> Vector2i:
	var p: Dictionary = sim.parcels.parcel(pid)
	if p.is_empty():
		return sim.fleet.depot_road()
	return Vector2i(int(p.rect[0]) + int(p.rect[2]) / 2, int(p.rect[1]) + int(p.rect[3]) / 2)


## Naechste Strassenzelle (Ringsuche), sonst das Rathaus.
func nearest_road(c: Vector2i, radius: int = 24) -> Vector2i:
	if sim.city.is_road(c):
		return c
	for r in range(1, radius + 1):
		for k in range(-r, r + 1):
			for q in [c + Vector2i(k, -r), c + Vector2i(k, r), c + Vector2i(-r, k), c + Vector2i(r, k)]:
				if sim.city.is_road(q):
					return q
	return sim.fleet.depot_road()


# ------------------------------------------------------------------ Darstellung (Stadtfuhrpark)
func _show(t: Dictionary, from: Vector2i, to: Vector2i) -> void:
	var v: Dictionary = _vehicles.get(t.id, {})
	if v.is_empty() or not sim.fleet.vehicles.has(v):
		v = sim.fleet._spawn("kolonne", from, to, 0.0, _v(t.home), str(t.name))
		_vehicles[t.id] = v
	else:
		sim.fleet.reroute(v, to)
	v["crew"] = t.id


func _drop_vehicle(id: String) -> void:
	var v: Dictionary = _vehicles.get(id, {})
	if not v.is_empty():
		sim.fleet.vehicles.erase(v)
	_vehicles.erase(id)


# ------------------------------------------------------------------ Anzeige, Speichern
func _job_label(t: Dictionary) -> String:
	if t.job.is_empty():
		return "-"
	if t.job.kind == "bp":
		var pr: Dictionary = sim.construction.projects.get(t.job.id, {})
		return "Bauvorhaben %s (%s)" % [t.job.id, Planning.DEFS.get(pr.get("def", ""), {}).get("label", "Gebäude")]
	var prj: Dictionary = sim.mayor.projects.get(t.job.id, {})
	return "Stadtprojekt %s (%s)" % [t.job.id, prj.get("kind", "")]


const STATE_TEXT := {"frei": "frei am Bauhof", "zum_lager": "fährt zum Lager", "laden": "lädt Material", "wartet_material": "wartet auf Material",
	"zur_baustelle": "fährt zur Baustelle", "bauen": "baut", "rueckfahrt": "fährt zurück zum Bauhof"}


func _log(t: Dictionary, text: String) -> void:
	sim.activity.add("stadt", _company_of(t), "bau", "%s %s" % [t.name, text], STATE_TEXT.get(t.state, t.state), _v(t.at) if not t.at.is_empty() else Vector2i.ZERO)


func _company_of(t: Dictionary) -> int:
	var b: Dictionary = sim.construction.builders.get(t.builder, {})
	return int(b.company) if b.has("company") else -1


func summary() -> Dictionary:
	var list: Array = crews.values().map(func(t): return {"id": t.id, "firma": sim.construction.builders.get(t.builder, {}).get("name", t.builder),
		"zustand": STATE_TEXT.get(t.state, t.state), "auftrag": _job_label(t), "hinweis": t.note})
	return {"trupps": list, "frei": crews.values().filter(func(t): return t.state == "frei").size(), "wartende_bauvorhaben": waiting().size(), "statistik": stats}


func to_dict() -> Dictionary:
	return {"crews": crews.duplicate(true), "next": _next, "stats": stats.duplicate()}


## Laden: Trupps mit ihrem Zustand; unterwegs befindliche Fahrzeuge werden neu angelegt.
func from_dict(d: Dictionary) -> void:
	crews = d.get("crews", {}).duplicate(true)
	_next = int(d.get("next", 1))
	stats = d.get("stats", stats)
	for t in crews.values():
		t.next = float(t.next)
		if t.state in ["zum_lager", "zur_baustelle", "rueckfahrt"]:
			_show(t, _v(t.at), _v(t.get("lager", t.at) if t.state == "zum_lager" else (t.site if t.state == "zur_baustelle" else t.home)))
		elif t.state in ["bauen", "laden", "wartet_material"]:
			_show(t, _v(t.at), _v(t.at))


static func _arr(v: Vector2i) -> Array:
	return [v.x, v.y]


static func _v(a) -> Vector2i:
	return Vector2i(int(a[0]), int(a[1])) if a is Array and a.size() >= 2 else Vector2i.ZERO
