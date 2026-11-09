class_name CivicView
extends Node2D
## Auftrag 19: sichtbare Anlagen der Buergermeister (Spielplaetze, Parks, Maerkte, Sportplaetze, Denkmaeler) und Leben im Grosslager.
## Liest nur den Zustand aus CivicWorks bzw. CityData.hub. Bauteile liegen in der y-sortierten Gebaeudeebene; Spielfeldlinien als
## Zeichnung auf dem Boden. Baustellen: Bauzaun, die Bauteile erscheinen mit dem Baufortschritt. Denkmaeler in Buergermeisterfarbe.

var sim: Simulation
var cv
var _nodes := {}         # Anlage-ID -> [Node2D]
var _sig := {}           # Anlage-ID -> Darstellungsstand (Status + sichtbare Teile)
var lines: LineLayer
var _forks: Array = []   # Gabelstapler im Grosslager: [Sprite2D, Start, Ziel, Phase]
var _t := 0.0


func setup(simulation: Simulation, city_view) -> void:
	sim = simulation
	cv = city_view
	lines = LineLayer.new()
	lines.view = self
	cv.decor_node.add_child(lines)
	if sim.civic != null:
		sim.civic.anlage_changed.connect(func(_id): _refresh())
	_build_hub_life()
	_refresh()


func _refresh() -> void:
	if sim.civic == null:
		return
	for a in sim.civic.anlagen.values():
		var vis := _visible_count(a)
		var sig := "%s|%d" % [a.status, vis]
		if _sig.get(a.id, "") == sig:
			continue
		_sig[a.id] = sig
		for n in _nodes.get(a.id, []):
			n.queue_free()
		_nodes[a.id] = _make(a, vis)
	lines.queue_redraw()


func _visible_count(a: Dictionary) -> int:
	var n: int = a.pieces.size()
	match str(a.status):
		"eroeffnet":
			return n
		"im_bau":
			return int(floor(float(n) * float(a.get("progress", 0.0))))
	return 0


func _make(a: Dictionary, vis: int) -> Array:
	var out: Array = []
	if str(a.status) in ["abgelehnt", "verworfen", "geplant"]:
		return out
	var r := Rect2i(int(a.rect[0]), int(a.rect[1]), int(a.rect[2]), int(a.rect[3]))
	if str(a.status) in ["material", "im_bau"]:   # Bauzaun am Rand
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				if x == r.position.x or y == r.position.y or x == r.end.x - 1 or y == r.end.y - 1:
					out.append(_sprite("fac_site", Vector2(x * 32 + 16, y * 32 + 16)))
	var col := Color(str(a.get("color", "#d4a017")))
	var shown := 0
	for pc in a.pieces:
		if shown >= vis:
			break
		shown += 1
		var spr := str(pc.sprite)
		if spr.begins_with("#"):
			continue   # echtes Gebaeude: zeichnet die Stadtansicht
		var w := Vector2((float(pc.x) + float(pc.w) * 0.5) * 32.0, (float(pc.y) + float(pc.h) * 0.5) * 32.0)
		var s := _sprite(spr, w)
		out.append(s)
		if cv.has_tex(spr + "_mask"):   # Denkmal in der Farbe seines Buergermeisters
			var m := Sprite2D.new()
			m.texture = cv.tex(spr + "_mask")
			m.centered = false
			m.offset = s.offset
			m.modulate = col
			s.add_child(m)
	return out


func _sprite(name: String, world: Vector2) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = cv.tex(name)
	s.centered = false
	s.offset = -cv.pivot_of(name)
	s.position = Iso.to_screen(world)
	cv.buildings_node.add_child(s)
	return s


## Leben im Grosslager: Palettenregale vor dem Hochregallager, Gabelstapler pendeln zwischen Warenannahme, Hallen und Ausgang.
func _build_hub_life() -> void:
	var H: Dictionary = sim.city.hub
	if H.is_empty():
		return
	var C: CityData = sim.city
	var B: Dictionary = H.buildings
	var rack: Dictionary = C.building(int(B.get("hochregal", -1)))
	if not rack.is_empty():
		for i in 4:
			var q := Vector2i(int(rack.x) + i, int(rack.y) + int(rack.h) + 1)
			if C.inside(q) and C.building_at[C.idx(q)] == -1 and not C.is_road(q):
				_sprite("d_rack", Vector2(q.x * 32 + 16, q.y * 32 + 16))
	var stops: Array = []
	for key in ["annahme", "hauptlager", "halle1", "halle2", "halle3", "ausgang"]:
		var b: Dictionary = C.building(int(B.get(key, -1)))
		if not b.is_empty():
			stops.append(Vector2((float(b.x) + float(b.w) * 0.5) * 32.0, (float(b.y) + float(b.h)) * 32.0 + 20.0))
	for i in mini(3, stops.size() - 1):
		var f := _sprite("d_forklift", stops[i])
		_forks.append([f, stops[i], stops[(i + 2) % stops.size()], float(i) * 0.7])


func _process(delta: float) -> void:
	_t += delta
	for fk in _forks:
		var ph: float = fmod(_t * 0.08 + float(fk[3]), 2.0)
		var u := ph if ph < 1.0 else 2.0 - ph
		var p: Vector2 = Vector2(fk[1]).lerp(Vector2(fk[2]), smoothstep(0.0, 1.0, u))
		(fk[0] as Sprite2D).position = Iso.to_screen(p)
		(fk[0] as Sprite2D).flip_h = ph >= 1.0


## Spielfeld-, Platz- und Laufbahnlinien auf dem Boden (unter den Bauteilen).
class LineLayer extends Node2D:
	var view: CivicView

	func _iso(x: float, y: float) -> Vector2:
		return Iso.to_screen(Vector2(x * 32.0, y * 32.0))

	func _draw() -> void:
		if view == null or view.sim.civic == null:
			return
		for a in view.sim.civic.anlagen.values():
			var kind := str(CivicWorks.TEMPLATES.get(a.template, {}).get("lines", ""))
			if kind == "" or str(a.status) not in ["im_bau", "eroeffnet"] or (a.status == "im_bau" and float(a.get("progress", 0.0)) < 0.4):
				continue
			var x0 := float(a.rect[0]) + 0.45
			var y0 := float(a.rect[1]) + 0.45
			var x1 := float(a.rect[0]) + float(a.rect[2]) - 0.45
			var y1 := float(a.rect[1]) + float(a.rect[3]) - 0.45
			var white := Color(1, 1, 1, 0.85)
			if kind == "stadium":   # Laufbahn um das Feld
				draw_colored_polygon(PackedVector2Array([_iso(x0 - 0.3, y0 - 0.3), _iso(x1 + 0.3, y0 - 0.3), _iso(x1 + 0.3, y1 + 0.3), _iso(x0 - 0.3, y1 + 0.3)]), Color("b5533c"))
				draw_colored_polygon(PackedVector2Array([_iso(x0 + 0.4, y0 + 0.4), _iso(x1 - 0.4, y0 + 0.4), _iso(x1 - 0.4, y1 - 0.4), _iso(x0 + 0.4, y1 - 0.4)]), Color("5f9a3e"))
				x0 += 0.5
				y0 += 0.5
				x1 -= 0.5
				y1 -= 0.5
			var c1 := _iso(x0, y0)
			var c2 := _iso(x1, y0)
			var c3 := _iso(x1, y1)
			var c4 := _iso(x0, y1)
			draw_polyline(PackedVector2Array([c1, c2, c3, c4, c1]), white, 2.0)
			var mx := (x0 + x1) * 0.5
			draw_line(_iso(mx, y0), _iso(mx, y1), white, 2.0)
			var pts := PackedVector2Array()
			var r := minf(1.0, (y1 - y0) * 0.22)
			for i in 25:
				var ang := TAU * float(i) / 24.0
				pts.append(_iso(mx + cos(ang) * r, (y0 + y1) * 0.5 + sin(ang) * r))
			draw_polyline(pts, white, 2.0)
			if kind != "court":
				var gy0 := (y0 + y1) * 0.5 - (y1 - y0) * 0.22
				var gy1 := (y0 + y1) * 0.5 + (y1 - y0) * 0.22
				for side in [[x0, x0 + 1.0], [x1, x1 - 1.0]]:
					draw_polyline(PackedVector2Array([_iso(side[0], gy0), _iso(side[1], gy0), _iso(side[1], gy1), _iso(side[0], gy1)]), white, 2.0)
