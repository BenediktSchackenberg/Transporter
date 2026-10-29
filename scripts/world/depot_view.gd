class_name DepotView
extends Node2D
## Sichtbare Lagerarbeit am kommunalen Zentrallager (Auftrag 5, Abschnitte 7 und 8). Liest nur aus Simulation.city_depot und dem StockBook.
##
## Immer sichtbar: Lkw an den Entladerampen und in der Warteschlange, Lagerarbeiter am Wareneingang, Paletten auf dem Vorplatz.
## Bei Auswahl des Lagers (oder eines Warenpostens) wird das Dach ausgeblendet und eine Innenansicht gezeichnet: Wareneingang mit Rampen,
## Pruefbereich, Lagerzonen mit Paletten (ihre Zahl folgt dem tatsaechlichen Bestand), Kommissionierung, Warenausgang, Buero, Stapler und
## Mitarbeiter mit ihren aktuellen Aufgaben. Paletten sind anklickbar (Herkunft, Eigentuemer, Menge, Standort, Auftrag).

const WALL_H := 18.0
const ZONE_AREAS := {            # lokale Flaechen (a entlang der Laderseite, d Tiefe ab der Laderseite), je [a0, d0, a1, d1]
	"rampe": [0.0, 0.0, 1.0, 0.16],
	"pruefung": [0.0, 0.18, 0.28, 0.42],
	"regal": [0.30, 0.18, 0.74, 0.58],
	"schuettgut": [0.76, 0.18, 1.0, 0.44],
	"lebensmittel": [0.76, 0.46, 1.0, 0.58],
	"kraftstoff": [0.30, 0.62, 0.52, 0.84],
	"geraete": [0.54, 0.62, 0.74, 0.84],
	"kommission": [0.0, 0.46, 0.28, 0.72],
	"ausgang": [0.0, 0.76, 0.42, 1.0],
	"buero": [0.76, 0.62, 1.0, 1.0],
}
const ZONE_COLORS := {"rampe": Color("5d6068"), "pruefung": Color("c9a63a"), "regal": Color("7b8aa0"), "schuettgut": Color("8c7a58"), "lebensmittel": Color("5ca0b0"),
	"kraftstoff": Color("a8503e"), "geraete": Color("6a8d5a"), "kommission": Color("7a6aa8"), "ausgang": Color("c4783a"), "buero": Color("9a9a9a")}
const ZONE_LABELS := {"rampe": "Wareneingang", "pruefung": "Prüfbereich", "regal": "Regallager", "schuettgut": "Schüttgut", "lebensmittel": "Kühllager", "kraftstoff": "Tanklager",
	"geraete": "Geräte", "kommission": "Kommissionierung", "ausgang": "Warenausgang", "buero": "Büro · Personal"}
const GROUP_COLORS := {"strassenunterbau": Color("a89878"), "strassenoberflaechen": Color("4a4a50"), "verkehrsfuehrung": Color("e0a030"), "elektro": Color("4a7ab8"), "leitungen": Color("4a9a8a"),
	"gebaeude": Color("b86a4a"), "gruenpflege": Color("5a9a4a"), "winterdienst": Color("d8d8e0"), "reinigung": Color("5aa8c8"), "verwaltung": Color("c8b890"), "schule": Color("d86a8a"),
	"einsatz": Color("d04a4a"), "fuhrpark": Color("707078"), "betriebsmittel": Color("a8503e"), "geraete": Color("c8a820")}
const ROLE_COLORS := {"vorarbeiter": Color("f2f2f2"), "stapler": Color("f2c14e"), "lager": Color("f28c28"), "kommission": Color("8a6ad8")}

var sim: Simulation
var cv
var node: DepotNode
var _t := 0.0
var _clock := 0.0
var _open := false
var _hidden: Array = []


func setup(simulation: Simulation, city_view) -> void:
	sim = simulation
	cv = city_view
	node = DepotNode.new()
	node.view = self
	add_child(node)
	_place()


func _footprint() -> Rect2:
	var b: Dictionary = sim.city.building(sim.city_depot.building)
	return Rect2(float(b.x) * 32.0, float(b.y) * 32.0, float(b.w) * 32.0, float(b.h) * 32.0)


## Seite der Zufahrt: 0 unten (hohe y), 1 oben, 2 rechts (hohe x), 3 links
func _dock_side() -> int:
	var b: Dictionary = sim.city.building(sim.city_depot.building)
	var r := _footprint()
	var road := Vector2(float(b.road.x) * 32.0 + 16.0, float(b.road.y) * 32.0 + 16.0)
	var c := r.get_center()
	var dx := (road.x - c.x) / r.size.x
	var dy := (road.y - c.y) / r.size.y
	if absf(dx) > absf(dy):
		return 2 if dx > 0.0 else 3
	return 0 if dy > 0.0 else 1


## Lokale Koordinaten (a entlang der Laderseite, d Tiefe) in Weltkoordinaten
func local_to_world(a: float, d: float) -> Vector2:
	var r := _footprint()
	match _dock_side():
		0: return Vector2(r.position.x + a * r.size.x, r.end.y - d * r.size.y)
		1: return Vector2(r.position.x + (1.0 - a) * r.size.x, r.position.y + d * r.size.y)
		2: return Vector2(r.end.x - d * r.size.x, r.position.y + (1.0 - a) * r.size.y)
	return Vector2(r.position.x + d * r.size.x, r.position.y + a * r.size.y)


func _place() -> void:
	var r := _footprint()
	node.position = Iso.to_screen(Vector2(r.end.x, r.end.y))
	node.origin = Vector2(r.end.x, r.end.y)


func update_view(delta: float, selected: Dictionary) -> void:
	_clock += delta
	var want: bool = (selected.get("kind", "") == "building" and int(selected.get("id", -1)) == sim.city_depot.building) or selected.get("kind", "") == "lot"
	if want != _open:
		_open = want
		var parts: Array = cv._building_parts.get(sim.city_depot.building, [])
		for p in parts:
			p.visible = not _open          # Dach und Waende ausblenden
		node.interior = _open
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var size := get_viewport_rect().size / cam.zoom
	var view := Rect2(cam.get_screen_center_position() - size * 0.5, size).grow(300.0)
	if not view.has_point(node.position):
		return
	_t += delta
	if _t >= 1.0 or node.layout.is_empty():
		_t = 0.0
		node.tasks = sim.city_depot.current_tasks()
		node.layout = _layout()
		node.ramps = sim.city_depot.ramps
	node.t = _clock
	node.queue_redraw()


## Paletten je Lagerbereich: Anzahl entspricht dem Fuellstand, Zuordnung zu den Posten nach Menge.
func _layout() -> Array:
	var D: CityDepot = sim.city_depot
	var out: Array = []
	for zone in CityGoods.ZONES:
		var lots: Array = sim.stock.lots.values().filter(func(l): return l.owner == CityDepot.OWNER and l.loc == D.building and str(CityGoods.get_item(l.item).get("zone", "")) == zone)
		if lots.is_empty():
			continue
		lots.sort_custom(func(a, b): return str(a.id) < str(b.id))
		var used := 0
		for l in lots:
			used += int(l.qty)
		var slots := _slots(zone)
		var fill := clampf(float(used) / float(CityGoods.ZONES[zone].cap), 0.0, 1.0)
		var count := clampi(int(ceil(fill * float(slots.size()))), 1, slots.size())
		var acc := 0.0
		var li := 0
		for i in count:
			var target := (float(i) + 0.5) / float(count) * float(used)
			while li < lots.size() - 1 and acc + float(lots[li].qty) < target:
				acc += float(lots[li].qty)
				li += 1
			out.append({"zone": zone, "slot": slots[i], "lot": lots[li].id, "item": lots[li].item, "state": lots[li].get("state", "ok")})
	return out


func _slots(zone: String) -> Array:
	var a: Array = ZONE_AREAS[zone]
	var cols := 6 if zone in ["regal", "schuettgut"] else 3
	var rows := 4 if zone == "regal" else 3
	var out: Array = []
	for j in rows:
		for i in cols:
			out.append(Vector2(lerpf(a[0] + 0.02, a[2] - 0.02, (float(i) + 0.5) / float(cols)), lerpf(a[1] + 0.02, a[3] - 0.02, (float(j) + 0.5) / float(rows))))
	return out


## Warenposten unter dem Mauszeiger (Bildschirmkoordinaten der Kamera) -> Posten-ID oder "".
func pick_lot(click: Vector2) -> String:
	if not _open:
		return ""
	var best := ""
	var best_d := 14.0
	for p in node.layout:
		var sp: Vector2 = Iso.to_screen(local_to_world(p.slot.x, p.slot.y)) + Vector2(0, -5)
		var d := sp.distance_to(click)
		if d < best_d:
			best_d = d
			best = str(p.lot)
	return best


class DepotNode extends Node2D:
	var view: DepotView
	var origin := Vector2.ZERO
	var interior := false
	var layout: Array = []
	var tasks := {}
	var ramps := 2
	var t := 0.0

	func _s(a: float, d: float) -> Vector2:
		return Iso.to_screen(view.local_to_world(a, d)) - Iso.to_screen(origin)

	func _quad(a0: float, d0: float, a1: float, d1: float, col: Color) -> void:
		draw_colored_polygon(PackedVector2Array([_s(a0, d0), _s(a1, d0), _s(a1, d1), _s(a0, d1)]), col)

	func _outline(a0: float, d0: float, a1: float, d1: float, col: Color, w := 1.5) -> void:
		draw_polyline(PackedVector2Array([_s(a0, d0), _s(a1, d0), _s(a1, d1), _s(a0, d1), _s(a0, d0)]), col, w)

	func _box(p: Vector2, w: float, h: float, col: Color) -> void:
		draw_rect(Rect2(p + Vector2(-w * 0.5, -h), Vector2(w, h)), col)
		draw_rect(Rect2(p + Vector2(-w * 0.5, -h), Vector2(w, 2.0)), col.lightened(0.25))

	func _draw() -> void:
		var D: CityDepot = view.sim.city_depot
		if interior:
			_draw_interior(D)
		_draw_yard(D)

	## Vorplatz: Lkw an den Rampen, wartende Lkw, Paletten und Arbeiter am Wareneingang
	func _draw_yard(D: CityDepot) -> void:
		var unloading: Array = D.trucks_here(["unloading"])
		var waiting: Array = D.trucks_here(["waiting_bay"])
		for i in unloading.size():
			var a := (float(i) + 0.5) / float(maxi(ramps, 1))
			_truck(_s(a, -0.12), view.sim.company(unloading[i].owner).color)
			_box(_s(a, -0.04) + Vector2(5, 0), 6, 5, Color("c8a24a"))
		for i in waiting.size():
			_truck(_s(0.12 + 0.2 * float(i), -0.5 - 0.1 * float(i)), view.sim.company(waiting[i].owner).color.darkened(0.2))
			draw_circle(_s(0.12 + 0.2 * float(i), -0.5 - 0.1 * float(i)) + Vector2(0, -26), 4.0, Color("e07a5f"))   # wartet
		if not interior:
			var n := 0
			for tk in tasks.get("tasks", []):
				if tk.task in ["entlädt", "prüft Ware", "bringt Palette ins Lager"] and n < 4:
					_worker(_s((float(n) + 0.5) / 4.0, -0.04 - 0.03 * sin(t * 1.2 + float(n))), tk.role, true)
					n += 1

	func _truck(p: Vector2, col: Color) -> void:
		draw_rect(Rect2(p + Vector2(-14, -12), Vector2(20, 10)), col)
		draw_rect(Rect2(p + Vector2(6, -10), Vector2(8, 8)), Color("d8d8d8"))
		draw_circle(p + Vector2(-8, -1), 2.5, Color("2b2b2b"))
		draw_circle(p + Vector2(8, -1), 2.5, Color("2b2b2b"))

	func _worker(p: Vector2, role: String, busy: bool) -> void:
		var vest: Color = DepotView.ROLE_COLORS.get(role, Color("f28c28"))
		var bob := 1.0 * sin(t * 8.0 + p.x) if busy else 0.0
		draw_rect(Rect2(p + Vector2(-2, -8 + bob), Vector2(4, 6)), vest)
		draw_rect(Rect2(p + Vector2(-2, -2), Vector2(4, 2)), Color("3a3f4a"))
		draw_rect(Rect2(p + Vector2(-2, -12 + bob), Vector2(4, 4)), Color("e0b48a"))
		draw_rect(Rect2(p + Vector2(-3, -13 + bob), Vector2(6, 2)), Color("f2c14e"))

	func _draw_interior(D: CityDepot) -> void:
		var wall := Color("8f8a80")
		_quad(0.0, 0.0, 1.0, 1.0, Color("56585f"))
		for zone in DepotView.ZONE_AREAS:
			var a: Array = DepotView.ZONE_AREAS[zone]
			var col: Color = DepotView.ZONE_COLORS[zone]
			_quad(a[0], a[1], a[2], a[3], Color(col.r, col.g, col.b, 0.45))
			_outline(a[0], a[1], a[2], a[3], col.lightened(0.2), 1.0)
		# Rampen
		for i in ramps:
			var a0 := float(i) / float(ramps)
			_quad(a0 + 0.015, 0.0, a0 + 1.0 / float(ramps) - 0.015, 0.05, Color("2f3136"))
		# Waende: nur die beiden hinteren Kanten sind hoch, die vorderen niedrig (Einblick)
		var back := Vector2(0, -DepotView.WALL_H)
		for edge in [[Vector2(0, 1), Vector2(1, 1)], [Vector2(0, 0), Vector2(0, 1)]]:
			var p0: Vector2 = _s(edge[0].x, edge[0].y)
			var p1: Vector2 = _s(edge[1].x, edge[1].y)
			draw_colored_polygon(PackedVector2Array([p0, p1, p1 + back, p0 + back]), wall)
			draw_polyline(PackedVector2Array([p0 + back, p1 + back]), Color("5a564f"), 2.0)
		# Paletten (Anzahl folgt dem Bestand)
		var font := ThemeDB.fallback_font
		for p in layout:
			var pos := _s(p.slot.x, p.slot.y)
			var g: String = str(CityGoods.get_item(p.item).get("group", ""))
			var col: Color = DepotView.GROUP_COLORS.get(g, Color("b09060"))
			if p.state == "pruefung":
				col = col.lightened(0.3)
			draw_rect(Rect2(pos + Vector2(-5, -2), Vector2(10, 3)), Color("8a6a3a"))
			_box(pos + Vector2(0, -2), 8, 7, col)
		for zone in ["rampe", "pruefung", "regal", "schuettgut", "lebensmittel", "kraftstoff", "geraete", "kommission", "ausgang", "buero"]:
			var a2: Array = DepotView.ZONE_AREAS[zone]
			var lp := _s((a2[0] + a2[2]) * 0.5, a2[1] + 0.02) + Vector2(-26, 9)
			draw_string(font, lp, DepotView.ZONE_LABELS[zone], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 1, 1, 0.85))
		# Mitarbeiter und Stapler an ihren Aufgaben
		var k := 0
		for tk in tasks.get("tasks", []):
			var pos2 := _task_pos(tk, k)
			var busy: bool = tk.task not in ["bereit", "organisiert den Ablauf"]
			if tk.role == "stapler" and tk.task in ["bringt Palette ins Lager", "verlädt Ware"]:
				_box(pos2 + Vector2(9, 1), 10, 6, Color("e0b020"))
				draw_line(pos2 + Vector2(14, -4), pos2 + Vector2(14, 1), Color("333333"), 1.0)
			_worker(pos2, tk.role, busy)
			draw_string(font, pos2 + Vector2(-18, 8), str(tk.name).get_slice(" ", 0), HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(1, 1, 1, 0.8))
			k += 1

	func _task_pos(tk: Dictionary, k: int) -> Vector2:
		var wiggle := 0.03 * sin(t * 0.9 + float(k) * 1.7)
		match str(tk.task):
			"entlädt":
				return _s(0.2 + 0.6 * float(k % 3) / 2.0, 0.11 + wiggle)
			"prüft Ware":
				return _s(0.14 + 0.04 * float(k % 3), 0.3 + wiggle)
			"bringt Palette ins Lager":
				var u := 0.5 + 0.5 * sin(t * 0.8 + float(k))
				return _s(lerpf(0.2, 0.5, u), lerpf(0.3, 0.38, u))
			"stellt Lieferung zusammen":
				return _s(0.14 + 0.05 * float(k % 3), 0.58 + wiggle)
			"verlädt Ware":
				var u2 := 0.5 + 0.5 * sin(t * 0.8 + float(k))
				return _s(lerpf(0.1, 0.36, u2), 0.88)
			"organisiert den Ablauf":
				return _s(0.62 + 0.1 * sin(t * 0.3), 0.6 + wiggle)
		return _s(0.82 + 0.04 * float(k % 4), 0.7 + 0.04 * float(k % 3))
