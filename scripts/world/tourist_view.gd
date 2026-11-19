class_name TouristView
extends Node2D
## Reisegruppen benutzen die normalen Figurenblaetter. Ihre Bewegung und Ankunft kommen aus Tourism.

const SHIRTS := [Color("#f1a649"), Color("#54b7c2"), Color("#eb769a"), Color("#b6d76c")]
const FRAMES := 7

var sim: Simulation
var cv: CityView
var figures := {} # Reise-ID -> sichtbare Gruppenmitglieder
var beach_spots := {} # Hotel-ID -> begehbare Sandzellen
var beach_routes := {} # Hotel-ID -> Fussweg vom Hotel zum Strand
var previous_positions := {} # Reise-ID -> letzte Weltposition fuer die Blickrichtung


func setup(s: Simulation, city_view: CityView) -> void:
	sim = s
	cv = city_view


func update_view(_delta: float) -> void:
	for id in figures.keys():
		if not sim.tourism.trips.has(id) or sim.tourism.trips[id].status in ["storniert", "abgereist"]:
			for n in figures[id]:
				n.queue_free()
			figures.erase(id)
			previous_positions.erase(id)
	for id in sim.tourism.trips:
		var t: Dictionary = sim.tourism.trips[id]
		if t.status in ["storniert", "abgereist"]:
			continue
		if not figures.has(id):
			figures[id] = []
			for i in mini(4, int(t.persons)):
				var n := _make_figure((int(id.substr(1)) + i) % Catalog.AVATAR_COUNT, SHIRTS[i % SHIRTS.size()])
				add_child(n)
				figures[id].append(n)
		var world_pos: Vector2 = sim.tourism.visual_position_of(t)
		var at_venue: bool = str(t.get("venue", "")) != "" and sim.game_min >= float(t.get("venue_from", 0.0)) - Tourism.local_transfer_minutes() and sim.game_min < float(t.get("venue_until", 0.0)) + Tourism.local_transfer_minutes()
		var hour := Catalog.hour_of_day(sim.game_min)
		var arriving: bool = GameCalendar.day_of(sim.game_min) == int(t.arrival_day) and sim.game_min < GameCalendar.day_start(int(t.arrival_day)) + Tourism.local_transfer_minutes() * 2.0
		var at_beach: bool = t.status == "im_hotel" and not arriving and not at_venue and hour >= 9.0 and hour < 18.0
		if at_beach:
			var hotel: Dictionary = sim.biz.get_b(str(t.hotel))
			if not hotel.is_empty():
				var hotel_pos: Vector2i = sim.city.building(int(hotel.site)).walk
				world_pos = _beach_world_position(str(t.hotel), hotel_pos, _beach_spot(str(t.hotel), hotel_pos), hour)
		var before: Vector2 = previous_positions.get(id, world_pos)
		var movement := world_pos - before
		previous_positions[id] = world_pos
		var direction := 2
		if movement.length_squared() > 0.03:
			if absf(movement.x) > absf(movement.y):
				direction = 3 if movement.x > 0.0 else 1
			else:
				direction = 2 if movement.y > 0.0 else 0
		for i in figures[id].size():
			var n: Node2D = figures[id][i]
			var phase := float(sim.game_min) * 0.045 + float(i) * 1.4
			var offset := Vector2(cos(phase), sin(phase * 0.7)) * (8.0 if at_beach else 3.0)
			n.position = Iso.to_screen(world_pos + offset + Vector2(i * 5, -i * 3))
			var walking: bool = movement.length_squared() > 0.03 or at_beach
			var frame := int(sim.game_min * 0.15 + i) % FRAMES if walking else 0
			for layer in n.get_children():
				(layer as Sprite2D).frame = direction * FRAMES + frame


func _make_figure(style: int, shirt: Color) -> Node2D:
	var n := Node2D.new()
	var fig: Dictionary = cv.man.figures["fig_%d" % style]
	var pivot := Vector2(float(fig.pivot[0]), float(fig.pivot[1]))
	for layer in ["base", "shirt"]:
		var sp := Sprite2D.new()
		sp.texture = cv.tex("fig_%d" % style if layer == "base" else "fig_%d_mask" % style)
		sp.hframes = FRAMES
		sp.vframes = 4
		sp.centered = false
		sp.offset = -pivot
		sp.scale = Vector2.ONE * 1.25
		if layer == "shirt":
			sp.modulate = shirt
		n.add_child(sp)
	return n


func _beach_spot(hotel_id: String, hotel_pos: Vector2i) -> Vector2i:
	if beach_spots.has(hotel_id):
		return beach_spots[hotel_id]
	var best := hotel_pos
	var best_d := 1 << 30
	for dy in range(-32, 33):
		for dx in range(-32, 33):
			var c := hotel_pos + Vector2i(dx, dy)
			if sim.city.g(c) != CityData.G.SAND or not sim.city.walkable(c):
				continue
			var d := absi(dx) + absi(dy)
			if d < best_d and sim.nav.walk_reachable(hotel_pos, c):
				best = c
				best_d = d
	beach_spots[hotel_id] = best
	return best


func _beach_world_position(hotel_id: String, hotel_pos: Vector2i, beach_pos: Vector2i, hour: float) -> Vector2:
	if not beach_routes.has(hotel_id):
		var path: Array[Vector2i] = sim.nav.walk_path(hotel_pos, beach_pos)
		beach_routes[hotel_id] = path.map(func(p): return [p.x, p.y]) if not path.is_empty() and path[-1] == beach_pos else []
	var route: Array = beach_routes[hotel_id]
	if route.is_empty():
		return sim.city.tile_center(hotel_pos)
	var progress := 1.0
	if hour < 10.0:
		progress = clampf(hour - 9.0, 0.0, 1.0)
	elif hour >= 17.0:
		progress = 1.0 - clampf(hour - 17.0, 0.0, 1.0)
	var index := progress * float(route.size() - 1)
	var a: Array = route[clampi(int(floorf(index)), 0, route.size() - 1)]
	var b: Array = route[clampi(int(ceilf(index)), 0, route.size() - 1)]
	return sim.city.tile_center(Vector2i(int(a[0]), int(a[1]))).lerp(sim.city.tile_center(Vector2i(int(b[0]), int(b[1]))), index - floorf(index))
