class_name PowerNetView
extends Node2D
## Hochspannungsnetz auf der Karte (Auftrag 22 Phase 3 Schritt 2): Gittermasten alle PowerNet.MAST_EVERY Felder entlang der Trasse,
## durchhaengende Leiterseile zwischen den Mastspitzen, Umspannwerke als eingezaeuntes Feld mit Transformatoren. Unterbrochene
## Trassen erscheinen rot gestrichelt mit Warnzeichen. Zeichnet nur den sichtbaren Ausschnitt, neu nur bei Aenderung.

const MAST := Color(0.42, 0.44, 0.47)
const WIRE := Color(0.12, 0.12, 0.14, 0.8)
const BROKEN := Color(0.9, 0.2, 0.15, 0.9)
const FENCE := Color(0.7, 0.72, 0.74)
const PAD := Color(0.55, 0.56, 0.52, 0.9)
const TRAFO := Color(0.3, 0.42, 0.33)
const MAST_H := 34.0
const STAKE := Color(0.95, 0.55, 0.12, 0.9)

var sim: Simulation
var _poll := 0.0
var _key := ""


func setup(simulation: Simulation) -> void:
	sim = simulation


func _net() -> PowerNet:
	return sim.grid.net if sim != null and sim.grid != null else null


func _process(delta: float) -> void:
	_poll -= delta
	if _poll > 0.0 or _net() == null or not _net().built():
		return
	_poll = 0.5
	var key := "%s|%s|%s" % [str(_view_cells()), ",".join(_net().edges.map(func(e): return "%s%s" % [e.id, e.state])), str(_net().planned.keys())]
	if key != _key:
		_key = key
		queue_redraw()


func _view_cells() -> Rect2i:
	var inv := get_canvas_transform().affine_inverse()
	var vs := get_viewport_rect().size
	var lo := Vector2i(999999, 999999)
	var hi := Vector2i(-999999, -999999)
	for c in [Vector2.ZERO, Vector2(vs.x, 0), vs, Vector2(0, vs.y)]:
		var w := Iso.to_world(inv * c) / 32.0
		lo = Vector2i(mini(lo.x, int(w.x)), mini(lo.y, int(w.y)))
		hi = Vector2i(maxi(hi.x, int(w.x)), maxi(hi.y, int(w.y)))
	return Rect2i(lo - Vector2i(4, 4), hi - lo + Vector2i(8, 8))


static func _foot(q: Vector2i) -> Vector2:
	return Iso.to_screen((Vector2(q) + Vector2(0.5, 0.5)) * 32.0)


func _draw() -> void:
	var N := _net()
	if N == null or not N.built():
		return
	var view := _view_cells()
	if view.size.x * view.size.y > 160000:
		return   # sehr weit herausgezoomt
	for e in N.edges:
		var cells: Array = e.cells
		var ok := str(e.state) == "ok"
		var masts: Array = []
		for i in range(0, cells.size(), PowerNet.MAST_EVERY):
			masts.append(Vector2i(int(cells[i][0]), int(cells[i][1])))
		var last := Vector2i(int(cells[-1][0]), int(cells[-1][1]))
		if masts[-1] != last:
			masts.append(last)
		for i in masts.size():
			var q: Vector2i = masts[i]
			var vis := view.has_point(q)
			if vis and i > 0 and i < masts.size() - 1:
				_draw_mast(_foot(q))
			if i == 0:
				continue
			var p: Vector2i = masts[i - 1]
			if not vis and not view.has_point(p):
				continue
			var a := _foot(p) + Vector2(0, -MAST_H)
			var b := _foot(q) + Vector2(0, -MAST_H)
			if ok:
				_draw_wire(a, b, WIRE)
			else:
				_draw_dashed(a, b)
		if not ok:   # Warnzeichen in der Mitte der unterbrochenen Trasse
			var m := Vector2i(int(cells[cells.size() / 2][0]), int(cells[cells.size() / 2][1]))
			if view.has_point(m):
				var c := _foot(m) + Vector2(0, -MAST_H - 14)
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -9), c + Vector2(8, 5), c + Vector2(-8, 5)]), Color(1.0, 0.82, 0.1))
				draw_line(c + Vector2(0, -4), c + Vector2(0, 1), Color.BLACK, 1.5)
				draw_circle(c + Vector2(0, 3), 0.9, Color.BLACK)
	for pid in N.planned:   # beschlossene Trasse (Ringschluss im Bau): abgesteckt mit Pflöcken
		var p: Dictionary = N.planned[pid]
		var cells := PowerNet.line_cells(N.nodes[str(p.a)].cell, N.nodes[str(p.b)].cell)
		for i in range(0, cells.size(), 2):
			var q: Vector2i = cells[i]
			if view.has_point(q):
				var c := _foot(q)
				draw_line(c, c + Vector2(0, -7), STAKE, 1.5)
	for id in N.nodes:
		var n: Dictionary = N.nodes[id]
		if int(n.town) >= 0 and view.has_point(n.cell):
			_draw_substation(n.cell, sim.grid.net.connected(int(n.town)))


## Gittermast: zwei schraege Beine, Querstreben, Traverse mit Isolatoren.
func _draw_mast(f: Vector2) -> void:
	var top := f + Vector2(0, -MAST_H)
	draw_line(f + Vector2(-5, 0), top, MAST, 1.4)
	draw_line(f + Vector2(5, 0), top, MAST, 1.4)
	for k in 3:
		var y := -6.0 - 9.0 * k
		var w := 4.0 - 1.2 * k
		draw_line(f + Vector2(-w, y), f + Vector2(w, y - 6), MAST, 0.8)
	draw_line(top + Vector2(-9, 3), top + Vector2(9, 3), MAST, 1.6)   # Traverse
	for x in [-8.0, 8.0]:
		draw_line(top + Vector2(x, 3), top + Vector2(x, 6), Color(0.85, 0.85, 0.9), 1.2)


## Leiterseil mit leichtem Durchhang (Parabel).
func _draw_wire(a: Vector2, b: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	var sag := clampf(a.distance_to(b) * 0.06, 2.0, 10.0)
	for i in 9:
		var t := float(i) / 8.0
		pts.append(a.lerp(b, t) + Vector2(0, sag * 4.0 * t * (1.0 - t) + 6.0))
	draw_polyline(pts, col, 1.0, true)


func _draw_dashed(a: Vector2, b: Vector2) -> void:
	var n := maxi(2, int(a.distance_to(b) / 8.0))
	for i in range(0, n, 2):
		draw_line(a.lerp(b, float(i) / n) + Vector2(0, 6), a.lerp(b, float(i + 1) / n) + Vector2(0, 6), BROKEN, 1.5)


## Umspannwerk: Schotterflaeche mit Zaun, zwei Transformatoren, Portal fuer die einlaufende Leitung; ohne Netz rote Lampe.
func _draw_substation(q: Vector2i, on: bool) -> void:
	var a := Vector2(q) * 32.0
	var pad := PackedVector2Array([Iso.to_screen(a), Iso.to_screen(a + Vector2(32, 0)), Iso.to_screen(a + Vector2(32, 32)), Iso.to_screen(a + Vector2(0, 32))])
	draw_colored_polygon(pad, PAD)
	var ring := pad.duplicate()
	ring.append(pad[0])
	draw_polyline(ring, FENCE, 1.0)
	var c := _foot(q)
	for x in [-12.0, 6.0]:
		var o := c + Vector2(x, -2)
		draw_rect(Rect2(o + Vector2(0, -10), Vector2(8, 10)), TRAFO)
		draw_rect(Rect2(o + Vector2(0, -10), Vector2(8, 3)), TRAFO.lightened(0.25))
		draw_line(o + Vector2(4, -10), o + Vector2(4, -14), Color(0.85, 0.85, 0.9), 1.2)
	draw_line(c + Vector2(-14, -MAST_H + 4), c + Vector2(14, -MAST_H + 4), MAST, 1.6)   # Portal
	draw_line(c + Vector2(-13, 0), c + Vector2(-13, -MAST_H + 4), MAST, 1.2)
	draw_line(c + Vector2(13, 0), c + Vector2(13, -MAST_H + 4), MAST, 1.2)
	draw_circle(c + Vector2(0, -MAST_H + 8), 2.2, Color(0.3, 0.9, 0.35) if on else Color(1.0, 0.2, 0.15))
