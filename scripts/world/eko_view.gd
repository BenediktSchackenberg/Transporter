class_name EkoView
extends Node2D
## Darstellung des Eko-Modus: Bloecke als Iso-Wuerfel (Farben und Schattierung wie FreeBuildView), je Feld ein Knoten in der
## tiefensortierten Gebaeudeebene; Wesen als kleine Pixelfigur mit getragenem Material und Sprechblase.

const BLOCK := 8.0          # Welteinheiten je Block (4 je Feld)
const BLOCK_H := 16.0       # Bildhoehe eines Blocks

var sim: Simulation
var cv
var _tiles := {}            # Feld -> TileNode
var _beings := {}           # Name -> BeingNode
var follow := false         # Kamera folgt dem ersten Wesen (--eko-folgen)


func setup(simulation: Simulation, city_view) -> void:
	sim = simulation
	cv = city_view
	sim.eko.changed.connect(_refresh)
	_refresh()


func _process(_delta: float) -> void:
	if follow and not sim.eko.beings.is_empty():
		cv.set_camera_world(sim.eko.beings.values()[0].mover.pos)
	for name in _beings:
		var n: BeingNode = _beings[name]
		var b: Dictionary = sim.eko.beings.get(name, {})
		if not b.is_empty():
			n.position = Iso.to_screen(b.mover.pos)
			n.queue_redraw()


func _refresh() -> void:
	var by_tile := {}
	for p in sim.eko.blocks:
		var t := Vector2i(floori(float(p.x) / EkoWorld.PER_TILE), floori(float(p.y) / EkoWorld.PER_TILE))
		if not by_tile.has(t):
			by_tile[t] = []
		by_tile[t].append(p)
	for t in _tiles.keys():
		if not by_tile.has(t):
			_tiles[t].queue_free()
			_tiles.erase(t)
	for t in by_tile:
		var n: TileNode = _tiles.get(t)
		if n == null:
			n = TileNode.new()
			n.sim = sim
			n.tile = t
			n.position = Iso.to_screen(Vector2(t + Vector2i.ONE) * 32.0)   # Sortierpunkt: vordere Ecke des Feldes
			cv.buildings_node.add_child(n)
			_tiles[t] = n
		n.cells = by_tile[t]
		n.queue_redraw()
	for name in sim.eko.beings:
		if not _beings.has(name):
			var bn := BeingNode.new()
			bn.sim = sim
			bn.being = name
			bn.z_index = 3   # ueber Gebaeuden wie die Markierungen der Figuren, sonst verdeckt der Bauhof das Wesen
			bn.scale = Vector2(1.5, 1.5)   # Groesse der Buergerfiguren
			cv.buildings_node.add_child(bn)
			_beings[name] = bn


class TileNode:
	extends Node2D
	var sim: Simulation
	var tile := Vector2i.ZERO
	var cells: Array = []

	func _draw() -> void:
		var bl: Dictionary = sim.eko.blocks
		var order := cells.duplicate()
		order.sort_custom(func(a, b): return a.x + a.y < b.x + b.y or (a.x + a.y == b.x + b.y and a.z < b.z))
		for p in order:
			var mat := str(bl.get(p, ""))
			if mat == "":
				continue
			var col := Color(str(FreeBuild.MATERIALS[mat].color))
			if mat == "glas":
				col.a = 0.75
			var w0 := Vector2(p.x, p.y) * EkoView.BLOCK
			var up := Vector2(0, -float(p.z) * EkoView.BLOCK_H)
			var top := up + Vector2(0, -EkoView.BLOCK_H)
			var p00 := Iso.to_screen(w0) - position
			var p10 := Iso.to_screen(w0 + Vector2(EkoView.BLOCK, 0)) - position
			var p11 := Iso.to_screen(w0 + Vector2(EkoView.BLOCK, EkoView.BLOCK)) - position
			var p01 := Iso.to_screen(w0 + Vector2(0, EkoView.BLOCK)) - position
			if not bl.has(p + Vector3i(0, 1, 0)):   # Suedseite
				draw_colored_polygon(PackedVector2Array([p01 + up, p11 + up, p11 + top, p01 + top]), col.darkened(0.15))
			if not bl.has(p + Vector3i(1, 0, 0)):   # Ostseite
				draw_colored_polygon(PackedVector2Array([p10 + up, p11 + up, p11 + top, p10 + top]), col.darkened(0.32))
			if not bl.has(p + Vector3i(0, 0, 1)):   # Oberseite
				draw_colored_polygon(PackedVector2Array([p00 + top, p10 + top, p11 + top, p01 + top]), col.lightened(0.08))
				draw_polyline(PackedVector2Array([p00 + top, p10 + top, p11 + top, p01 + top, p00 + top]), col.darkened(0.25), 0.6)


class BeingNode:
	extends Node2D
	var sim: Simulation
	var being := ""

	func _draw() -> void:
		var b: Dictionary = sim.eko.beings.get(being, {})
		if b.is_empty():
			return
		var col: Color = b.color
		draw_circle(Vector2(0, 1), 6.0, Color(0, 0, 0, 0.25))                       # Schatten
		draw_rect(Rect2(-3, -6, 2, 6), Color("#2d2a32"))                            # Beine
		draw_rect(Rect2(1, -6, 2, 6), Color("#2d2a32"))
		draw_rect(Rect2(-4, -16, 8, 10), col)                                       # Koerper
		draw_rect(Rect2(-3, -23, 6, 7), Color("#f1c9a5"))                           # Kopf
		draw_rect(Rect2(-3, -24, 6, 2), col.darkened(0.4))                          # Haare
		var held: Array = b.held
		for i in held.size():   # getragene Bloecke ueber dem Kopf gestapelt
			var c := Color(str(FreeBuild.MATERIALS[str(held[i])].color))
			draw_rect(Rect2(-4, -31 - i * 5, 8, 5), c)
			draw_rect(Rect2(-4, -31 - i * 5, 8, 5), c.darkened(0.35), false, 0.6)
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(-30, 12), str(b.name), HORIZONTAL_ALIGNMENT_CENTER, 60, 7, Color.WHITE)
		if float(b.say_left) > 0.0 and str(b.say) != "":
			var text := str(b.say)
			var w := minf(160.0, font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x + 10.0)
			var lines := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, w - 8.0, 7)
			var box := Rect2(-w * 0.5, -40 - held.size() * 5 - lines.y, w, lines.y + 6)
			draw_rect(box, Color(1, 1, 1, 0.92))
			draw_rect(box, col.darkened(0.3), false, 1.0)
			draw_multiline_string(font, box.position + Vector2(4, 9), text, HORIZONTAL_ALIGNMENT_LEFT, w - 8.0, 7, -1, Color("#222"))
