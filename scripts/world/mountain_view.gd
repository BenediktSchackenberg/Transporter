class_name MountainView
extends Node2D
## Berge auf den Lagerstaetten und sichtbarer Bergbau (Auftrag 14, Etappe 4/5; docs/ENTREPRENEURS.md Abschnitt 5).
## Liest nur aus Simulation (Production.terrain, Bergwerke, Lager); zeichnet prozedural in der Iso-Projektion wie SiteView.
##
## Gelaende: Hoehensaeulen je Zelle (Wiese, Fels, Schnee, Nadelbaeume). Abgebautes erscheint als Grube in der Rohstofffarbe.
## Laufendes Bergwerk: Foerdergeruest mit Seilrad (Erz, Kohle) bzw. Brecher mit Foerderband (Kalk, Kies), Bagger an der Abbaufront,
## pendelnder Muldenkipper, Bergleute, Halde nach Lagerbestand, Staub, Sprengungen, Flutlicht bei Nacht, Schild bei Stillstand.
## Gelaende und Arbeit eines Bergs werden gemeinsam nach Tiefe sortiert gezeichnet (richtige Verdeckung an Felskanten).

const STEP := 24.0                     # Pixel je Hoehenstufe
const MAN := 1.8                       # Massstab der Figuren
const MACHINE := 2.2                   # Massstab der Maschinen
const ORE := {"eisenerz": Color("9c4a32"), "kohle": Color("2c2a2a"), "kalkstein": Color("e4e0d4"), "rohmaterial": Color("d8b878")}
const GRASS := Color("5f8f45")
const ROCK := Color("8d857a")
const ROCK_DARK := Color("6e665d")
const SNOW := Color("eef2f6")

var sim: Simulation
var cv
var _nodes := {}          # Parzelle -> MountainNode
var _clock := 0.0
var _t := 0.0


func setup(simulation: Simulation, city_view) -> void:
	sim = simulation
	cv = city_view
	y_sort_enabled = true
	for pid in sim.prod.terrain:
		var n := MountainNode.new()
		n.view = self
		n.pid = pid
		n.configure()
		add_child(n)
		_nodes[pid] = n


func update_view(delta: float) -> void:
	_clock += delta
	_t += delta
	var refresh := _t >= 0.5
	if refresh:
		_t = 0.0
	var cam := get_viewport().get_camera_2d()
	var view := Rect2()
	if cam != null:
		var size := get_viewport_rect().size / cam.zoom
		view = Rect2(cam.get_screen_center_position() - size * 0.5, size).grow(400.0)
	for n in _nodes.values():
		if refresh:
			n.refresh()
		if n.active and view.has_point(n.position):
			n.t = _clock
			n.queue_redraw()


## Berg unter dem Mauszeiger (Weltposition) -> Parzelle oder "".
func pick(world: Vector2) -> String:
	for pid in _nodes:
		var p: Dictionary = sim.parcels.parcel(pid)
		var r := Rect2(float(p.rect[0]) * 32.0, float(p.rect[1]) * 32.0, float(p.rect[2]) * 32.0, float(p.rect[3]) * 32.0)
		if r.has_point(world):
			return pid
	# auch die sichtbare Bergflanke ueber dem Grund (Bildschirm) zaehlt
	var click := Iso.to_screen(world)
	for pid in _nodes:
		var n: MountainNode = _nodes[pid]
		if n.screen_box.has_point(click - n.position):
			return pid
	return ""


## Weltposition (Kamera) eines Bergwerks fuer die Taste B.
func mine_targets() -> Array:
	var out: Array = []
	for pid in _nodes:
		if not sim.prod.mine_on(pid).is_empty():
			out.append(Iso.to_screen(_nodes[pid].center_world))
	return out


class MountainNode extends Node2D:
	var view
	var pid := ""
	var cells := {}
	var rect := Rect2i()
	var origin := Vector2.ZERO          # Weltpunkt (Pixel) der vorderen Ecke: Bezug fuer Tiefensortierung
	var center_world := Vector2.ZERO
	var screen_box := Rect2()
	var art := ""
	var pit := {}
	var sig := ""
	var active := false
	var t := 0.0
	var mine := {}
	var halde_cell := Vector2i.ZERO
	var rig_cell := Vector2i.ZERO
	var face := Vector2i.ZERO
	var stock := 0
	var staff := 0
	var working := false
	var blocker := ""
	var blast_age := 9999.0
	var color := Color.WHITE

	func configure() -> void:
		var tr: Dictionary = view.sim.prod.terrain[pid]
		cells = tr.cells
		art = str(tr.art)
		var p: Dictionary = view.sim.parcels.parcel(pid)
		rect = Rect2i(int(p.rect[0]), int(p.rect[1]), int(p.rect[2]), int(p.rect[3]))
		origin = Vector2(float(rect.end.x), float(rect.end.y)) * 32.0
		center_world = (Vector2(rect.position) + Vector2(rect.size) * 0.5) * 32.0
		position = Iso.to_screen(origin)
		var top := 0.0
		for c in cells:
			top = maxf(top, float(cells[c]))
		var a := _s(Vector2(rect.position) * 32.0)
		var b := _s(Vector2(rect.end.x, rect.position.y) * 32.0)
		var d := _s(Vector2(rect.position.x, rect.end.y) * 32.0)
		screen_box = Rect2(Vector2(d.x, a.y - top * MountainView.STEP - 40.0), Vector2(b.x - d.x, -a.y + top * MountainView.STEP + 40.0))
		refresh()

	func _s(w: Vector2) -> Vector2:
		return Iso.to_screen(w) - Iso.to_screen(origin)

	func _rnd(c: Vector2i, k: int) -> float:
		return float(absi(hash([pid, c, k])) % 1000) / 1000.0

	## Zustand aus der Simulation (alle 0,5 s): Grube, Bergwerk, Halde, Personal, Blockaden.
	func refresh() -> void:
		var sim: Simulation = view.sim
		var ex: Dictionary = sim.prod.excavated(pid)
		pit = ex.get("grube", {})
		var order: Array = sim.prod.terrain[pid].order
		face = order[mini(pit.size(), order.size() - 1)]
		mine = sim.prod.mine_on(pid)
		active = not mine.is_empty()
		if active:
			var acct := "C%d" % int(mine.owner)
			stock = sim.stock.qty(art, acct, int(mine.site))
			staff = sim.biz.staff_of(mine.id).size()
			working = int(mine.get("today", 0)) > 0 and mine.status != "blockiert"
			blocker = str(mine.blockers[0].text) if not mine.blockers.is_empty() else ("Kein Personal" if staff == 0 else "")
			color = sim.company(int(mine.owner)).color
			var bt: float = float(sim.prod.blasts.get(mine.id, -99999.0))
			blast_age = sim.game_min - bt
			_place_rig(sim)
		var s := "%d|%s|%d|%d" % [pit.size(), str(active), stock / 25, staff]
		if s != sig:
			sig = s
			queue_redraw()

	## Vorplatz: Zellen der Parzelle ohne Berg und ohne Gebaeude; Halde nahe der Abbaufront, Geruest daneben.
	func _place_rig(sim: Simulation) -> void:
		var free: Array = []
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var c := Vector2i(x, y)
				if not cells.has(c) and sim.city.building_at[sim.city.idx(c)] < 0 and not sim.city.is_road(c):
					free.append(c)
		free.sort_custom(func(a, b): return absi(a.x - face.x) + absi(a.y - face.y) < absi(b.x - face.x) + absi(b.y - face.y))
		halde_cell = free[0] if not free.is_empty() else face
		rig_cell = free[1] if free.size() > 1 else halde_cell

	func _draw() -> void:
		var items: Array = []
		for c in cells:
			items.append([float(c.x + c.y) + 1.0, 0, c])
		if active:
			for i in mini(staff, 8):
				items.append([0.0, 1, i])          # Tiefe wird in _worker_pos bestimmt
			items.append([float(halde_cell.x + halde_cell.y) + 1.0, 2, halde_cell])
			items.append([float(rig_cell.x + rig_cell.y) + 1.0, 3, rig_cell])
			items.append([float(face.x + face.y) + 0.5, 4, face])
			items.append([0.0, 5, 0])              # Kipper (Tiefe dynamisch)
			for it in items:
				if it[1] == 1:
					it[0] = _worker_world(int(it[2])).x / 32.0 + _worker_world(int(it[2])).y / 32.0
				elif it[1] == 5:
					var tw := _truck_world()
					it[0] = tw.x / 32.0 + tw.y / 32.0
		items.sort_custom(func(a, b): return a[0] < b[0])
		for it in items:
			match int(it[1]):
				0: _draw_cell(it[2])
				1: _draw_worker(int(it[2]))
				2: _draw_halde()
				3: _draw_rig()
				4: _draw_face()
				5: _draw_truck()
		if active:
			_draw_effects()

	func _level(c: Vector2i) -> float:
		return 0.45 if pit.has(c) else float(cells.get(c, 0.0))

	## Hoehe der Nachbarzelle (ausserhalb des Bergs 0).
	func _nb(c: Vector2i) -> float:
		return _level(c) if cells.has(c) else 0.0

	## Farbe der Oberseite nach Hoehe mit weichen Uebergaengen: Wiese, Geroell, Fels, Schnee.
	func _top_color(L: float, c: Vector2i) -> Color:
		var j := (_rnd(c, 2) - 0.5) * 0.06
		var col: Color
		if L < 2.2:
			col = MountainView.GRASS
		elif L < 3.4:
			col = MountainView.GRASS.lerp(Color("8f8a6a"), (L - 2.2) / 1.2)
		elif L < 6.0:
			col = Color("8f8a6a").lerp(MountainView.ROCK, (L - 3.4) / 2.6)
		elif L < 7.6:
			col = MountainView.ROCK.lerp(MountainView.ROCK_DARK, (L - 6.0) / 1.6)
		else:
			col = MountainView.SNOW.lerp(Color("dfe8f2"), _rnd(c, 6) * 0.5)
		return col.lightened(j) if j > 0.0 else col.darkened(-j)

	func _draw_cell(c: Vector2i) -> void:
		var L := _level(c)
		var up := Vector2(0, -L * MountainView.STEP)
		var n := _s(Vector2(c) * 32.0)
		var e := _s(Vector2(c.x + 1, c.y) * 32.0)
		var so := _s(Vector2(c.x + 1, c.y + 1) * 32.0)
		var w := _s(Vector2(c.x, c.y + 1) * 32.0)
		var top: Color
		var rock := Color("7d7266")
		if pit.has(c):
			top = MountainView.ORE.get(art, MountainView.ROCK).lerp(Color.BLACK, 0.08 * _rnd(c, 1))
			rock = top.darkened(0.3)
		else:
			top = _top_color(L, c)
			# Licht von Nordwest: Hang zur Sonne heller, abgewandt dunkler
			var slope := (L - 0.5 * (_nb(c + Vector2i(-1, 0)) + _nb(c + Vector2i(0, -1))))
			top = top.lightened(clampf(slope * 0.05, 0.0, 0.18)) if slope > 0.0 else top.darkened(clampf(-slope * 0.06, 0.0, 0.25))
		# Flanken nur, wo sie sichtbar sind (Nachbar davor niedriger), mit Gesteinsschichten
		var lw := _nb(c + Vector2i(0, 1))
		var le := _nb(c + Vector2i(1, 0))
		if lw < L:
			var lo := Vector2(0, -lw * MountainView.STEP)
			draw_colored_polygon(PackedVector2Array([w + up, so + up, so + lo, w + lo]), rock.darkened(0.05))
			_strata(w, so, lw, L, rock.darkened(0.2))
		if le < L:
			var lo2 := Vector2(0, -le * MountainView.STEP)
			draw_colored_polygon(PackedVector2Array([so + up, e + up, e + lo2, so + lo2]), rock.darkened(0.32))
			_strata(so, e, le, L, rock.darkened(0.45))
		draw_colored_polygon(PackedVector2Array([n + up, e + up, so + up, w + up]), top)
		if L >= 7.6 and not pit.has(c):   # Schneekante an den Flanken
			draw_colored_polygon(PackedVector2Array([w + up, so + up, so + up + Vector2(0, 7), w + up + Vector2(0, 5)]), Color("e6edf5"))
			draw_colored_polygon(PackedVector2Array([so + up, e + up, e + up + Vector2(0, 5), so + up + Vector2(0, 7)]), Color("c9d6e4"))
		draw_polyline(PackedVector2Array([w + up, n + up, e + up]), Color(1, 1, 1, 0.10), 1.0)   # Lichtkante
		if pit.has(c):   # Abbauterrasse
			draw_line((n + w) * 0.5 + up, (e + so) * 0.5 + up, top.darkened(0.25), 1.5)
			return
		var mid := (n + e + so + w) * 0.25 + up
		if L >= 3.4 and L < 7.6 and _rnd(c, 7) < 0.5:   # Geroellbrocken
			var bp := mid + Vector2((_rnd(c, 8) - 0.5) * 34.0, (_rnd(c, 9) - 0.5) * 12.0)
			draw_colored_polygon(PackedVector2Array([bp + Vector2(-5, 0), bp + Vector2(-3, -5), bp + Vector2(3, -6), bp + Vector2(6, -1), bp + Vector2(1, 2)]), Color("9a9389"))
			draw_colored_polygon(PackedVector2Array([bp + Vector2(1, 2), bp + Vector2(6, -1), bp + Vector2(3, -6)]), Color("6f685f"))
		if L < 3.6:   # Bergwald am Fuss, dichter je niedriger
			var trees := 2 if L < 2.2 else 1
			for k in trees:
				if _rnd(c, 10 + k) > 0.75:
					continue
				var base := mid + Vector2((_rnd(c, 12 + k) - 0.5) * 40.0, (_rnd(c, 14 + k) - 0.5) * 16.0)
				var hgt := 22.0 + 12.0 * _rnd(c, 16 + k)
				draw_rect(Rect2(base + Vector2(-1.5, -5), Vector2(3, 5)), Color("5b4030"))
				draw_colored_polygon(PackedVector2Array([base + Vector2(-9, -5), base + Vector2(9, -5), base + Vector2(0, -hgt)]), Color("264f33"))
				draw_colored_polygon(PackedVector2Array([base + Vector2(0, -5), base + Vector2(9, -5), base + Vector2(0, -hgt)]), Color("1d3d27"))
				draw_colored_polygon(PackedVector2Array([base + Vector2(-7, -hgt * 0.5), base + Vector2(7, -hgt * 0.5), base + Vector2(0, -hgt - 6)]), Color("31653f"))

	## Gesteinsschichten auf einer Flanke zwischen den Hoehen lo und hi.
	func _strata(a: Vector2, b: Vector2, lo: float, hi: float, col: Color) -> void:
		var k := ceilf(lo + 0.01)
		while k < hi:
			var y := Vector2(0, -k * MountainView.STEP)
			draw_line(a + y, b + y, Color(col, 0.55), 1.0)
			k += 1.0

	func _cell_center(c: Vector2i) -> Vector2:
		return (Vector2(c) + Vector2(0.5, 0.5)) * 32.0

	func _worker_world(i: int) -> Vector2:
		# Bergleute verteilt ueber die Grube und die Abbaufront (nicht hinter den Maschinen)
		var spots: Array = pit.keys()
		var home: Vector2i = spots[i % spots.size()] if not spots.is_empty() else face
		var a := _cell_center(home) + Vector2(_rnd(Vector2i(i, 0), 1) - 0.5, _rnd(Vector2i(i, 0), 2) - 0.5) * 24.0 + Vector2(-24.0, 18.0) * float(i % 2)
		if i % 3 == 2:   # pendelt zwischen Front und Halde
			var u := 0.5 + 0.5 * sin(t * 0.7 + float(i))
			return a.lerp(_cell_center(halde_cell), u if working else 0.0)
		return a

	func _draw_worker(i: int) -> void:
		var w := _worker_world(i)
		var c := Vector2i(int(w.x / 32.0), int(w.y / 32.0))
		var pos := _s(w) + Vector2(0, -_level(c) * MountainView.STEP if cells.has(c) else 0.0)
		var bob := sin(t * 8.0 + float(i)) if working else 0.0
		draw_set_transform(pos, 0.0, Vector2(MountainView.MAN, MountainView.MAN))
		pos = Vector2.ZERO
		draw_rect(Rect2(pos + Vector2(-2, -9 + bob), Vector2(5, 7)), Color("f28c28") if i % 2 == 0 else Color("3e7cb1"))
		draw_rect(Rect2(pos + Vector2(-2, -2), Vector2(5, 2)), Color("2f343c"))
		draw_rect(Rect2(pos + Vector2(-2, -13 + bob), Vector2(5, 4)), Color("e0b48a"))
		draw_rect(Rect2(pos + Vector2(-3, -15 + bob), Vector2(7, 2)), Color("f2c14e"))
		draw_circle(pos + Vector2(1, -14 + bob), 1.2, Color(1.0, 0.95, 0.6, 0.9))   # Grubenlampe
		if working and i % 3 != 2:
			var swing := sin(t * 6.0 + float(i) * 1.7)
			var tip := pos + Vector2(4 + 5.0 * swing, -14 + 6.0 * absf(swing))
			draw_line(pos + Vector2(3, -8), tip, Color("6d5a44"), 1.5)
			draw_line(tip + Vector2(-2, 0), tip + Vector2(2, 2), Color("c0c0c0"), 2.0)   # Hacke
			if swing > 0.92:
				draw_circle(tip + Vector2(2, 2), 2.0, Color(1.0, 0.85, 0.4, 0.9))           # Funken
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	func _draw_halde() -> void:
		var base := _s(_cell_center(halde_cell))
		var size := clampf(float(stock) / 600.0, 0.05, 1.0)
		var r := 10.0 + 34.0 * size
		var h := 6.0 + 38.0 * size
		var col: Color = MountainView.ORE.get(art, MountainView.ROCK)
		draw_colored_polygon(PackedVector2Array([base + Vector2(-r, 0), base + Vector2(0, -h), base + Vector2(r, 0), base + Vector2(0, r * 0.5)]), col)
		draw_colored_polygon(PackedVector2Array([base + Vector2(0, -h), base + Vector2(r, 0), base + Vector2(0, r * 0.5)]), col.darkened(0.25))
		for k in 6:
			var p := base + Vector2((_rnd(Vector2i(k, 3), 1) - 0.5) * r, -(_rnd(Vector2i(k, 3), 2)) * h * 0.7)
			draw_circle(p, 1.5, col.lightened(0.2))

	func _draw_rig() -> void:
		var base0 := _s(_cell_center(rig_cell))
		var spin := t * 3.0 if working else 0.0
		var S := 1.5
		if art in ["eisenerz", "kohle"]:
			draw_line(base0 + Vector2(12, -92) * S, _s(_cell_center(face)) + Vector2(0, -_level(face) * MountainView.STEP - 6), Color(0.15, 0.15, 0.15, 0.7), 1.5)   # Foerderseil
		else:
			var a0 := base0 + Vector2(0, -30) * S
			var b0 := _s(_cell_center(halde_cell)) + Vector2(0, -20)
			draw_line(a0, b0, Color("3a3a3a"), 4.0)   # Foerderband
			if working:
				for k in 8:
					var u0 := fmod(t * 0.6 + float(k) / 8.0, 1.0)
					draw_circle(a0.lerp(b0, u0) + Vector2(0, -3), 3.0, MountainView.ORE.get(art, MountainView.ROCK))
		draw_set_transform(base0, 0.0, Vector2(S, S))
		var base := Vector2.ZERO
		if art in ["eisenerz", "kohle"]:
			# Foerdergeruest mit Seilrad
			var top := base + Vector2(0, -92)
			draw_line(base + Vector2(-18, 0), top, Color("7a3b2e"), 4.0)
			draw_line(base + Vector2(18, 0), top, Color("7a3b2e"), 4.0)
			draw_line(base + Vector2(-10, -46), base + Vector2(10, -46), Color("7a3b2e"), 3.0)
			draw_line(base + Vector2(-18, 0), base + Vector2(10, -46), Color("7a3b2e"), 2.0)
			draw_arc(top, 12.0, 0.0, TAU, 20, Color("3a3a3a"), 3.0)
			for k in 4:
				var a := spin + float(k) * PI / 4.0
				draw_line(top - Vector2(cos(a), sin(a)) * 12.0, top + Vector2(cos(a), sin(a)) * 12.0, Color("3a3a3a"), 1.5)
			draw_rect(Rect2(base + Vector2(-22, -18), Vector2(44, 18)), Color("8c8478"))   # Maschinenhaus
			draw_rect(Rect2(base + Vector2(-22, -22), Vector2(44, 4)), Color("5f574d"))
			draw_rect(Rect2(top + Vector2(-2, -28), Vector2(2, 16)), Color("dddddd"))   # Fahne des Betreibers
			draw_rect(Rect2(top + Vector2(0, -28), Vector2(14, 8)), color)
		else:
			# Brecher mit Foerderband zur Halde
			draw_rect(Rect2(base + Vector2(-18, -26), Vector2(36, 26)), Color("b1a58d"))
			draw_colored_polygon(PackedVector2Array([base + Vector2(-18, -26), base + Vector2(18, -26), base + Vector2(10, -38), base + Vector2(-10, -38)]), Color("8c8070"))
			draw_rect(Rect2(base + Vector2(14, -50), Vector2(2, 16)), Color("dddddd"))
			draw_rect(Rect2(base + Vector2(16, -50), Vector2(14, 8)), color)
		if blocker != "":
			var sign := base + Vector2(-30, -70)
			draw_rect(Rect2(sign, Vector2(60, 18)), Color(0.95, 0.85, 0.3, 0.95))
			draw_rect(Rect2(sign, Vector2(60, 18)), Color(0.2, 0.2, 0.2), false, 1.0)
			draw_string(ThemeDB.fallback_font, sign + Vector2(4, 13), "! " + blocker.left(14), HORIZONTAL_ALIGNMENT_LEFT, 56.0, 9, Color.BLACK)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	func _draw_face() -> void:
		# Bagger an der Abbaufront: Arm schwenkt zur Felswand, Schaufel fuellt sich
		var base := _s(_cell_center(face)) + Vector2(0, -_level(face) * MountainView.STEP)
		var swing := sin(t * 1.3) if working else 0.0
		draw_set_transform(base, 0.0, Vector2(MountainView.MACHINE, MountainView.MACHINE))
		base = Vector2.ZERO
		draw_rect(Rect2(base + Vector2(-14, -4), Vector2(28, 5)), Color("2b2b2b"))
		draw_rect(Rect2(base + Vector2(-12, -14), Vector2(24, 10)), Color("e0a526"))
		draw_rect(Rect2(base + Vector2(-8, -22), Vector2(12, 8)), Color("c98c14"))
		draw_rect(Rect2(base + Vector2(-6, -20), Vector2(6, 4)), Color("9ec9e8"))
		var elbow := base + Vector2(14, -30 + 6.0 * swing)
		var bucket := elbow + Vector2(14 + 6.0 * swing, 14 - 4.0 * swing)
		draw_line(base + Vector2(4, -18), elbow, Color("e0a526"), 4.0)
		draw_line(elbow, bucket, Color("c98c14"), 3.0)
		draw_colored_polygon(PackedVector2Array([bucket + Vector2(-5, -3), bucket + Vector2(5, -3), bucket + Vector2(3, 5), bucket + Vector2(-4, 4)]), Color("4a4a4a"))
		if working and swing > 0.3:
			draw_circle(bucket + Vector2(0, -1), 3.0, MountainView.ORE.get(art, MountainView.ROCK))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	func _truck_world() -> Vector2:
		var u := 0.5 + 0.5 * sin(t * 0.5) if working else 0.0
		return _cell_center(face).lerp(_cell_center(halde_cell), u)

	func _draw_truck() -> void:
		var w := _truck_world()
		var c := Vector2i(int(w.x / 32.0), int(w.y / 32.0))
		var pos := _s(w) + Vector2(0, -_level(c) * MountainView.STEP if cells.has(c) else 0.0)
		var loaded := working and cos(t * 0.5) > 0.0      # auf dem Weg zur Halde beladen
		var dump := working and sin(t * 0.5) > 0.97       # an der Halde kippen
		draw_set_transform(pos, 0.0, Vector2(MountainView.MACHINE, MountainView.MACHINE))
		pos = Vector2.ZERO
		draw_circle(pos + Vector2(-9, 0), 4.0, Color("1e1e1e"))
		draw_circle(pos + Vector2(9, 0), 4.0, Color("1e1e1e"))
		draw_rect(Rect2(pos + Vector2(6, -14), Vector2(9, 10)), Color("e0a526"))
		draw_rect(Rect2(pos + Vector2(8, -12), Vector2(5, 4)), Color("9ec9e8"))
		var tilt := -8.0 if dump else 0.0
		draw_colored_polygon(PackedVector2Array([pos + Vector2(-15, -4), pos + Vector2(5, -4), pos + Vector2(5, -16 + tilt), pos + Vector2(-15, -14)]), Color("c98c14"))
		if loaded:
			draw_colored_polygon(PackedVector2Array([pos + Vector2(-13, -14), pos + Vector2(3, -16 + tilt), pos + Vector2(-5, -22 + tilt)]), MountainView.ORE.get(art, MountainView.ROCK))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	func _draw_effects() -> void:
		var f := _s(_cell_center(face)) + Vector2(0, -_level(face) * MountainView.STEP)
		if working:   # Staub an der Front
			for k in 5:
				var u := fmod(t * 0.4 + float(k) * 0.2, 1.0)
				draw_circle(f + Vector2(18 + 10.0 * float(k % 3), -20.0 - 30.0 * u), 6.0 + 10.0 * u, Color(0.8, 0.75, 0.65, 0.25 * (1.0 - u)))
		# Sprengung: Blitz und Rauchwolke in den ersten 40 Spielminuten danach
		if blast_age >= 0.0 and blast_age < 40.0:
			var u2 := blast_age / 40.0
			if u2 < 0.12:
				draw_circle(f + Vector2(10, -24), 30.0 * (1.0 - u2 * 4.0) + 6.0, Color(1.0, 0.9, 0.5, 0.8))
			for k in 7:
				var a := float(k) * TAU / 7.0
				var p := f + Vector2(10, -24) + Vector2(cos(a), sin(a) * 0.5) * (12.0 + 50.0 * u2) + Vector2(0, -30.0 * u2)
				draw_circle(p, 8.0 + 16.0 * u2, Color(0.55, 0.52, 0.5, 0.55 * (1.0 - u2)))
		# Flutlicht bei Nacht
		if view.cv != null and float(view.cv.night_factor) > 0.3:
			var lamp := _s(_cell_center(rig_cell)) + Vector2(0, -60)
			draw_line(lamp, lamp + Vector2(0, 60), Color("555555"), 2.0)
			draw_circle(lamp, 4.0, Color(1.0, 0.95, 0.7))
			draw_colored_polygon(PackedVector2Array([lamp, f + Vector2(-40, 10), f + Vector2(50, 10)]), Color(1.0, 0.92, 0.6, 0.12 * float(view.cv.night_factor)))
