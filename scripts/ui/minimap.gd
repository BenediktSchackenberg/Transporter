class_name Minimap
extends Control
## Uebersichtskarte (1 Pixel je Tile) mit Firmenfahrzeugen, Figuren und Kamerarahmen. Klick = Kamera springen.

signal jump(world_pos: Vector2)

var sim: Simulation
var camera: Camera2D
var map_tex: ImageTexture


func build(simulation: Simulation, cam: Camera2D) -> void:
	sim = simulation
	camera = cam
	var c := sim.city
	var img := Image.create(c.size, c.size, false, Image.FORMAT_RGB8)
	var G := CityData.G
	var cols := {G.GRASS: Color("#4f8a3a"), G.PARK: Color("#62ad4c"), G.GRAVEL: Color("#cdb88f"),
		G.SIDEWALK: Color("#8d8b85"), G.PLAZA: Color("#b9a27c"), G.CONCRETE: Color("#77797e"), G.QUAY: Color("#9a9a9a"),
		G.SAND: Color("#d9c38c"), G.FIELD: Color("#8a6a3c"), G.CROP: Color("#7fa040"), G.WATER: Color("#2d6aa3"),
		G.RAIL: Color("#6a6055"), G.ROAD: Color("#30333c"), G.PARKING: Color("#3d414c")}
	var bcols := [Color("#c9a36b"), Color("#b0705a"), Color("#8a5a44"), Color("#5a7a9a"), Color("#9a8a70"), Color("#9a6a3a")]
	for y in c.size:
		for x in c.size:
			var p := Vector2i(x, y)
			var b: int = c.building_at[c.idx(p)]
			img.set_pixel(x, y, bcols[c.buildings[b].district] if b >= 0 else cols.get(c.g(p), Color.BLACK))
	map_tex = ImageTexture.create_from_image(img)
	custom_minimum_size = Vector2(220, 220)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _draw() -> void:
	if sim == null:
		return
	var s := size.x / sim.city.size
	draw_texture_rect(map_tex, Rect2(Vector2.ZERO, size), false)
	for site in sim.depot_owner:
		var b: Dictionary = sim.city.building(site)
		draw_rect(Rect2(Vector2(b.x, b.y) * s - Vector2(1, 1), Vector2(b.w, b.h) * s + Vector2(2, 2)),
			sim.company(sim.depot_owner[site]).color, false, 2.0)
	for v in sim.vehicles.values():
		draw_rect(Rect2(v.pos / 32.0 * s - Vector2(1.5, 1.5), Vector2(3, 3)), sim.company(v.owner).color)
	for cid in sim.avatars:
		var p: Vector2 = sim.avatars[cid].pos / 32.0 * s
		draw_circle(p, 4.0, Color.BLACK)
		draw_circle(p, 3.0, sim.company(cid).color.lightened(0.3))
	for e in sim.traffic_events:
		for cell in e.cells:
			draw_rect(Rect2(Vector2(cell) * s - Vector2(1, 1), Vector2(3, 3)), Color.ORANGE if e.kind == "baustelle" else Color.RED)
	# Sichtfeld: Bildschirmrechteck der Kamera, in Kartenkoordinaten (wegen der Isometrie eine Raute)
	var vp := camera.get_viewport_rect().size / camera.zoom
	var cc := camera.get_screen_center_position()
	var quad := PackedVector2Array()
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1)]:
		quad.append(Iso.to_world(cc + corner * vp * 0.5) / 32.0 * s)
	draw_polyline(quad, Color(1, 1, 1, 0.9), 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0), false, 2.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT \
			or event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		jump.emit(event.position / size.x * sim.city.size * 32.0)
		accept_event()
