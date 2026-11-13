class_name FreeBuildView
extends Node2D
## Freie Bauwerke (FreeBuild) Stein auf Stein: je Bauwerk ein Knoten in der tiefensortierten Gebaeudeebene, der die bereits
## gesetzten Bloecke als Iso-Wuerfel zeichnet (Oberseite hell, Sued- und Ostseite schattiert, verdeckte Flaechen weggelassen).
## Glas leicht durchscheinend. Auf der Baustelle: Bauzaun-Ecken und der naechste Block als Umriss.

const BLOCK := 8.0          # Welteinheiten je Block (4 je Feld)
const BLOCK_H := 16.0       # Bildhoehe eines Blocks (2 Pixel je Voxel)

var sim: Simulation
var cv
var _nodes := {}            # Bauwerk-ID -> Node2D
var _drawn := {}            # Bauwerk-ID -> gezeichnete Blockzahl


func setup(simulation: Simulation, city_view) -> void:
	sim = simulation
	cv = city_view
	if sim.freebuild != null:
		sim.freebuild.build_changed.connect(func(_id): _refresh())
	_refresh()


func _refresh() -> void:
	if sim.freebuild == null:
		return
	for fb in sim.freebuild.builds.values():
		var key := "%d|%s" % [int(fb.placed), str(fb.status)]
		if _drawn.get(fb.id, "") == key:
			continue
		_drawn[fb.id] = key
		var n: Node2D = _nodes.get(fb.id)
		if n == null:
			n = BuildNode.new()
			n.fb_id = fb.id
			n.sim = sim
			cv.buildings_node.add_child(n)
			_nodes[fb.id] = n
		# Sortierpunkt: vordere Ecke der Grundflaeche (wie Gebaeude)
		var r := Rect2i(int(fb.rect[0]), int(fb.rect[1]), int(fb.rect[2]), int(fb.rect[3]))
		n.position = Iso.to_screen(Vector2(r.end) * 32.0)
		n.queue_redraw()


class BuildNode:
	extends Node2D
	var fb_id := ""
	var sim: Simulation

	func _draw() -> void:
		var fb: Dictionary = sim.freebuild.builds.get(fb_id, {})
		if fb.is_empty():
			return
		var o := Vector2(float(fb.rect[0]), float(fb.rect[1])) * 32.0
		var origin := position
		var placed := int(fb.placed)
		var occ := {}
		for i in placed:
			var b: Array = fb.blocks[i]
			occ[Vector3i(int(b[0]), int(b[1]), int(b[2]))] = true
		var order: Array = fb.blocks.slice(0, placed)
		order.sort_custom(func(a, b): return int(a[0]) + int(a[1]) < int(b[0]) + int(b[1]) or (int(a[0]) + int(a[1]) == int(b[0]) + int(b[1]) and int(a[2]) < int(b[2])))
		for b in order:
			var x := int(b[0])
			var y := int(b[1])
			var z := int(b[2])
			var col := Color(str(FreeBuild.MATERIALS[str(b[3])].color))
			if str(b[3]) == "glas":
				col.a = 0.75
			var w0 := o + Vector2(x, y) * FreeBuildView.BLOCK
			var up := Vector2(0, -float(z) * FreeBuildView.BLOCK_H)
			var top := up + Vector2(0, -FreeBuildView.BLOCK_H)
			var p00 := Iso.to_screen(w0) - origin
			var p10 := Iso.to_screen(w0 + Vector2(FreeBuildView.BLOCK, 0)) - origin
			var p11 := Iso.to_screen(w0 + Vector2(FreeBuildView.BLOCK, FreeBuildView.BLOCK)) - origin
			var p01 := Iso.to_screen(w0 + Vector2(0, FreeBuildView.BLOCK)) - origin
			if not occ.has(Vector3i(x, y + 1, z)):   # Suedseite
				draw_colored_polygon(PackedVector2Array([p01 + up, p11 + up, p11 + top, p01 + top]), col.darkened(0.15))
			if not occ.has(Vector3i(x + 1, y, z)):   # Ostseite
				draw_colored_polygon(PackedVector2Array([p10 + up, p11 + up, p11 + top, p10 + top]), col.darkened(0.32))
			if not occ.has(Vector3i(x, y, z + 1)):   # Oberseite
				draw_colored_polygon(PackedVector2Array([p00 + top, p10 + top, p11 + top, p01 + top]), col.lightened(0.08))
				draw_polyline(PackedVector2Array([p00 + top, p10 + top, p11 + top, p01 + top, p00 + top]), col.darkened(0.25), 0.6)
			if str(b[3]) == "ziegel" and not occ.has(Vector3i(x, y + 1, z)):   # Fugen
				draw_line((p01 + p11) * 0.5 + up + Vector2(0, -FreeBuildView.BLOCK_H * 0.5), (p01 + p11) * 0.5 + up + Vector2(0, -FreeBuildView.BLOCK_H), col.darkened(0.4), 0.6)
		if str(fb.status) != "fertig" and placed < fb.blocks.size():   # naechster Block als Umriss, Bauzaun-Ecken
			var nb: Array = fb.blocks[placed]
			var w1 := o + Vector2(int(nb[0]), int(nb[1])) * FreeBuildView.BLOCK
			var up1 := Vector2(0, -float(int(nb[2])) * FreeBuildView.BLOCK_H - FreeBuildView.BLOCK_H)
			var q := [Iso.to_screen(w1), Iso.to_screen(w1 + Vector2(FreeBuildView.BLOCK, 0)), Iso.to_screen(w1 + Vector2(FreeBuildView.BLOCK, FreeBuildView.BLOCK)), Iso.to_screen(w1 + Vector2(0, FreeBuildView.BLOCK))]
			var ring := PackedVector2Array()
			for p in q:
				ring.append(p - origin + up1)
			ring.append(ring[0])
			draw_polyline(ring, Color(1.0, 0.85, 0.2, 0.9), 1.2)
			var rw := Vector2(float(fb.rect[2]), float(fb.rect[3])) * 32.0
			for c in [Vector2.ZERO, Vector2(rw.x, 0), rw, Vector2(0, rw.y)]:
				var f := Iso.to_screen(o + c) - origin
				draw_line(f, f + Vector2(0, -12), Color(0.95, 0.55, 0.12), 2.0)
