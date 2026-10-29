class_name CityView
extends Node2D
## Stellt die Stadt isometrisch dar (Dimetrie 2:1, siehe ART_DIRECTION.md): Boden-Tilemap, Gebaeude in Sortierstreifen,
## Baeume, Laternen, Ampeln, Nachtlichter, Tag-Nacht-Faerbung und Wetter (Regen, Naesse, Pfuetzen, Schnee, Wind, Nebel, Hitze).
## Liest nur aus Simulation/CityData. Kamerakoordinaten sind Bildschirmkoordinaten; Simulationskoordinaten wandelt Iso um.

const ISO := "res://assets/iso/"
const GFX := "res://assets/gfx/"
const STRIP := 64                          # Breite der Tiefensortierstreifen in Pixeln

var sim: Simulation
var man: Dictionary                        # assets/iso/manifest.json
var ground: TileMapLayer
var buildings_node := Node2D.new()
var decor_node := Node2D.new()
var fx_node := Node2D.new()
var lights_layer := CanvasLayer.new()      # folgt der Kamera, ueber der Nachtfaerbung
var night_layer := CanvasLayer.new()
var weather_layer := CanvasLayer.new()
var night_rect := ColorRect.new()
var fog_rect := ColorRect.new()
var heat_rect := ColorRect.new()
var rain: CPUParticles2D
var leaves: CPUParticles2D
var camera := Camera2D.new()
var night_factor := 0.0
var wet := 0.0                              # 0..1 sichtbare Naesse (Regenintensitaet, verzoegert)
var snow := 0.0
var wind := 0.0
var _fog := 0.0
var _heat := 0.0
var estate_view := EstateView.new()
var site_view := SiteView.new()
var depot_view := DepotView.new()
var parcel_layer := ParcelLayer.new()
var _lit_nodes: Array = []                 # Fensterlichter (Sprite2D)
var _blink_nodes: Array = []
var _traffic_lights: Array = []            # [Sprite2D, Vector2i, bool erste Ampel]
var _depot_marks := {}                     # Standort -> {masks: [Sprite2D], label: Label}
var _roadwork_nodes := {}                  # Vector2i -> Sprite2D
var _office_marks := {}                    # Buerostandort -> [Node2D, Signatur der Mieter]
var _building_parts := {}                  # Gebaeude-ID -> Sprites (Zustandsfarbe)
var _roofs: Array = []                     # Dachmasken (Sprite2D) fuer Schnee und Naesse
var _roof_key := ""
var _puddles: Array = []
var _puddle_timer := 0.0
var _tex_cache := {}
var _additive := CanvasItemMaterial.new()
var _ground_mat := ShaderMaterial.new()
var _sway_mat := ShaderMaterial.new()
var _fog_mat := ShaderMaterial.new()
var _heat_mat := ShaderMaterial.new()
var _filter_zoom := -1.0
var _detail_nodes: Array = []        # kleine Requisiten (Baenke, Laternen): erst ab Detailzoom sichtbar
const DETAIL_ZOOM := 0.4


func tex(name: String) -> Texture2D:
	if not _tex_cache.has(name):
		var path := ISO + name + ".png"
		_tex_cache[name] = load(path if ResourceLoader.exists(path) else GFX + name + ".png")
	return _tex_cache[name]


func has_tex(name: String) -> bool:
	return ResourceLoader.exists(ISO + name + ".png")


## Ankerdaten: Bildposition des Ursprungs (Gebaeude, Boden) bzw. Pivot (Figuren, Fahrzeuge, Requisiten).
func pivot_of(name: String) -> Vector2:
	for sec in ["props", "vehicles"]:
		var d: Dictionary = man.get(sec, {})
		if d.has(name):
			return Vector2(d[name].pivot[0], d[name].pivot[1])
	return Vector2.ZERO


func build(simulation: Simulation) -> void:
	sim = simulation
	_additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	man = JSON.parse_string(FileAccess.get_file_as_string(ISO + "manifest.json"))
	_ground_mat.shader = load("res://assets/shaders/ground.gdshader")
	_sway_mat.shader = load("res://assets/shaders/sway.gdshader")
	_fog_mat.shader = load("res://assets/shaders/fog.gdshader")
	_heat_mat.shader = load("res://assets/shaders/heat.gdshader")
	y_sort_enabled = true
	for n in [buildings_node, decor_node, fx_node]:
		n.y_sort_enabled = true
	fx_node.z_index = 20
	_build_ground()
	add_child(decor_node)
	add_child(buildings_node)
	add_child(fx_node)
	lights_layer.layer = 2
	lights_layer.follow_viewport_enabled = true
	night_layer.layer = 1
	weather_layer.layer = 3
	add_child(night_layer)
	add_child(lights_layer)
	add_child(weather_layer)
	night_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	night_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	night_rect.material = mat
	night_layer.add_child(night_rect)
	_build_buildings()
	buildings_node.add_child(estate_view)
	estate_view.setup(sim, self)
	buildings_node.add_child(site_view)
	site_view.setup(sim)
	buildings_node.add_child(depot_view)
	depot_view.setup(sim, self)
	buildings_node.add_child(parcel_layer)
	parcel_layer.setup(sim)
	_build_decor()
	_build_weather_fx()
	camera.position = Iso.to_screen(sim.city.tile_center(sim.city.building(sim.companies[0].depots[0]).road))
	camera.zoom = Vector2(0.5, 0.5)
	add_child(camera)
	camera.make_current()


# ------------------------------------------------------------------ Kamera
func camera_world() -> Vector2:
	return Iso.to_world(camera.position)


func set_camera_world(p: Vector2) -> void:
	camera.position = Iso.to_screen(p)


# ------------------------------------------------------------------ Boden
func _build_ground() -> void:
	var gm: Dictionary = man.ground
	ground = TileMapLayer.new()
	var ts := TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	ts.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	ts.tile_size = Vector2i(128, 64)
	var src := TileSetAtlasSource.new()
	src.texture = tex("ground")
	src.texture_region_size = Vector2i(int(gm.cell[0]), int(gm.cell[1]))
	var tiles: Dictionary = gm.tiles
	for name in tiles:
		if name in ["water1", "water2", "water3"]:
			continue
		var at := Vector2i(int(tiles[name][0]), int(tiles[name][1]))
		src.create_tile(at)
		if name == "water0":
			src.set_tile_animation_frames_count(at, 4)
			src.set_tile_animation_columns(at, 4)
			for f in 4:
				src.set_tile_animation_frame_duration(at, f, 0.45)
	ts.add_source(src, 0)
	ground.tile_set = ts
	ground.y_sort_enabled = true
	ground.z_index = -10
	ground.material = _ground_mat
	ground.position = Vector2(0, 30)   # Zellmitte der Godot-Raute liegt am Ursprung; unsere Kachel hat ihre Mitte 30 px darunter
	add_child(ground)
	var c := sim.city
	var G := CityData.G
	var rng := RandomNumberGenerator.new()
	rng.seed = c.seed_value
	for y in c.size:
		for x in c.size:
			var p := Vector2i(x, y)
			var name := ""
			match c.g(p):
				G.GRASS: name = "grass%d" % (rng.randi() % 3)
				G.PARK: name = "park%d" % (rng.randi() % 2)
				G.GRAVEL: name = "gravel"
				G.SIDEWALK: name = "sidewalk"
				G.PLAZA: name = "plaza"
				G.CONCRETE: name = "concrete"
				G.QUAY: name = "quay"
				G.SAND: name = "sand"
				G.FIELD: name = "field"
				G.CROP: name = "crop"
				G.WATER: name = "water0"
				G.RAIL: name = "rail_h"
				G.ROAD: name = "road%d" % c.road_mask(p)
				G.PARKING: name = "parking"
			var at: Array = tiles[name]
			ground.set_cell(p, 0, Vector2i(int(at[0]), int(at[1])))


# ------------------------------------------------------------------ Gebaeude
func _build_buildings() -> void:
	for b in sim.city.buildings:
		add_building_sprite(b)
	sim.events.buildings_added.connect(func(ids):
		for id in ids:
			add_building_sprite(sim.city.building(id)))
	sim.month_changed.connect(func(_m): refresh_wear())
	_build_cranes()


## Zerlegt ein Objekt (Gebaeude/Einrichtung) in senkrechte Streifen, die einzeln nach der Vorderkante ihrer Grundflaeche
## sortiert werden. Gibt die Streifen-Sprites zurueck; Dachmaske und Firmenmaske haengen als Kinder an jedem Streifen.
func add_iso_object(parent: Node2D, key: String, info: Dictionary, origin: Vector2, w: int, h: int, with_top := true, mask_key := "") -> Array:
	var t: Texture2D = tex(key)
	var anchor := Vector2(info.anchor[0], info.anchor[1])
	var sz := Vector2(info.size[0], info.size[1])
	var top_t: Texture2D = tex(key + "_top") if with_top and has_tex(key + "_top") else null
	var mask_t: Texture2D = tex(mask_key) if mask_key != "" and has_tex(mask_key) else null
	var out: Array = []
	var x_left := -anchor.x
	var x_right := sz.x - anchor.x
	var strips := (w + h) >= 6
	var k0 := floori(x_left / STRIP) if strips else 0
	var k1 := ceili(x_right / STRIP) if strips else 1
	for k in range(k0, k1):
		var sl := maxf(k * STRIP, x_left) if strips else x_left
		var sr := minf((k + 1) * STRIP, x_right) if strips else x_right
		var xc := ((k + 0.5) * STRIP) if strips else 64.0 * (w - h)   # Einzel-Sprite: Sortierpunkt = vordere Ecke
		var yf := Iso.front_edge_y(w, h, xc)
		var s := Sprite2D.new()
		s.texture = t
		s.centered = false
		s.region_enabled = true
		s.region_rect = Rect2(sl + anchor.x, 0, sr - sl, sz.y)
		s.position = origin + Vector2(xc, yf)
		s.offset = Vector2(sl - xc, -anchor.y - yf)
		parent.add_child(s)
		out.append(s)
		for ov in [[top_t, true], [mask_t, false]]:
			if ov[0] == null:
				continue
			var o := Sprite2D.new()
			o.texture = ov[0]
			o.centered = false
			o.region_enabled = true
			o.region_rect = s.region_rect
			o.offset = s.offset
			if ov[1]:
				o.modulate = Color(1, 1, 1, 0)
				_roofs.append(o)
			else:
				o.set_meta("mask", true)
			s.add_child(o)
	return out


func _apply_wear(id: int) -> void:
	if not _building_parts.has(id):
		return
	var tint := BuildingCare.tint(sim.care.get_condition(id)) if sim.care.condition.has(id) else Color.WHITE
	# kleine, feste Farbabweichung je Gebaeude: keine zwei Haeuser sehen exakt gleich aus
	var h := absi(hash("tint_%d" % id))
	var jitter := Color(0.94 + float(h % 11) * 0.01, 0.94 + float((h / 11) % 11) * 0.01, 0.94 + float((h / 121) % 11) * 0.01, 1.0)
	tint = Color(tint.r * jitter.r, tint.g * jitter.g, tint.b * jitter.b, 1.0)
	for s in _building_parts[id]:
		s.self_modulate = tint


## Nach jedem Spielmonat die Zustandsfarben aller Gebaeude aktualisieren.
func refresh_wear() -> void:
	for id in _building_parts:
		_apply_wear(id)


func add_building_sprite(b: Dictionary) -> void:
	if b.type == "plot":
		return   # Firmengrundstuecke zeichnet EstateView
	var info: Dictionary = man.buildings.get(b.sprite, {})
	if info.is_empty():
		return
	var origin := Iso.tile_origin(Vector2i(b.x, b.y))
	var key: String = "b_" + b.sprite
	var parts := add_iso_object(buildings_node, key, info, origin, int(b.w), int(b.h), true, key + "_mask" if b.sprite == "depot" else "")
	_building_parts[int(b.id)] = parts
	_apply_wear(int(b.id))
	var anchor := Vector2(info.anchor[0], info.anchor[1])
	if info.lit:
		var lit := Sprite2D.new()
		lit.centered = false
		lit.texture = tex(key + "_lit")
		lit.position = origin - anchor
		lit.modulate.a = 0.0
		lights_layer.add_child(lit)
		_lit_nodes.append(lit)
	if info.has("smoke"):
		_add_smoke(origin + Vector2(info.smoke[0], info.smoke[1]))
	if b.role == "office_site":
		var om := Node2D.new()
		om.position = Iso.to_screen(Vector2((b.x + b.w) * 32.0 - 6.0, (b.y + b.h) * 32.0 - 6.0))
		fx_node.add_child(om)
		_office_marks[b.id] = [om, ""]
	if b.role == "depot_site":
		var masks: Array = []
		for s in parts:
			for ch in s.get_children():
				if ch.has_meta("mask"):
					masks.append(ch)
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_outline_color", Color(0.06, 0.06, 0.1))
		label.add_theme_constant_override("outline_size", 4)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.size = Vector2(240, 16)
		label.position = origin + Iso.to_screen(Vector2(b.w * 16.0, b.h * 16.0)) + Vector2(-120, -2.0 * float(info.height) - 24.0)
		fx_node.add_child(label)
		_depot_marks[b.id] = {"masks": masks, "label": label, "owner": -2}
		_refresh_depot(b.id)


func _build_cranes() -> void:
	# Kraene wirken lebendiger mit Blinklicht an der Auslegerspitze
	for b in sim.city.buildings:
		if b.type == "crane":
			var g := Sprite2D.new()
			g.texture = tex("glow_small")
			g.material = _additive
			g.modulate = Color(1, 0.3, 0.2)
			g.scale = Vector2(0.5, 0.5)
			g.position = Iso.tile_origin(Vector2i(b.x, b.y)) + Vector2(30, -138)
			lights_layer.add_child(g)
			_blink_nodes.append(g)


func _add_smoke(pos: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.texture = tex("smoke")
	p.position = pos
	p.amount = 12
	p.lifetime = 4.0
	p.direction = Vector2(0.5, -1)
	p.spread = 12.0
	p.gravity = Vector2(8, -6)
	p.initial_velocity_min = 8.0
	p.initial_velocity_max = 16.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.2
	var grad := Gradient.new()
	grad.set_color(0, Color(0.85, 0.85, 0.85, 0.8))
	grad.set_color(1, Color(0.6, 0.6, 0.65, 0.0))
	p.color_ramp = grad
	fx_node.add_child(p)


# ------------------------------------------------------------------ Deko
func _prop(name: String, world: Vector2, parent: Node2D, sway := false) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex(name)
	s.centered = false
	s.offset = -pivot_of(name)
	s.position = Iso.to_screen(world)
	if sway:
		s.material = _sway_mat
	parent.add_child(s)
	return s


func _build_decor() -> void:
	var c := sim.city
	for t in c.trees:
		var s := _prop("d_tree%d" % t[1], Vector2(t[0].x * 32 + 16, t[0].y * 32 + 16), buildings_node)
		s.material = _sway_mat
	for b in c.benches:
		_detail_nodes.append(_prop("d_bench", Vector2(b.x * 32 + 16, b.y * 32 + 16), decor_node))
	for p in c.lamps:
		var w := Vector2(p.x * 32 + 16, p.y * 32 + 16)
		_detail_nodes.append(_prop("d_lamp", w, buildings_node))
		var g := Sprite2D.new()
		g.texture = tex("glow_big")
		g.material = _additive
		g.modulate = Color(0.55, 0.45, 0.25, 0.0)
		g.position = Iso.to_screen(w) + Vector2(0, -50)
		lights_layer.add_child(g)
		_lit_nodes.append(g)
	for p in c.intersections:
		var m := c.road_mask(p)
		var s := _prop("d_light_red", Vector2(p.x * 32 + 5, p.y * 32 + 5), decor_node)
		_traffic_lights.append([s, p, true])
		if m == 15:
			var s2 := _prop("d_light_red", Vector2(p.x * 32 + 27, p.y * 32 + 27), decor_node)
			_traffic_lights.append([s2, p, false])


func _build_weather_fx() -> void:
	rain = CPUParticles2D.new()
	rain.texture = tex("rain")
	rain.amount = 500
	rain.lifetime = 1.2
	rain.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	rain.direction = Vector2(-0.25, 1)
	rain.spread = 2.0
	rain.gravity = Vector2.ZERO
	rain.initial_velocity_min = 700.0
	rain.initial_velocity_max = 900.0
	rain.emitting = false
	weather_layer.add_child(rain)
	var img := Image.create(4, 3, false, Image.FORMAT_RGBA8)
	img.fill(Color("#5f9a3e"))
	img.set_pixel(1, 1, Color("#8dbb55"))
	leaves = CPUParticles2D.new()
	leaves.texture = ImageTexture.create_from_image(img)
	leaves.amount = 36
	leaves.lifetime = 3.5
	leaves.direction = Vector2(1, 0.25)
	leaves.spread = 25.0
	leaves.gravity = Vector2(0, 40)
	leaves.initial_velocity_min = 300.0
	leaves.initial_velocity_max = 520.0
	leaves.angular_velocity_min = -180.0
	leaves.angular_velocity_max = 180.0
	leaves.scale_amount_min = 1.5
	leaves.scale_amount_max = 3.0
	leaves.emitting = false
	weather_layer.add_child(leaves)
	for r in [fog_rect, heat_rect]:
		r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.color = Color.WHITE
		weather_layer.add_child(r)
	fog_rect.material = _fog_mat
	heat_rect.material = _heat_mat
	fog_rect.visible = false
	heat_rect.visible = false
	var pimg := Image.create(32, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 32:
			var d := Vector2((x - 15.5) / 15.5, (y - 7.5) / 7.5).length()
			if d < 1.0:
				pimg.set_pixel(x, y, Color(0.62, 0.72, 0.86, 0.55 * (1.0 - d * 0.5)) if d < 0.8 else Color(0.45, 0.55, 0.7, 0.4))
	var ptex := ImageTexture.create_from_image(pimg)
	for i in 90:
		var s := Sprite2D.new()
		s.texture = ptex
		s.z_index = -8
		s.visible = false
		decor_node.add_child(s)
		_puddles.append(s)


func _refresh_depot(site: int) -> void:
	var d: Dictionary = _depot_marks[site]
	var owner: int = sim.depot_owner.get(site, -1)
	d.owner = owner
	var label: Label = d.label
	if owner >= 0:
		for m in d.masks:
			m.modulate = sim.company(owner).color
		label.text = sim.company(owner).company_name
		label.add_theme_color_override("font_color", sim.company(owner).color.lightened(0.3))
	else:
		for m in d.masks:
			m.modulate = Color(0.62, 0.62, 0.62)
		label.text = "ZU VERMIETEN"
		label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.6))


# ------------------------------------------------------------------ Takt
func update_view(delta: float) -> void:
	# Tag/Nacht
	var h := Catalog.hour_of_day(sim.game_min)
	var day := Color(1, 1, 1)
	var dusk := Color(1.0, 0.82, 0.66)
	var night := Color(0.32, 0.36, 0.58)
	var col: Color
	if h >= 7.0 and h < 18.0:
		col = day
		night_factor = 0.0
	elif h >= 18.0 and h < 20.5:
		var t := (h - 18.0) / 2.5
		col = day.lerp(dusk, minf(1.0, t * 2.0)) if t < 0.5 else dusk.lerp(night, (t - 0.5) * 2.0)
		night_factor = clampf((t - 0.3) / 0.7, 0.0, 1.0)
	elif h >= 5.0 and h < 7.0:
		var t := (h - 5.0) / 2.0
		col = night.lerp(dusk, minf(1.0, t * 2.0)) if t < 0.5 else dusk.lerp(day, (t - 0.5) * 2.0)
		night_factor = clampf(1.0 - t * 1.4, 0.0, 1.0)
	else:
		col = night
		night_factor = 1.0
	var wx: Weather = sim.wx
	if wx.is_heavy_rain():
		col = col * Color(0.74, 0.78, 0.88)
	elif wx.is_rain():
		col = col * Color(0.82, 0.85, 0.92)
	elif wx.is_fog():
		col = col.lerp(Color(0.78, 0.8, 0.84), 0.35)
	elif wx.is_snow():
		col = col * Color(0.9, 0.93, 1.0)
	elif wx.cur.cond in ["bewölkt", "wolkig"]:
		col = col * Color(0.92, 0.92, 0.95)
	elif wx.is_hot() and wx.cur.is_day:
		col = col * Color(1.0, 0.96, 0.88)
	night_rect.color = col
	var blink_on := int(Time.get_ticks_msec() / 600) % 2 == 0
	for n in _lit_nodes:
		n.modulate.a = night_factor
	for n in _blink_nodes:
		n.modulate.a = (0.35 + night_factor * 0.65) if blink_on else night_factor * 0.3
	_update_weather_fx(delta, wx)
	_update_filter()
	# Ampeln
	for tl in _traffic_lights:
		var green_h := sim.light_green(tl[1], true)
		tl[0].texture = tex("d_light_green" if green_h == tl[2] else "d_light_red")
	estate_view.update_view(blink_on)
	site_view.update_view(delta)
	parcel_layer.update_view(delta)
	# Depots: Besitzerwechsel und Stoerungen
	for site in _depot_marks:
		var d: Dictionary = _depot_marks[site]
		if d.owner != sim.depot_owner.get(site, -1):
			_refresh_depot(site)
		var owner: int = sim.depot_owner.get(site, -1)
		var disrupted := owner >= 0 and sim.company(owner).is_disrupted(sim.game_min)
		var label: Label = d.label
		var warn: Node = label.get_node_or_null("warn")
		if disrupted and warn == null:
			var w := Sprite2D.new()
			w.name = "warn"
			w.texture = tex("i_warn")
			w.scale = Vector2(2, 2)
			w.position = Vector2(120, -14)
			label.add_child(w)
		elif not disrupted and warn != null:
			warn.queue_free()
		if warn != null:
			warn.visible = blink_on
	# Bueros: eine Fahne je Mieterfirma
	for site in _office_marks:
		var sig := ""
		for c in sim.companies:
			if site in c.offices:
				sig += "%d:%d," % [c.id, c.office_level if c.offices[0] == site else 0]
		if sig != _office_marks[site][1]:
			_office_marks[site][1] = sig
			var om: Node2D = _office_marks[site][0]
			for ch in om.get_children():
				ch.queue_free()
			var k := 0
			for c in sim.companies:
				if site in c.offices:
					for layer in ["flag", "flag_mask"]:
						var f := Sprite2D.new()
						f.texture = tex(layer)
						f.centered = false
						f.offset = -pivot_of("flag")
						f.position = Vector2(-k * 40, k * 20)
						f.material = _sway_mat
						if layer == "flag_mask":
							f.modulate = c.color
						om.add_child(f)
					k += 1
	# Baustellen
	for p in sim.nav.roadworks:
		if not _roadwork_nodes.has(p):
			_roadwork_nodes[p] = _prop("roadwork", Vector2(p.x * 32 + 16, p.y * 32 + 16), decor_node)
	for p in _roadwork_nodes.keys():
		if not sim.nav.roadworks.has(p):
			_roadwork_nodes[p].queue_free()
			_roadwork_nodes.erase(p)


## Naesse, Schnee, Wind, Nebel, Hitze und Pfuetzen. Alles weich ueberblendet, damit sich Wetterwechsel nicht ruckartig zeigen.
func _update_weather_fx(delta: float, wx: Weather) -> void:
	var vp := get_viewport_rect().size
	var rainy := wx.is_rain()
	rain.emitting = rainy
	var rain_amount := 1100 if wx.is_heavy_rain() else 500
	if rain.amount != rain_amount:
		rain.amount = rain_amount
	rain.position = Vector2(vp.x * 0.5 + 100, -20)
	rain.emission_rect_extents = Vector2(vp.x * 0.7, 10)
	wet = move_toward(wet, (1.0 if wx.is_heavy_rain() else 0.7) if rainy else 0.0, delta * (0.25 if rainy else 0.05))
	snow = move_toward(snow, 1.0 if wx.is_snow() else 0.0, delta * 0.1)
	var gust_n := clampf(float(wx.cur.gust) / 80.0, 0.0, 1.0)
	wind = move_toward(wind, gust_n if wx.is_strong_wind() else gust_n * 0.25, delta * 0.3)
	_ground_mat.set_shader_parameter("wet", wet)
	_ground_mat.set_shader_parameter("snow", snow)
	_sway_mat.set_shader_parameter("wind", wind)
	leaves.emitting = wx.is_strong_wind()
	leaves.position = Vector2(-30, vp.y * 0.5)
	leaves.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	leaves.emission_rect_extents = Vector2(10, vp.y * 0.5)
	_fog = move_toward(_fog, 1.0 if wx.is_fog() else 0.0, delta * 0.2)
	fog_rect.visible = _fog > 0.01
	_fog_mat.set_shader_parameter("density", _fog)
	_heat = move_toward(_heat, 1.0 if (wx.is_hot() and wx.cur.is_day) else 0.0, delta * 0.2)
	heat_rect.visible = _heat > 0.01
	_heat_mat.set_shader_parameter("amount", _heat)
	# Dachmasken: Schnee weiss, Naesse dunkelblau-glaenzend
	var key := "%d_%d" % [int(snow * 20.0), int(wet * 20.0)]
	if key != _roof_key:
		_roof_key = key
		var c := Color(1, 1, 1, snow * 0.92) if snow > 0.02 else Color(0.28, 0.4, 0.62, wet * 0.3)
		for o in _roofs:
			o.modulate = c
	# Pfuetzen auf Strassen und Gehwegen in Kamerarichtung
	_puddle_timer -= delta
	var show := wet > 0.3
	if _puddle_timer <= 0.0 and show:
		_puddle_timer = 4.0
		_place_puddles()
	for s in _puddles:
		s.visible = show and s.has_meta("on")
		s.modulate.a = clampf((wet - 0.3) * 1.6, 0.0, 1.0)


func _place_puddles() -> void:
	var cw := camera_world()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(cw.x / 64.0) * 7919 + int(cw.y / 64.0) * 104729 + sim.city.seed_value
	var G := CityData.G
	for s in _puddles:
		var t := Vector2i(int(cw.x / 32.0) + rng.randi_range(-12, 12), int(cw.y / 32.0) + rng.randi_range(-12, 12))
		var ok: bool = sim.city.inside(t) and sim.city.g(t) in [G.ROAD, G.SIDEWALK, G.PLAZA, G.PARKING, G.CONCRETE]
		s.set_meta("on", ok)
		if ok:
			s.position = Iso.to_screen(Vector2(t.x * 32 + rng.randf_range(6, 26), t.y * 32 + rng.randf_range(6, 26)))
			s.scale = Vector2.ONE * rng.randf_range(0.7, 1.4)


## Pixelgrafik: bei Zoom >= 1 hart (Nearest), darunter mit Mipmaps heruntergerechnet, damit nichts flimmert.
func _update_filter() -> void:
	if is_equal_approx(_filter_zoom, camera.zoom.x):
		return
	_filter_zoom = camera.zoom.x
	var detail := camera.zoom.x >= DETAIL_ZOOM
	for n in _detail_nodes:
		n.visible = detail
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if camera.zoom.x >= 1.0 else CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
