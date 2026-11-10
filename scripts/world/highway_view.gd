class_name HighwayView
extends Node2D
## Autobahn auf der Karte (Auftrag 21, docs/HIGHWAY.md): beschlossene Trasse als abgesteckter Streifen (Pflocke), gebauter Teil nach
## Baufortschritt als dunkler Asphalt mit Leitplanken, Mittelstreifen und gestrichelten Fahrstreifen, Baustellenspitze mit Baken,
## blaue Schilder an den Anschlussstellen. Zeichnet nur den sichtbaren Ausschnitt, neu nur bei Aenderung (Pruefung alle 0,5 s).

const ASPHALT := Color(0.18, 0.19, 0.21, 0.96)
const RAIL := Color(0.78, 0.8, 0.82, 0.95)
const LINE := Color(0.96, 0.96, 0.92, 0.9)
const STAKE := Color(0.95, 0.55, 0.12, 0.9)
const PLAN := Color(0.62, 0.48, 0.3, 0.7)   # abgesteckte, abgeschobene Trasse (Erdreich)
const SIGN := Color(0.12, 0.3, 0.75)

var sim: Simulation
var _poll := 0.0
var _key := ""


func setup(simulation: Simulation) -> void:
	sim = simulation


func _process(delta: float) -> void:
	_poll -= delta
	if _poll > 0.0 or sim == null or sim.regional == null:
		return
	_poll = 0.5
	var hw: Array = _items()
	if hw.is_empty() and _key == "":
		return
	var key := "%s|%s" % [str(_view_cells()), ",".join(hw.map(func(r): return "%s%s%.2f" % [r.id, r.status, sim.regional.progress(r)]))]
	if key != _key:
		_key = key
		queue_redraw()


func _items() -> Array:
	return sim.regional.items.values().filter(func(r): return str(r.get("kind", "")) == "autobahn" and r.status in ["beschlossen", "im_bau", "fertig"])


func _view_cells() -> Rect2i:
	var inv := get_canvas_transform().affine_inverse()
	var vs := get_viewport_rect().size
	var lo := Vector2i(999999, 999999)
	var hi := Vector2i(-999999, -999999)
	for c in [Vector2.ZERO, Vector2(vs.x, 0), vs, Vector2(0, vs.y)]:
		var w := Iso.to_world(inv * c) / 32.0
		lo = Vector2i(mini(lo.x, int(w.x)), mini(lo.y, int(w.y)))
		hi = Vector2i(maxi(hi.x, int(w.x)), maxi(hi.y, int(w.y)))
	return Rect2i(lo - Vector2i(2, 2), hi - lo + Vector2i(4, 4))


func _cell(q: Vector2i, inset: float) -> PackedVector2Array:
	var a := Vector2(q) + Vector2(inset, inset)
	var b := Vector2(q) + Vector2(1.0 - inset, 1.0 - inset)
	return PackedVector2Array([Iso.to_screen(a * 32.0), Iso.to_screen(Vector2(b.x, a.y) * 32.0), Iso.to_screen(b * 32.0), Iso.to_screen(Vector2(a.x, b.y) * 32.0)])


func _draw() -> void:
	if sim == null:
		return
	var view := _view_cells()
	if view.size.x * view.size.y > 160000:
		return   # sehr weit herausgezoomt: nur die Strassentextur
	for r in _items():
		var cells: Array = r.cells
		var built := int(round(sim.regional.progress(r) * float(cells.size())))
		for i in cells.size():
			var q := Vector2i(int(cells[i][0]), int(cells[i][1]))
			if not view.has_point(q):
				continue
			if i < built:
				_draw_lane(q, i)
			else:
				draw_colored_polygon(_cell(q, 0.08), PLAN)
				if i % 3 == 0:
					var c := Iso.to_screen((Vector2(q) + Vector2(0.5, 0.5)) * 32.0)
					draw_line(c, c + Vector2(0, -7), STAKE, 1.5)   # Absteckpflock
		if built > 0 and built < cells.size():   # Baustellenspitze: Baken
			var f := Vector2i(int(cells[built - 1][0]), int(cells[built - 1][1]))
			if view.has_point(f):
				var c := Iso.to_screen((Vector2(f) + Vector2(0.5, 0.5)) * 32.0)
				for k in 3:
					var p := c + Vector2(-10 + 10 * k, 2)
					draw_colored_polygon(PackedVector2Array([p + Vector2(-3, 0), p + Vector2(3, 0), p + Vector2(0, -10)]), Color(1.0, 0.45, 0.1))
					draw_line(p + Vector2(-2, -4), p + Vector2(2, -4), Color.WHITE, 1.0)
		for j in r.get("junctions", []):
			var q := Vector2i(int(j[0]), int(j[1]))
			if view.has_point(q):
				_draw_sign(q, sim.towns.name_of(sim.towns.of_cell(q)))


func _draw_lane(q: Vector2i, i: int) -> void:
	draw_colored_polygon(_cell(q, 0.0), ASPHALT)
	var poly := _cell(q, 0.0)
	draw_line(poly[0], poly[1], RAIL, 1.2)   # Leitplanken an den Raendern
	draw_line(poly[2], poly[3], RAIL, 1.2)
	if i % 2 == 0:   # gestrichelte Fahrstreifenmarkierung
		var c := Iso.to_screen((Vector2(q) + Vector2(0.5, 0.5)) * 32.0)
		draw_line(c + Vector2(-6, -3), c + Vector2(6, 3), LINE, 1.5)


func _draw_sign(q: Vector2i, town: String) -> void:
	var c := Iso.to_screen((Vector2(q) + Vector2(0.5, 0.2)) * 32.0)
	draw_line(c, c + Vector2(0, -30), Color(0.4, 0.42, 0.45), 2.0)
	draw_rect(Rect2(c + Vector2(-28, -46), Vector2(56, 16)), SIGN)
	draw_rect(Rect2(c + Vector2(-28, -46), Vector2(56, 16)), Color.WHITE, false, 1.0)
	draw_string(ThemeDB.fallback_font, c + Vector2(-25, -34), "A  " + town.left(9), HORIZONTAL_ALIGNMENT_LEFT, 54, 10, Color.WHITE)
