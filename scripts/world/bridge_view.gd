class_name BridgeView
extends Node2D
## Bruecken sichtbar (Auftrag 15, Etappe D): Baufortschritt in Phasen (Widerlager, Pfeiler, Fahrbahn, Gelaender, Abnahme),
## Absperrung bis zur Freigabe, Aussehen je Variante (Holz, Stein, Stahlbeton). Liest nur aus der Simulation; prozedural gezeichnet.

const STEP := 18.0                # Bildschirmhoehe je Hoehenstufe (wie ShipView)
const DECK_Z := 0.7               # Fahrbahnhoehe ueber dem Wasser

var sim: Simulation
var _nodes := {}                  # Bruecken-ID -> BridgeNode


func setup(simulation: Simulation) -> void:
	sim = simulation


func update_view(_delta: float) -> void:
	for id in sim.bridges.items:
		var b: Dictionary = sim.bridges.items[id]
		var n: BridgeNode = _nodes.get(id)
		if n == null:
			n = BridgeNode.new()
			n.configure(b)
			add_child(n)
			_nodes[id] = n
		var p := snappedf(sim.bridges.progress(b), 0.02)
		var ph := sim.bridges.phase(b)
		if p != n.progress or ph != n.phase:
			n.progress = p
			n.phase = ph
			n.queue_redraw()


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
			var lbl: String = {"ausgeschrieben": "Brücke ausgeschrieben", "widerlager": "Widerlager", "pfeiler": "Pfeiler", "fahrbahn": "Fahrbahn",
				"gelaender": "Geländer", "abnahme": "Abnahme", "wartet": "wartet auf Material"}.get(phase, phase)
			draw_string(ThemeDB.fallback_font, _s(mid - Vector2(0.5, 0.5), z + 1.6) + Vector2(-60, 0), "%s %d %%" % [lbl, int(progress * 100.0)],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.9))
