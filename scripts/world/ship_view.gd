class_name ShipView
extends Node2D
## Schiffe sichtbar: je Hafenstadt ein Holzanleger und das Linienschiff (Harbor; legt am Ankunftstag an und am Folgetag ab) sowie die
## Schiffe des Seeverkehrs zwischen den Haefen (SeaTraffic: Kreuzfahrtschiff, Autotransporter), die einem Wasserweg folgen.
## Liest nur aus der Simulation; alle Bewegungen sind Funktionen der Spieluhr. Prozedural gezeichnet (ShipNode): echter Rumpf mit Bug,
## Wasserlinie und Aufbauten, gedreht in Fahrtrichtung; vier Bauarten (Container, Schuettgut, Kreuzfahrt, Autotransporter).

const SAIL_MIN := 40.0            # Spielminuten fuer An- und Abfahrt des Linienschiffs
const LEN := 7.0                  # Anlegerlaenge in Feldern (Liegeplatz)
const BEAM := 2.0
const STEP := 18.0                # Bildschirmhoehe je Hoehenstufe
const GRID := 2                   # Wasserweg: Suchraster in Feldern

var sim: Simulation
var berth := Vector2.ZERO         # Liegeplatz des Linienschiffs von Ort 0 (Kamera-Ziel im Autotest)
var _ports := {}                  # Ort -> {berth, berth2, edge, west, liner: ShipNode}
var _voyage_nodes := {}           # Schiff-ID -> ShipNode
var _routes := {}                 # "a>b" -> PackedVector2Array (Weltpixel)
var _astar: AStarGrid2D


func setup(simulation: Simulation) -> void:
	sim = simulation
	var towns: Array = range(sim.towns.count()) if sim.towns != null and sim.towns.count() > 0 else [0]
	for k in towns:
		var H: Harbor = sim.towns.harbor(k) if sim.towns != null and sim.towns.count() > 0 else sim.harbor
		if not H.enabled:
			continue
		var info := _port_info(int(k))
		if info.is_empty():
			continue
		var jetty := JettyNode.new()   # Holzanleger vom Ufer ins Wasser, das Linienschiff liegt suedlich laengsseits
		jetty.from_x = info.jx0
		jetty.to_x = info.jx1
		jetty.y = info.jy
		jetty.position = Iso.to_screen(Vector2((jetty.from_x + jetty.to_x) * 0.5, jetty.y + 0.5) * 32.0)
		add_child(jetty)
		var liner := ShipNode.new()
		liner.visible = false
		add_child(liner)
		info["liner"] = liner
		_ports[int(k)] = info
	if _ports.has(0):
		berth = _ports[0].berth
	elif not _ports.is_empty():
		berth = _ports.values()[0].berth


## Liegeplatz, Einfahrt am Kartenrand und Anleger eines Hafenorts (Weltpixel bzw. Felder).
func _port_info(k: int) -> Dictionary:
	var port := {}
	if not sim.city.towns.is_empty() and k < sim.city.towns.size():
		port = sim.city.building(int(sim.city.towns[k].get("port_office", -1)))
	if port.is_empty() and k == 0:
		for b in sim.city.buildings:
			if b.type == "port_office":
				port = b
				break
	if port.is_empty():
		var H: Harbor = sim.towns.harbor(k) if sim.towns != null and sim.towns.count() > 0 else sim.harbor
		port = sim.city.building(H.building)
	if port.is_empty():
		return {}
	var y: int = int(port.y) + int(port.h) + 1
	var west := sim.city.world == "region" and k < sim.city.towns.size() and str(sim.city.towns[k].get("ecke", "")).ends_with("W")
	var x: int = int(port.x) if west else int(port.x) + int(port.w)
	var direction := -1 if west else 1
	while x > 0 and x < sim.city.size - 1 and sim.city.g(Vector2i(x, y)) != CityData.G.WATER:
		x += direction
	var bx := float(x) + (-(LEN * 0.5) if west else LEN * 0.5) + 0.4
	var by := float(y) + BEAM * 0.5 + 0.15
	return {"berth": Vector2(bx, by) * 32.0, "berth2": Vector2(bx + (-2.0 if west else 2.0), by + BEAM + 1.4) * 32.0,
		"edge": Vector2(-LEN if west else float(sim.city.size) + LEN, by) * 32.0, "west": west,
		"jx0": float(x) - LEN - 1.0 if west else float(x) - 1.0, "jx1": float(x) + 1.0 if west else float(x) + LEN + 1.0, "jy": float(y) - 1.0}


func update_view(_delta: float) -> void:
	if sim == null:
		return
	var now: float = sim.game_min
	var night := GameCalendar.hour_of(now) >= 19.0 or GameCalendar.hour_of(now) < 6.0
	for k in _ports:
		_update_liner(int(k), now, night)
	_update_voyages(now, night)


## Linienschiff eines Hafens: Anfahrt vom Kartenrand am Ankunftstag, Liegezeit, Abfahrt am Folgetag.
func _update_liner(k: int, now: float, night: bool) -> void:
	var info: Dictionary = _ports[k]
	var node: ShipNode = info.liner
	var H: Harbor = sim.towns.harbor(k) if sim.towns != null and sim.towns.count() > 0 else sim.harbor
	var sh: Dictionary = H.ship
	if sh.is_empty():
		node.visible = false
		return
	var docked_at := GameCalendar.day_start(int(sh.day))
	var pos: Vector2 = info.berth
	var moving := 0.0
	var inbound := true
	if sh.status == "am_kai":
		var t := clampf((now - docked_at) / SAIL_MIN, 0.0, 1.0)
		pos = (info.edge as Vector2).lerp(info.berth, _ease(t))
		moving = 1.0 - t
	else:
		var t2 := clampf((now - GameCalendar.day_start(int(sh.day) + 1)) / SAIL_MIN, 0.0, 1.0)
		if t2 >= 1.0:
			node.visible = false
			return
		pos = (info.berth as Vector2).lerp(info.edge, _ease(t2))
		moving = 1.0 - absf(t2 - 0.5) * 2.0
		inbound = false
	# Bug zeigt in Fahrtrichtung: einlaufend vom Rand zum Kai, auslaufend zum Rand
	var to_edge: Vector2 = (info.edge as Vector2) - (info.berth as Vector2)
	var heading := (-to_edge).angle() if inbound else to_edge.angle()
	node.kind = "schuettgut" if posmod(hash(str(sh.name)), 3) == 0 else "container"
	node.cargo = maxi(int(sh.get("geloescht", {}).size()), int(sh.get("geladen", {}).size())) if sh.status == "am_kai" else int(sh.get("geladen", {}).size())
	_place(node, pos, heading, str(sh.name), moving, night)


## Kreuzfahrtschiff und Autotransporter: entlang des Wasserwegs vom Liegeplatz des Abgangsorts zum Zielort, dort Liegezeit.
func _update_voyages(now: float, night: bool) -> void:
	var shown := {}
	if sim.sea != null and sim.sea.enabled:
		for leg in sim.sea.visible_legs(now):
			var a := int(leg.from)
			var b := int(leg.to)
			if not _ports.has(a) or not _ports.has(b):
				continue
			var node: ShipNode = _voyage_nodes.get(leg.ship)
			if node == null:
				node = ShipNode.new()
				add_child(node)
				_voyage_nodes[leg.ship] = node
			node.kind = str(leg.kind)
			node.cargo = 3
			var path := _route(a, b)
			var t := clampf((now - float(leg.depart)) / maxf(1.0, float(leg.arrive) - float(leg.depart)), 0.0, 1.0)
			var pose := _along(path, _ease(t))
			var moving := 0.0 if t >= 1.0 else 1.0 - absf(t - 0.5) * 2.0
			if pose.pos.x < -64.0 or pose.pos.y < -64.0 or pose.pos.x > sim.city.size * 32.0 + 64.0 or pose.pos.y > sim.city.size * 32.0 + 64.0:
				node.visible = false   # Umweg ueber die offene See jenseits des Kartenrands
				shown[leg.ship] = true
				continue
			_place(node, pose.pos, pose.heading, str(leg.name), moving, night)
			shown[leg.ship] = true
	for id in _voyage_nodes:
		if not shown.has(id):
			_voyage_nodes[id].visible = false


func _place(node: ShipNode, pos: Vector2, heading: float, label: String, moving: float, night: bool) -> void:
	node.visible = true
	node.position = Iso.to_screen(pos)
	node.world = pos
	node.heading = heading
	node.label = label
	node.wake = moving
	node.night = night
	node.queue_redraw()


## Wasserweg zwischen zwei Haefen (gecacht): A* auf Wasserfeldern im Raster GRID (Abstand zur Kueste), sonst Umweg ueber den Kartenrand.
func _route(a: int, b: int) -> PackedVector2Array:
	var key := "%d>%d" % [a, b]
	if _routes.has(key):
		return _routes[key]
	var pa: Vector2 = _ports[a].berth2
	var pb: Vector2 = _ports[b].berth2
	var out := PackedVector2Array()
	var grid_path := _water_path(pa, pb)
	if grid_path.size() >= 2:
		out.append(pa)
		for i in range(1, grid_path.size() - 1):
			if i % 3 == 0:
				out.append((Vector2(grid_path[i]) * GRID + Vector2(GRID, GRID) * 0.5) * 32.0)
		out.append(pb)
	else:
		# Andere See (Land dazwischen): hinaus aufs offene Meer, ausserhalb der Karte um das Festland herum (kuerzere Seite) und wieder herein
		var ea := Vector2(float(_ports[a].edge.x), pa.y)
		var eb := Vector2(float(_ports[b].edge.x), pb.y)
		var size := float(sim.city.size) * 32.0
		var off := LEN * 3.0 * 32.0
		var y_out := -off if (pa.y + pb.y) * 0.5 < size * 0.5 else size + off
		out = PackedVector2Array([pa, ea, Vector2(ea.x, y_out), Vector2(eb.x, y_out), eb, pb])
	_routes[key] = out
	return out


func _water_path(from: Vector2, to: Vector2) -> Array:
	var n := int(ceil(float(sim.city.size) / GRID))
	if _astar == null:
		_astar = AStarGrid2D.new()
		_astar.region = Rect2i(0, 0, n, n)
		_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		_astar.update()
		for gy in n:
			for gx in n:
				var all_water := true
				for dy in GRID:
					for dx in GRID:
						var c := Vector2i(gx * GRID + dx, gy * GRID + dy)
						if not sim.city.inside(c) or sim.city.g(c) != CityData.G.WATER:
							all_water = false
				_astar.set_point_solid(Vector2i(gx, gy), not all_water)
	var s := _nearest_free(Vector2i(from / 32.0 / GRID), n)
	var e := _nearest_free(Vector2i(to / 32.0 / GRID), n)
	if s.x < 0 or e.x < 0:
		return []
	return _astar.get_id_path(s, e)


func _nearest_free(c: Vector2i, n: int) -> Vector2i:
	for r in 6:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var q := c + Vector2i(dx, dy)
				if q.x >= 0 and q.y >= 0 and q.x < n and q.y < n and not _astar.is_point_solid(q):
					return q
	return Vector2i(-1, -1)


## Position und Kurs bei Anteil t (0..1) entlang eines Polygonzugs; Kurs geglaettet ueber ein Stueck vor und hinter dem Schiff.
func _along(path: PackedVector2Array, t: float) -> Dictionary:
	if path.size() < 2:
		return {"pos": path[0] if path.size() == 1 else Vector2.ZERO, "heading": 0.0}
	var total := 0.0
	for i in path.size() - 1:
		total += path[i].distance_to(path[i + 1])
	var d := t * total
	var pos := _at(path, d)
	var ahead := _at(path, minf(total, d + 48.0))
	var behind := _at(path, maxf(0.0, d - 48.0))
	var dir := ahead - behind
	return {"pos": pos, "heading": dir.angle() if dir.length() > 0.1 else (path[path.size() - 1] - path[path.size() - 2]).angle()}


func _at(path: PackedVector2Array, d: float) -> Vector2:
	for i in path.size() - 1:
		var seg := path[i].distance_to(path[i + 1])
		if d <= seg:
			return path[i].lerp(path[i + 1], d / maxf(seg, 0.001))
		d -= seg
	return path[path.size() - 1]


func _ease(k: float) -> float:
	return k * k * (3.0 - 2.0 * k)


class JettyNode extends Node2D:
	var from_x := 0.0
	var to_x := 0.0
	var y := 0.0
	const PLANK := Color("8a6a45")
	const PLANK_DARK := Color("5e4630")
	const POST := Color("3f2f22")

	func _s(wx: float, wy: float, z: float = 0.0) -> Vector2:
		return Iso.to_screen(Vector2(wx, wy) * 32.0) - position + Vector2(0, -z * ShipView.STEP)

	func _draw() -> void:
		var z := 0.6
		for i in int(to_x - from_x) + 1:   # Pfaehle
			var px := from_x + float(i)
			for py in [y + 0.1, y + 0.9]:
				draw_line(_s(px, py, -0.4), _s(px, py, z), POST, 5.0)
		draw_colored_polygon(PackedVector2Array([_s(from_x, y + 1.0, z - 0.2), _s(to_x, y + 1.0, z - 0.2), _s(to_x, y + 1.0, z), _s(from_x, y + 1.0, z)]), PLANK_DARK)
		draw_colored_polygon(PackedVector2Array([_s(from_x, y, z), _s(to_x, y, z), _s(to_x, y + 1.0, z), _s(from_x, y + 1.0, z)]), PLANK)
		var k := from_x + 0.5
		while k < to_x:   # Bohlenfugen
			draw_line(_s(k, y, z), _s(k, y + 1.0, z), PLANK_DARK, 1.5)
			k += 0.5
		for px in [from_x + 2.0, from_x + 5.0, to_x - 0.5]:   # Poller
			draw_line(_s(px, y + 0.85, z), _s(px, y + 0.85, z + 0.5), Color("2a2a2a"), 6.0)


## Ein Schiff, prozedural in Isometrie: Rumpf als Prisma ueber dem Grundriss (Bug spitz, Heck stumpf), sichtbare Seiten per
## Normalen-Test gegen die Blickrichtung (+x,+y), Aufbauten als gedrehte Quader nach Tiefe sortiert. Lokale Koordinaten in Feldern:
## x entlang des Schiffs (Bug bei +x), y quer, z in Hoehenstufen ueber der Wasserlinie.
class ShipNode extends Node2D:
	var world := Vector2.ZERO
	var heading := 0.0
	var kind := "container"
	var label := ""
	var cargo := 0
	var wake := 0.0
	var night := false
	const VIEW := Vector2(0.70710678, 0.70710678)
	const BOOT := Color("9b2f2a")
	const BOXES := [Color("c8553d"), Color("3d7cc8"), Color("e0a83a"), Color("4f9a5b"), Color("8a5bb5"), Color("d9d4c7")]
	const SPEC := {
		"container": {"len": 7.0, "beam": 1.9, "bow": 1.4, "h": 1.5, "hull": "1f3a5f", "deck": "6b6f73", "band": ""},
		"schuettgut": {"len": 7.0, "beam": 1.9, "bow": 1.3, "h": 1.6, "hull": "5b2420", "deck": "55534f", "band": "1e1e1e"},
		"kreuzfahrt": {"len": 8.6, "beam": 2.1, "bow": 1.9, "h": 1.8, "hull": "f2f3f5", "deck": "c9b48c", "band": "1d2f5e"},
		"autotransporter": {"len": 7.8, "beam": 2.0, "bow": 0.8, "h": 4.2, "hull": "e3e3e0", "deck": "9c9c98", "band": "8c1c1c"},
	}

	func _w(dx: float, dy: float) -> Vector2:
		return world + Vector2(dx, dy).rotated(heading) * 32.0

	func _p(dx: float, dy: float, z: float) -> Vector2:
		return Iso.to_screen(_w(dx, dy)) - Iso.to_screen(world) + Vector2(0, -z * ShipView.STEP)

	## Seitenflaeche zwischen zwei Grundrisspunkten (lokal) von z0 bis z1, nur wenn sie zum Betrachter zeigt.
	func _side(a: Vector2, b: Vector2, center: Vector2, z0: float, z1: float, col: Color) -> bool:
		var wa := _w(a.x, a.y)
		var wb := _w(b.x, b.y)
		var e := wb - wa
		var n := Vector2(e.y, -e.x)
		if n.dot((wa + wb) * 0.5 - _w(center.x, center.y)) < 0.0:
			n = -n
		if n.dot(VIEW) <= 0.0:
			return false
		var shade := 0.82 + 0.18 * clampf(n.normalized().dot(Vector2(1, 0)), -1.0, 1.0)   # Licht von Osten etwas heller
		draw_colored_polygon(PackedVector2Array([_p(a.x, a.y, z0), _p(b.x, b.y, z0), _p(b.x, b.y, z1), _p(a.x, a.y, z1)]), col * Color(shade, shade, shade, 1.0))
		return true

	func _prism(outline: Array, z0: float, z1: float, side: Color, top: Color, bands: Array = []) -> void:
		var c := Vector2.ZERO
		for p in outline:
			c += p
		c /= float(outline.size())
		for i in outline.size():
			var a: Vector2 = outline[i]
			var b: Vector2 = outline[(i + 1) % outline.size()]
			if _side(a, b, c, z0, z1, side):
				for band in bands:   # farbige Streifen (Wasserlinie, Zierband): [z0, z1, Farbe]
					_side(a, b, c, maxf(z0, band[0]), minf(z1, band[1]), band[2])
		var pts := PackedVector2Array()
		for p in outline:
			pts.append(_p(p.x, p.y, z1))
		draw_colored_polygon(pts, top)

	func _box(x0: float, y0: float, x1: float, y1: float, z0: float, z1: float, col: Color, top: Color = Color(0, 0, 0, 0)) -> void:
		_prism([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)], z0, z1, col, top if top.a > 0.0 else col.lightened(0.12))

	## Fensterreihe auf den sichtbaren Laengsseiten eines Aufbaus (Punkte entlang x bei Hoehe z).
	func _windows(x0: float, x1: float, y_abs: float, z: float, step: float, col: Color) -> void:
		for sgn in [-1.0, 1.0]:
			var y: float = y_abs * sgn
			var n: Vector2 = Vector2(0, sgn).rotated(heading)
			if n.dot(VIEW) <= 0.0:
				continue
			var x := x0 + step * 0.5
			while x < x1:
				draw_line(_p(x - step * 0.22, y, z), _p(x + step * 0.22, y, z), col, 2.5)
				x += step

	func _hull_outline(l: float, b: float, bow: float, round_stern: bool) -> Array:
		var pts := [Vector2(l, 0.0), Vector2(l - bow, b), Vector2(l - bow * 2.2, b)]
		if round_stern:
			pts += [Vector2(-l + 0.5, b), Vector2(-l, b * 0.55), Vector2(-l, -b * 0.55), Vector2(-l + 0.5, -b)]
		else:
			pts += [Vector2(-l, b * 0.92), Vector2(-l, -b * 0.92)]
		pts += [Vector2(l - bow * 2.2, -b), Vector2(l - bow, -b)]
		return pts

	func _draw() -> void:
		var sp: Dictionary = SPEC.get(kind, SPEC.container)
		var l := float(sp.len) * 0.5
		var b := float(sp.beam) * 0.5
		var h := float(sp.h)
		var hull := Color(str(sp.hull))
		var lit := Color("ffd76a") if night else Color("2c3e52")
		# Kielwasser am Heck
		if wake > 0.05:
			for i in 5:
				var a := Color(1, 1, 1, 0.38 * wake * (1.0 - i * 0.18))
				draw_line(_p(-l - 0.3 - i * 1.1, -b * 0.6 - i * 0.25, 0.0), _p(-l - 1.2 - i * 1.1, -b * 1.1 - i * 0.35, 0.0), a, 3.0)
				draw_line(_p(-l - 0.3 - i * 1.1, b * 0.6 + i * 0.25, 0.0), _p(-l - 1.2 - i * 1.1, b * 1.1 + i * 0.35, 0.0), a, 3.0)
			draw_line(_p(l + 0.1, -0.3, 0.0), _p(l - 0.8, -b - 0.4, 0.0), Color(1, 1, 1, 0.5 * wake), 2.5)   # Bugwelle
			draw_line(_p(l + 0.1, 0.3, 0.0), _p(l - 0.8, b + 0.4, 0.0), Color(1, 1, 1, 0.5 * wake), 2.5)
		var outline := _hull_outline(l, b, float(sp.bow), kind == "kreuzfahrt")
		var bands: Array = [[0.0, 0.28, BOOT]]
		if str(sp.band) != "":
			bands.append([0.28, 0.62 if kind != "autotransporter" else 1.3, Color(str(sp.band))])
		_prism(outline, 0.0, h, hull, Color(str(sp.deck)), bands)
		match kind:
			"container":
				_draw_container(l, b, h, lit)
			"schuettgut":
				_draw_bulk(l, b, h, lit)
			"kreuzfahrt":
				_draw_cruise(l, b, h, lit)
			"autotransporter":
				_draw_carrier(l, b, h, lit)
		if label != "":
			draw_string(ThemeDB.fallback_font, _p(-l * 0.5, 0.0, h + 4.2) + Vector2(-40, 0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.92))

	## Containerschiff: Bruecke achtern, Containerstapel in Reihen, Hoehe nach Ladung.
	func _draw_container(l: float, b: float, h: float, lit: Color) -> void:
		var tiers := clampi(cargo, 1, 3)
		var boxes: Array = []
		var x := -l + 2.0
		var i := 0
		while x + 0.85 < l - 1.4:
			for row in 2:
				var y0: float = -b + 0.2 + row * (b - 0.2)
				var stack: int = tiers - (1 if (i + row) % 4 == 3 else 0)
				for t in maxi(1, stack):
					boxes.append([x, y0, x + 0.82, y0 + b - 0.25, h + t * 0.62, h + (t + 1) * 0.62, BOXES[(i * 3 + row * 2 + t) % BOXES.size()]])
			x += 0.92
			i += 1
		var stern_far := _w(-l, 0.0).dot(VIEW) < _w(l, 0.0).dot(VIEW)   # Bruecke hinten: zuerst zeichnen
		if not stern_far:
			_draw_boxes(boxes)
		_bridge(-l + 0.3, -l + 1.5, b, h, 2.8, lit, Color("e8e4da"))
		_box(-l + 0.7, -0.18, -l + 1.05, 0.18, h + 2.8, h + 3.8, Color("a33b32"))   # Schornstein
		if stern_far:
			_draw_boxes(boxes)

	## Schuettgutfrachter: grosse Ladeluken, Bordkraene, Bruecke achtern.
	func _draw_bulk(l: float, b: float, h: float, lit: Color) -> void:
		var boxes: Array = []
		var x := -l + 2.1
		while x + 1.1 < l - 1.3:
			boxes.append([x, -b + 0.3, x + 1.1, b - 0.3, h, h + 0.22, Color("3f6b3a")])
			x += 1.45
		var stern_far := _w(-l, 0.0).dot(VIEW) < _w(l, 0.0).dot(VIEW)
		if stern_far:
			_bridge(-l + 0.3, -l + 1.7, b, h, 1.8, lit, Color("e8e4da"))
			_box(-l + 0.7, -0.18, -l + 1.05, 0.18, h + 1.8, h + 2.6, Color("1e1e1e"))
		_draw_boxes(boxes)
		for cx in [-l + 3.35, -l + 6.25]:   # Kraene zwischen den Luken: Mast und Ausleger
			_box(cx - 0.1, -0.1, cx + 0.1, 0.1, h, h + 2.2, Color("d9a32c"))
			draw_line(_p(cx, 0.0, h + 2.1), _p(cx + 1.2, b * 0.6, h + 1.0), Color("d9a32c"), 2.5)
		if not stern_far:
			_bridge(-l + 0.3, -l + 1.7, b, h, 1.8, lit, Color("e8e4da"))
			_box(-l + 0.7, -0.18, -l + 1.05, 0.18, h + 1.8, h + 2.6, Color("1e1e1e"))

	## Kreuzfahrtschiff: drei gestaffelte Decks mit Fensterreihen, Rettungsboote, blauer Schornstein, Pool.
	func _draw_cruise(l: float, b: float, h: float, lit: Color) -> void:
		var white := Color("f4f5f7")
		var teak := Color("ddd5c2")
		var win := lit if night else Color("2f557f")
		var decks := [[-l + 0.5, l - 1.5, 0.0, 1.3], [-l + 0.9, l - 2.2, 1.3, 2.5], [-l + 1.5, l - 3.0, 2.5, 3.5]]
		for d in decks:
			_box(d[0], -b + 0.12, d[1], b - 0.12, h + d[2], h + d[3], white, teak)
			_windows(d[0] + 0.2, d[1] - 0.1, b - 0.12, h + d[2] + 0.5, 0.3, win)
		_windows(-l + 1.0, l - 2.6, b, h - 0.35, 0.45, win)   # Bullaugen im Rumpf
		for bx in [-l + 1.6, -l + 2.6, -l + 3.6, -l + 4.6]:   # Rettungsboote an der Bordwand (in den Davits)
			for sgn in [-1.0, 1.0]:
				var y: float = sgn * (b + 0.05)
				_box(bx, y - 0.16, bx + 0.6, y + 0.16, h + 0.6, h + 1.0, Color("f28c28"), Color("ffb066"))
		_box(-l + 2.3, -0.3, -l + 2.9, 0.3, h + 3.5, h + 3.56, Color("3fa7d6"))   # Pool auf dem Sonnendeck
		_box(-l + 1.0, -0.32, -l + 1.8, 0.32, h + 3.5, h + 5.0, Color("1d4e8f"))   # Schornstein mit weissem Band
		_box(-l + 1.0, -0.33, -l + 1.8, 0.33, h + 4.3, h + 4.55, white)
		draw_line(_p(l - 2.8, 0.0, h + 3.5), _p(l - 2.8, 0.0, h + 5.4), Color("cfcfcf"), 2.0)   # Mast

	## Autotransporter: hoher kastenfoermiger Rumpf (schon im Prisma), Bruecke vorn oben, Fensterpunkte, Heckrampe.
	func _draw_carrier(l: float, b: float, h: float, lit: Color) -> void:
		# Zierstreifen und Reederei-Schriftzug unter der Oberkante, Fensterpunkte der Ladedecks
		var c := Vector2(0.0, 0.0)
		var outline := _hull_outline(l, b, 0.8, false)
		for i in outline.size():
			_side(outline[i], outline[(i + 1) % outline.size()], c, h - 0.75, h - 0.45, Color("1d3d6b"))
		_windows(-l + 0.6, l - 2.4, b, h - 1.4, 0.7, Color("8a8a86") if not night else lit)
		for vx in [-l + 1.6, -l + 3.0, -l + 4.4]:   # Lueftungsaufbauten auf dem Wetterdeck
			_box(vx, -b + 0.3, vx + 0.5, -b + 0.7, h, h + 0.35, Color("bdbdb8"))
			_box(vx, b - 0.7, vx + 0.5, b - 0.3, h, h + 0.35, Color("bdbdb8"))
		_box(l - 2.0, -b + 0.1, l - 0.9, b - 0.1, h, h + 0.9, Color("f0f0ee"))   # Bruecke vorn
		_windows(l - 2.0, l - 0.9, b - 0.1, h + 0.55, 0.22, lit if night else Color("2c3e52"))
		_box(-l + 0.6, -0.22, -l + 1.1, 0.22, h, h + 1.0, Color("8c1c1c"))   # Schornstein
		draw_line(_p(-l, -b * 0.7, 0.2), _p(-l, b * 0.7, 0.2), Color("3a3a38"), 3.0)   # Heckrampe

	func _bridge(x0: float, x1: float, b: float, h: float, height: float, lit: Color, col: Color) -> void:
		_box(x0, -b + 0.15, x1, b - 0.15, h, h + height, col)
		_windows(x0, x1, b - 0.15, h + height - 0.35, 0.28, lit if night else Color("2c3e52"))
		_box(x0 - 0.05, -b - 0.05, x0 + 0.5, b + 0.05, h + height, h + height + 0.08, col.darkened(0.1))   # Nock

	## Quader nach Tiefe sortiert (hinten zuerst): Tiefe = Weltposition entlang der Blickrichtung, dann Hoehe.
	func _draw_boxes(boxes: Array) -> void:
		boxes.sort_custom(func(p, q):
			var dp := _w((float(p[0]) + float(p[2])) * 0.5, (float(p[1]) + float(p[3])) * 0.5).dot(VIEW)
			var dq := _w((float(q[0]) + float(q[2])) * 0.5, (float(q[1]) + float(q[3])) * 0.5).dot(VIEW)
			return dp < dq - 0.5 or (absf(dp - dq) <= 0.5 and float(p[4]) < float(q[4])))
		for bx in boxes:
			var c: Color = bx[6]
			_box(bx[0], bx[1], bx[2], bx[3], bx[4], bx[5], c, c.lightened(0.18))
