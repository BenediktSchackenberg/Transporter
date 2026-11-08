class_name PlacementOverlay
extends Node2D
## Diagnoseansicht Gebaeudeplatzierung (Auftrag 18, Taste F8): fuer alle Gebaeude im Bild Baufeld (lot, gelb), belegte Zellen
## (building_at, blau), Bildgrundflaeche laut Manifest (weiss gestrichelt), Eingang/Fussweg (walk, cyan), Lieferzugang (road, gruen),
## Strassen-/Gehwegzellen (grau) und den tatsaechlich geladenen Asset-Schluessel samt Variante. Zeichnet nur den sichtbaren Ausschnitt.

var sim: Simulation
var cv


func setup(simulation: Simulation, city_view) -> void:
	sim = simulation
	cv = city_view
	visible = false
	z_index = 30


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _cell_poly(q: Vector2i, inset: float = 0.0) -> PackedVector2Array:
	var a := Vector2(q) + Vector2(inset, inset)
	var b := Vector2(q) + Vector2(1.0 - inset, 1.0 - inset)
	return PackedVector2Array([Iso.to_screen(a * 32.0), Iso.to_screen(Vector2(b.x, a.y) * 32.0), Iso.to_screen(b * 32.0), Iso.to_screen(Vector2(a.x, b.y) * 32.0)])


func _rect_line(r: Rect2, col: Color, width: float) -> void:
	var p := PackedVector2Array([Iso.to_screen(r.position * 32.0), Iso.to_screen(Vector2(r.end.x, r.position.y) * 32.0),
		Iso.to_screen(r.end * 32.0), Iso.to_screen(Vector2(r.position.x, r.end.y) * 32.0), Iso.to_screen(r.position * 32.0)])
	draw_polyline(p, col, width)


func _draw() -> void:
	if sim == null:
		return
	var C := sim.city
	var cam: Camera2D = cv.camera
	var half := get_viewport_rect().size / cam.zoom * 0.5
	var view := Rect2(cam.position - half, half * 2.0)
	var center := Iso.to_world(cam.position) / 32.0
	var rad := int(maxf(half.x, half.y) / 32.0) + 4
	# Strassen/Gehwege im Ausschnitt
	for y in range(int(center.y) - rad, int(center.y) + rad):
		for x in range(int(center.x) - rad, int(center.x) + rad):
			var q := Vector2i(x, y)
			if not C.inside(q):
				continue
			var g: int = C.g(q)
			if g == CityData.G.ROAD:
				draw_colored_polygon(_cell_poly(q, 0.1), Color(0.5, 0.5, 0.5, 0.25))
			elif g == CityData.G.SIDEWALK:
				draw_colored_polygon(_cell_poly(q, 0.2), Color(0.8, 0.8, 0.8, 0.25))
	var man: Dictionary = cv.man
	var font := ThemeDB.fallback_font
	for b in C.buildings:
		var anchor := Iso.to_screen(Vector2(float(b.x) + float(b.w) * 0.5, float(b.y) + float(b.h) * 0.5) * 32.0)
		if not view.grow(200).has_point(anchor):
			continue
		if b.has("lot"):
			_rect_line(Rect2(float(b.lot[0]), float(b.lot[1]), float(b.lot[2]), float(b.lot[3])), Color(1.0, 0.85, 0.2, 0.9), 2.0)
		for y in range(int(b.y), int(b.y) + int(b.h)):
			for x in range(int(b.x), int(b.x) + int(b.w)):
				var q := Vector2i(x, y)
				var own: bool = C.inside(q) and C.building_at[C.idx(q)] == int(b.id)
				draw_colored_polygon(_cell_poly(q, 0.06), Color(0.2, 0.45, 1.0, 0.28) if own else Color(1.0, 0.1, 0.1, 0.45))
				if C.inside(q) and C.g(q) in [CityData.G.ROAD, CityData.G.WATER]:
					draw_colored_polygon(_cell_poly(q, 0.25), Color(1, 0, 0, 0.8))   # unzulaessige Belegung
		var info: Dictionary = man.buildings.get(str(b.get("sprite", "")), {})
		if not info.is_empty():
			var cell: Vector2i = cv.sprite_cell(b, info)
			_rect_line(Rect2(Vector2(cell), Vector2(float(info.w), float(info.h))), Color(1, 1, 1, 0.85), 1.0)
		var road: Vector2i = b.get("road", Vector2i(-1, -1))
		var walk: Vector2i = b.get("walk", Vector2i(-1, -1))
		if road.x >= 0:
			draw_circle(Iso.to_screen((Vector2(road) + Vector2(0.5, 0.5)) * 32.0), 5.0, Color(0.2, 0.9, 0.3))
		if walk.x >= 0:
			draw_circle(Iso.to_screen((Vector2(walk) + Vector2(0.5, 0.5)) * 32.0), 4.0, Color(0.2, 0.9, 1.0))
		draw_string(font, anchor + Vector2(-40, -6), "#%d %s" % [int(b.id), str(b.get("sprite", ""))], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.95))
