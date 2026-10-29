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
		var pr: Dictionary = sim.construction.projects[id]
		var p: Dictionary = sim.parcels.parcel(pr.parcel)
		var r := Rect2(float(p.rect[0]) * 32.0, float(p.rect[1]) * 32.0, float(p.rect[2]) * 32.0, float(p.rect[3]) * 32.0)
		if r.has_point(world):
			return id
	return ""


class SiteNode extends Node2D:
	var parcel_rect := Rect2()
	var foot := Rect2()
	var origin := Vector2.ZERO
	var state := 0
	var height := 0.0
	var blocked := false
	var crew := {}
	var t := 0.0
	var seed_key := 0

	func _s(p: Vector2) -> Vector2:
		return Iso.to_screen(p) - Iso.to_screen(origin)

	func _poly(pts: Array, color: Color) -> void:
		draw_colored_polygon(PackedVector2Array(pts), color)

	func _draw() -> void:
		var r := parcel_rect
		var a := _s(r.position)
		var b := _s(Vector2(r.end.x, r.position.y))
		var c := _s(r.end)
		var d := _s(Vector2(r.position.x, r.end.y))
		_poly([a, b, c, d], Color(0.55, 0.47, 0.35, 0.55))
		var f := foot
		var fa := _s(f.position)
		var fb := _s(Vector2(f.end.x, f.position.y))
		var fc := _s(f.end)
		var fd := _s(Vector2(f.position.x, f.end.y))
		if state == 1:
			_poly([fa, fb, fc, fd], SiteView.PIT)
		elif state >= 2:
			var h := height
			var cols: Array = SiteView.SLAB if state == 2 else SiteView.WALL
			var up := Vector2(0, -h)
			_poly([fd + up, fc + up, fc, fd], cols[0])
			_poly([fc + up, fb + up, fb, fc], cols[1])
			_poly([fa + up, fb + up, fc + up, fd + up], cols[2] if state < 4 else SiteView.ROOF[2])
			var edge := Color(0.18, 0.16, 0.14, 0.9)
			draw_polyline(PackedVector2Array([fd, fc, fb]), edge, 2.0)
			draw_polyline(PackedVector2Array([fd + up, fc + up, fb + up, fa + up, fd + up]), edge, 2.0)
			draw_line(fc, fc + up, edge, 2.0)
			draw_line(fd, fd + up, edge, 2.0)
			draw_line(fb, fb + up, edge, 2.0)
			if state >= 4:
				var roof_up := Vector2(0, -h - 14.0)
				var mid_l := (fa + fd) * 0.5 + roof_up
				var mid_r := (fb + fc) * 0.5 + roof_up
				_poly([fd + up, fc + up, mid_r, mid_l], SiteView.ROOF[0])
				_poly([fc + up, fb + up, mid_r], SiteView.ROOF[1])
		# Absperrung und Warnbaken
		for seg in [[a, b], [b, c], [c, d], [d, a]]:
			draw_line(seg[0], seg[1], SiteView.FENCE, 3.0)
		for corner in [a, b, c, d]:
			draw_line(corner, corner + Vector2(0, -18), SiteView.FENCE, 3.0)
		if blocked:
			draw_circle((a + c) * 0.5 + Vector2(0, -height - 30.0), 9.0, Color("e07a5f"))
		if not crew.is_empty():
			_draw_crew()

	## Zufallswert 0..1 je Figur und Merkmal, stabil ueber die Zeit
	func _rnd(i: int, k: int) -> float:
		return float(absi(hash([seed_key, i, k])) % 1000) / 1000.0

	func _spot(i: int, k: int) -> Vector2:
		var r := parcel_rect
		var p := Vector2(r.position.x + r.size.x * (0.1 + 0.8 * _rnd(i, k)), r.position.y + r.size.y * (0.1 + 0.8 * _rnd(i, k + 1)))
		if state >= 2 and foot.grow(2.0).has_point(p):
			p.y = minf(r.end.y - 3.0, foot.end.y + 4.0 + 6.0 * _rnd(i, k + 2))
		return p

	func _draw_crew() -> void:
		var working: bool = crew.working
		var people: int = int(crew.workers) + int(crew.operators) + int(crew.foreman)
		for i in people:
			var a := _spot(i, 1)
			var b := _spot(i, 4)
			var u := 0.5 + 0.5 * sin(t * (0.6 + _rnd(i, 7)) + _rnd(i, 8) * 6.28) if working else 0.5
			var pos := _s(a.lerp(b, u))
			var vest := Color("e8e8e8") if i == 0 else Color("f28c28") if i < int(crew.workers) + 1 else Color("3e7cb1")
			var hat := Color("ffffff") if i == 0 else Color("f2c14e")
			var bob := 1.0 * sin(t * 9.0 + float(i)) if working and u > 0.02 and u < 0.98 else 0.0
			draw_rect(Rect2(pos + Vector2(-2, -8 + bob), Vector2(4, 6)), vest)
			draw_rect(Rect2(pos + Vector2(-2, -2), Vector2(4, 2)), Color("3a3f4a"))
			draw_rect(Rect2(pos + Vector2(-2, -12 + bob), Vector2(4, 4)), Color("e0b48a"))
			draw_rect(Rect2(pos + Vector2(-3, -13 + bob), Vector2(6, 2)), hat)
			if working and int(t * 2.0 + float(i)) % 3 == 0 and (u <= 0.02 or u >= 0.98):
				draw_line(pos + Vector2(3, -6), pos + Vector2(6, -9 + 3.0 * sin(t * 14.0)), Color("c0c0c0"), 2.0)   # hammert
		var gi := 0
		for g in crew.gear:
			var gp := _s(Vector2(parcel_rect.position.x + parcel_rect.size.x * (0.18 + 0.22 * float(gi)), parcel_rect.position.y + parcel_rect.size.y * 0.2))
			if str(g) != "kran":
				draw_set_transform(gp, 0.0, Vector2(1.7, 1.7))
				gp = Vector2.ZERO
			match str(g):
				"bagger":
					draw_rect(Rect2(gp + Vector2(-9, -8), Vector2(18, 8)), Color("e0a526"))
					draw_rect(Rect2(gp + Vector2(-5, -15), Vector2(8, 7)), Color("c98c14"))
					var swing := 6.0 * sin(t * 1.4) if working else 0.0
					draw_line(gp + Vector2(2, -13), gp + Vector2(16, -20 + swing), Color("e0a526"), 3.0)
					draw_line(gp + Vector2(16, -20 + swing), gp + Vector2(18, -8 + swing), Color("c98c14"), 3.0)
					draw_rect(Rect2(gp + Vector2(-10, -2), Vector2(20, 3)), Color("2b2b2b"))
				"lkw":
					draw_rect(Rect2(gp + Vector2(-10, -9), Vector2(14, 8)), Color("8a8f98"))
					draw_rect(Rect2(gp + Vector2(4, -7), Vector2(6, 6)), Color("d8d8d8"))
					draw_circle(gp + Vector2(-6, 0), 2.5, Color("2b2b2b"))
					draw_circle(gp + Vector2(6, 0), 2.5, Color("2b2b2b"))
				"betonmischer":
					draw_rect(Rect2(gp + Vector2(-8, -3), Vector2(16, 3)), Color("555a63"))
					var drum := PackedVector2Array([gp + Vector2(-7, -5), gp + Vector2(5, -5), gp + Vector2(8, -13), gp + Vector2(-4, -16)])
					draw_colored_polygon(drum, Color("d46a2a"))
					if working:
						draw_line(gp + Vector2(-4, -8), gp + Vector2(4 + 2.0 * sin(t * 6.0), -11), Color("f2c14e"), 1.5)
				"kran":
					var base := _s(Vector2(foot.end.x + 4.0, foot.position.y - 4.0))
					var top := base + Vector2(0, -(height + 70.0))
					draw_line(base, top, Color("f2c14e"), 3.0)
					var sway := 22.0 * sin(t * 0.5) if working else 8.0
					draw_line(top + Vector2(-34, 4), top + Vector2(34, -4 + sway * 0.1), Color("f2c14e"), 3.0)
					var hook := top + Vector2(sway, 6)
					draw_line(hook, hook + Vector2(0, 26 + 8.0 * sin(t * 0.9)), Color("333333"), 1.0)
					draw_rect(Rect2(base + Vector2(-5, -6), Vector2(10, 6)), Color("777777"))
			gi += 1
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
