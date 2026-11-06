class_name BridgeView
extends Node2D
## Bruecken sichtbar (Auftrag 15, Etappe D): Baufortschritt in Phasen (Widerlager, Pfeiler, Fahrbahn, Gelaender, Abnahme),
## Absperrung bis zur Freigabe, Aussehen je Variante (Holz, Stein, Stahlbeton), dazu die Mannschaft der Baufirma mit Maschinen je Phase.
## Wegebau der Zufahrten: abgesteckte Trasse, Arbeitsfront mit Bagger, pendelnden Kipplastern, Walze und Arbeitern, die ueber den Tag
## vorrueckt. Liest nur aus der Simulation; prozedural gezeichnet (CrewArt).

const STEP := 18.0                # Bildschirmhoehe je Hoehenstufe (wie ShipView)
const DECK_Z := 0.7               # Fahrbahnhoehe ueber dem Wasser

var sim: Simulation
var _nodes := {}                  # Bruecken-ID -> BridgeNode
var _roads := {}                  # Zufahrt-ID -> RoadWorksNode
var _clock := 0.0


func setup(simulation: Simulation) -> void:
	sim = simulation
	y_sort_enabled = true


## Firmenfarbe und Name der ausfuehrenden Baufirma eines Stadtprojekts (staedtische Baufirmen: Orange).
func _firm(prj_id: String) -> Array:
	var e: Dictionary = sim.construction.public.get(prj_id, {})
	if e.is_empty():
		return [Color("e07a2a"), "Ausschreibung läuft"]
	var bd: Dictionary = sim.construction.builders.get(e.builder, {})
	var col := Color("e07a2a")
	if bd.has("company"):
		col = sim.company(int(bd.company)).color
	return [col, str(bd.get("name", "Baufirma"))]


func update_view(delta: float) -> void:
	_clock += delta
	var view := _view_rect()
	for id in sim.bridges.items:
		var b: Dictionary = sim.bridges.items[id]
		var n: BridgeNode = _nodes.get(id)
		if n == null:
			n = BridgeNode.new()
			n.configure(b)
			add_child(n)
			_nodes[id] = n
		var p := snappedf(sim.bridges.progress(b), 0.01)
		var ph := sim.bridges.phase(b)
		var crew := ph != "freigegeben"
		if p != n.progress or ph != n.phase or (crew and view.has_point(n.position)):
			n.progress = p
			n.phase = ph
			n.t = _clock
			var f := _firm(str(b.project))
			n.firm = f[0]
			n.builder = f[1]
			n.working = sim.construction.public_running(str(b.project))
			n.queue_redraw()
	var seen := {}
	for j in sim.access.jobs.values():
		if j.status != "im_bau":
			continue
		seen[j.id] = true
		var r: RoadWorksNode = _roads.get(j.id)
		if r == null:
			r = RoadWorksNode.new()
			add_child(r)
			_roads[j.id] = r
		var fr: Dictionary = sim.access.front(j)
		if fr.cells.is_empty():
			continue
		var day_k := clampf((sim.game_min - GameCalendar.day_start(GameCalendar.day_of(sim.game_min))) / GameCalendar.days_to_min(1), 0.0, 1.0)
		r.cells = fr.cells
		r.built = int(fr.built)
		r.front = minf(float(fr.cells.size() - 1), float(fr.built) + (float(fr.rate) * day_k if fr.running else 0.0))
		r.working = bool(fr.running)
		var f2 := _firm(str(j.project))
		r.firm = f2[0]
		r.builder = f2[1]
		r.note = "" if r.working else ("wartet auf Material" if str(sim.construction.public.get(str(j.project), {}).get("waiting", "")) != "" else ("Ausschreibung" if not sim.construction.public.has(str(j.project)) else "Baubeginn folgt"))
		r.position = Iso.to_screen((r.cells[int(r.front)] + Vector2(0.5, 0.5)) * 32.0)
		if view.has_point(r.position):
			r.t = _clock
			r.queue_redraw()
	for id in _roads.keys():
		if not seen.has(id):
			_roads[id].queue_free()
			_roads.erase(id)


func _view_rect() -> Rect2:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return Rect2(-1e9, -1e9, 2e9, 2e9)
	var size := get_viewport_rect().size / cam.zoom
	return Rect2(cam.get_screen_center_position() - size * 0.5, size).grow(400.0)


## Bruecke unter dem Mauszeiger (Weltposition) oder "".
func pick(world: Vector2) -> String:
	var t := CityData.to_tile(world)
	for id in _nodes:
		for q in _nodes[id].points:
			if Vector2i(q) == t:
				return id
	return ""


func center_of(id: String) -> Vector2:
	var n: BridgeNode = _nodes.get(id)
	return n.mid * 32.0 if n != null else Vector2(-9999, -9999)


class BridgeNode extends Node2D:
	var points: Array = []        # Feldmitten (Vector2) vom einen Ufer ueber das Wasser zum anderen (Enden = Uferfelder)
	var water := 0                # Anzahl Wasserfelder
	var variant := "holz"
	var progress := 0.0
	var phase := ""
	var mid := Vector2.ZERO
	var t := 0.0
	var firm := Color("e07a2a")
	var builder := ""
	var working := false
	const LOOK := {
		"holz": {"deck": Color("8a6a45"), "side": Color("5e4630"), "pier": Color("3f2f22"), "rail": Color("6b5136"), "abut": Color("7d7468")},
		"stein": {"deck": Color("a39b8b"), "side": Color("7a7266"), "pier": Color("8c8476"), "rail": Color("9b9383"), "abut": Color("8c8476")},
		"stahlbeton": {"deck": Color("b8bcbf"), "side": Color("868b8f"), "pier": Color("9ea3a6"), "rail": Color("4f6a86"), "abut": Color("9ea3a6")},
	}

	func configure(b: Dictionary) -> void:
		variant = str(b.variant)
		var cells: Array = b.cells.map(func(a): return Vector2(float(a[0]), float(a[1])))
		water = cells.size()
		points = [Vector2(float(b.ends[0][0]), float(b.ends[0][1]))] + cells + [Vector2(float(b.ends[1][0]), float(b.ends[1][1]))]
		mid = (points[0] + points[points.size() - 1]) * 0.5 + Vector2(0.5, 0.5)
		position = Iso.to_screen(mid * 32.0)

	## Feldkoordinate (Mitte bei +0.5) und Hoehe -> Bildschirm relativ zum Knoten.
	func _s(w: Vector2, z: float) -> Vector2:
		return Iso.to_screen((w + Vector2(0.5, 0.5)) * 32.0) - position + Vector2(0, -z * BridgeView.STEP)

	func _quad(a: Vector2, b: Vector2, half: float, z0: float, z1: float, col: Color) -> void:
		var d := (b - a).normalized()
		var n := Vector2(-d.y, d.x) * half
		draw_colored_polygon(PackedVector2Array([_s(a - n, z0), _s(b - n, z0), _s(b + n, z1), _s(a + n, z1)]), col)

	func _draw() -> void:
		var L: Dictionary = LOOK.get(variant, LOOK.holz)
		var z := BridgeView.DECK_Z
		var ends := [points[0], points[points.size() - 1]]
		var k_ab := clampf(progress / 0.25, 0.0, 1.0)
		var k_pier := clampf((progress - 0.25) / 0.25, 0.0, 1.0)
		var k_deck := clampf((progress - 0.5) / 0.3, 0.0, 1.0)
		var k_rail := clampf((progress - 0.8) / 0.15, 0.0, 1.0)
		if phase == "freigegeben":
			k_ab = 1.0; k_pier = 1.0; k_deck = 1.0; k_rail = 1.0
		# Vermessung: Absteckpfloecke an beiden Ufern, solange noch nicht gebaut wird
		if progress <= 0.0 and phase != "freigegeben":
			for e in ends:
				for o in [Vector2(-0.3, -0.3), Vector2(0.3, 0.3)]:
					draw_line(_s(e + o, 0.0), _s(e + o, 0.5), Color("e07a2a"), 3.0)
		# Widerlager: Bloecke an den Ufern, wachsen bis zur Fahrbahnhoehe
		if k_ab > 0.0:
			for i in 2:
				var e: Vector2 = ends[i]
				var inner: Vector2 = points[1] if i == 0 else points[points.size() - 2]
				var a: Vector2 = e + (inner - e) * 0.15
				var b: Vector2 = e + (inner - e) * 0.55
				var h := z * k_ab
				_quad(a, b, 0.42, h, h, L.abut)
				draw_colored_polygon(PackedVector2Array([_s(a + Vector2(-0.42, 0.42), 0.0), _s(b + Vector2(-0.42, 0.42), 0.0), _s(b + Vector2(-0.42, 0.42), h), _s(a + Vector2(-0.42, 0.42), h)]), L.abut.darkened(0.25))
		# Pfeiler unter jedem zweiten Wasserfeld (Holz: jedes Feld)
		if k_pier > 0.0:
			var step := 1 if variant == "holz" else 2
			for i in range(1, points.size() - 1, step):
				var p: Vector2 = points[i]
				var w := 6.0 if variant == "holz" else 10.0
				draw_line(_s(p, -0.3), _s(p, (z + 0.3) * k_pier - 0.3), L.pier, w)
				if variant == "holz":
					draw_line(_s(p + Vector2(0.3, -0.3), -0.3), _s(p + Vector2(0.3, -0.3), (z + 0.3) * k_pier - 0.3), L.pier, w)
		# Fahrbahn: waechst vom ersten Ufer aus ueber die Segmente
		if k_deck > 0.0:
			var segs := points.size() - 1
			var upto := k_deck * segs
			for i in segs:
				if float(i) >= upto:
					break
				var a: Vector2 = points[i]
				var b: Vector2 = points[i + 1]
				var t := minf(1.0, upto - float(i))
				var bb := a + (b - a) * t
				_quad(a, bb, 0.42, z - 0.25, z - 0.25, L.side)
				_quad(a, bb, 0.42, z, z, L.deck)
				if variant == "holz":   # Bohlenfugen
					draw_line(_s(a.lerp(bb, 0.5) + Vector2(-0.4, 0.4), z), _s(a.lerp(bb, 0.5) + Vector2(0.4, -0.4), z), L.side, 1.5)
		# Gelaender: Pfosten und Handlauf auf beiden Seiten
		if k_rail > 0.0:
			var segs2 := points.size() - 1
			for i in segs2:
				if float(i) >= k_rail * segs2:
					break
				var a: Vector2 = points[i]
				var b: Vector2 = points[i + 1]
				var d := (b - a).normalized()
				var n := Vector2(-d.y, d.x) * 0.42
				for sgn in [-1.0, 1.0]:
					draw_line(_s(a + n * sgn, z), _s(a + n * sgn, z + 0.45), L.rail, 2.0)
					draw_line(_s(a + n * sgn, z + 0.45), _s(b + n * sgn, z + 0.45), L.rail, 2.0)
		# Bis zur Abnahme gesperrt: rot-weisse Schranken an beiden Ufern
		if phase != "freigegeben" and progress > 0.0:
			for i in 2:
				var e: Vector2 = ends[i]
				var inner2: Vector2 = points[1] if i == 0 else points[points.size() - 2]
				var c := e + (inner2 - e) * 0.1
				var d2 := (inner2 - e).normalized()
				var nn := Vector2(-d2.y, d2.x) * 0.45
				for k in 4:
					var col := Color("d23b2f") if k % 2 == 0 else Color("f0ece4")
					draw_line(_s(c - nn + nn * 0.5 * k, 0.35), _s(c - nn + nn * 0.5 * (k + 1), 0.35), col, 4.0)
				draw_line(_s(c - nn, 0.0), _s(c - nn, 0.4), Color("2a2a2a"), 2.0)
				draw_line(_s(c + nn, 0.0), _s(c + nn, 0.4), Color("2a2a2a"), 2.0)
		if phase != "freigegeben":
			_draw_crew(L)
		if phase != "freigegeben":
			var lbl: String = {"ausgeschrieben": "Brücke ausgeschrieben", "widerlager": "Widerlager", "pfeiler": "Pfeiler", "fahrbahn": "Fahrbahn",
				"gelaender": "Geländer", "abnahme": "Abnahme", "wartet": "wartet auf Material"}.get(phase, phase)
			draw_string(ThemeDB.fallback_font, _s(mid - Vector2(0.5, 0.5), z + 1.6) + Vector2(-60, 0), "%s %d %%" % [lbl, int(progress * 100.0)],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.9))

	## Mannschaft und Maschinen je Phase. Ufer A = points[0] (Lagerstaettenseite), Ufer B = letzter Punkt (Strassenseite, Bauleitung).
	func _draw_crew(L: Dictionary) -> void:
		var s := Callable(self, "_s")
		var a: Vector2 = points[0]
		var b: Vector2 = points[points.size() - 1]
		var d := (a - b).normalized()          # von der Strassenseite uebers Wasser
		var nrm := Vector2(-d.y, d.x)
		var z := BridgeView.DECK_Z
		var orange := Color("f28c28")
		CrewArt.site_office(self, s, b - d * 1.6 + nrm * 1.3, firm, builder)
		CrewArt.stack(self, s, b - d * 1.2 - nrm * 1.2, variant, 1.0 - progress * 0.8)
		if phase in ["ausgeschrieben", "wartet"] or not working:
			CrewArt.worker(self, s, b - d * 0.6 + nrm * 0.8, t, "messen", orange, firm, 1)
			CrewArt.worker(self, s, b - d * 1.0 + nrm * 0.4, t, "winken", Color("ffffff"), firm, 2)
			return
		match phase:
			"widerlager":
				CrewArt.mixer(self, s, b - d * 0.9 - nrm * 0.2, d, t, firm)
				for i in 2:
					var e: Vector2 = a if i == 0 else b
					CrewArt.worker(self, s, e + d * (0.3 if i == 1 else -0.3) + nrm * 0.45, t, "haemmern", orange, firm, 3 + i)
					CrewArt.worker(self, s, e - nrm * 0.45, t, "schaufeln", orange, firm, 5 + i)
			"pfeiler":
				var k := clampi(int((progress - 0.25) / 0.25 * float(points.size() - 2)), 0, points.size() - 3)
				var pier: Vector2 = points[1 + k]
				CrewArt.pile_driver(self, s, b - d * 0.4 + nrm * 0.1, (pier - b).normalized(), t, true)
				CrewArt.worker(self, s, b - d * 0.2 - nrm * 0.6, t, "winken", Color("ffffff"), firm, 7)
				CrewArt.worker(self, s, b + d * 0.1 + nrm * 0.6, t, "tragen", orange, firm, 8)
			"fahrbahn":
				var segs := float(points.size() - 1)
				var k2 := clampf((progress - 0.5) / 0.3, 0.0, 1.0) * segs
				var tip: Vector2 = points[mini(int(k2), points.size() - 2)].lerp(points[mini(int(k2) + 1, points.size() - 1)], fmod(k2, 1.0))
				var lift := 0.5 + 0.5 * sin(t * 0.7)
				CrewArt.crane(self, s, b - d * 0.8 - nrm * 0.9, tip, lift, L.deck)
				CrewArt.dump_truck(self, s, b - d * 1.8 - nrm * 0.1, -d, firm, true)
				CrewArt.worker(self, s, tip - d * 0.4 + nrm * 0.2, t, "winken", orange, firm, 9)
				CrewArt.worker(self, s, tip - d * 0.7 - nrm * 0.2, t, "haemmern", orange, firm, 10)
			"gelaender":
				for i in 3:
					var q: Vector2 = points[0].lerp(b, 0.25 + 0.25 * i)
					_worker_on_deck(q + nrm * 0.3 * (1 if i % 2 == 0 else -1), "haemmern", 11 + i, z, firm)
			"abnahme":
				_worker_on_deck(a.lerp(b, 0.5), "messen", 15, z, firm, Color("ffffff"))
				_worker_on_deck(a.lerp(b, 0.35), "winken", 16, z, firm)

	## Arbeiter auf der Fahrbahn (um die Deckhoehe angehoben).
	func _worker_on_deck(at: Vector2, action: String, seed_v: int, z: float, f: Color, vest: Color = Color("f28c28")) -> void:
		var raised := func(w: Vector2, h: float) -> Vector2: return _s(w, h + z)
		CrewArt.worker(self, raised, at, t, action, vest, f, seed_v)


## Wegebau einer Zufahrt: Trasse abgesteckt, Arbeitsfront mit Bagger, Kipplaster, Walze und Kolonne. Knoten sitzt an der Front.
class RoadWorksNode extends Node2D:
	var cells: Array = []          # Vector2 in Bauordnung (von der Strasse weg)
	var built := 0
	var front := 0.0
	var working := false
	var firm := Color("e07a2a")
	var builder := ""
	var note := ""
	var t := 0.0

	func _s(w: Vector2, z: float) -> Vector2:
		return Iso.to_screen((w + Vector2(0.5, 0.5)) * 32.0) - position + Vector2(0, -z * BridgeView.STEP)

	func _at(f: float) -> Vector2:
		var i := clampi(int(f), 0, cells.size() - 1)
		var j := mini(i + 1, cells.size() - 1)
		return (cells[i] as Vector2).lerp(cells[j], f - float(i))

	func _dir(f: float) -> Vector2:
		var i := clampi(int(f), 0, cells.size() - 2)
		var d: Vector2 = cells[i + 1] - cells[i] if cells.size() > 1 else Vector2(1, 0)
		return d.normalized() if d != Vector2.ZERO else Vector2(1, 0)

	func _cell(c: Vector2, col: Color) -> void:
		draw_colored_polygon(PackedVector2Array([_s(c + Vector2(-0.5, -0.5), 0.02), _s(c + Vector2(0.5, -0.5), 0.02), _s(c + Vector2(0.5, 0.5), 0.02), _s(c + Vector2(-0.5, 0.5), 0.02)]), col)

	func _draw() -> void:
		if cells.is_empty():
			return
		var s := Callable(self, "_s")
		var fi := int(front)
		# Trasse: Pfloecke im Abstand von drei Feldern ueber die naechsten 45 Felder
		for k in range(fi + 2, mini(cells.size(), fi + 45), 3):
			var c: Vector2 = cells[k]
			draw_line(_s(c, 0.0), _s(c, 0.6), Color("e07a2a"), 2.5)
			draw_rect(Rect2(_s(c, 0.6) + Vector2(-2, -2), Vector2(4, 3)), Color("f0ece4"))
		# heute bearbeitete Felder: Planum (Erde) an der Front, dahinter Schotter
		for k in range(built, mini(fi + 1, cells.size())):
			_cell(cells[k], Color("8a6a48") if k > fi - 3 else Color("9a968c"))
		var d := _dir(front)
		var nrm := Vector2(-d.y, d.x)
		var orange := Color("f28c28")
		var head := _at(front)
		if not working:
			CrewArt.excavator(self, s, head + d * 0.3 + nrm * 0.9, d, t, false)
			CrewArt.worker(self, s, head + nrm * 0.5, t, "messen", orange, firm, 1)
			CrewArt.worker(self, s, head - d * 0.6 - nrm * 0.5, t, "winken", Color("ffffff"), firm, 2)
			if note != "":
				draw_string(ThemeDB.fallback_font, _s(head, 3.0) + Vector2(-70, 0), "%s – %s" % [builder, note], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.9))
			return
		# Bagger an der Front, graebt das naechste Feld
		CrewArt.excavator(self, s, head - d * 0.2 + nrm * 0.05, d, t, true)
		# Kipplaster pendelt zwischen fertigem Weg und Front (Schotter hin, leer zurueck)
		var back := maxf(0.0, front - 9.0)
		var k := fmod(t * 0.12, 2.0)
		var going := k < 1.0
		var tf := lerpf(back, front - 1.6, k if going else 2.0 - k)
		var tdir := _dir(tf) * (1.0 if going else -1.0)
		CrewArt.dump_truck(self, s, _at(tf) + nrm * 0.12, tdir, firm, going, 0.0)
		# Walze verdichtet die Schotterfelder hinter der Front
		var r0 := maxf(float(built) - 1.0, front - 6.0)
		var rk := 0.5 + 0.5 * sin(t * 0.5)
		CrewArt.roller(self, s, _at(lerpf(r0, maxf(r0, front - 2.5), rk)) - nrm * 0.12, _dir(r0))
		# Kolonne: zwei schaufeln am Planum, einer misst voraus, einer weist den Laster ein
		CrewArt.worker(self, s, _at(front - 1.0) + nrm * 0.55, t, "schaufeln", orange, firm, 3)
		CrewArt.worker(self, s, _at(front - 1.4) - nrm * 0.55, t, "schaufeln", orange, firm, 4)
		CrewArt.worker(self, s, _at(minf(front + 3.0, float(cells.size() - 1))) + nrm * 0.3, t, "messen", orange, firm, 5)
		CrewArt.worker(self, s, _at(tf) + nrm * 0.75 - tdir * 0.6, t, "winken", Color("ffffff"), firm, 6)
		draw_string(ThemeDB.fallback_font, _s(head, 3.2) + Vector2(-60, 0), builder, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.85))
