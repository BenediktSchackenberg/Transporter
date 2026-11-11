class_name WasteView
extends Node2D
## Muellabfuhr sichtbar (Waste, CityFleet): Deponie am Stadtrand als wachsender Muellberg mit Planierraupe, Moewen und Abladestaub;
## an jedem Halt eines Muellwagens leeren zwei Muellwerker die Tonnen (Hin- und Rueckweg mit Tonne, Kippen am Wagen).
## Liest nur aus der Simulation; zeichnet prozedural in der Iso-Projektion.

const STEP := 18.0
const ORANGE := Color("f28c28")

var sim: Simulation
var landfill: LandfillNode
var _crews := {}          # Fahrzeug-ID -> CrewNode
var _clock := 0.0


func setup(simulation: Simulation) -> void:
	sim = simulation
	y_sort_enabled = true
	if sim.waste.landfill_pid != "":
		landfill = LandfillNode.new()
		landfill.view = self
		landfill.configure()
		add_child(landfill)


func update_view(delta: float) -> void:
	_clock += delta
	if landfill != null:
		landfill.t = _clock
		landfill.queue_redraw()
	var seen := {}
	for v in sim.fleet.vehicles:
		if v.kind != "muell" and v.kind != "wertstoff" or v.phase != "leeren":
			continue
		var id := int(v.id)
		seen[id] = true
		var n: CrewNode = _crews.get(id)
		if n == null:
			n = CrewNode.new()
			add_child(n)
			_crews[id] = n
		n.stream = str(v.get("stream", "rest"))
		var m: Mover = v.mover
		var b: Dictionary = sim.city.building(int(v.stops[int(v.stop)].building))
		n.truck = m.pos
		n.house = Vector2(float(b.x) + float(b.w) * 0.5, float(b.y) + float(b.h) * 0.5) * 32.0
		n.position = Iso.to_screen(m.pos)
		n.t = _clock
		n.queue_redraw()
	for id in _crews.keys():
		if not seen.has(id):
			_crews[id].queue_free()
			_crews.erase(id)


## Deponie unter dem Mauszeiger (Weltposition)?
func pick_landfill(world: Vector2) -> bool:
	if landfill == null:
		return false
	var p: Dictionary = sim.parcels.parcel(sim.waste.landfill_pid)
	return Rect2(float(p.rect[0]) * 32.0, float(p.rect[1]) * 32.0, float(p.rect[2]) * 32.0, float(p.rect[3]) * 32.0).has_point(world)


func landfill_center() -> Vector2:
	var p: Dictionary = sim.parcels.parcel(sim.waste.landfill_pid)
	return Vector2(float(p.rect[0]) + float(p.rect[2]) * 0.5, float(p.rect[1]) + float(p.rect[3]) * 0.5) * 32.0


class LandfillNode extends Node2D:
	var view
	var cells := {}
	var rect := Rect2i()
	var origin := Vector2.ZERO
	var t := 0.0

	func configure() -> void:
		cells = view.sim.waste.landfill_cells
		var p: Dictionary = view.sim.parcels.parcel(view.sim.waste.landfill_pid)
		rect = Rect2i(int(p.rect[0]), int(p.rect[1]), int(p.rect[2]), int(p.rect[3]))
		origin = Vector2(rect.end) * 32.0
		position = Iso.to_screen(origin)

	func _s(w: Vector2) -> Vector2:
		return Iso.to_screen(w) - Iso.to_screen(origin)

	func _rnd(c: Vector2i, k: int) -> float:
		return float(absi(hash([c, k, "deponie"])) % 1000) / 1000.0

	func _h(c: Vector2i) -> float:
		var f: float = float(cells.get(c, 0.0))
		return (1.2 + 7.0 * view.sim.waste.fill_share()) * pow(f, 0.7)   # Kuppel, waechst mit dem Fuellstand

	func _draw() -> void:
		var order: Array = cells.keys()
		order.sort_custom(func(a, b): return a.x + a.y < b.x + b.y)
		var dozer_c: Vector2i = order[int(order.size() * (0.5 + 0.3 * sin(t * 0.2)))] if not order.is_empty() else Vector2i.ZERO
		for c in order:
			var L := _h(c)
			var up := Vector2(0, -L * WasteView.STEP)
			var n := _s(Vector2(c) * 32.0)
			var e := _s(Vector2(c.x + 1, c.y) * 32.0)
			var so := _s(Vector2(c.x + 1, c.y + 1) * 32.0)
			var w := _s(Vector2(c.x, c.y + 1) * 32.0)
			var lw: float = _h(c + Vector2i(0, 1)) if cells.has(c + Vector2i(0, 1)) else 0.0
			var le: float = _h(c + Vector2i(1, 0)) if cells.has(c + Vector2i(1, 0)) else 0.0
			if lw < L:
				draw_colored_polygon(PackedVector2Array([w + up, so + up, so + Vector2(0, -lw * WasteView.STEP), w + Vector2(0, -lw * WasteView.STEP)]), Color("5e5242"))
			if le < L:
				draw_colored_polygon(PackedVector2Array([so + up, e + up, e + Vector2(0, -le * WasteView.STEP), so + Vector2(0, -le * WasteView.STEP)]), Color("4a4034"))
			var top := Color("7a6c56").lerp(Color("8a8270"), _rnd(c, 1))
			draw_colored_polygon(PackedVector2Array([n + up, e + up, so + up, w + up]), top)
			var mid := (n + e + so + w) * 0.25 + up
			for k in 7:   # Abfallbrocken: Saecke, Kartons, Kanister
				var col: Color = [Color("3d6fb0"), Color("c8463c"), Color("e8e4dc"), Color("2f8a4a"), Color("d9b64a"), Color("1f1f1f"), Color("9b6a3a")][int(_rnd(c, 10 + k) * 7.0) % 7]
				var bp := mid + Vector2((_rnd(c, 20 + k) - 0.5) * 50.0, (_rnd(c, 30 + k) - 0.5) * 20.0)
				var sz := Vector2(5 + 5.0 * _rnd(c, 40 + k), 4 + 3.0 * _rnd(c, 50 + k))
				draw_rect(Rect2(bp - Vector2(0, sz.y), sz), col)
				draw_rect(Rect2(bp - Vector2(0, sz.y), Vector2(sz.x, 1)), col.lightened(0.25))
			if c == dozer_c:   # Planierraupe schiebt den Muell
				var d := mid + Vector2(10.0 * sin(t * 0.9), 0)
				draw_set_transform(d, 0.0, Vector2(2.0, 2.0))
				draw_rect(Rect2(Vector2(-10, -3), Vector2(20, 4)), Color("2b2b2b"))
				draw_rect(Rect2(Vector2(-8, -11), Vector2(14, 8)), Color("e0a526"))
				draw_rect(Rect2(Vector2(-5, -16), Vector2(7, 5)), Color("c98c14"))
				draw_rect(Rect2(Vector2(6, -9), Vector2(4, 8)), Color("6a6a6a"))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# Bauzaun um die Deponie
		var fa := _s(Vector2(rect.position) * 32.0)
		var fb := _s(Vector2(rect.end.x, rect.position.y) * 32.0)
		var fc := _s(Vector2(rect.end) * 32.0)
		var fd := _s(Vector2(rect.position.x, rect.end.y) * 32.0)
		for seg in [[fa, fb], [fb, fc], [fc, fd], [fd, fa]]:
			draw_line(seg[0] + Vector2(0, -10), seg[1] + Vector2(0, -10), Color(0.75, 0.75, 0.72, 0.8), 1.5)
			for k in 12:
				var q: Vector2 = seg[0].lerp(seg[1], float(k) / 12.0)
				draw_line(q, q + Vector2(0, -12), Color(0.55, 0.55, 0.52), 1.5)
		# Moewen kreisen
		var center := _s((Vector2(rect.position) + Vector2(rect.size) * 0.5) * 32.0) + Vector2(0, -140.0 * view.sim.waste.fill_share() - 60.0)
		for k in 6:
			var a := t * (0.5 + 0.1 * float(k)) + float(k) * TAU / 6.0
			var p := center + Vector2(cos(a) * (60.0 + 10.0 * float(k)), sin(a) * 24.0 - 8.0 * float(k % 3))
			var flap := 4.0 * sin(t * 10.0 + float(k))
			draw_polyline(PackedVector2Array([p + Vector2(-7, flap), p, p + Vector2(7, flap)]), Color(0.97, 0.97, 0.97), 2.0)
		# Abladender Muellwagen: Staubwolke an der Zufahrt
		for v in view.sim.fleet.vehicles:
			if v.kind == "muell" and v.phase == "abladen":
				var m: Mover = v.mover
				var q := Iso.to_screen(m.pos) - position
				for k in 5:
					var u := fmod(t * 0.5 + float(k) * 0.2, 1.0)
					draw_circle(q + Vector2(-20.0 + 10.0 * float(k), -20.0 - 30.0 * u), 8.0 + 12.0 * u, Color(0.6, 0.55, 0.45, 0.35 * (1.0 - u)))


class CrewNode extends Node2D:
	var truck := Vector2.ZERO          # Weltposition des Wagens
	var house := Vector2.ZERO          # Weltposition des Hauses
	var t := 0.0
	var stream := "rest"               # "rest" (Orange, Resttonne) oder "wert" (Gruen, Bio- und Wertstofftonnen)

	func _draw() -> void:
		var body := ORANGE if stream == "rest" else Color("3f8a4a")
		var bin := truck.lerp(house, 0.35)          # Tonnenplatz am Gehweg
		var b := Iso.to_screen(bin) - position
		var back := Iso.to_screen(truck + (truck - house).normalized() * -4.0) - position
		for k in 2:   # zwei Muellwerker: Tonne holen, am Wagen kippen, zurueckbringen
			var cyc := fmod(t * 0.35 + float(k) * 0.5, 1.0)
			var u := cyc * 2.0 if cyc < 0.5 else 2.0 - cyc * 2.0
			var pos := b.lerp(back + Vector2(8.0 * float(k) - 4.0, 0), u) + Vector2(10.0 * float(k), 4.0 * float(k))
			draw_set_transform(pos, 0.0, Vector2(1.8, 1.8))
			var bob := sin(t * 9.0 + float(k))
			draw_rect(Rect2(Vector2(-2, -9 + bob), Vector2(5, 7)), body)
			draw_rect(Rect2(Vector2(-2, -6 + bob), Vector2(5, 1)), Color("e8e8e8"))   # Reflexstreifen
			draw_rect(Rect2(Vector2(-2, -2), Vector2(5, 2)), Color("2f343c"))
			draw_rect(Rect2(Vector2(-2, -13 + bob), Vector2(5, 4)), Color("e0b48a"))
			draw_rect(Rect2(Vector2(-3, -14 + bob), Vector2(7, 2)), body)
			var tipping := u > 0.92
			# rest: Resttonne (grau) und Bio (gruen); wert: Bio (gruen) und Wertstoffe (blau)
			var bin_col := Color("4a6b3f") if k == 0 else (Color("6b6f78") if stream == "rest" else Color("3d6fb0"))
			if tipping:
				draw_colored_polygon(PackedVector2Array([Vector2(4, -16), Vector2(12, -18), Vector2(13, -10), Vector2(6, -8)]), bin_col)
				draw_circle(Vector2(10, -20), 2.0, Color("8a7a60"))
			else:
				draw_rect(Rect2(Vector2(4, -10), Vector2(7, 9)), bin_col)
				draw_rect(Rect2(Vector2(4, -11), Vector2(7, 2)), bin_col.darkened(0.3))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# Tonnen, die noch am Gehweg warten
		for k in 2:
			var p := b + Vector2(-14.0 - 8.0 * float(k), 6.0)
			var c2 := Color("4a6b3f") if k == 0 else (Color("6b6f78") if stream == "rest" else Color("3d6fb0"))
			draw_rect(Rect2(p + Vector2(0, -16), Vector2(11, 15)), c2)
			draw_rect(Rect2(p + Vector2(0, -18), Vector2(11, 3)), Color("2f3a2a"))
