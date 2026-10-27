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


func setup(simulation: Simulation) -> void:
	sim = simulation
	y_sort_enabled = true


func update_view(delta: float) -> void:
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
