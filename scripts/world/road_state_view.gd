class_name RoadStateView
extends Node2D
## Strassenzustand auf der Karte (Auftrag 20, Etappe 6): Schneedecke auf ungeraeumten Abschnitten (weiss, Dichte nach Schneehoehe),
## geraeumte und gestreute Abschnitte bleiben dunkel mit Salzkoernern; Schlagloecher als dunkle Flecken auf Abschnitten unter 35 %.
## Zeichnet nur den sichtbaren Ausschnitt und nur neu, wenn sich Ausschnitt oder Zustand aendern (Pruefung alle 0,5 s).

var sim: Simulation
var _poll := 0.0
var _key := ""


func setup(simulation: Simulation) -> void:
	sim = simulation


func _process(delta: float) -> void:
	_poll -= delta
	if _poll > 0.0 or sim == null or sim.winter == null:
		return
	_poll = 0.5
	var r := _view_cells()
	var key := "%s|%d|%d|%d|%d" % [str(r), int(_sum(sim.winter.snow) / 20.0), sim.winter.salted.size(), sim.winter.potholes().size(), sim.transit.lines.size()]
	if key != _key:
		_key = key
		queue_redraw()


static func _sum(d: Dictionary) -> float:
	var s := 0.0
	for v in d.values():
		s += float(v)
	return s


## Sichtbarer Kartenausschnitt in Feldern (grob, mit Rand).
func _view_cells() -> Rect2i:
	var inv := get_canvas_transform().affine_inverse()
	var vs := get_viewport_rect().size
	var lo := Vector2i(999999, 999999)
	var hi := Vector2i(-999999, -999999)
	for c in [Vector2.ZERO, Vector2(vs.x, 0), vs, Vector2(0, vs.y)]:
		var w := Iso.to_world(inv * c) / 32.0
		lo = Vector2i(mini(lo.x, int(w.x)), mini(lo.y, int(w.y)))
		hi = Vector2i(maxi(hi.x, int(w.x)), maxi(hi.y, int(w.y)))
	var n: int = sim.city.size
	lo = Vector2i(clampi(lo.x - 2, 0, n), clampi(lo.y - 2, 0, n))
	hi = Vector2i(clampi(hi.x + 2, 0, n), clampi(hi.y + 2, 0, n))
	return Rect2i(lo, hi - lo)


func _cell(q: Vector2i, inset: float) -> PackedVector2Array:
	var a := Vector2(q) + Vector2(inset, inset)
	var b := Vector2(q) + Vector2(1.0 - inset, 1.0 - inset)
	return PackedVector2Array([Iso.to_screen(a * 32.0), Iso.to_screen(Vector2(b.x, a.y) * 32.0), Iso.to_screen(b * 32.0), Iso.to_screen(Vector2(a.x, b.y) * 32.0)])


func _draw() -> void:
	if sim == null or sim.winter == null:
		return
	var W: WinterService = sim.winter
	var holes := {}
	for seg in W.potholes():
		holes[seg] = true
	_draw_stops()
	if W.snow.is_empty() and holes.is_empty() and W.salted.is_empty():
		return
	var r := _view_cells()
	if r.size.x * r.size.y > 40000:
		return   # weit herausgezoomt: keine Einzelheiten
	var now: float = sim.game_min
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var q := Vector2i(x, y)
			if not sim.city.is_road(q):
				continue
			var seg := RoadCare.seg_of(q)
			var s := float(W.snow.get(seg, 0.0))
			if s > 5.0:
				draw_colored_polygon(_cell(q, 0.0), Color(0.96, 0.97, 1.0, clampf(s / 100.0, 0.15, 0.9)))
			elif float(W.salted.get(seg, -1.0)) > now:
				draw_colored_polygon(_cell(q, 0.0), Color(0.22, 0.24, 0.27, 0.35))   # nass-dunkel geraeumt
				if (x * 7 + y * 3) % 4 == 0:
					var c := Iso.to_screen((Vector2(q) + Vector2(0.3, 0.6)) * 32.0)
					draw_rect(Rect2(c, Vector2(2, 2)), Color(0.95, 0.95, 0.95, 0.8))
			if holes.has(seg) and absi(hash(q)) % 3 == 0:
				var h := Iso.to_screen((Vector2(q) + Vector2(0.35 + 0.3 * float(absi(hash(q)) % 10) / 10.0, 0.5)) * 32.0)
				draw_colored_polygon(PackedVector2Array([h + Vector2(-7, 0), h + Vector2(0, -3), h + Vector2(7, 0), h + Vector2(0, 3)]), Color(0.1, 0.1, 0.11, 0.85))
				draw_line(h + Vector2(-6, 1), h + Vector2(5, 2), Color(0.35, 0.33, 0.3, 0.8), 1.0)


## Bushaltestellen (Etappe 7): Mast mit gelbem H-Schild am Strassenrand.
func _draw_stops() -> void:
	for l in sim.transit.lines.values():
		for st in l.stops:
			var p := Iso.to_screen((Vector2(float(st[0]), float(st[1])) + Vector2(0.85, 0.15)) * 32.0)
			draw_line(p, p + Vector2(0, -26), Color(0.3, 0.32, 0.35), 2.0)
			draw_rect(Rect2(p + Vector2(-6, -36), Vector2(12, 12)), Color(0.95, 0.78, 0.15))
			draw_rect(Rect2(p + Vector2(-6, -36), Vector2(12, 12)), Color(0.15, 0.4, 0.2), false, 1.5)
			draw_string(ThemeDB.fallback_font, p + Vector2(-4, -26), "H", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.1, 0.35, 0.15))
