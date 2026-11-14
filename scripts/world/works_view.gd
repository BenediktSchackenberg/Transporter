class_name WorksView
extends Node2D
## Auftrag 24: Fahrzeugwerk als Querschnitt (vordere Waende aufgeschnitten): Backsteinhalle mit hohen Sprossenfenstern und vier
## Schornsteinen, Konstruktionsbuero auf der Empore, Montageband mit vier Stationen (Karosseriebau mit Schweissrobotern, Lackierkabine,
## Montage, Lichttunnel der Endkontrolle), Hallenkran, Werkshof mit fertigen Fahrzeugen und verglastes Autohaus. Die Fahrzeuge auf dem
## Band sind die echten Einheiten aus VehicleWorks.line in Farbe und Form ihres Entwurfs. An den Stadtwerkstaetten arbeitet ein
## Mechaniker, solange ein Fahrzeug gewartet wird. Liest nur aus Simulation.vworks und Municipal.

var sim: Simulation
var _nodes := {}     # Einrichtungs-ID -> Node2D
var _t := 0.0


func setup(simulation: Simulation) -> void:
	sim = simulation
	y_sort_enabled = true


func update_view(delta: float) -> void:
	_t += delta
	for n in _nodes.values():
		n.t += delta
		n.queue_redraw()
	if _t < 1.0:
		return
	_t = 0.0
	var seen := {}
	for f in sim.municipal.facilities.values():
		if f.status != "in_betrieb" or str(f.code) not in ["FZ-01", "KW-01", "KW-02"]:
			continue
		seen[f.id] = true
		if _nodes.has(f.id):
			continue
		var b: Dictionary = sim.city.building(int(f.building))
		if b.is_empty():
			continue
		var n = PlantNode.new() if str(f.code) == "FZ-01" else ShopNode.new()
		n.sim = sim
		n.fid = str(f.id)
		n.rect = Rect2i(int(b.x), int(b.y), int(b.w), int(b.h))
		n.road = Vector2i(b.road)
		n.origin = Vector2(n.rect.end) * 32.0
		n.position = Iso.to_screen(n.origin)
		add_child(n)
		_nodes[f.id] = n
	for id in _nodes.keys():
		if not seen.has(id):
			_nodes[id].queue_free()
			_nodes.erase(id)


## Gemeinsame Zeichenhilfen: Feldkoordinaten relativ zur Grundstuecksecke, Hoehe in Stufen zu 18 Bildpunkten (wie SiteView/CrewArt).
class WorksNode extends Node2D:
	var sim: Simulation
	var fid := ""
	var rect := Rect2i()
	var road := Vector2i.ZERO
	var origin := Vector2.ZERO
	var t := 0.0
	const Z := 18.0

	func _f(l: Vector2, z: float) -> Vector2:
		return Iso.to_screen((Vector2(rect.position) + l) * 32.0) - Iso.to_screen(origin) + Vector2(0, -z * Z)

	func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
		draw_colored_polygon(PackedVector2Array([_f(Vector2(a.x, a.y), a.z), _f(Vector2(b.x, b.y), b.z), _f(Vector2(c.x, c.y), c.z), _f(Vector2(d.x, d.y), d.z)]), col)

	func _line3(a: Vector3, b: Vector3, col: Color, w: float = 2.0) -> void:
		draw_line(_f(Vector2(a.x, a.y), a.z), _f(Vector2(b.x, b.y), b.z), col, w)

	func _box(x0: float, y0: float, x1: float, y1: float, z0: float, z1: float, col: Color) -> void:
		CrewArt.box(self, Callable(self, "_f"), x0, y0, x1, y1, z0, z1, col)

	func _text(p: Vector2, s: String, size: int, col: Color, bg: Color = Color(0, 0, 0, 0)) -> void:
		var font := ThemeDB.fallback_font
		var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		if bg.a > 0.0:
			draw_rect(Rect2(p + Vector2(-w * 0.5 - 4, -size - 2), Vector2(w + 8, size + 6)), bg)
		draw_string(font, p + Vector2(-w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

	func _night() -> bool:
		var h := GameCalendar.hour_of(sim.game_min)
		return h < 6.0 or h >= 21.0

	## Fahrzeug entlang +x mit Mitte c (Felder), Bauzustand stage 0 Rohbau, 1 lackiert, 2 mit Raedern, 3 fertig (Scheiben, Licht).
	func _vehicle(c: Vector2, d: Dictionary, stage: int, z0: float, sc: float = 1.0) -> void:
		var klasse := str(d.get("klasse", "pkw"))
		var form := str(d.get("form", "kantig"))
		var body := Color("a9adb2") if stage == 0 else Color(str(d.get("farbe", "c8322b")))
		var acc := Color(str(d.get("akzent", "eeeeea")))
		var glass := Color("9cc4dc") if stage >= 3 else Color("3a3d42")
		var Ls := {"pkw": 0.62, "transporter": 0.8, "lkw": 0.95, "sattelzug": 1.15}
		var L := float(Ls.get(klasse, 0.7)) * sc
		var W := (0.3 if klasse == "pkw" else 0.36) * sc
		var x0 := c.x - L * 0.5
		var x1 := c.x + L * 0.5
		var y0 := c.y - W * 0.5
		var y1 := c.y + W * 0.5
		draw_colored_polygon(PackedVector2Array([_f(Vector2(x0, y0), z0), _f(Vector2(x1, y0), z0), _f(Vector2(x1, y1), z0), _f(Vector2(x0, y1), z0)]), Color(0, 0, 0, 0.25))
		var zb := z0 + (0.12 if stage >= 2 else 0.04) * sc
		match klasse:
			"pkw":
				var hood := (0.3 if form == "keil" else 0.36) * sc
				_box(x0, y0, x1, y1, zb, zb + hood, body)
				var cx0 := c.x - (0.2 if form == "keil" else 0.13) * sc
				var cx1 := c.x + (0.06 if form == "keil" else (0.12 if form == "rund" else 0.16)) * sc
				var inset := (0.04 if form == "rund" else 0.02) * sc
				var top := zb + hood + (0.26 if form == "keil" else (0.3 if form == "rund" else 0.34)) * sc
				_box(cx0, y0 + inset, cx1, y1 - inset, zb + hood, top, body.lightened(0.04))
				if form == "rund":
					_box(cx0 + 0.03 * sc, y0 + inset * 2.0, cx1 - 0.03 * sc, y1 - inset * 2.0, top, top + 0.05 * sc, body.lightened(0.08))
				_quad(Vector3(cx0 + 0.03 * sc, y1 - inset, zb + hood + 0.04 * sc), Vector3(cx1 - 0.03 * sc, y1 - inset, zb + hood + 0.04 * sc),
					Vector3(cx1 - 0.03 * sc, y1 - inset, top - 0.04 * sc), Vector3(cx0 + 0.03 * sc, y1 - inset, top - 0.04 * sc), glass)
				_quad(Vector3(cx1, y0 + inset + 0.03 * sc, zb + hood + 0.03 * sc), Vector3(cx1, y1 - inset - 0.03 * sc, zb + hood + 0.03 * sc),
					Vector3(cx1, y1 - inset - 0.03 * sc, top - 0.04 * sc), Vector3(cx1, y0 + inset + 0.03 * sc, top - 0.04 * sc), glass.darkened(0.1))
				if stage >= 1:
					_quad(Vector3(x0, y1, zb + hood * 0.45), Vector3(x1, y1, zb + hood * 0.45), Vector3(x1, y1, zb + hood * 0.6), Vector3(x0, y1, zb + hood * 0.6), acc)
			"transporter":
				var h := (0.9 if form == "kantig" else 0.82) * sc
				_box(x0, y0, x1 - 0.12 * sc, y1, zb, zb + h, body)
				var nose := 0.45 * sc if form != "keil" else 0.38 * sc
				_box(x1 - 0.12 * sc, y0, x1, y1, zb, zb + nose, body.darkened(0.03))
				_quad(Vector3(x1 - 0.12 * sc, y0 + 0.03 * sc, zb + nose), Vector3(x1 - 0.12 * sc, y1 - 0.03 * sc, zb + nose),
					Vector3(x1 - 0.12 * sc, y1 - 0.03 * sc, zb + h - 0.05 * sc), Vector3(x1 - 0.12 * sc, y0 + 0.03 * sc, zb + h - 0.05 * sc), glass)
				_quad(Vector3(x1 - 0.32 * sc, y1, zb + nose + 0.02 * sc), Vector3(x1 - 0.14 * sc, y1, zb + nose + 0.02 * sc),
					Vector3(x1 - 0.14 * sc, y1, zb + h - 0.08 * sc), Vector3(x1 - 0.32 * sc, y1, zb + h - 0.08 * sc), glass)
				if stage >= 1:
					_quad(Vector3(x0, y1, zb + h * 0.35), Vector3(x1 - 0.34 * sc, y1, zb + h * 0.35), Vector3(x1 - 0.34 * sc, y1, zb + h * 0.47), Vector3(x0, y1, zb + h * 0.47), acc)
			_:
				var cab := 0.26 * sc
				var ch := (1.0 if form == "kantig" else 0.92) * sc
				var bx1 := x1 - cab - 0.03 * sc
				var boxc := acc if stage >= 1 else body
				_box(x0, y0, bx1, y1, zb + 0.14 * sc, zb + (1.2 if klasse == "lkw" else 1.25) * sc, boxc)
				if klasse == "sattelzug":
					_box(bx1 - 0.08 * sc, y0 + 0.08 * sc, bx1 + 0.03 * sc, y1 - 0.08 * sc, zb, zb + 0.16 * sc, Color("3a3d42"))
				if stage >= 1:
					_quad(Vector3(x0 + 0.04 * sc, y1, zb + 0.5 * sc), Vector3(bx1 - 0.04 * sc, y1, zb + 0.5 * sc), Vector3(bx1 - 0.04 * sc, y1, zb + 0.62 * sc), Vector3(x0 + 0.04 * sc, y1, zb + 0.62 * sc), body)
				_box(x1 - cab, y0, x1, y1, zb, zb + ch, body)
				if form == "keil":
					_box(x1 - cab, y0 + 0.02 * sc, x1 - 0.06 * sc, y1 - 0.02 * sc, zb + ch, zb + ch + 0.12 * sc, body.lightened(0.1))   # Windleitblech
				_quad(Vector3(x1, y0 + 0.03 * sc, zb + ch * 0.55), Vector3(x1, y1 - 0.03 * sc, zb + ch * 0.55), Vector3(x1, y1 - 0.03 * sc, zb + ch - 0.06 * sc), Vector3(x1, y0 + 0.03 * sc, zb + ch - 0.06 * sc), glass)
				_quad(Vector3(x1 - cab + 0.03 * sc, y1, zb + ch * 0.55), Vector3(x1 - 0.04 * sc, y1, zb + ch * 0.55), Vector3(x1 - 0.04 * sc, y1, zb + ch - 0.06 * sc), Vector3(x1 - cab + 0.03 * sc, y1, zb + ch - 0.06 * sc), glass)
		if stage >= 2:
			var n := 2 if klasse in ["pkw", "transporter"] else 3
			for i in n:
				var wx := x0 + 0.12 * sc + (L - 0.24 * sc) * float(i) / float(n - 1)
				var p := _f(Vector2(wx, y1), z0 + 0.1 * sc)
				draw_circle(p, 4.0 * sc, Color("1e2023"))
				draw_circle(p, 1.8 * sc, Color("b8bcc2"))
		if stage >= 3:
			draw_circle(_f(Vector2(x1, y1 - 0.05 * sc), zb + 0.2 * sc), 1.8 * sc, Color("fff6c8"))


## Fahrzeugwerk (5 x 4 Felder): Halle hinten (y 0..HH), Werkshof und Autohaus vorne.
class PlantNode extends WorksNode:
	const W := 5.0
	const HH := 2.7          # Hallentiefe
	const HZ := 4.2          # Traufhoehe
	const BRICK := Color("a5492f")
	const BRICK_IN := Color("8d3f2a")
	const MORTAR := Color("6f3020")
	const CUT := Color("e2c09a")
	const FLOOR := Color("bdb8ac")
	const ROBOT := Color("e07a2a")
	const OVERALL := Color("2f5fb3")
	const STATIONS := [0.3, 1.37, 2.15, 3.7, 4.4]   # Grenzen Karosserie | Lack | Montage | Endkontrolle

	func _draw() -> void:
		var vw = sim.vworks
		var f: Dictionary = sim.municipal.facilities.get(fid, {})
		if vw == null or f.is_empty():
			return
		var night := _night()
		var h := GameCalendar.hour_of(sim.game_min)
		var shift: bool = h >= VehicleWorks.SHIFT[0] and h < VehicleWorks.SHIFT[1]
		var monteure: int = sim.municipal.staff_count(fid, "monteur")
		# Boden: Hof und Hallenboden
		_quad(Vector3(0, 0, 0), Vector3(W, 0, 0), Vector3(W, 4, 0), Vector3(0, 4, 0), Color("6b6e72"))
		_quad(Vector3(0, 0, 0.01), Vector3(W, 0, 0.01), Vector3(W, HH, 0.01), Vector3(0, HH, 0.01), FLOOR)
		for i in 9:   # Fugen im Hallenboden
			var x := 0.5 * float(i + 1)
			_line3(Vector3(x, 0, 0.02), Vector3(x, HH, 0.02), FLOOR.darkened(0.08), 1.0)
		# Rueckwaende (Innenseiten) mit Sprossenfenstern
		_quad(Vector3(0, 0, 0), Vector3(W, 0, 0), Vector3(W, 0, HZ), Vector3(0, 0, HZ), BRICK_IN)
		_quad(Vector3(0, 0, 0), Vector3(0, HH, 0), Vector3(0, HH, HZ), Vector3(0, 0, HZ), BRICK_IN.darkened(0.12))
		for zz in range(1, 17):
			var z := 0.25 * float(zz)
			_line3(Vector3(0, 0.005, z), Vector3(W, 0.005, z), MORTAR, 1.0)
			_line3(Vector3(0.005, 0, z), Vector3(0.005, HH, z), MORTAR.darkened(0.1), 1.0)
		var glass := Color("f5d77a") if night and shift else (Color("2a3240") if night else Color("b9d2e2"))
		for i in 6:
			var x0 := 0.25 + 0.8 * float(i)
			_quad(Vector3(x0, 0.01, 1.0), Vector3(x0 + 0.42, 0.01, 1.0), Vector3(x0 + 0.42, 0.01, 3.7), Vector3(x0, 0.01, 3.7), glass)
			for k in 4:
				var z := 1.0 + 0.675 * float(k + 1)
				_line3(Vector3(x0, 0.012, z), Vector3(x0 + 0.42, 0.012, z), Color("3a3330"), 1.0)
			_line3(Vector3(x0 + 0.21, 0.012, 1.0), Vector3(x0 + 0.21, 0.012, 3.7), Color("3a3330"), 1.0)
		for i in 3:
			var y0 := 0.35 + 0.8 * float(i)
			_quad(Vector3(0.01, y0, 1.0), Vector3(0.01, y0 + 0.42, 1.0), Vector3(0.01, y0 + 0.42, 3.7), Vector3(0.01, y0, 3.7), glass.darkened(0.08))
		# Mauerkronen (Schnittkante)
		_quad(Vector3(0, -0.12, HZ), Vector3(W, -0.12, HZ), Vector3(W, 0, HZ), Vector3(0, 0, HZ), CUT)
		_quad(Vector3(-0.12, 0, HZ), Vector3(0, 0, HZ), Vector3(0, HH, HZ), Vector3(-0.12, HH, HZ), CUT)
		# Dachstreifen hinten mit Oberlichtern und die vier Schornsteine
		_box(0, 0, W, 0.9, HZ, HZ + 0.35, Color("4b5056"))
		for i in 5:
			var x := 0.3 + float(i)
			_quad(Vector3(x, 0.15, HZ + 0.36), Vector3(x + 0.5, 0.15, HZ + 0.36), Vector3(x + 0.5, 0.75, HZ + 0.36), Vector3(x, 0.75, HZ + 0.36), Color("8fb0c4"))
		for i in 4:
			var cx := 0.75 + 1.15 * float(i)
			_box(cx - 0.17, 0.25, cx + 0.17, 0.59, HZ + 0.35, 13.0, BRICK)
			_box(cx - 0.2, 0.22, cx + 0.2, 0.62, 12.6, 13.0, BRICK.lightened(0.15))
			for k in 4:   # Rauchfahne (Betrieb: dichter)
				var ph := fmod(t * 0.6 + float(k) * 0.25 + float(i) * 0.13, 1.0)
				var p := _f(Vector2(cx, 0.42), 13.2) + Vector2(18.0 * ph, -60.0 * ph)
				draw_circle(p, 5.0 + 12.0 * ph, Color(0.86, 0.86, 0.86, (0.4 if shift else 0.18) * (1.0 - ph)))
		# Empore mit Konstruktionsbuero
		_box(0.15, 0.08, 2.5, 0.75, 2.3, 2.45, Color("9a9a9a"))
		var dev := {}
		for d in vw.designs.values():
			if d.status == "entwicklung" or dev.is_empty():
				dev = d
		for i in 2:
			var bx := 0.55 + 1.0 * float(i)
			_quad(Vector3(bx, 0.25, 2.75), Vector3(bx + 0.5, 0.25, 2.75), Vector3(bx + 0.5, 0.5, 3.05), Vector3(bx, 0.5, 3.05), Color("f4f1e8"))
			if not dev.is_empty():   # Skizze des aktuellen Entwurfs
				var mid := (_f(Vector2(bx + 0.25, 0.37), 2.9))
				draw_rect(Rect2(mid + Vector2(-12, -4), Vector2(24, 7)), Color(str(dev.farbe)))
				draw_rect(Rect2(mid + Vector2(-5, -9), Vector2(11, 5)), Color(str(dev.farbe)).lightened(0.2))
				draw_circle(mid + Vector2(-7, 4), 2.0, Color("26282c"))
				draw_circle(mid + Vector2(7, 4), 2.0, Color("26282c"))
		var eng: int = sim.municipal.staff_count(fid, "ingenieur")
		var S2 := func(w: Vector2, z: float) -> Vector2: return _f(w, z + 2.45)
		for i in (mini(eng, 2) if shift else 0):
			CrewArt.worker(self, S2, Vector2(0.75 + 1.0 * float(i), 0.62), t + float(i), "messen", Color("f4f4f4"), Color("2f5fb3"), i + 3)
		_line3(Vector3(0.15, 0.75, 2.85), Vector3(2.5, 0.75, 2.85), Color("d0b030"), 2.0)
		for i in 6:
			var x := 0.2 + 0.45 * float(i)
			_line3(Vector3(x, 0.75, 2.45), Vector3(x, 0.75, 2.85), Color("d0b030"), 1.5)
		# Montageband mit Stationen
		var by := 1.8
		_box(STATIONS[0], by - 0.22, STATIONS[4], by + 0.22, 0.0, 0.28, Color("3a3d42"))
		var roll := fmod(t * (0.25 if shift and not vw.line.is_empty() else 0.0), 0.2)
		var rx := STATIONS[0] + roll
		while rx < STATIONS[4]:
			_line3(Vector3(rx, by - 0.21, 0.285), Vector3(rx, by + 0.21, 0.285), Color("5b6068"), 1.0)
			rx += 0.2
		for i in 4:
			_quad(Vector3(STATIONS[i], by + 0.24, 0.01), Vector3(STATIONS[i + 1] - 0.03, by + 0.24, 0.01), Vector3(STATIONS[i + 1] - 0.03, by + 0.3, 0.01), Vector3(STATIONS[i], by + 0.3, 0.01), Color("e8b830"))
		# Einheiten am Band (nach Station sortiert von hinten nach vorne gezeichnet)
		var units: Array = vw.line.duplicate()
		units.sort_custom(func(a, b): return float(a.done_h) / maxf(0.01, float(a.need_h)) < float(b.done_h) / maxf(0.01, float(b.need_h)))
		var at_station := [false, false, false, false]
		for u in units:
			var p := float(u.done_h) / maxf(0.01, float(u.need_h))
			var st := VehicleWorks.stage_of(u)
			at_station[st] = true
			var x := 0.42 + p * 3.85
			var d: Dictionary = vw.designs.get(str(u.design), {})
			_vehicle(Vector2(x, by), d, st, 0.28, 0.85)
			if st == 1:   # Lacknebel
				for k in 5:
					var q := _f(Vector2(x - 0.2 + 0.1 * float(k), by - 0.1), 0.7 + 0.2 * sin(t * 4.0 + float(k)))
					draw_circle(q, 6.0, Color(Color(str(d.get("farbe", "c8322b"))), 0.22))
		# Station 1: Schweissroboter mit Funkenflug
		for r in 2:
			var base := Vector2(0.6 + 0.45 * float(r), by - 0.45 if r == 0 else by + 0.45)
			_box(base.x - 0.08, base.y - 0.08, base.x + 0.08, base.y + 0.08, 0.0, 0.3, ROBOT.darkened(0.2))
			var sw := sin(t * (3.0 if at_station[0] and shift else 0.6) + float(r) * 1.7)
			var elbow := _f(base + Vector2(0.05 * sw, 0.0), 1.1)
			var tip := _f(Vector2(base.x + 0.15 + 0.1 * sw, by + (-0.12 if r == 0 else 0.12)), 0.75)
			draw_line(_f(base, 0.3), elbow, ROBOT, 5.0)
			draw_line(elbow, tip, ROBOT, 4.0)
			draw_circle(elbow, 3.0, Color("3a3d42"))
			draw_circle(tip, 2.0, Color("3a3d42"))
			if at_station[0] and shift:
				for k in 6:
					var a := t * 23.0 + float(k) * 1.1 + float(r)
					if fmod(a, 2.0) < 1.2:
						draw_line(tip, tip + Vector2(cos(a), sin(a) * 0.6 + 0.4) * (4.0 + 6.0 * fmod(a * 3.0, 1.0)), Color("ffd84a"), 1.2)
		# Station 2: Lackierkabine (Glas)
		var lk := Color(0.85, 0.92, 1.0, 0.16)
		_quad(Vector3(1.4, by - 0.42, 0), Vector3(2.12, by - 0.42, 0), Vector3(2.12, by - 0.42, 1.9), Vector3(1.4, by - 0.42, 1.9), lk)
		_quad(Vector3(1.4, by + 0.42, 0), Vector3(2.12, by + 0.42, 0), Vector3(2.12, by + 0.42, 1.9), Vector3(1.4, by + 0.42, 1.9), lk)
		_quad(Vector3(1.4, by - 0.42, 1.9), Vector3(2.12, by - 0.42, 1.9), Vector3(2.12, by + 0.42, 1.9), Vector3(1.4, by + 0.42, 1.9), Color(0.9, 0.95, 1.0, 0.35))
		for c in [Vector3(1.4, by + 0.42, 0), Vector3(2.12, by + 0.42, 0), Vector3(2.12, by - 0.42, 0)]:
			_line3(c, c + Vector3(0, 0, 1.9), Color("dfe6ec"), 1.5)
		# Station 3: Monteure, Raederstapel; Station 4: Lichttunnel und Pruefer
		for k in 3:
			var wp := _f(Vector2(2.35 + 0.18 * float(k), by + 0.62), 0.12)
			for j in 3:
				draw_circle(wp + Vector2(0, -5.0 * float(j)), 4.0, Color("1e2023"))
		for x in [3.85, 4.2]:
			_line3(Vector3(x, by - 0.38, 0), Vector3(x, by - 0.38, 1.7), Color("fff4c0"), 3.0)
			_line3(Vector3(x, by - 0.38, 1.7), Vector3(x, by + 0.38, 1.7), Color("fff4c0"), 3.0)
			_line3(Vector3(x, by + 0.38, 1.7), Vector3(x, by + 0.38, 0), Color("fff4c0"), 3.0)
		var spots := [[Vector2(0.9, by + 0.62), "haemmern"], [Vector2(2.5, by - 0.5), "haemmern"], [Vector2(2.9, by + 0.6), "haemmern"],
			[Vector2(3.3, by - 0.5), "haemmern"], [Vector2(3.5, by + 0.6), "tragen"], [Vector2(4.05, by + 0.6), "messen"],
			[Vector2(1.75, by + 0.6), "messen"], [Vector2(0.4, 2.45), "tragen"]]
		var crew := mini(monteure, spots.size()) if shift else mini(monteure, 1)
		for i in crew:
			var sp: Array = spots[i]
			var act := str(sp[1]) if shift else "gehen"
			var at: Vector2 = sp[0]
			if act == "tragen":
				at += Vector2(0.3 * sin(t * 0.7 + float(i)), 0.0)
			CrewArt.worker(self, Callable(self, "_f"), at, t + float(i) * 0.37, act, OVERALL, Color("e8b830"), i)
		# Hallenkran ueber dem Band
		var kx := 0.6 + 3.6 * (0.5 + 0.5 * sin(t * 0.15))
		_line3(Vector3(0, 1.1, HZ - 0.3), Vector3(W - 0.2, 1.1, HZ - 0.3), Color("4a4f55"), 3.0)
		_line3(Vector3(0, 2.5, HZ - 0.3), Vector3(W - 0.2, 2.5, HZ - 0.3), Color("4a4f55"), 3.0)
		_box(kx - 0.07, 1.1, kx + 0.07, 2.5, HZ - 0.45, HZ - 0.3, Color("e8b830"))
		_line3(Vector3(kx, by, HZ - 0.45), Vector3(kx, by, 2.2), Color("2a2c30"), 1.0)
		_box(kx - 0.12, by - 0.08, kx + 0.12, by + 0.08, 2.0, 2.2, Color("70757c"))
		# Dachbinder ueber dem offenen Teil (Schnitt)
		for i in 5:
			var x := 0.5 + float(i)
			_line3(Vector3(x, 0.9, HZ + 0.1), Vector3(x, HH, HZ + 0.1), Color("5b6068"), 3.0)
			_line3(Vector3(x, 0.9, HZ + 0.35), Vector3(x, HH, HZ), Color("5b6068"), 2.0)
		# Vordere Waende: aufgeschnittene Bruestung mit stehender Ecke
		_box(0, HH - 0.12, 3.0, HH, 0, 0.7, BRICK)
		_box(W - 0.12, 0, W, 1.6, 0, 0.7, BRICK)
		var jag := [Vector3(3.0, HH, 0.7), Vector3(3.5, HH, 1.0), Vector3(3.8, HH, 0.8), Vector3(4.2, HH, 1.1), Vector3(4.5, HH, 0.9), Vector3(4.75, HH, HZ * 0.85), Vector3(W, HH, HZ)]
		var poly := PackedVector2Array([_f(Vector2(3.0, HH), 0.0), _f(Vector2(W, HH), 0.0)])
		for i in range(jag.size() - 1, -1, -1):
			poly.append(_f(Vector2(jag[i].x, jag[i].y), jag[i].z))
		draw_colored_polygon(poly, BRICK.darkened(0.15))
		for i in jag.size() - 1:
			_line3(jag[i], jag[i + 1], CUT, 2.5)
		var jag2 := [Vector3(W, 1.6, 0.7), Vector3(W, 1.85, 1.4), Vector3(W, 2.05, 1.0), Vector3(W, 2.35, HZ * 0.8), Vector3(W, HH, HZ)]
		var poly2 := PackedVector2Array([_f(Vector2(W, 1.6), 0.0), _f(Vector2(W, HH), 0.0)])
		for i in range(jag2.size() - 1, -1, -1):
			poly2.append(_f(Vector2(jag2[i].x, jag2[i].y), jag2[i].z))
		draw_colored_polygon(poly2, BRICK.darkened(0.3))
		for i in jag2.size() - 1:
			_line3(jag2[i], jag2[i + 1], CUT, 2.5)
		_quad(Vector3(W - 0.12, HH - 0.12, HZ), Vector3(W, HH - 0.12, HZ), Vector3(W, HH, HZ), Vector3(W - 0.12, HH, HZ), CUT)
		# Werkshof: fertige Fahrzeuge, Parkmarkierungen, Tor
		for i in 5:
			var x := 0.2 + 0.68 * float(i)
			_line3(Vector3(x, 2.95, 0.01), Vector3(x, 3.9, 0.01), Color("e8e4d8"), 1.0)
		var slot := 0
		for e in vw.hof:
			if slot >= 8:
				break
			var d: Dictionary = vw.designs.get(str(e.design), {})
			var pos := Vector2(0.54 + 0.68 * float(slot % 4) + 0.0, 3.12 if slot < 4 else 3.62)
			_vehicle(pos, d, 3, 0.0, 0.6)
			slot += 1
		_line3(Vector3(0.05, 3.0, 0), Vector3(0.05, 3.0, 2.4), Color("c9ccd1"), 2.0)
		_line3(Vector3(0.05, 3.9, 0), Vector3(0.05, 3.9, 2.4), Color("c9ccd1"), 2.0)
		var wave := sin(t * 2.0) * 3.0
		for k in 2:
			var tp := _f(Vector2(0.05, 3.0 + 0.9 * float(k)), 2.4)
			draw_colored_polygon(PackedVector2Array([tp, tp + Vector2(14, 2 + wave), tp + Vector2(14, 9 + wave), tp + Vector2(0, 7)]), Color("c8322b") if k == 0 else Color("f2ead8"))
		# Autohaus (Glas): Drehteller mit dem neuesten Modell, Verkaeufer und Kunde
		var ax0 := 3.45
		var ay0 := 2.92
		_quad(Vector3(ax0, ay0, 0.01), Vector3(4.92, ay0, 0.01), Vector3(4.92, 3.95, 0.01), Vector3(ax0, 3.95, 0.01), Color("e8e6e0"))
		_quad(Vector3(ax0, ay0, 0), Vector3(4.92, ay0, 0), Vector3(4.92, ay0, 1.5), Vector3(ax0, ay0, 1.5), Color(0.75, 0.86, 0.95, 0.35))
		_quad(Vector3(ax0, ay0, 0), Vector3(ax0, 3.95, 0), Vector3(ax0, 3.95, 1.5), Vector3(ax0, ay0, 1.5), Color(0.75, 0.86, 0.95, 0.3))
		var newest := {}
		for d in vw.designs.values():
			if d.status == "serie" and (newest.is_empty() or int(d.day) > int(newest.day)):
				newest = d
		var tc := _f(Vector2(4.15, 3.42), 0.02)
		draw_set_transform(tc, 0.0, Vector2(1.0, 0.5))
		draw_circle(Vector2.ZERO, 34.0, Color("c9ccd1"))
		draw_arc(Vector2.ZERO, 34.0, t, t + 4.0, 24, Color("fff4c0"), 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if not newest.is_empty():
			_vehicle(Vector2(4.15, 3.42), newest, 3, 0.04, 0.7)
		var sellers: int = sim.municipal.staff_count(fid, "autohaendler")
		if sellers > 0 and (shift or not night):
			CrewArt.worker(self, Callable(self, "_f"), Vector2(3.7, 3.75), t, "winken", Color("2a2c30"), Color("f4f4f4"), 7)
			if not vw.sales.is_empty() and int(vw.sales[-1].day) >= GameCalendar.day_of(sim.game_min) - 1:
				CrewArt.worker(self, Callable(self, "_f"), Vector2(4.6, 3.8), t + 1.0, "gehen", Color("6a8a4a"), Color("6a8a4a"), 9)
		_quad(Vector3(ax0, 3.95, 0), Vector3(4.92, 3.95, 0), Vector3(4.92, 3.95, 1.5), Vector3(ax0, 3.95, 1.5), Color(0.8, 0.9, 1.0, 0.22))
		_quad(Vector3(4.92, ay0, 0), Vector3(4.92, 3.95, 0), Vector3(4.92, 3.95, 1.5), Vector3(4.92, ay0, 1.5), Color(0.8, 0.9, 1.0, 0.18))
		_quad(Vector3(ax0, ay0, 1.55), Vector3(4.92, ay0, 1.55), Vector3(4.92, 3.95, 1.55), Vector3(ax0, 3.95, 1.55), Color(0.85, 0.9, 0.95, 0.18))   # Glasdach
		for e2 in [[Vector3(ax0, ay0, 1.55), Vector3(4.92, ay0, 1.55)], [Vector3(4.92, ay0, 1.55), Vector3(4.92, 3.95, 1.55)], [Vector3(4.92, 3.95, 1.55), Vector3(ax0, 3.95, 1.55)], [Vector3(ax0, 3.95, 1.55), Vector3(ax0, ay0, 1.55)]]:
			_line3(e2[0], e2[1], Color("d8d8d4"), 3.0)
		for c in [Vector2(ax0, 3.95), Vector2(4.92, 3.95), Vector2(4.92, ay0)]:
			_line3(Vector3(c.x, c.y, 0), Vector3(c.x, c.y, 1.5), Color("9a9ea4"), 2.0)
		_text(_f(Vector2(4.2, 3.95), 1.95), "AUTOHAUS", 11, Color("ffffff"), Color(0.15, 0.3, 0.55, 0.85))
		# Schilder zuletzt (liegen ueber allem)
		var labels := ["KAROSSERIE", "LACK", "MONTAGE", "KONTROLLE"]
		for i in 4:
			_text(_f(Vector2((float(STATIONS[i]) + float(STATIONS[i + 1])) * 0.5, by), 3.4), labels[i], 9, Color("1e2023"), Color(0.95, 0.85, 0.3, 0.9))
		_text(_f(Vector2(2.4, 1.0), HZ + 0.5), str(f.name).to_upper(), 13, Color("f2ead8"), Color(0.15, 0.1, 0.08, 0.75))
		if not dev.is_empty() and dev.status == "entwicklung":
			_text(_f(Vector2(1.3, 0.75), 3.5), "Konstruktion: %s" % str(dev.name), 10, Color("ffffff"), Color(0.1, 0.2, 0.35, 0.8))
		if str(f.get("hinweis", "")) != "":
			_text(_f(Vector2(1.5, 2.0), 5.4), str(f.hinweis).left(70), 10, Color("ffffff"), Color(0.6, 0.15, 0.1, 0.8))


## Stadtwerkstatt: das Gebaeude zeichnet CityView; hier nur Mechaniker an der Hebebuehne, solange gewartet wird.
class ShopNode extends WorksNode:
	func _draw() -> void:
		var busy: Array = sim.vworks.in_service(fid)
		if busy.is_empty():
			return
		var at := Vector2(road - rect.position) + Vector2(0.5, 0.5)
		_quad(Vector3(at.x - 0.35, at.y - 0.2, 0.02), Vector3(at.x + 0.35, at.y - 0.2, 0.02), Vector3(at.x + 0.35, at.y + 0.2, 0.02), Vector3(at.x - 0.35, at.y + 0.2, 0.02), Color("e8b830"))
		for i in mini(busy.size(), 2):
			CrewArt.worker(self, Callable(self, "_f"), at + Vector2(-0.3 + 0.6 * float(i), 0.35), t + float(i), "haemmern", Color("2f5fb3"), Color("e07a2a"), i + 11)
		_text(_f(at, 2.2), "Wartung", 10, Color("ffffff"), Color(0.15, 0.3, 0.55, 0.85))
