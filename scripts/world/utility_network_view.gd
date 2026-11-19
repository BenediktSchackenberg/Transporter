class_name UtilityNetworkView
extends Node2D
## Sichtbare Ortsnetze und lebendige Anlagen. V wechselt zwischen allen Netzen,
## Strom, Frischwasser, Kanal und nur den Anlagen. Die Leitungen liegen auf Straßen.

const POWER := Color(1.0, 0.79, 0.25, 0.42)
const WATER := Color(0.20, 0.78, 1.0, 0.48)
const SEWER := Color(0.44, 0.82, 0.52, 0.43)
const ALERT := Color(1.0, 0.25, 0.18)

var sim: Simulation
var mode := 0
var phase := 0.0
var _poll := 0.0


func setup(simulation: Simulation) -> void:
	sim = simulation


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_V:
		mode = (mode + 1) % 5
		queue_redraw()


func _process(delta: float) -> void:
	if sim == null:
		return
	phase += delta
	_poll -= delta
	if _poll <= 0.0:
		_poll = 0.22
		queue_redraw()


func _view_cells() -> Rect2i:
	var inv := get_canvas_transform().affine_inverse()
	var size := get_viewport_rect().size
	var lo := Vector2i(999999, 999999)
	var hi := Vector2i(-999999, -999999)
	for p in [Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)]:
		var q := Iso.to_world(inv * p) / 32.0
		lo = Vector2i(mini(lo.x, int(q.x)), mini(lo.y, int(q.y)))
		hi = Vector2i(maxi(hi.x, int(q.x)), maxi(hi.y, int(q.y)))
	return Rect2i(lo - Vector2i(3, 3), hi - lo + Vector2i(6, 6))


static func _foot(q: Vector2i) -> Vector2:
	return Iso.to_screen((Vector2(q) + Vector2(0.5, 0.5)) * 32.0)


func _draw() -> void:
	if sim == null or sim.grid == null:
		return
	var view := _view_cells()
	if view.size.x * view.size.y > 50000:
		return
	if mode != 4:
		for k in sim.towns.count():
			if mode in [0, 1]:
				_draw_cells(sim.grid.net.local_roads(k), POWER, -5.0, view, 13)
			if sim.water != null and sim.water.enabled():
				if mode in [0, 2]:
					_draw_cells(sim.water.main_cells(k, "wasser"), WATER, 2.0, view, 11)
				if mode in [0, 3]:
					_draw_cells(sim.water.main_cells(k, "abwasser"), SEWER, 8.0, view, 17)
		if sim.water != null and sim.water.enabled():
			_draw_sites(view)
	_draw_facilities(view)


func _has(cells: Dictionary, q: Vector2i) -> bool:
	return cells.has(q) or cells.has("%d:%d" % [q.x, q.y])


func _draw_cells(cells: Dictionary, color: Color, offset: float, view: Rect2i, marker_every: int) -> void:
	for key in cells:
		var q := Vector2i.ZERO
		if key is Vector2i:
			q = key
		else:
			var xy := str(key).split(":")
			if xy.size() < 2:
				continue
			q = Vector2i(int(xy[0]), int(xy[1]))
		if not view.has_point(q):
			continue
		var a := _foot(q) + Vector2(0, offset)
		for d in [Vector2i.RIGHT, Vector2i.DOWN]:
			var next: Vector2i = q + d
			if _has(cells, next):
				draw_line(a, _foot(next) + Vector2(0, offset), color, 2.2, true)
		if posmod(q.x * 7 + q.y * 13, marker_every) == 0:
			draw_circle(a, 3.1, Color(0.05, 0.12, 0.16, 0.8))
			draw_circle(a, 2.0, color.lightened(0.5))
			var pulse := 0.5 + 0.5 * sin(phase * 3.2 + float(q.x + q.y))
			draw_circle(a, 0.7 + pulse, Color(color.r, color.g, color.b, 0.8))


func _draw_sites(view: Rect2i) -> void:
	for id in sim.water.main_projects:
		var site: Dictionary = sim.water.main_projects[id]
		var color := WATER if str(site.art) == "wasser" else SEWER
		for a in site.cells:
			var q := Vector2i(int(a[0]), int(a[1]))
			if not view.has_point(q):
				continue
			var f := _foot(q)
			draw_line(f + Vector2(-4, 4), f + Vector2(4, -4), color.lightened(0.3), 1.7)
			draw_line(f + Vector2(-4, -4), f + Vector2(4, 4), color.lightened(0.3), 1.7)
	for key in sim.water.breaks:
		var a: Array = sim.water.breaks[key].cell
		var q := Vector2i(int(a[0]), int(a[1]))
		if view.has_point(q):
			var f := _foot(q)
			draw_arc(f, 7.0 + 2.0 * sin(phase * 5.0), 0.0, TAU, 16, ALERT, 2.0)
			draw_line(f + Vector2(-4, -9), f + Vector2(4, -9), WATER, 2.0)


func _draw_facilities(view: Rect2i) -> void:
	var plant: Dictionary = sim.city.building(int(sim.plant.building)) if sim.plant != null else {}
	if not plant.is_empty():
		var center := Vector2i(int(plant.x) + int(plant.w) / 2, int(plant.y) + int(plant.h) / 2)
		if view.has_point(center):
			var f := _foot(center)
			var live := float(sim.grid.last.get("kraftwerk_kw", 0.0)) > 0.0
			var glow := Color(0.28, 0.93, 0.48) if live else ALERT
			draw_circle(f + Vector2(39, -53), 2.5 + 0.8 * sin(phase * 5.0), glow)
			if live:
				for i in 5:
					var lift := fmod(phase * 11.0 + float(i) * 12.0, 58.0)
					var drift := sin(phase * 1.3 + float(i)) * (2.0 + lift * 0.08)
					draw_circle(f + Vector2(-32 + drift, -45 - lift), 3.0 + lift * 0.07, Color(0.82, 0.91, 0.94, 0.32 * (1.0 - lift / 60.0)))
					draw_circle(f + Vector2(-9 + drift, -42 - lift), 2.5 + lift * 0.06, Color(0.82, 0.91, 0.94, 0.27 * (1.0 - lift / 60.0)))
	if sim.water == null or not sim.water.enabled():
		return
	for facility in sim.municipal.facilities.values():
		if str(facility.code) not in ["WW-01", "WT-01", "KA-01"] or str(facility.status) != "in_betrieb":
			continue
		var b: Dictionary = sim.city.building(int(facility.building))
		if b.is_empty():
			continue
		var q := Vector2i(int(b.x) + int(b.w) / 2, int(b.y) + int(b.h) / 2)
		if not view.has_point(q):
			continue
		var f := _foot(q)
		var k := int(facility.town)
		var powered := sim.water.power_ok(k)
		var lamp := Color(0.19, 0.94, 0.55) if powered else ALERT
		draw_circle(f + Vector2(18, -25), 2.2 + 0.5 * sin(phase * 4.0), lamp)
		match str(facility.code):
			"WW-01":
				for i in 4:
					var t := fmod(phase * 0.8 + float(i) * 0.27, 1.0)
					draw_arc(f + Vector2(-18 + i * 9, -10), 3.0 + t * 5.0, PI, TAU, 8, Color(0.32, 0.86, 1.0, (1.0 - t) * 0.55), 1.1)
			"WT-01":
				var fill := float(sim.water.storage.get(str(k), 0.0)) / maxf(1.0, sim.water.tank_capacity(k))
				draw_rect(Rect2(f + Vector2(-8, -45), Vector2(5, 22)), Color(0.08, 0.16, 0.2, 0.75))
				draw_rect(Rect2(f + Vector2(-7, -24 - 20.0 * fill), Vector2(3, 20.0 * fill)), Color(0.26, 0.79, 1.0, 0.85))
			"KA-01":
				var angle := phase * 0.9
				draw_arc(f + Vector2(-12, -7), 13.0, 0.0, TAU, 24, Color(0.35, 0.76, 0.75, 0.55), 1.3)
				draw_line(f + Vector2(-12, -7), f + Vector2(-12, -7) + Vector2(cos(angle), sin(angle)) * 12.0,
					Color(0.83, 0.89, 0.84, 0.8), 1.7)
