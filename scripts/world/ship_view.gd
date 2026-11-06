class_name ShipView
extends Node2D
## Linienschiff sichtbar (Harbor, Auftrag 15 Etappe C): faehrt am Ankunftstag vom Kartenrand an den Kai, liegt dort mit Ladung
## (Container je geloeschter/geladener Warengruppe) und legt am Folgetag wieder ab. Liest nur aus der Simulation; prozedural gezeichnet.

const SAIL_MIN := 40.0            # Spielminuten fuer An- und Abfahrt
const LEN := 7.0                  # Laenge in Feldern (entlang x)
const BEAM := 2.0                 # Breite in Feldern
const STEP := 18.0                # Bildschirmhoehe je Hoehenstufe

var sim: Simulation
var berth := Vector2.ZERO         # Liegeplatz (Weltpixel, Schiffsmitte)
var edge := Vector2.ZERO          # Einfahrt am Kartenrand
var _ship: ShipNode


func setup(simulation: Simulation) -> void:
	sim = simulation
	if not sim.harbor.enabled:
		return
	var port := {}
	for b in sim.city.buildings:
		if b.type == "port_office":
			port = b
	if port.is_empty():
		port = sim.city.building(sim.harbor.building)
	var y: int = int(port.road.y) + 3
	var x: int = int(port.road.x)
	while x < sim.city.size - 1 and sim.city.g(Vector2i(x, y)) != CityData.G.WATER:
		x += 1
	berth = Vector2(float(x) + LEN * 0.5 + 0.4, float(y) + BEAM * 0.5 + 0.15) * 32.0
	edge = Vector2(float(sim.city.size) + LEN, float(y) + BEAM * 0.5 + 0.15) * 32.0
	var jetty := JettyNode.new()   # Holzanleger vom Ufer ins Wasser, das Schiff liegt suedlich laengsseits
	jetty.from_x = float(x) - 1.0
	jetty.to_x = float(x) + LEN + 1.0
	jetty.y = float(y) - 1.0
	jetty.position = Iso.to_screen(Vector2((jetty.from_x + jetty.to_x) * 0.5, jetty.y + 0.5) * 32.0)
	add_child(jetty)
	_ship = ShipNode.new()
	_ship.visible = false
	add_child(_ship)


func update_view(_delta: float) -> void:
	if _ship == null:
		return
	var sh: Dictionary = sim.harbor.ship
	if sh.is_empty():
		_ship.visible = false
		return
	var now: float = sim.game_min
	var docked_at := GameCalendar.day_start(int(sh.day))
	var pos := berth
	var moving := 0.0
	if sh.status == "am_kai":
		var k := clampf((now - docked_at) / SAIL_MIN, 0.0, 1.0)
		pos = edge.lerp(berth, _ease(k))
		moving = 1.0 - k
	else:
		var k2 := clampf((now - GameCalendar.day_start(int(sh.day) + 1)) / SAIL_MIN, 0.0, 1.0)
		if k2 >= 1.0:
			_ship.visible = false
			return
		pos = berth.lerp(edge, _ease(k2))
		moving = 1.0 - absf(k2 - 0.5) * 2.0
	_ship.visible = true
	_ship.position = Iso.to_screen(pos)
	_ship.world = pos
	_ship.label = str(sh.name)
	_ship.cargo = maxi(int(sh.get("geloescht", {}).size()), int(sh.get("geladen", {}).size())) if sh.status == "am_kai" else int(sh.get("geladen", {}).size())
	_ship.wake = moving
	_ship.queue_redraw()


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


class ShipNode extends Node2D:
	var world := Vector2.ZERO
	var label := ""
	var cargo := 0
	var wake := 0.0
	const HULL := Color("2f4a6b")
	const HULL_DARK := Color("22374f")
	const DECK := Color("b9a27a")
	const RED := Color("a33b32")
	const WHITE := Color("e8e4da")
	const BOXES := [Color("c8553d"), Color("3d7cc8"), Color("e0a83a"), Color("4f9a5b")]

	func _s(dx: float, dy: float, z: float = 0.0) -> Vector2:
		return Iso.to_screen(world + Vector2(dx, dy) * 32.0) - Iso.to_screen(world) + Vector2(0, -z * ShipView.STEP)

	## Quader von (x0, y0) bis (x1, y1) in Feldern relativ zur Schiffsmitte, Hoehe z0..z1; sichtbare Seiten Sued und Ost.
	func _box(x0: float, y0: float, x1: float, y1: float, z0: float, z1: float, top: Color, side: Color, front: Color) -> void:
		draw_colored_polygon(PackedVector2Array([_s(x0, y1, z0), _s(x1, y1, z0), _s(x1, y1, z1), _s(x0, y1, z1)]), side)
		draw_colored_polygon(PackedVector2Array([_s(x1, y0, z0), _s(x1, y1, z0), _s(x1, y1, z1), _s(x1, y0, z1)]), front)
		draw_colored_polygon(PackedVector2Array([_s(x0, y0, z1), _s(x1, y0, z1), _s(x1, y1, z1), _s(x0, y1, z1)]), top)

	func _draw() -> void:
		var l := ShipView.LEN * 0.5
		var b := ShipView.BEAM * 0.5
		# Kielwasser hinter dem Heck (Fahrt nach Westen: Heck liegt im Osten)
		if wake > 0.05:
			for i in 4:
				var a := Color(1, 1, 1, 0.35 * wake * (1.0 - i * 0.22))
				draw_line(_s(l + 0.5 + i * 1.2, -b * 0.8), _s(l + 1.4 + i * 1.2, -b * 1.4 - i * 0.3), a, 3.0)
				draw_line(_s(l + 0.5 + i * 1.2, b * 0.8), _s(l + 1.4 + i * 1.2, b * 1.4 + i * 0.3), a, 3.0)
		# Rumpf mit spitzem Bug im Westen
		draw_colored_polygon(PackedVector2Array([_s(-l, 0, 0.2), _s(-l + 1.2, b, 0), _s(l, b, 0), _s(l, b, 1.1), _s(-l + 1.2, b, 1.1), _s(-l, 0, 1.3)]), HULL)
		draw_colored_polygon(PackedVector2Array([_s(l, -b, 0), _s(l, b, 0), _s(l, b, 1.1), _s(l, -b, 1.1)]), HULL_DARK)
		draw_colored_polygon(PackedVector2Array([_s(-l, 0, 1.3), _s(-l + 1.2, -b, 1.1), _s(l, -b, 1.1), _s(l, b, 1.1), _s(-l + 1.2, b, 1.1)]), DECK)
		draw_line(_s(-l + 1.2, b, 0.15), _s(l, b, 0.15), RED, 3.0)   # Wasserlinie
		# Ladung: Containerreihen mittschiffs
		for i in mini(cargo, 4):
			var x0 := -l + 1.5 + i * 0.95
			var c: Color = BOXES[i % BOXES.size()]
			_box(x0, -b + 0.25, x0 + 0.85, b - 0.25, 1.1, 1.9, c.lightened(0.15), c, c.darkened(0.25))
		# Bruecke am Heck mit Schornstein
		_box(l - 1.6, -b + 0.2, l - 0.3, b - 0.2, 1.1, 2.9, WHITE, WHITE.darkened(0.12), WHITE.darkened(0.25))
		_box(l - 1.5, -b + 0.25, l - 0.4, b - 0.25, 2.3, 2.55, Color("4c6a86"), Color("2c3e52"), Color("22303f"))   # Fensterband
		_box(l - 1.05, -0.2, l - 0.7, 0.2, 2.9, 3.8, RED, RED.darkened(0.15), RED.darkened(0.3))
		draw_string(ThemeDB.fallback_font, _s(-l * 0.4, b, 4.4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, 0.9))
