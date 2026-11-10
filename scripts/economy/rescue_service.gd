class_name RescueService
extends RefCounted
## Rettungsdienst und Krankenhaeuser (Auftrag 20, Etappe 5, docs/PUBLIC_SERVICES.md). Baut auf Municipal und PublicSafety auf:
##  - Schwere Erkrankungen (PublicSafety) loesen in der Region einen Notfall aus. Alarm an die Rettungswache mit der kuerzesten
##    Ankunftszeit (freies RTW, 2 Notfallsanitaeter); bei lebensbedrohlichen Faellen faehrt zusaetzlich das NEF mit Notarzt, wenn vorhanden.
##  - Hilfsfrist: Zeit vom Notruf bis zum Eintreffen; Ziel 15 Spielminuten. Statistik je Stadt.
##  - Versorgung vor Ort (verbraucht Sanitaetsmaterial aus dem Stadtlager; fehlt es, dauert sie laenger), Transport in das naechste
##    Krankenhaus mit freiem Bett. Betten: Plaetze des Hauses, begrenzt durch Personal (je Pflegekraft 4 Betten, mindestens ein Arzt).
##    Ohne freies Bett: Notversorgung in der Arztpraxis der Stadt.
##  - Behandlungskosten bucht weiterhin PublicSafety (Stadtkasse an Dienstleister); hier nur Einsatzablauf, Betten und Material.

const TURNOUT := 2.0              # Ausrueckzeit (Spielminuten)
const CARE_MIN := 10.0            # Versorgung vor Ort
const CARE_NO_MATERIAL := 5.0     # ... laenger ohne Sanitaetsmaterial
const HANDOVER_MIN := 5.0         # Uebergabe in der Klinik
const HILFSFRIST := 15.0
const NEF_SHARE := 0.25           # Anteil lebensbedrohlicher Notfaelle
const CREW := 2
const BEDS_PER_NURSE := 4
const SPEED := 3.6
const KEEP_DONE := 80

var sim
var missions := {}        # "N<n>" -> Einsatz
var movers := {}          # Fahrzeug-ID -> Mover (nicht gespeichert)
var stats := {"notfaelle": 0, "hilfsfrist_ok": 0, "eingetroffen": 0, "hilfsfrist_summe": 0.0, "krankenhaus": 0, "arztpraxis": 0,
	"nef": 0, "material_fehlt": 0, "wartend": 0}
var by_town := {}         # Stadt -> {notfaelle, eingetroffen, hilfsfrist_ok, hilfsfrist_summe}
var _next := 1


func setup(simulation) -> void:
	sim = simulation


func enabled() -> bool:
	return sim != null and sim.municipal != null and sim.municipal.enabled()


func _today() -> int:
	return GameCalendar.day_of(sim.game_min)


# ------------------------------------------------------------------ Krankenhausbetten
func hospitals() -> Array:
	return sim.municipal.facilities.values().filter(func(f): return f.code == "KH-01" and f.status == "in_betrieb")


## Betriebsbereite Betten: Plaetze des Hauses, aber nur so viele, wie Pflegekraefte versorgen koennen, und nur mit mindestens einem Arzt.
func beds(f: Dictionary) -> int:
	var M: Municipal = sim.municipal
	if M.staff_count(f.id, "arzt") < 1:
		return 0
	return mini(int(f.capacity), M.staff_count(f.id, "pflege") * BEDS_PER_NURSE)


func occupied(f: Dictionary) -> int:
	var day := _today()
	var n := 0
	for p in sim.citizens.people:
		if str(p.get("hospital_of", "")) == str(f.id) and int(p.get("sick_until", -1)) > day:
			n += 1
	return n


func free_bed(near: Vector2i) -> Dictionary:
	var best := {}
	var best_d := INF
	for f in hospitals():
		if occupied(f) + _incoming(f.id) >= beds(f):
			continue
		var d := float(sim.nav.path_length(near, sim.city.building(int(f.building)).road))
		if d >= 0.0 and d < best_d:
			best_d = d
			best = f
	return best


func _incoming(fid: String) -> int:
	return missions.values().filter(func(m): return str(m.hospital) == fid and m.phase in ["transport", "uebergabe"]).size()


# ------------------------------------------------------------------ Notruf
## Schwerer Fall eines Buergers (von PublicSafety). Gibt die Einsatznummer zurueck ("" = keine Rettungswache in der Region).
func emergency(p: Dictionary, cell: Vector2i) -> String:
	var k: int = sim.citizens.home_town(p)
	var id := "N%d" % _next
	_next += 1
	var crit: bool = Citizens.roll(int(p.id), _today(), 81) < NEF_SHARE
	var m := {"id": id, "patient": int(p.id), "name": str(p.name), "town": k, "cell": [cell.x, cell.y], "critical": crit, "rtw": "", "nef": "",
		"station": "", "task": "", "hospital": "", "phase": "wartet", "alarm": sim.game_min, "t": sim.game_min, "status": "laufend"}
	missions[id] = m
	stats.notfaelle = int(stats.notfaelle) + 1
	_town(k).notfaelle = int(_town(k).notfaelle) + 1
	_dispatch(m)
	return id


## Strasse vor der Wohnung eines Buergers (ohne Wohnung: Rathaus seiner Stadt).
func home_road(p: Dictionary) -> Vector2i:
	var u: Dictionary = sim.housing.units.get(str(p.get("home", "")), {})
	if not u.is_empty():
		return sim.city.building(int(u.building)).road
	return sim.city.building(int(sim.towns.get_t(sim.citizens.home_town(p)).town_hall)).road


func _town(k: int) -> Dictionary:
	if not by_town.has(k):
		by_town[k] = {"notfaelle": 0, "eingetroffen": 0, "hilfsfrist_ok": 0, "hilfsfrist_summe": 0.0}
	return by_town[k]


func eta(st: Dictionary, target: Vector2i) -> float:
	var tiles: int = sim.nav.path_length(sim.city.building(int(st.building)).road, target)
	return INF if tiles < 0 else TURNOUT + float(tiles) / SPEED * Catalog.GAME_MIN_PER_SIM_SEC


func _free(st: Dictionary, vtype: String) -> String:
	for vid in st.vehicles:
		var v: Dictionary = sim.municipal.vehicles[vid]
		if str(v.type) == vtype and v.status == "bereit":
			return vid
	return ""


func _dispatch(m: Dictionary) -> void:
	var M: Municipal = sim.municipal
	var target := Vector2i(int(m.cell[0]), int(m.cell[1]))
	var best := {}
	var best_t := INF
	for st in M.facilities.values():
		if st.code != "RW-01" or st.status != "in_betrieb" or _free(st, "RTW") == "":
			continue
		var e: float = eta(st, target)
		if e < best_t:
			best_t = e
			best = st
	if best.is_empty():
		return   # bleibt "wartet"; update() versucht es erneut
	var need: Array = ["RTW"]
	var nef: bool = m.critical and _free(best, "NEF") != "" and M.staff_count(best.id, "notarzt") > 0
	if nef:
		need.append("NEF")
	var t: Dictionary = M.open_task(best.id, "notfall", target, 3, CREW + (1 if nef else 0), need, {"notfall": m.id})
	var r: Dictionary = M.dispatch(t.id)
	if not r.ok and nef:   # ohne Notarzt-Besatzung: nur RTW
		M.finish(t.id, "ohne NEF neu disponiert")
		nef = false
		t = M.open_task(best.id, "notfall", target, 3, CREW, ["RTW"], {"notfall": m.id})
		r = M.dispatch(t.id)
	if not r.ok:
		M.finish(t.id, "nicht ausgerückt: " + str(r.msg))
		return
	m.station = best.id
	m.task = t.id
	m.rtw = str(t.vehicles[0])
	m.nef = str(t.vehicles[1]) if nef else ""
	if nef:
		stats.nef = int(stats.nef) + 1
	m.phase = "ausruecken"
	m.t = sim.game_min + TURNOUT
	sim.activity.add("stadt", -1, "gesundheit", "%s rückt aus: Notfall bei %s" % [best.name, m.name], "lebensbedrohlich, mit Notarzt" if nef else "schwer erkrankt", target)


func mover_of(vid: String) -> Mover:
	if not movers.has(vid):
		var M: Municipal = sim.municipal
		var mv := Mover.new()
		mv.speed = SPEED
		mv.pos = sim.city.tile_center(sim.city.building(M.building_of(str(M.vehicles[vid].facility))).road)
		movers[vid] = mv
	return movers[vid]


# ------------------------------------------------------------------ Ablauf
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
					for vid in _vehicles(m):
						sim.route(mover_of(vid), to)
			"anfahrt":
				if _drive(m, dt):
					var hf: float = now - float(m.alarm)
					m["hilfsfrist"] = hf
					stats.eingetroffen = int(stats.eingetroffen) + 1
					stats.hilfsfrist_summe = float(stats.hilfsfrist_summe) + hf
					var tw := _town(int(m.town))
					tw.eingetroffen = int(tw.eingetroffen) + 1
					tw.hilfsfrist_summe = float(tw.hilfsfrist_summe) + hf
					if hf <= HILFSFRIST:
						stats.hilfsfrist_ok = int(stats.hilfsfrist_ok) + 1
						tw.hilfsfrist_ok = int(tw.hilfsfrist_ok) + 1
					m.phase = "versorgung"
					m.t = now + CARE_MIN + (0.0 if _material(m) else CARE_NO_MATERIAL)
			"versorgung":
				if now >= float(m.t):
					_to_hospital(m)
			"transport":
				if _drive(m, dt, true):
					m.phase = "uebergabe"
					m.t = now + HANDOVER_MIN
			"uebergabe":
				if now >= float(m.t):
					_handover(m)
			"rueckfahrt":
				if _drive(m, dt):
					m.status = "fertig"
					m.phase = "fertig"
					m["end"] = now
					sim.municipal.finish(m.task, "Notfall %s: %s" % [m.id, "Krankenhaus" if m.hospital != "" else "Arztpraxis"])
					_prune()


func _vehicles(m: Dictionary) -> Array:
	return [m.rtw] + ([m.nef] if m.nef != "" else [])


## Alle Fahrzeuge des Einsatzes fahren; fertig, wenn alle angekommen sind. only_rtw: nur das RTW (Transport).
func _drive(m: Dictionary, dt: float, only_rtw := false) -> bool:
	var done := true
	for vid in ([m.rtw] if only_rtw else _vehicles(m)):
		var mv := mover_of(vid)
		if not mv.arrived():
			mv.advance(dt, 1.0)
			done = false
	return done


func _material(m: Dictionary) -> bool:
	var D = sim.towns.depot(int(m.town))
	if D == null or D.building < 0:
		return true
	var got: int = sim.stock.consume("sanitaet", 1, D.owner(), D.building, "Rettungseinsatz %s" % m.id, sim.game_min)
	if got < 1:
		stats.material_fehlt = int(stats.material_fehlt) + 1
		return false
	return true


func _to_hospital(m: Dictionary) -> void:
	var from := Vector2i(int(m.cell[0]), int(m.cell[1]))
	var h := free_bed(from)
	var dest := -1
	if not h.is_empty():
		m.hospital = h.id
		dest = int(h.building)
	else:
		dest = _practice(int(m.town))
	m.phase = "transport"
	if dest < 0:
		_handover(m)
		return
	sim.route(mover_of(m.rtw), sim.city.building(dest).road)
	if m.nef != "":   # Notarzt begleitet nur bis zur Uebergabe an das RTW-Team, faehrt dann zurueck
		sim.route(mover_of(m.nef), sim.city.building(sim.municipal.building_of(str(m.station))).road)


func _practice(k: int) -> int:
	for b in sim.city.buildings:
		if b.role == "doctor" and sim.towns.of_building(int(b.id)) == k:
			return int(b.id)
	return -1


func _handover(m: Dictionary) -> void:
	var p: Dictionary = {}
	for q in sim.citizens.people:
		if int(q.id) == int(m.patient):
			p = q
			break
	if m.hospital != "":
		stats.krankenhaus = int(stats.krankenhaus) + 1
		if not p.is_empty():
			p["hospital_of"] = m.hospital
			p.in_hospital = true
		sim.activity.add("stadt", -1, "gesundheit", "%s im %s aufgenommen" % [m.name, sim.municipal.facilities[m.hospital].name], "Notaufnahme",
			sim.city.building(int(sim.municipal.facilities[m.hospital].building)).road)
	else:
		stats.arztpraxis = int(stats.arztpraxis) + 1
		if not p.is_empty():
			p.in_hospital = false
			p.erase("hospital_of")
		sim.log_event("Kein freies Krankenhausbett: %s wird in der Arztpraxis notversorgt." % m.name, "warn")
	m.phase = "rueckfahrt"
	var home: Vector2i = sim.city.building(sim.municipal.building_of(str(m.station))).road
	for vid in _vehicles(m):
		sim.route(mover_of(vid), home)


func _prune() -> void:
	var done: Array = missions.values().filter(func(m): return m.status == "fertig")
	if done.size() > KEEP_DONE:
		done.sort_custom(func(a, b): return float(a.get("end", 0.0)) < float(b.get("end", 0.0)))
		for i in done.size() - KEEP_DONE:
			missions.erase(done[i].id)


# ------------------------------------------------------------------ Anzeige, Uebersicht, Speichern
## Fahrzeuge auf der Strasse fuer die Karte: [{vid, mover, siren}]
func on_road() -> Array:
	var out: Array = []
	for m in missions.values():
		if m.status != "laufend" or m.phase in ["wartet", "ausruecken"]:
			continue
		for vid in _vehicles(m):
			if movers.has(vid):
				out.append({"vid": vid, "mover": movers[vid], "siren": m.phase in ["anfahrt", "transport"]})
	return out


func summary(k: int = -1) -> Dictionary:
	var s: Dictionary = stats if k < 0 else _town(k)
	var n := int(s.eingetroffen)
	return {"notfaelle": int(s.notfaelle), "mittlere_hilfsfrist_min": snappedf(float(s.hilfsfrist_summe) / maxf(1.0, float(n)), 0.1),
		"hilfsfrist_eingehalten_anteil": snappedf(float(s.hilfsfrist_ok) / maxf(1.0, float(n)), 0.01),
		"krankenhaeuser": hospitals().map(func(f): return "%s: %d/%d Betten belegt" % [f.name, occupied(f), beds(f)]),
		"laufend": missions.values().filter(func(m): return m.status == "laufend" and (k < 0 or int(m.town) == k)).size()}


func to_dict() -> Dictionary:
	return {"missions": missions.duplicate(true), "stats": stats.duplicate(), "by_town": by_town.duplicate(true), "next": _next}


## Laden: laufende Einsaetze werden abgeschlossen (Fahrzeuge stehen in der Wache); der Patient gilt als versorgt (Arztpraxis).
func from_dict(d: Dictionary) -> void:
	if d.is_empty():
		return
	missions = d.get("missions", {})
	stats = d.get("stats", stats)
	_next = int(d.get("next", 1))
	for k in d.get("by_town", {}):
		by_town[int(k)] = d.by_town[k]
	for m in missions.values():
		m.patient = int(m.patient)
		m.town = int(m.town)
		if m.status == "laufend":
			if m.task != "" and sim.municipal.tasks.has(m.task):
				sim.municipal.finish(m.task, "beim Laden abgeschlossen")
			m.status = "fertig"
			m.phase = "fertig"
