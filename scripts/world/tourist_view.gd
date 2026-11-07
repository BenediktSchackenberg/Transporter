class_name TouristView
extends Node2D
## Reisegruppen benutzen die normalen Figurenblaetter. Ihre Bewegung und Ankunft kommen aus Tourism.

const SHIRTS := [Color("#f1a649"), Color("#54b7c2"), Color("#eb769a"), Color("#b6d76c")]
const FRAMES := 7

var sim: Simulation
var cv: CityView
var figures := {} # Reise-ID -> sichtbare Gruppenmitglieder
var beach_spots := {} # Hotel-ID -> begehbare Sandzellen


func setup(s: Simulation, city_view: CityView) -> void:
	sim = s
	cv = city_view


func update_view(_delta: float) -> void:
	for id in figures.keys():
		if not sim.tourism.trips.has(id) or sim.tourism.trips[id].status in ["storniert", "abgereist"]:
			for n in figures[id]:
				n.queue_free()
			figures.erase(id)
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
		var pos := sim.tourism.position_of(t)
		var at_venue: bool = str(t.get("venue", "")) != "" and sim.game_min >= float(t.get("venue_from", 0.0)) and sim.game_min < float(t.get("venue_until", 0.0))
		var at_beach: bool = t.status == "im_hotel" and not at_venue and Catalog.hour_of_day(sim.game_min) >= 10.0 and Catalog.hour_of_day(sim.game_min) <= 18.0
		if at_beach:
			pos = _beach_spot(str(t.hotel), pos)
		for i in figures[id].size():
			var n: Node2D = figures[id][i]
			var phase := float(sim.game_min) * 0.045 + float(i) * 1.4
			var offset := Vector2(cos(phase), sin(phase * 0.7)) * (8.0 if at_beach else 3.0)
			n.position = Iso.to_screen(sim.city.tile_center(pos) + offset + Vector2(i * 5, -i * 3))
			var walking: bool = t.status == "unterwegs" and t.mode == "strasse" or at_beach
			var frame := int(sim.game_min * 0.15 + i) % FRAMES if walking else 0
			for layer in n.get_children():
				(layer as Sprite2D).frame = 2 * FRAMES + frame


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
			if d < best_d:
				best = c
				best_d = d
	beach_spots[hotel_id] = best
	return best
