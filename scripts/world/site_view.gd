class_name SiteView
extends Node2D
## Baustellen der Stadtentwicklung (Auftrag 7, Etappe 7): Absperrung des Grundstuecks und der Rohbau waechst mit den Bauphasen
## (Baugrube, Fundament, Wände, Dach, Hülle, Ausbau). Liest nur aus Simulation.construction; fertige Gebaeude zeichnet CityView.

const ACTIVE := ["erschliessung", "im_bau", "pruefung", "wartet_anschluss"]
const FLOOR_H := 44.0
const WALL := [Color("d9cdb4"), Color("b7ab92"), Color("e8dcc2")]       # links, rechts, oben
const SLAB := [Color("9a9a9a"), Color("7d7d7d"), Color("b4b4b4")]
const ROOF := [Color("a8553f"), Color("8c4331"), Color("c46a52")]
const PIT := Color("6b4f36")
const FENCE := Color("f2c14e")

var sim: Simulation
var _nodes := {}          # Bauvorhaben-ID -> {node, sig}
var _t := 0.0
var _clock := 0.0


func setup(simulation: Simulation) -> void:
	sim = simulation
	y_sort_enabled = true


func update_view(delta: float) -> void:
	_clock += delta
	_animate()
	_t += delta
	if _t < 0.5:
		return
	_t = 0.0
	var seen := {}
	for pr in sim.construction.projects.values():
		if pr.status not in ACTIVE:
			continue
		seen[pr.id] = true
		var sig := "%s|%d|%d|%s" % [pr.status, int(pr.phase), int(pr.progress * 8.0), str(pr.blockers.size())]
		if not _nodes.has(pr.id):
			var n := SiteNode.new()
			add_child(n)
			_nodes[pr.id] = {"node": n, "sig": ""}
		var e: Dictionary = _nodes[pr.id]
		if e.sig != sig:
			e.sig = sig
			_configure(e.node, pr)
	# Betriebsbauten der Unternehmer (Construction.works): Baustelle auf dem Gebaeudeplatz, Trupp nur wenn er vor Ort ist
	for w in sim.construction.works.values():
		if w.status != "laufend":
			continue
		var key := "works:" + str(w.id)
		seen[key] = true
		var k := sim.construction.works_progress(w)
		var on := sim.crews.on_site("cw", str(w.id))
		var sig2 := "%d|%s" % [int(k * 10.0), str(on)]
		if not _nodes.has(key):
			var n2 := SiteNode.new()
			add_child(n2)
			_nodes[key] = {"node": n2, "sig": ""}
		var e2: Dictionary = _nodes[key]
		if e2.sig != sig2:
			e2.sig = sig2
			_configure_works(e2.node, w, k, on)
	# Bautrupps der Strassenwartung (RoadCare): Absperrung um die Arbeitsstelle, Trupp mit Gerät
	for j in sim.road_care.jobs.values():
		if j.status != "laufend":
			continue
		var key := "road:" + str(j.id)
		seen[key] = true
		if not _nodes.has(key):
			var n := SiteNode.new()
			add_child(n)
			_nodes[key] = {"node": n, "sig": "road"}
			var r := Rect2(float(j.cell.x) * 32.0 - 16.0, float(j.cell.y) * 32.0 - 16.0, 64.0, 64.0)
			n.position = Iso.to_screen(r.end)
			n.parcel_rect = r
			n.foot = Rect2(r.position, Vector2.ZERO)
			n.origin = r.end
			n.state = 0
			n.crew = sim.road_care.crew_of(j)
			n.seed_key = hash(j.id)
			n.queue_redraw()
	# Bautrupps des Stadtfuhrparks an den uebrigen Strassenbaustellen (Leitungsbau): Trupp mit Geraet, sobald der Wagen da ist
	for v in sim.fleet.crews_at_work():
		var site: Vector2i = v.site
		if sim.road_care.under_works(site):
			continue   # Instandsetzung zeichnet schon RoadCare
		var key := "fleet:%d" % int(v.id)
		seen[key] = true
		if not _nodes.has(key):
			var n := SiteNode.new()
			add_child(n)
			_nodes[key] = {"node": n, "sig": "fleet"}
			var r := Rect2(float(site.x) * 32.0 - 16.0, float(site.y) * 32.0 - 16.0, 64.0, 64.0)
			n.position = Iso.to_screen(r.end)
			n.parcel_rect = r
			n.foot = Rect2(r.position, Vector2.ZERO)
			n.origin = r.end
			n.state = 0
			n.crew = {"phase": "strasse", "role": "Leitungsbau", "foreman": 1, "workers": 3, "operators": 0, "gear": ["lkw"],
				"working": true, "people": 4, "builder": str(v.label)}
			n.seed_key = int(v.id) * 7919
			n.queue_redraw()
	for id in _nodes.keys():
		if not seen.has(id):
			_nodes[id].node.queue_free()
			_nodes.erase(id)


## Mannschaft laeuft nur im sichtbaren Bildausschnitt neu gezeichnet (Leistung bei der grossen Karte).
func _animate() -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var size := get_viewport_rect().size / cam.zoom
	var view := Rect2(cam.get_screen_center_position() - size * 0.5, size).grow(200.0)
	for e in _nodes.values():
		var n: SiteNode = e.node
		if n.crew.is_empty() or not view.has_point(n.position):
			continue
		n.t = _clock
		n.queue_redraw()


func _configure(n: SiteNode, pr: Dictionary) -> void:
	var p: Dictionary = sim.parcels.parcel(pr.parcel)
	var r := Rect2(float(p.rect[0]) * 32.0, float(p.rect[1]) * 32.0, float(p.rect[2]) * 32.0, float(p.rect[3]) * 32.0)
	var d: Dictionary = Planning.DEFS[pr.def]
	var w := float(d.w) * 32.0
	var h := float(d.h) * 32.0
	if w > r.size.x or h > r.size.y:
		var t := w
		w = h
		h = t
	var foot := Rect2(r.position + (r.size - Vector2(w, h)) * 0.5, Vector2(w, h))
	var front := Vector2(r.end.x, r.end.y)
	n.position = Iso.to_screen(front)
	n.parcel_rect = r
	n.foot = foot
	n.origin = front
	n.state = _stage(pr)
	n.height = _height(pr)
	n.blocked = not pr.blockers.is_empty()
	n.crew = sim.construction.crew_of(pr)
	n.seed_key = hash(pr.id)
	n.queue_redraw()


## Betriebsbau: Baustelle in der Groesse des kuenftigen Gebaeudes; Stufe und Hoehe nach Fortschritt, Mannschaft je Phase.
func _configure_works(n: SiteNode, w: Dictionary, k: float, on_site: bool) -> void:
	var b: Dictionary = sim.city.building(int(w.building))
	var foot := Rect2(float(b.x) * 32.0, float(b.y) * 32.0, float(b.w) * 32.0, float(b.h) * 32.0)
	var r := foot.grow(16.0)
	n.position = Iso.to_screen(r.end)
	n.parcel_rect = r
	n.foot = foot
	n.origin = r.end
	n.state = 1 if k < 0.2 else (2 if k < 0.35 else (3 if k < 0.75 else 4))
	n.height = (34.0 if w.kind == "betrieb" else 46.0) * clampf((k - 0.2) / 0.55, 0.0, 1.0)
	n.blocked = str(w.waiting) != ""
	var ph: String = ["erdarbeiten", "fundament", "rohbau", "dach", "innenausbau"][clampi(int(k * 5.0), 0, 4)]
	var spec: Dictionary = Construction.CREW[ph]
	var bd: Dictionary = sim.construction.builders.get(w.builder, {})
	var col: Color = sim.company(int(bd.company)).color if bd.has("company") else Color("e07a2a")
	n.crew = {} if not on_site else {"phase": ph, "role": spec.role, "foreman": 1, "workers": int(spec.work) + 1, "operators": int(spec.ops),
		"gear": spec.gear.duplicate(), "working": true, "people": 2 + int(spec.work) + int(spec.ops), "builder": w.builder, "color": col}
	n.seed_key = hash(w.id)
	n.queue_redraw()


## Aussehen nach Bauphase: 0 Absperrung, 1 Baugrube, 2 Fundament, 3 Rohbau, 4 Dach, 5 Huelle/Ausbau
func _stage(pr: Dictionary) -> int:
	if pr.status == "erschliessung":
		return 0
	var ph := int(pr.phase)
	if pr.status in ["pruefung", "wartet_anschluss"]:
		return 5
	return [0, 1, 2, 3, 4, 5, 5, 5, 5, 5][clampi(ph, 0, 9)]


func _height(pr: Dictionary) -> float:
	var floors := float(pr.floors)
	var ph := int(pr.phase)
	if pr.status != "im_bau":
		return floors * FLOOR_H if pr.status in ["pruefung", "wartet_anschluss"] else 0.0
	if ph == 2:
		return 6.0 * float(pr.progress)
	if ph == 3:
		return 6.0 + (floors * FLOOR_H - 6.0) * float(pr.progress)
	if ph >= 4:
		return floors * FLOOR_H
	return 0.0


## Baustelle unter dem Mauszeiger (Weltposition in Simulationskoordinaten) -> Bauvorhaben-ID oder "".
func pick(world: Vector2) -> String:
	for id in _nodes:
		if not sim.construction.projects.has(id):   # Bautrupps (road:, fleet:) sind keine Bauvorhaben
			continue
		var pr: Dictionary = sim.construction.projects[id]
		var p: Dictionary = sim.parcels.parcel(pr.parcel)
		var r := Rect2(float(p.rect[0]) * 32.0, float(p.rect[1]) * 32.0, float(p.rect[2]) * 32.0, float(p.rect[3]) * 32.0)
		if r.has_point(world):
			return id
	return ""


class SiteNode extends Node2D:
	## Eine Baustelle (Auftrag 23, Phase 3): Bauzaun mit Tor, Baucontainer, WC, Materiallager je Bauphase, Baugrube, Bewehrung,
	## Mauerwerk mit Fensteroeffnungen, Geruest mit Bohlen und Netz, Dachstuhl, Ziegel; Geraete aus CrewArt (Bagger, Kipper,
	## Fahrmischer, Turmdrehkran). Jeder Arbeiter bekommt vom Polier eine eigene Aufgabe (graben, betonieren, mauern, decken,
	## Material tragen, messen); Strassenbaustellen mit Baken, frischem Asphalt, Walze und Ruettelplatte.
	var parcel_rect := Rect2()
	var foot := Rect2()
	var origin := Vector2.ZERO
	var state := 0
	var height := 0.0
	var blocked := false
	var crew := {}
	var t := 0.0
	var seed_key := 0

	const Z := 18.0                        # Bildpunkte je Hoehenstufe (wie CrewArt)
	const BRICK := Color("b5654a")
	const MORTAR := Color("8e4a36")
	const PLASTER := Color("e8dcc2")
	const GLASS := Color("8fb8cf")
	const HOLE := Color("3a3330")
	const TIMBER := Color("a0784e")
	const TILE := Color("a8553f")
	const SCAFF := Color("c9ccd1")
	const PLANK := Color("b08850")
	const NET := Color(0.3, 0.55, 0.3, 0.22)
	const REBAR := Color("8a4b2a")
	const ASPHALT := Color("2b2b2e")
	const CONE := Color("f06a1d")

	func _s(p: Vector2) -> Vector2:
		return Iso.to_screen(p) - Iso.to_screen(origin)

	## Feldkoordinate und Hoehenstufe -> Bildpunkt (Signatur wie CrewArt erwartet)
	func _f(w: Vector2, z: float) -> Vector2:
		return _s(w * 32.0) + Vector2(0, -z * Z)

	func _poly(pts: Array, color: Color) -> void:
		draw_colored_polygon(PackedVector2Array(pts), color)

	## Zufallswert 0..1 je Figur und Merkmal, stabil ueber die Zeit
	func _rnd(i: int, k: int) -> float:
		return float(absi(hash([seed_key, i, k])) % 1000) / 1000.0

	## Bauphase: aus dem Trupp, sonst aus dem sichtbaren Baufortschritt
	func _job() -> String:
		if crew.has("phase"):
			return str(crew.phase)
		return ["vorbereitung", "erdarbeiten", "fundament", "rohbau", "dach", "innenausbau"][clampi(state, 0, 5)]

	func _firm() -> Color:
		return crew.get("color", Color("e07a2a"))

	func _working() -> bool:
		return bool(crew.get("working", false)) and not blocked

	func _draw() -> void:
		var S := Callable(self, "_f")
		if _job() == "strasse":
			_draw_roadworks(S)
			return
		var P := Rect2(parcel_rect.position / 32.0, parcel_rect.size / 32.0)
		var F := Rect2(foot.position / 32.0, foot.size / 32.0)
		var yard := _yard(P, F)
		var mid := F.get_center().x + F.get_center().y
		_draw_ground(P, F)
		_draw_fence(P, true)
		for it in yard:
			if it.p.x + it.p.y < mid:
				_draw_item(S, it)
		if not crew.is_empty():
			_draw_crew(S, P, F, yard, true)
		_draw_building(F)
		if not crew.is_empty():
			_draw_gear(S, P, F, yard)
		for it in yard:
			if it.p.x + it.p.y >= mid:
				_draw_item(S, it)
		if not crew.is_empty():
			_draw_crew(S, P, F, yard, false)
		_draw_fence(P, false)
		if blocked:   # Baustopp: Schild ueber dem Bau
			var top := _f(F.get_center(), height / Z + 2.2)
			draw_circle(top, 10.0, Color("e07a5f"))
			draw_rect(Rect2(top + Vector2(-5, -2), Vector2(10, 4)), Color.WHITE)

	# ------------------------------------------------------------------ Boden, Zaun, Lager
	func _quad(r: Rect2, z: float) -> Array:
		return [_f(r.position, z), _f(Vector2(r.end.x, r.position.y), z), _f(r.end, z), _f(Vector2(r.position.x, r.end.y), z)]

	func _draw_ground(P: Rect2, F: Rect2) -> void:
		_poly(_quad(P, 0.0), Color(0.55, 0.47, 0.35, 0.62))
		for k in 7:   # Erdflecken und Pfuetzen
			var q := Vector2(P.position.x + P.size.x * _rnd(k, 31), P.position.y + P.size.y * _rnd(k, 32))
			if not F.grow(0.2).has_point(q):
				draw_circle(_f(q, 0.0), 4.0 + 6.0 * _rnd(k, 33), Color(0.42, 0.34, 0.24, 0.5) if k % 3 else Color(0.45, 0.55, 0.62, 0.35))
		var gate := Vector2(F.get_center().x, P.end.y)   # Reifenspuren vom Tor zum Bau
		for off in [-0.18, 0.18]:
			draw_line(_f(gate + Vector2(off, 0), 0.0), _f(Vector2(F.get_center().x + off, F.end.y + 0.1), 0.0), Color(0.33, 0.26, 0.18, 0.55), 3.0)

	## Bauzaun: Fuesse, Pfosten, Gitterfelder; back = Nord- und Westseite (vor dem Bau gezeichnet), sonst Sued und Ost mit Tor.
	func _draw_fence(P: Rect2, back: bool) -> void:
		var c0 := P.position
		var c1 := Vector2(P.end.x, P.position.y)
		var c2 := P.end
		var c3 := Vector2(P.position.x, P.end.y)
		var sides: Array = [[c3, c0], [c0, c1]] if back else [[c1, c2], [c2, c3]]
		var gate_x := (c2.x + c3.x) * 0.5
		for sd in sides:
			var a: Vector2 = sd[0]
			var b: Vector2 = sd[1]
			var steps := maxi(1, int(round(a.distance_to(b) / 0.7)))
			for k in steps:
				var p0 := a.lerp(b, float(k) / float(steps))
				var p1 := a.lerp(b, float(k + 1) / float(steps))
				if not back and sd[0] == c2 and absf((p0.x + p1.x) * 0.5 - gate_x) < 0.5:
					continue   # Tor (offen)
				var q0 := _f(p0, 0.0)
				var q1 := _f(p1, 0.0)
				var h := Vector2(0, -16)
				_poly([q0, q1, q1 + h, q0 + h], Color(0.78, 0.8, 0.82, 0.22))
				for m in 4:   # Gitterstaebe
					var g := q0.lerp(q1, (float(m) + 0.5) / 4.0)
					draw_line(g, g + h, Color(0.65, 0.68, 0.7, 0.5), 1.0)
				draw_line(q0 + h, q1 + h, Color("9aa0a6"), 1.5)
				draw_line(q0 + h * 0.45, q1 + h * 0.45, Color(0.6, 0.63, 0.66, 0.6), 1.0)
				draw_line(q0, q0 + h, Color("7f858b"), 2.0)
				draw_rect(Rect2(q0 + Vector2(-4, -2), Vector2(8, 3)), Color("b8402f"))   # Betonfuss
		if not back:   # Bauschild am Tor
			var sp := _f(Vector2(gate_x - 0.75, c3.y + 0.05), 0.0)
			draw_line(sp, sp + Vector2(0, -26), Color("555555"), 2.0)
			draw_rect(Rect2(sp + Vector2(-11, -36), Vector2(22, 12)), Color("f2c14e"))
			draw_rect(Rect2(sp + Vector2(-9, -33), Vector2(18, 2)), Color("2a2a2a"))
			draw_rect(Rect2(sp + Vector2(-9, -29), Vector2(12, 2)), _firm())

	## Lagerplaetze ausserhalb des Baukoerpers: Baucontainer, WC und Material der aktuellen Phase.
	func _yard(P: Rect2, F: Rect2) -> Array:
		var spots: Array = []
		var y := P.position.y + 0.45
		while y < P.end.y - 0.35:
			var x := P.position.x + 0.5
			while x < P.end.x - 0.4:
				var q := Vector2(x, y)
				if not F.grow(0.55).has_point(q) and absf(q.x - F.get_center().x) + maxf(0.0, q.y - F.end.y) > 0.6:
					spots.append(q)
				x += 0.95
			y += 0.8
		spots.sort_custom(func(a, b): return a.x + a.y < b.x + b.y)   # hinten zuerst: Container und WC hinten
		var kinds: Array = ["buero", "wc"]
		match _job():
			"vorbereitung", "erdarbeiten", "aussenanlagen":
				kinds += ["schotter", "schotter", "holz"]
			"fundament":
				kinds += ["stahl", "schotter", "stahl"]
			"rohbau":
				kinds += ["stein", "stein", "stahl", "stein"]
			"dach":
				kinds += ["holz", "ziegel", "holz", "ziegel"]
			"huelle":
				kinds += ["fenster", "stein", "fenster"]
			_:
				kinds += ["paletten", "holz", "paletten"]
		var out: Array = []
		for i in mini(kinds.size(), spots.size()):
			out.append({"kind": kinds[i], "p": spots[i], "amount": 0.4 + 0.6 * _rnd(i, 40)})
		return out

	func _draw_item(S: Callable, it: Dictionary) -> void:
		var c: Vector2 = it.p
		match str(it.kind):
			"buero":
				CrewArt.site_office(self, S, c, _firm(), "")
			"wc":
				CrewArt.box(self, S, c.x - 0.14, c.y - 0.14, c.x + 0.14, c.y + 0.14, 0.0, 1.15, Color("3e7cb1"))
				draw_line(_f(c + Vector2(0.14, -0.05), 0.2), _f(c + Vector2(0.14, -0.05), 0.95), Color("2b5c86"), 2.0)
			"ziegel":
				for k in maxi(1, int(round(4.0 * float(it.amount)))):
					CrewArt.box(self, S, c.x - 0.3, c.y - 0.2, c.x + 0.3, c.y + 0.2, 0.17 * k, 0.17 * k + 0.14, TILE)
			"fenster":   # Scheiben im Bock
				CrewArt.box(self, S, c.x - 0.35, c.y - 0.05, c.x + 0.35, c.y + 0.05, 0.0, 0.08, Color("6b6b6b"))
				for k in 3:
					var q := c + Vector2(-0.25 + 0.25 * k, 0.0)
					_poly([_f(q + Vector2(-0.1, 0), 0.1), _f(q + Vector2(0.1, 0), 0.1), _f(q + Vector2(0.1, 0), 1.0), _f(q + Vector2(-0.1, 0), 1.0)], Color(0.62, 0.8, 0.9, 0.75))
			"paletten":
				CrewArt.box(self, S, c.x - 0.3, c.y - 0.25, c.x + 0.3, c.y + 0.25, 0.0, 0.1, TIMBER.lightened(0.2))
				CrewArt.box(self, S, c.x - 0.25, c.y - 0.2, c.x + 0.25, c.y + 0.2, 0.1, 0.6, Color("d8cfb8"))
			"stahl":   # Bewehrungsstahl auf Kanthoelzern
				for k in 2:
					CrewArt.box(self, S, c.x - 0.4, c.y - 0.2 + 0.3 * k, c.x + 0.4, c.y - 0.12 + 0.3 * k, 0.0, 0.08, TIMBER)
				for k in 6:
					var yy := c.y - 0.2 + 0.08 * k
					draw_line(_f(Vector2(c.x - 0.45, yy), 0.12), _f(Vector2(c.x + 0.45, yy), 0.12), REBAR, 2.0)
			_:
				CrewArt.stack(self, S, c, str(it.kind), float(it.amount))

	# ------------------------------------------------------------------ Baukoerper
	func _draw_building(F: Rect2) -> void:
		var fa := _f(F.position, 0.0)
		var fb := _f(Vector2(F.end.x, F.position.y), 0.0)
		var fc := _f(F.end, 0.0)
		var fd := _f(Vector2(F.position.x, F.end.y), 0.0)
		if state == 0:   # Schnurgeruest: Pfloecke und Schnur um den kuenftigen Bau
			for p in [fa, fb, fc, fd]:
				draw_line(p, p + Vector2(0, -10), TIMBER, 3.0)
			draw_polyline(PackedVector2Array([fa + Vector2(0, -7), fb + Vector2(0, -7), fc + Vector2(0, -7), fd + Vector2(0, -7), fa + Vector2(0, -7)]), Color(1, 1, 1, 0.8), 1.0)
			return
		if state == 1:   # Baugrube mit Boeschung und Grubensohle
			var dn := Vector2(0, 12)
			_poly([fa, fb, fc, fd], Color("4f3a28"))
			_poly([fa + dn, fb + dn, fc, fd], Color("6b4f36"))
			_poly([fa, fb, fb + dn, fa + dn], Color("5a432e"))
			_poly([fa, fa + dn, fd, fd], Color("53402c"))
			return
		var h := height
		var up := Vector2(0, -h)
		if state == 2:   # Bodenplatte mit Bewehrungskorb
			var hs := maxf(h, 4.0)
			var us := Vector2(0, -hs)
			_poly([fd + us, fc + us, fc, fd], SiteView.SLAB[0])
			_poly([fc + us, fb + us, fb, fc], SiteView.SLAB[1])
			_poly([fa + us, fb + us, fc + us, fd + us], SiteView.SLAB[2])
			var cols := maxi(2, int(F.size.x * 3.0))
			var rows := maxi(2, int(F.size.y * 3.0))
			for k in cols + 1:
				var u := float(k) / float(cols)
				draw_line((fa + us).lerp(fb + us, u) + Vector2(0, -3), (fd + us).lerp(fc + us, u) + Vector2(0, -3), REBAR, 1.2)
			for k in rows + 1:
				var u := float(k) / float(rows)
				draw_line((fa + us).lerp(fd + us, u) + Vector2(0, -3), (fb + us).lerp(fc + us, u) + Vector2(0, -3), REBAR, 1.2)
			return
		var shell := state >= 5
		var job := _job()
		var wall: Color = PLASTER if shell else BRICK
		_face(fd, fc, h, wall.darkened(0.05), shell, F.size.x)
		_face(fc, fb, h, wall.darkened(0.22), shell, F.size.y)
		var edge := Color(0.18, 0.16, 0.14, 0.9)
		if state == 3:   # Rohbau oben offen: Mauerkrone und Innenraum
			_poly([fa + up, fb + up, fc + up, fd + up], Color("5d4a3c"))
			var w := 6.0
			draw_polyline(PackedVector2Array([fd + up, fc + up, fb + up, fa + up, fd + up]), BRICK.lightened(0.15), w * 0.5)
		else:
			_roof(fa, fb, fc, fd, h, state >= 5 or job not in ["dach"], F.size.y)
		draw_polyline(PackedVector2Array([fd, fc, fb]), edge, 1.5)
		draw_line(fc, fc + up, edge, 1.5)
		if (state == 3) or (job == "huelle") or (state == 4 and job == "dach"):
			_scaffold(F, h)

	## Wandflaeche zwischen den Fusspunkten A und B: Mauerwerk mit Fugen und Fensteroeffnungen bzw. Putz mit Glas.
	func _face(A: Vector2, B: Vector2, h: float, col: Color, plaster: bool, fields: float) -> void:
		_poly([A, B, B + Vector2(0, -h), A + Vector2(0, -h)], col)
		if not plaster:
			var z := 6.0
			var row := 0
			while z < h:
				draw_line(A + Vector2(0, -z), B + Vector2(0, -z), MORTAR, 1.0)
				z += 6.0
				row += 1
		var nwin := maxi(1, int(round(fields * 1.3)))
		var fl := 0
		while float(fl) * SiteView.FLOOR_H + 34.0 <= h:
			for k in nwin:
				var u0 := (float(k) + 0.3) / float(nwin)
				var u1 := (float(k) + 0.7) / float(nwin)
				var z0 := float(fl) * SiteView.FLOOR_H + 12.0
				var z1 := float(fl) * SiteView.FLOOR_H + 32.0
				var quad := [A.lerp(B, u0) + Vector2(0, -z0), A.lerp(B, u1) + Vector2(0, -z0), A.lerp(B, u1) + Vector2(0, -z1), A.lerp(B, u0) + Vector2(0, -z1)]
				_poly(quad, GLASS if plaster else HOLE)
				if plaster:
					draw_polyline(PackedVector2Array(quad + [quad[0]]), Color(1, 1, 1, 0.8), 1.0)
					draw_line((quad[0] + quad[1]) * 0.5, (quad[2] + quad[3]) * 0.5, Color(1, 1, 1, 0.7), 1.0)
				else:
					draw_line(quad[3] + Vector2(-1, -1), quad[2] + Vector2(1, -1), Color("9a9a9a"), 2.0)   # Sturz
			fl += 1

	## Satteldach (First in x-Richtung). tiles: fertig gedeckt; sonst Dachstuhl mit Sparren, unten halb gelattet und gedeckt.
	func _roof(fa: Vector2, fb: Vector2, fc: Vector2, fd: Vector2, h: float, tiles: bool, depth: float) -> void:
		var up := Vector2(0, -h)
		var ridge := Vector2(0, -h - clampf(depth * 12.0, 22.0, 70.0))   # Dachneigung bleibt bei tiefen Haeusern sichtbar
		var mid_l := (fa + fd) * 0.5 + ridge
		var mid_r := (fb + fc) * 0.5 + ridge
		_poly([fc + up, fb + up, mid_r], PLASTER.darkened(0.25) if state >= 5 else BRICK.darkened(0.2))   # Giebel
		if tiles:
			_poly([fa + up, fb + up, mid_r, mid_l], TILE.darkened(0.15))
			_poly([fd + up, fc + up, mid_r, mid_l], TILE)
			for k in 8:
				var u := float(k + 1) / 9.0
				draw_line((fd + up).lerp(mid_l, u), (fc + up).lerp(mid_r, u), TILE.darkened(0.25), 1.0)
			return
		_poly([fa + up, fb + up, fc + up, fd + up], SiteView.SLAB[2])   # Geschossdecke unter dem Dachstuhl
		var rafters := maxi(5, int(fa.distance_to(fb) / 18.0))
		for k in rafters + 1:
			var u := float(k) / float(rafters)
			var top := mid_l.lerp(mid_r, u)
			draw_line((fa + up).lerp(fb + up, u), top, TIMBER.darkened(0.1), 2.0)
			draw_line((fd + up).lerp(fc + up, u), top, TIMBER, 2.5)
		draw_line(mid_l, mid_r, TIMBER.darkened(0.2), 3.0)   # Firstpfette
		var done := 0.5   # untere Haelfte schon gedeckt
		_poly([fd + up, fc + up, (fc + up).lerp(mid_r, done), (fd + up).lerp(mid_l, done)], TILE)
		for k in 3:
			var u := done + (1.0 - done) * float(k + 1) / 4.0
			draw_line((fd + up).lerp(mid_l, u), (fc + up).lerp(mid_r, u), TIMBER.lightened(0.15), 1.0)   # Lattung

	## Fassadengeruest vor Sued- und Ostwand: Staender, Bohlen je halber Geschosshoehe, Diagonalen, Netz.
	func _scaffold(F: Rect2, h: float) -> void:
		var top := h + 10.0
		var faces := [[Vector2(F.position.x, F.end.y + 0.3), Vector2(F.end.x + 0.3, F.end.y + 0.3)], [Vector2(F.end.x + 0.3, F.end.y + 0.3), Vector2(F.end.x + 0.3, F.position.y)]]
		for fc in faces:
			var a: Vector2 = fc[0]
			var b: Vector2 = fc[1]
			var n := maxi(2, int(round(a.distance_to(b) / 0.8)) + 1)
			var A := _f(a, 0.0)
			var B := _f(b, 0.0)
			_poly([A, B, B + Vector2(0, -top), A + Vector2(0, -top)], NET)
			for k in n:
				var p := A.lerp(B, float(k) / float(n - 1))
				draw_line(p, p + Vector2(0, -top), SCAFF, 2.0)
			var z := 22.0
			var lvl := 0
			while z <= top:
				draw_line(A + Vector2(0, -z), B + Vector2(0, -z), PLANK, 3.0)
				draw_line(A + Vector2(0, -z - 8), B + Vector2(0, -z - 8), SCAFF, 1.0)   # Gelaender
				if lvl % 2 == 0:
					for k in n - 1:
						var p0 := A.lerp(B, float(k) / float(n - 1))
						var p1 := A.lerp(B, float(k + 1) / float(n - 1))
						draw_line(p0 + Vector2(0, -z + 22.0), p1 + Vector2(0, -z), SCAFF.darkened(0.15), 1.0)
				z += 22.0
				lvl += 1

	# ------------------------------------------------------------------ Geraete
	func _draw_gear(S: Callable, P: Rect2, F: Rect2, yard: Array) -> void:
		var w := _working()
		var firm := _firm()
		for g in crew.get("gear", []):
			match str(g):
				"bagger":
					var c := Vector2(F.position.x - 0.55, F.get_center().y) if F.position.x - P.position.x > 1.1 else Vector2(F.get_center().x, F.end.y + 0.8)
					CrewArt.excavator(self, S, c, (F.get_center() - c).normalized(), t, w)
				"lkw":
					var u := 0.5 + 0.5 * sin(t * 0.35) if w else 0.0
					CrewArt.dump_truck(self, S, Vector2(F.end.x - 0.6, minf(P.end.y - 0.45, F.end.y + 1.0)), Vector2(1, 0), firm, true, clampf(u * 1.4 - 0.4, 0.0, 1.0))
				"betonmischer":
					var mc := Vector2(F.get_center().x + 0.7, minf(P.end.y - 0.45, F.end.y + 0.9))
					CrewArt.mixer(self, S, mc, Vector2(1, 0), t if w else 0.0, firm)
					if w:   # Schuette in die Schalung
						draw_line(_f(mc + Vector2(-0.45, 0), 0.5), _f(Vector2(mc.x - 0.9, F.end.y - 0.2), 0.3), Color("9a9a9a"), 3.0)
				"kran":
					_tower_crane(S, P, F, yard, w)

	## Turmdrehkran an der Nordostecke: Gittermast, Ausleger dreht zwischen Lager und Bau, Laufkatze mit Last.
	func _tower_crane(S: Callable, P: Rect2, F: Rect2, yard: Array, w: bool) -> void:
		var base := Vector2(minf(F.end.x + 0.6, P.end.x - 0.3), maxf(F.position.y - 0.4, P.position.y + 0.3))
		var zt := height / Z + 5.5
		var b0 := _f(base, 0.0)
		var b1 := _f(base, zt)
		var sx := Vector2(5, 0)
		CrewArt.box(self, S, base.x - 0.3, base.y - 0.3, base.x + 0.3, base.y + 0.3, 0.0, 0.25, Color("8d8a82"))   # Fundament
		draw_line(b0 - sx, b1 - sx, CrewArt.YELLOW, 2.0)
		draw_line(b0 + sx, b1 + sx, CrewArt.YELLOW, 2.0)
		var segs := int(zt * 2.0)
		for k in segs:   # Gitter
			var p0 := b0.lerp(b1, float(k) / float(segs))
			var p1 := b0.lerp(b1, float(k + 1) / float(segs))
			draw_line(p0 - sx if k % 2 == 0 else p0 + sx, p1 + sx if k % 2 == 0 else p1 - sx, CrewArt.YELLOW_D, 1.0)
		var src: Vector2 = yard[2].p if yard.size() > 2 else P.position + Vector2(0.6, 0.6)
		var dst := F.get_center()
		var k := 0.5 + 0.5 * sin(t * 0.22) if w else 0.3
		var target := src.lerp(dst, k)
		var dir := (target - base).normalized() if target != base else Vector2(-1, 0)
		var reach := maxf(1.5, base.distance_to(src) + 0.5)
		var tip := _f(base + dir * reach, zt + 0.3)
		var back := _f(base - dir * 1.2, zt + 0.3)
		draw_line(back, tip, CrewArt.YELLOW, 4.0)
		draw_line(b1 + Vector2(0, -16), tip, CrewArt.YELLOW_D, 1.0)   # Abspannung
		draw_line(b1 + Vector2(0, -16), back, CrewArt.YELLOW_D, 1.0)
		var bw := _f(base - dir * 1.0, zt + 0.3)
		draw_rect(Rect2(bw + Vector2(-7, -2), Vector2(14, 9)), Color("6b6b6b"))   # Gegengewicht
		draw_rect(Rect2(b1 + Vector2(-6, -12), Vector2(12, 10)), Color("e8e8e8"))   # Fuehrerhaus
		var trolley := _f(target, zt + 0.3)
		var lift := 0.5 + 0.5 * sin(t * 0.44 + 1.0) if w else 0.6
		var load_z := (height / Z + 1.0) * lift + 0.4
		var hook := _f(target, load_z)
		draw_line(trolley, hook, Color("222222"), 1.0)
		var load_col: Color = {"rohbau": Color("a39b8b"), "dach": TIMBER}.get(_job(), Color("b8bcbf"))
		draw_rect(Rect2(hook + Vector2(-10, 0), Vector2(20, 7)), load_col)

	# ------------------------------------------------------------------ Mannschaft
	## Polier-KI: jeder Arbeiter hat eine eigene Aufgabe nach Bauphase und Reihenfolge im Trupp (stabil je Baustelle).
	func _draw_crew(S: Callable, P: Rect2, F: Rect2, yard: Array, back_pass: bool) -> void:
		var people: int = int(crew.get("workers", 0)) + int(crew.get("operators", 0)) + int(crew.get("foreman", 1))
		var stock: Vector2 = yard[2].p if yard.size() > 2 else (yard[0].p if not yard.is_empty() else P.position + Vector2(0.5, 0.5))
		var mid := F.get_center().x + F.get_center().y
		for i in people:
			var task := _task(i, P, F, stock)
			var pos: Vector2 = task.p
			var z: float = task.z
			var behind := z <= 0.01 and pos.x + pos.y < mid
			if behind != back_pass:
				continue
			var vest := Color("f0f0f0") if i == 0 else (Color("f28c28") if i <= int(crew.get("workers", 0)) else Color("3e7cb1"))
			var lift := z
			var S2 := func(w: Vector2, zz: float) -> Vector2: return S.call(w, zz + lift)
			CrewArt.worker(self, S2, pos, t, str(task.a), vest, _firm(), seed_key + i)

	func _task(i: int, P: Rect2, F: Rect2, stock: Vector2) -> Dictionary:
		var r1 := _rnd(i, 1)
		var r2 := _rnd(i, 2)
		var job := _job()
		if not _working():   # Pause oder Baustopp: Trupp steht am Container
			return {"p": stock + Vector2(0.35 * float(i % 3) - 0.3, 0.45 + 0.3 * float(i / 3)), "z": 0.0, "a": "gehen"}
		if i == 0:   # Polier: misst nach, winkt Geraete und Kran ein
			return {"p": Vector2(F.position.x - 0.35, F.end.y + 0.45), "z": 0.0, "a": "messen" if fmod(t * 0.05 + r1, 1.0) < 0.5 else "winken"}
		var door := Vector2(F.position.x + F.size.x * (0.3 + 0.4 * r1), F.end.y + 0.25)
		var floors := maxi(1, int(height / SiteView.FLOOR_H))
		var wander := 0.12 * sin(t * (0.15 + 0.1 * r2) + r1 * 6.0)
		var on_face := Vector2(F.position.x + F.size.x * clampf(0.1 + 0.8 * r1 + wander, 0.05, 0.95), F.end.y + 0.32) if i % 2 == 0 \
			else Vector2(F.end.x + 0.32, F.position.y + F.size.y * clampf(0.1 + 0.8 * r1 + wander, 0.05, 0.95))
		var inside := Vector2(F.position.x + F.size.x * (0.15 + 0.7 * r1), F.position.y + F.size.y * (0.15 + 0.7 * r2))
		if i % 3 == 2 and job not in ["vorbereitung", "uebergabe"]:   # jeder Dritte holt Material vom Lager
			return _carry(i, stock, door)
		match job:
			"vorbereitung":
				var corners := [F.position, Vector2(F.end.x, F.position.y), F.end, Vector2(F.position.x, F.end.y)]
				return {"p": corners[i % 4], "z": 0.0, "a": "messen"}
			"erdarbeiten":
				return {"p": inside, "z": -0.55, "a": "schaufeln"}
			"fundament":
				return {"p": inside, "z": maxf(height, 4.0) / Z, "a": "schaufeln" if i % 2 else "haemmern"}
			"rohbau":
				var lvl := float(int(r2 * float(floors))) * SiteView.FLOOR_H / Z + 22.0 / Z
				return {"p": on_face, "z": minf(lvl, height / Z), "a": "haemmern"}
			"dach":
				return {"p": Vector2(inside.x, F.position.y + F.size.y * (0.55 + 0.3 * r2)), "z": height / Z + 0.7, "a": "haemmern"}
			"huelle":
				var lvl2 := float(int(r2 * float(floors))) * SiteView.FLOOR_H / Z + 22.0 / Z
				return {"p": on_face, "z": lvl2, "a": "tragen" if i % 2 else "messen"}
			"aussenanlagen":
				var ring := F.grow(0.6)
				var e := Vector2(ring.position.x + ring.size.x * r1, ring.end.y) if i % 2 else Vector2(ring.end.x, ring.position.y + ring.size.y * r1)
				return {"p": e, "z": 0.0, "a": "schaufeln"}
			"uebergabe":
				var u := fmod(t * 0.02 + r1, 1.0)
				var path := [Vector2(F.position.x, F.end.y + 0.5), Vector2(F.end.x + 0.5, F.end.y + 0.5), Vector2(F.end.x + 0.5, F.position.y)]
				var seg := int(u * 2.0)
				return {"p": (path[seg] as Vector2).lerp(path[seg + 1], u * 2.0 - float(seg)), "z": 0.0, "a": "messen"}
			_:   # Installation, Innenausbau: Material ins Haus
				return _carry(i, stock, door)

	## Materialgang: zum Bau tragen, abladen, leer zurueck.
	func _carry(i: int, a: Vector2, b: Vector2) -> Dictionary:
		var u := fmod(t * (0.05 + 0.03 * _rnd(i, 5)) + _rnd(i, 6), 1.0)
		if u < 0.42:
			return {"p": a.lerp(b, u / 0.42), "z": 0.0, "a": "tragen"}
		if u < 0.55:
			return {"p": b, "z": 0.0, "a": "schaufeln"}
		return {"p": b.lerp(a, (u - 0.55) / 0.45), "z": 0.0, "a": "gehen"}

	# ------------------------------------------------------------------ Strassenbau
	## Instandsetzung oder Leitungsbau auf 2x2 Feldern: Baken und Leitkegel, Fahrbahn aufgerissen bzw. frisch asphaltiert
	## (dampft), Walze faehrt hin und her, Arbeiter verteilen Asphalt, einer verdichtet mit der Ruettelplatte, einer regelt den Verkehr.
	func _draw_roadworks(S: Callable) -> void:
		var P := Rect2(parcel_rect.position / 32.0, parcel_rect.size / 32.0)
		var c := P.get_center()
		var pipe := str(crew.get("role", "")) == "Leitungsbau"
		var w := bool(crew.get("working", true))
		var A := Rect2(c - Vector2(0.75, 0.42), Vector2(1.5, 0.84))
		if pipe:   # Graben mit Rohr und Aushub
			_poly(_quad(A, 0.0), Color("6b4f36"))
			_poly(_quad(A.grow(-0.18), 0.0), Color("3e2e20"))
			draw_line(_f(Vector2(A.position.x + 0.1, c.y), -0.2), _f(Vector2(A.end.x - 0.1, c.y), -0.2), Color("4a7fb5"), 6.0)
			CrewArt.stack(self, S, Vector2(A.end.x + 0.25, A.position.y - 0.15), "schotter", 0.8)
		else:
			_poly(_quad(A, 0.0), Color("55524e"))   # abgefraeste Decke
			var done := 0.5 + 0.5 * sin(t * 0.1) if w else 0.5
			var fresh := Rect2(A.position, Vector2(A.size.x * done, A.size.y))
			_poly(_quad(fresh, 0.0), ASPHALT)
			if w:
				for k in 4:   # Dampf ueber dem heissen Asphalt
					var f := fmod(t * 0.35 + float(k) * 0.25, 1.0)
					var q := _f(fresh.position + Vector2(fresh.size.x * (0.2 + 0.2 * k), fresh.size.y * 0.5), 0.2 + 1.6 * f)
					draw_circle(q + Vector2(4.0 * sin(t + k), 0), 3.0 + 4.0 * f, Color(1, 1, 1, 0.28 * (1.0 - f)))
		for k in 8:   # Baken rundum, Leitkegel an den Ecken
			var u := float(k) / 8.0
			var q := _perimeter(P.grow(-0.08), u)
			if k % 2 == 0:
				CrewArt.barrier(self, S, q)
			else:
				var b := _f(q, 0.0)
				_poly([b + Vector2(-4, 0), b + Vector2(4, 0), b + Vector2(0, -12)], CONE)
				draw_line(b + Vector2(-2, -5), b + Vector2(2, -5), Color.WHITE, 2.0)
		var gear: Array = crew.get("gear", [])
		if gear.has("bagger"):
			CrewArt.excavator(self, S, Vector2(A.position.x + 0.2, A.end.y + 0.25), Vector2(1, -0.3).normalized(), t, w)
		if gear.has("lkw"):
			CrewArt.dump_truck(self, S, Vector2(A.end.x - 0.1, A.position.y - 0.3), Vector2(1, 0), _firm(), true, 0.0)
		if not pipe:
			var x := A.position.x + 0.3 + (A.size.x - 0.6) * (0.5 + 0.5 * sin(t * 0.3)) if w else A.get_center().x
			CrewArt.roller(self, S, Vector2(x, A.get_center().y + 0.1), Vector2(1, 0))
		var people: int = int(crew.get("workers", 3)) + int(crew.get("foreman", 1))
		for i in people:
			var r1 := _rnd(i, 1)
			var pos := Vector2(A.position.x + A.size.x * (0.15 + 0.7 * r1), A.end.y - 0.1)
			var act := "schaufeln"
			var vest := Color("f28c28")
			if i == 0:   # Sicherungsposten mit Kelle
				pos = Vector2(P.position.x + 0.2, P.end.y - 0.15)
				act = "winken"
				vest = Color("f0f0f0")
			elif i == 1 and not pipe:   # Ruettelplatte
				pos = Vector2(A.position.x + 0.2 + 0.3 * (0.5 + 0.5 * sin(t * 0.5)), A.position.y + 0.2)
				act = "gehen"
				var pl := _f(pos + Vector2(0.18, 0), 0.0) + Vector2(sin(t * 40.0), 0)
				draw_rect(Rect2(pl + Vector2(-6, -5), Vector2(12, 5)), Color("d0482f"))
			elif pipe:
				pos = Vector2(A.position.x + A.size.x * (0.2 + 0.6 * r1), c.y)
				act = "schaufeln"
			var lift := -0.4 if pipe and i > 0 else 0.0
			var S2 := func(wp: Vector2, zz: float) -> Vector2: return S.call(wp, zz + lift)
			CrewArt.worker(self, S2, pos, t, act if w else "gehen", vest, _firm(), seed_key + i)

	func _perimeter(r: Rect2, u: float) -> Vector2:
		var per := 2.0 * (r.size.x + r.size.y)
		var d := u * per
		if d < r.size.x:
			return r.position + Vector2(d, 0)
		d -= r.size.x
		if d < r.size.y:
			return Vector2(r.end.x, r.position.y + d)
		d -= r.size.y
		if d < r.size.x:
			return Vector2(r.end.x - d, r.end.y)
		return Vector2(r.position.x, r.end.y - (d - r.size.x))
