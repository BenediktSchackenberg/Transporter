class_name EntityView
extends Node2D
## Zeichnet bewegte Objekte isometrisch: Firmenfahrzeuge (Firmenfarbe ueber Maskenebene, sichtbare Ladung), NPC-Verkehr,
## Unternehmerfiguren mit Namensschild und Sprechblasen, Arbeiter, Kundenfiguren mit Anliegen und dekorative Fussgaenger.
## Alle Positionen kommen als Simulationskoordinaten und werden mit Iso.to_screen umgerechnet; die Tiefensortierung
## uebernimmt die y-Sortierung ueber den Fusspunkt jedes Knotens.

const PED_COUNT_PER_TILE := 1.0 / 450.0
const SHIRTS := [Color("#d04a4a"), Color("#4a7ad0"), Color("#e0c050"), Color("#5ab060"), Color("#c070c0"),
	Color("#e08a40"), Color("#f0f0f0"), Color("#404858")]
const CAR_NAMES := ["silver", "black", "red", "blue", "gold", "white", "green", "violet"]
const MODEL_HEIGHT := {"cargobike": 14, "van": 24, "transporter": 31, "reefer": 35, "truck": 38, "semi": 44}
const FRAMES := 7                       # Bilder je Richtung in den Figurenblaettern
const FREE_SHIRT := Color("#8a8f99")
## Kleidungsfarbe der Kundenfiguren nach Gebaeudetyp (erkennbarer Beruf)
const OUTFIT := {"restaurant": Color("#f2f0ea"), "clinic": Color("#f6f6f6"), "pharmacy": Color("#7ad0a0"), "construction": Color("#f0a020"),
	"factory": Color("#e0782a"), "school": Color("#6a8ac0"), "kindergarten": Color("#e8788a"), "shop": Color("#4f9a5a"),
	"warehouse": Color("#c9a24a"), "airport_cargo": Color("#e0c030"), "office": Color("#4a5a80"), "bank": Color("#3a4a6a")}
const TASK_ICONS := {"fahren": "i_drive", "reparieren": "i_wrench", "bewachen": "i_shield", "verladen": "i_crate",
	"auskundschaften": "i_eye", "sabotage": "i_bolt", "unterstuetzen": "i_handshake"}

var sim: Simulation
var cv: CityView
var vehicle_nodes := {}
var traffic_nodes: Array = []
var avatar_nodes := {}
var peds: Array = []                    # [Mover, Node2D, Wartezeit]
var bubble_nodes := {}
var headlights: Array = []              # [Sprite2D Licht, Node2D Fahrzeug]
var route_lines := {}                   # Fahrzeug-ID bzw. "a<Firma>" -> Line2D (geplante Route)
var worker_nodes := {}                  # Arbeiter-ID -> Node2D
var person_nodes := {}                  # Kunden-ID -> Node2D
var marker_node := Node2D.new()         # Ressourcen-Markierungen (Haendlerbestand, Waren, Vorraete)
var select_marker := Node2D.new()
var selected := {}                      # {kind: vehicle|avatar|worker|person|building, id}
var anim_time := 0.0
var _marker_timer := 0.0
var _ped_rng := RandomNumberGenerator.new()
var _pick_cache := {}                   # Textur -> Image (Alpha-Test beim Anklicken von Gebaeuden)


func build(simulation: Simulation, city_view: CityView) -> void:
	sim = simulation
	cv = city_view
	y_sort_enabled = true
	_ped_rng.seed = sim.city.seed_value + 99
	for m in sim.traffic:
		var n := _make_vehicle_node("car", CAR_NAMES[_ped_rng.randi() % CAR_NAMES.size()], Color.WHITE, false)
		traffic_nodes.append(n)
		add_child(n)
	var count := int(sim.city.size * sim.city.size * PED_COUNT_PER_TILE)
	for k in count:
		_spawn_ped()
	for cid in sim.avatars:
		_make_avatar(cid)
	marker_node.z_index = 3
	add_child(marker_node)
	var ring := Line2D.new()
	ring.width = 2.0
	ring.default_color = Color(1.0, 0.9, 0.4, 0.95)
	var pts := PackedVector2Array()
	for i in 25:
		pts.append(Vector2(cos(i * TAU / 24.0) * 26.0, sin(i * TAU / 24.0) * 13.0))
	ring.points = pts
	select_marker.add_child(ring)
	select_marker.visible = false
	select_marker.z_index = 50
	add_child(select_marker)


# ------------------------------------------------------------------ Knoten
## Fahrzeug: Karosserie + Firmenfarbmaske (Sprite wird je Fahrtrichtung getauscht); Fusspunkt = Knotenposition.
func _make_vehicle_node(model: String, car_color: String, color: Color, company: bool) -> Node2D:
	var n := Node2D.new()
	n.set_meta("model", model)
	n.set_meta("car_color", car_color)
	n.set_meta("dir", -1)
	var body := Sprite2D.new()
	body.name = "body"
	body.centered = false
	n.add_child(body)
	if company:
		var mask := Sprite2D.new()
		mask.name = "mask"
		mask.centered = false
		mask.modulate = color
		n.add_child(mask)
	var light := Sprite2D.new()
	light.texture = cv.tex("glow_small")
	light.material = cv._additive
	light.modulate = Color(0.6, 0.55, 0.35, 0.0)
	light.scale = Vector2(0.6, 0.6)
	cv.lights_layer.add_child(light)
	headlights.append([light, n])
	return n


static func _dir_of(h: Vector2) -> int:
	if absf(h.x) >= absf(h.y):
		return 0 if h.x >= 0.0 else 2
	return 1 if h.y >= 0.0 else 3


func _set_vehicle_dir(n: Node2D, h: Vector2) -> void:
	var d := _dir_of(h)
	if n.get_meta("dir") == d:
		return
	n.set_meta("dir", d)
	var model: String = n.get_meta("model")
	var key: String = ("car_%s_%d" % [n.get_meta("car_color"), d]) if model == "car" else ("%s_%d" % [model, d])
	var piv := cv.pivot_of(key)
	var body: Sprite2D = n.get_node("body")
	body.texture = cv.tex("v_" + key)
	body.offset = -piv
	var mask: Sprite2D = n.get_node_or_null("mask")
	if mask:
		mask.texture = cv.tex("v_" + key + "_mask")
		mask.offset = -piv


## Figur aus einem Blatt (7 Bilder x 4 Richtungen) mit Hemd in Firmen-/Berufsfarbe und optionalem Regenschirm.
func _make_figure(style: int, scale_f: float, shirt: Color) -> Node2D:
	var n := Node2D.new()
	var fig: Dictionary = cv.man.figures["fig_%d" % style]
	var piv := Vector2(fig.pivot[0], fig.pivot[1])
	for layer in ["base", "shirt"]:
		var sp := Sprite2D.new()
		sp.name = layer
		sp.texture = cv.tex("fig_%d" % style if layer == "base" else "fig_%d_mask" % style)
		sp.hframes = FRAMES
		sp.vframes = 4
		sp.centered = false
		sp.offset = -piv
		sp.scale = Vector2(scale_f, scale_f)
		if layer == "shirt":
			sp.modulate = shirt
		n.add_child(sp)
	var um := Node2D.new()
	um.name = "umbrella"
	um.visible = false
	var uf: Dictionary = cv.man.figures["fig_umbrella"]
	for layer in ["u_base", "u_mask"]:
		var sp := Sprite2D.new()
		sp.name = layer
		sp.texture = cv.tex("fig_umbrella" if layer == "u_base" else "fig_umbrella_mask")
		sp.hframes = 1
		sp.vframes = 4
		sp.centered = false
		sp.offset = -Vector2(uf.pivot[0], uf.pivot[1])
		sp.scale = Vector2(scale_f, scale_f)
		if layer == "u_mask":
			sp.modulate = SHIRTS[(style * 3 + 1) % SHIRTS.size()]
		um.add_child(sp)
	n.add_child(um)
	n.set_meta("scale", scale_f)
	return n


func _set_figure_frame(n: Node2D, dir: int, frame: int, rainy: bool) -> void:
	for s in [n.get_node("base"), n.get_node("shirt")]:
		s.frame = dir * FRAMES + frame
	var um: Node2D = n.get_node("umbrella")
	um.visible = rainy
	if rainy:
		for s in um.get_children():
			s.frame = dir


func _make_avatar(cid: int) -> void:
	var c := sim.company(cid)
	var n := _make_figure(c.avatar_style % Catalog.AVATAR_COUNT, 1.4, c.color)
	var tag := Label.new()
	tag.name = "tag"
	tag.text = c.player_name
	tag.add_theme_font_size_override("font_size", 12)
	tag.add_theme_color_override("font_color", c.color.lightened(0.35))
	tag.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.08))
	tag.add_theme_constant_override("outline_size", 4)
	tag.position = Vector2(-40, -80)
	tag.size = Vector2(80, 14)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.z_index = 40
	n.add_child(tag)
	add_child(n)
	avatar_nodes[cid] = n
	var bubble := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.98, 0.97, 0.92, 0.96)
	sb.border_color = Color(0.1, 0.1, 0.15)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	bubble.add_theme_stylebox_override("panel", sb)
	var lbl := Label.new()
	lbl.name = "text"
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size = Vector2(180, 0)
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.1, 0.1, 0.15))
	bubble.add_child(lbl)
	bubble.visible = false
	bubble.z_index = 60
	add_child(bubble)
	bubble_nodes[cid] = bubble


func _spawn_ped() -> void:
	var G := CityData.G
	for attempt in 30:
		var p := Vector2i(_ped_rng.randi_range(0, sim.city.size - 1), _ped_rng.randi_range(0, sim.city.size - 1))
		if sim.city.g(p) in [G.SIDEWALK, G.PLAZA, G.PARK, G.GRAVEL] and sim.city.walkable(p):
			var m := Mover.new()
			m.lane = 0.0
			m.speed = _ped_rng.randf_range(0.8, 1.2)
			m.pos = sim.city.tile_center(p) + Vector2(_ped_rng.randf_range(-8, 8), _ped_rng.randf_range(-8, 8))
			var n := _make_figure(_ped_rng.randi() % Catalog.AVATAR_COUNT, 1.0, SHIRTS[_ped_rng.randi() % SHIRTS.size()])
			n.set_meta("umbrella_user", _ped_rng.randf() < 0.55)
			add_child(n)
			peds.append([m, n, _ped_rng.randf_range(0.0, 3.0)])
			return


func _make_worker(w: Worker) -> Node2D:
	var style := (hash(w.id) & 0x7fffffff) % Catalog.AVATAR_COUNT
	var n := _make_figure(style, 1.2, FREE_SHIRT)
	var icon := Sprite2D.new()
	icon.name = "icon"
	icon.z_index = 40
	n.add_child(icon)
	var carry := Sprite2D.new()   # getragene Kiste beim Verladen
	carry.name = "carry"
	carry.texture = cv.tex("c_pakete")
	carry.centered = false
	carry.offset = -cv.pivot_of("c_pakete")
	carry.position = Vector2(0, -22)
	carry.visible = false
	n.add_child(carry)
	add_child(n)
	worker_nodes[w.id] = n
	return n


func _make_person(p: Dictionary) -> Node2D:
	var b: Dictionary = sim.city.building(p.building)
	var style := (hash(p.id) & 0x7fffffff) % Catalog.AVATAR_COUNT
	var n := _make_figure(style, 1.25, OUTFIT.get(Residents.prof(b.type), SHIRTS[(hash(p.id) & 0x7fffffff) % SHIRTS.size()]))
	var icon := Sprite2D.new()
	icon.name = "icon"
	icon.z_index = 40
	n.add_child(icon)
	var spot: Vector2 = sim.city.tile_center(b.walk)
	var off := Vector2(((hash(p.id) >> 3) % 17) - 8.0, ((hash(p.id) >> 7) % 13) - 6.0)
	n.set_meta("world", spot + off)
	n.position = Iso.to_screen(spot + off)
	add_child(n)
	person_nodes[p.id] = n
	return n


# ------------------------------------------------------------------ Takt
func update_view(delta: float, sim_speed: float, zoom: float) -> void:
	anim_time += delta
	var inv := clampf(1.0 / zoom, 0.6, 2.5)
	var rainy := sim.wx.is_rain()
	for id in vehicle_nodes.keys():
		if not sim.vehicles.has(id):
			vehicle_nodes[id].queue_free()
			vehicle_nodes.erase(id)
	for v in sim.vehicles.values():
		var n: Node2D = vehicle_nodes.get(v.id)
		if n == null or n.get_meta("owner") != v.owner:
			if n:
				n.queue_free()
			n = _make_vehicle_node(v.model, "", sim.company(v.owner).color, true)
			n.set_meta("owner", v.owner)
			var cargo := Sprite2D.new()
			cargo.name = "cargo"
			cargo.centered = false
			n.add_child(cargo)
			var warn := Sprite2D.new()
			warn.name = "warn"
			warn.texture = cv.tex("i_warn")
			warn.position = Vector2(0, -2.0 * float(MODEL_HEIGHT.get(v.model, 30)) - 22.0)
			warn.z_index = 40
			n.add_child(warn)
			add_child(n)
			vehicle_nodes[v.id] = n
		n.position = Iso.to_screen(v.pos)
		_set_vehicle_dir(n, v.heading)
		var cs: Sprite2D = n.get_node("cargo")
		cs.visible = v.cargo != ""
		if v.cargo != "":
			var cname: String = "c_" + v.cargo
			cs.texture = cv.tex(cname)
			cs.offset = -cv.pivot_of(cname) + Vector2(0, -2.0 * float(MODEL_HEIGHT.get(v.model, 30)) - 6.0 + (1.0 if int(anim_time * 4) % 2 == 0 else 0.0))
		n.get_node("warn").visible = v.state == "broken" and int(anim_time * 3) % 2 == 0
	for i in sim.traffic.size():
		var m: Mover = sim.traffic[i]
		var n: Node2D = traffic_nodes[i]
		n.position = Iso.to_screen(m.pos)
		_set_vehicle_dir(n, m.heading)
	for hl in headlights:
		var veh: Node2D = hl[1]
		if not is_instance_valid(veh):
			hl[0].queue_free()
			continue
		var d := int(veh.get_meta("dir"))
		var hv := Vector2([1, 0, -1, 0][maxi(d, 0)], [0, 1, 0, -1][maxi(d, 0)])
		hl[0].position = veh.position + Iso.to_screen(hv * 18.0) + Vector2(0, -8)
		hl[0].modulate.a = cv.night_factor * 0.8
	headlights = headlights.filter(func(hl): return is_instance_valid(hl[1]))
	_update_routes()
	_update_workers(inv, rainy)
	_update_people(inv, rainy)
	_marker_timer -= delta
	if _marker_timer <= 0.0:
		_marker_timer = 0.5
		_update_markers()
	# Figuren der Unternehmer
	for cid in sim.avatars:
		var a: Avatar = sim.avatars[cid]
		var n: Node2D = avatar_nodes[cid]
		n.position = Iso.to_screen(a.pos)
		var moving := a.state in ["walking", "wander"] and not a.arrived()
		var talking: bool = a.state == "talking" or a.bubble_timer > 0.0
		var afr := (1 + int(anim_time * 8.0) % 4) if moving else (5 + int(anim_time * 2.5) % 2 if talking else 0)   # Sprechen: gestikulieren
		_set_figure_frame(n, _dir_of(a.heading), afr, rainy and moving)
		var tag: Label = n.get_node("tag")
		tag.scale = Vector2(inv, inv)
		tag.position = Vector2(-40 * inv, -84 - 14 * (inv - 1.0))
		var bubble: PanelContainer = bubble_nodes[cid]
		bubble.visible = a.bubble_timer > 0.0
		if bubble.visible:
			var lbl: Label = bubble.get_node("text")
			if lbl.text != a.bubble:
				lbl.text = a.bubble
				bubble.reset_size()
			var sb: StyleBoxFlat = bubble.get_theme_stylebox("panel")
			sb.bg_color = Color(0.92, 0.88, 1.0, 0.96) if a.bubble_private else Color(0.98, 0.97, 0.92, 0.96)
			bubble.scale = Vector2(inv, inv)
			bubble.position = Iso.to_screen(a.pos) + Vector2(-bubble.size.x * 0.5 * inv, -100.0 * inv - bubble.size.y * inv)
	# Fussgaenger (rein dekorativ)
	for p in peds:
		var m: Mover = p[0]
		var n: Node2D = p[1]
		if m.arrived():
			p[2] -= delta * sim_speed
			if p[2] <= 0.0:
				var t := m.tile() + Vector2i(_ped_rng.randi_range(-10, 10), _ped_rng.randi_range(-10, 10))
				if sim.city.walkable(t) and sim.city.g(t) != CityData.G.ROAD:
					var path := sim.nav.walk_path(m.tile(), t)
					if path.size() > 1:
						m.set_path(path)
				p[2] = _ped_rng.randf_range(1.0, 5.0)
		else:
			m.advance(delta * sim_speed, 1.0)
		n.position = Iso.to_screen(m.pos)
		var moving := not m.arrived()
		_set_figure_frame(n, _dir_of(m.heading), (1 + int(anim_time * 7.0 + m.speed * 10.0) % 4) if moving else 0, rainy and bool(n.get_meta("umbrella_user")))
	# Auswahlmarkierung
	select_marker.visible = false
	if not selected.is_empty():
		var pos := selected_position()
		if pos.x > -9000.0:
			select_marker.visible = true
			select_marker.position = Iso.to_screen(pos)
			select_marker.scale = Vector2.ONE * (1.0 + 0.08 * sin(anim_time * 6.0))


## Restliche Fahrtroute je Firmenfahrzeug (Firmenfarbe) und Fussweg der Figuren.
func _update_routes() -> void:
	var seen := {}
	for v in sim.vehicles.values():
		if v.state in ["to_pickup", "to_dropoff", "returning", "to_workshop"] and not v.arrived():
			_route_line(str(v.id), v, sim.company(v.owner).color, 3.0, 0.4)
			seen[str(v.id)] = true
	for cid in sim.avatars:
		var a: Avatar = sim.avatars[cid]
		if a.state == "walking" and not a.arrived():
			_route_line("a%d" % cid, a, sim.company(cid).color.lightened(0.3), 2.0, 0.35)
			seen["a%d" % cid] = true
	for key in route_lines.keys():
		if not seen.has(key):
			route_lines[key].queue_free()
			route_lines.erase(key)


func _route_line(key: String, m: Mover, color: Color, width: float, alpha: float) -> void:
	var line: Line2D = route_lines.get(key)
	if line == null:
		line = Line2D.new()
		line.width = width
		line.default_color = Color(color, alpha)
		line.z_index = 4
		add_child(line)
		route_lines[key] = line
	var pts := PackedVector2Array([Iso.to_screen(m.pos) + Vector2(0, -2)])
	for i in range(m.path_i, m.path.size()):
		pts.append(Iso.to_screen(m.point_for(i)) + Vector2(0, -2))
	line.points = pts


## Arbeiter und Vorarbeiter: Hemd in Firmenfarbe (grau = verfuegbar), Symbol der aktuellen Aufgabe,
## Arbeitsanimation am Einsatzort. Fahrer sind im Fahrzeug unsichtbar; verlorene Arbeiter verschwinden.
func _update_workers(inv: float, rainy: bool) -> void:
	for w in sim.personnel.workers.values():
		var n: Node2D = worker_nodes.get(w.id)
		if n == null:
			n = _make_worker(w)
		var inside: bool = w.vehicle_id >= 0 and sim.vehicles.has(w.vehicle_id)
		n.visible = not w.lost and not inside
		if not n.visible:
			continue
		n.position = Iso.to_screen(w.pos)
		var shirt: Color = sim.company(w.employer).color if w.employer >= 0 else FREE_SHIRT
		n.get_node("shirt").modulate = shirt
		var t: WorkerTask = sim.personnel.tasks.get(w.task_id)
		var working: bool = t != null and t.status == "in Bearbeitung"
		var moving: bool = not w.arrived()
		var frame := 0
		if moving:
			frame = 1 + int(anim_time * 7.0) % 4
		elif working:
			frame = 5 + int(anim_time * 3.0) % 2   # Arbeitsbewegung
		var dir := _dir_of(w.heading)
		if working and t.kind in ["reparieren", "sabotage", "verladen"]:
			dir = 1   # zum Fahrzeug/Gebaeude gewandt
		var carrying: bool = t != null and not t.is_final() and t.kind == "verladen" and t.status in ["unterwegs", "in Bearbeitung"]
		n.get_node("carry").visible = carrying
		_set_figure_frame(n, dir, frame, rainy and not working)
		var icon: Sprite2D = n.get_node("icon")
		var key: String = "i_clipboard" if w.role == "foreman" else (TASK_ICONS.get(t.kind, "") if t and not t.is_final() else "")
		icon.visible = key != ""
		if icon.visible:
			icon.texture = cv.tex(key)
			icon.position = Vector2(0, -66 + (sin(anim_time * 5.0) * 1.5 if working else 0.0))
		icon.scale = Vector2(inv, inv) * 0.9


## Kundenfiguren: stehen am Eingang, solange sie ein Anliegen haben oder gerade ein Ergebnis zeigen.
func _update_people(inv: float, rainy: bool) -> void:
	var vis := {}
	for p in sim.residents.visible_people():
		vis[p.id] = true
		var n: Node2D = person_nodes.get(p.id)
		if n == null:
			n = _make_person(p)
		n.visible = true
		var wait: bool = p.state == "wartet"
		_set_figure_frame(n, 1, (5 + int(anim_time * 1.6) % 2) if wait else 0, rainy)   # Wartende winken
		var icon: Sprite2D = n.get_node("icon")
		icon.texture = cv.tex({"wartet": "i_chat", "zufrieden": "i_star", "verärgert": "i_bolt"}[p.state])
		icon.position = Vector2(0, -78 + sin(anim_time * 4.0 + float(hash(p.id) % 7)) * 2.0)
		icon.scale = Vector2(inv, inv) * 1.6
	for id in person_nodes.keys():
		if not vis.has(id):
			person_nodes[id].queue_free()
			person_nodes.erase(id)


## Sichtbare Ressourcen: Fahrzeuge im Haendlerbestand, wartende Waren an Abholorten, Vorraete an Tankstellen/Werkstaetten.
func _update_markers() -> void:
	for ch in marker_node.get_children():
		ch.queue_free()
	var per_dealer := {}
	for o in sim.resources.available_offers():
		var b: Dictionary = sim.city.building(o.dealer)
		var i: int = per_dealer.get(o.dealer, 0)
		per_dealer[o.dealer] = i + 1
		var key := "%s_0" % o.model
		var node := Node2D.new()
		node.position = Iso.to_screen(Vector2(b.x * 32 + 18 + i * 28, (b.y + b.h) * 32 + 14))
		var body := Sprite2D.new()
		body.texture = cv.tex("v_" + key)
		body.centered = false
		body.offset = -cv.pivot_of(key)
		body.modulate = Color("#d8dde4") if o.condition >= 100 else Color("#b8a888")   # gebraucht = matter
		node.add_child(body)
		marker_node.add_child(node)
	var goods := {}
	for k in sim.contracts.values():
		if k.status in ["open", "accepted", "assigned", "loading"]:
			goods[k.pickup] = goods.get(k.pickup, []) + [k]
	for bid in goods:
		var b: Dictionary = sim.city.building(bid)
		var list: Array = goods[bid]
		for i in mini(list.size(), 3):
			var cname: String = "c_" + list[i].cargo
			var crate := Sprite2D.new()
			crate.texture = cv.tex(cname)
			crate.centered = false
			crate.offset = -cv.pivot_of(cname)
			crate.position = Iso.to_screen(sim.city.tile_center(b.walk) + Vector2(-6 + i * 9, -4 + i * 5))
			marker_node.add_child(crate)
	for sp in sim.resources.supplies.values():
		var b: Dictionary = sim.city.building(sp.building)
		var lbl := Label.new()
		lbl.text = ("Diesel %d l · %.2f €" % [int(sp.stock), sim.resources.fuel_price(sp)]) if sp.kind == "fuel" \
			else ("Teile %d · %d €" % [int(sp.stock), int(sp.price)])
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", Color("#ffe39a") if sp.kind == "fuel" else Color("#bfe0f2"))
		lbl.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.08))
		lbl.add_theme_constant_override("outline_size", 4)
		var info: Dictionary = cv.man.buildings.get(b.sprite, {})
		lbl.position = Iso.to_screen(Vector2((b.x + b.w * 0.5) * 32, (b.y + b.h * 0.5) * 32)) + Vector2(-50, -2.0 * float(info.get("height", 30)) - 18.0)
		marker_node.add_child(lbl)


## Weltposition (Simulationskoordinaten) der Auswahl; (-9999, -9999) wenn nichts gewaehlt.
func selected_position() -> Vector2:
	match selected.get("kind", ""):
		"vehicle":
			if sim.vehicles.has(selected.id):
				return sim.vehicles[selected.id].pos
		"avatar":
			return sim.avatars[selected.id].pos
		"worker":
			var w: Worker = sim.personnel.workers.get(selected.id)
			if w and not w.lost:
				return w.pos
		"person":
			var pn: Node2D = person_nodes.get(selected.id)
			if pn:
				return pn.get_meta("world")
		"building":
			var b: Dictionary = sim.city.building(selected.id)
			return Vector2(b.x * 32 + b.w * 16, b.y * 32 + b.h * 16)
	return Vector2(-9999, -9999)


func _sprite_hit(foot: Vector2, pivot: Vector2, size: Vector2, click: Vector2, scale_f := 1.0) -> bool:
	return Rect2(foot - pivot * scale_f, size * scale_f).has_point(click)


## Auswahl per Klick (Bildschirmkoordinaten): Figuren vor Fahrzeugen vor Gebaeuden; bei Gebaeuden zaehlt das sichtbare Pixel.
func pick(click: Vector2) -> Dictionary:
	var best := {}
	var best_d := INF
	for cid in sim.avatars:
		var d := (Iso.to_screen(sim.avatars[cid].pos) + Vector2(0, -26)).distance_to(click)
		if d < 30.0 and d < best_d:
			best = {"kind": "avatar", "id": cid}
			best_d = d
	for w in sim.personnel.workers.values():
		if not w.lost and w.vehicle_id < 0:
			var d := (Iso.to_screen(w.pos) + Vector2(0, -22)).distance_to(click)
			if d < 26.0 and d < best_d:
				best = {"kind": "worker", "id": w.id}
				best_d = d
	for pid in person_nodes:
		var d: float = (person_nodes[pid].position + Vector2(0, -24)).distance_to(click)
		if d < 28.0 and d < best_d:
			best = {"kind": "person", "id": pid}
			best_d = d
	if not best.is_empty():
		return best
	for v in sim.vehicles.values():
		var n: Node2D = vehicle_nodes.get(v.id)
		if n and n.get_meta("dir") >= 0:
			var key := "%s_%d" % [v.model, n.get_meta("dir")]
			var info: Dictionary = cv.man.vehicles[key]
			var piv := Vector2(info.pivot[0], info.pivot[1])
			var d := (n.position - Vector2(0, float(MODEL_HEIGHT.get(v.model, 30)))).distance_to(click)
			if _sprite_hit(n.position, piv, Vector2(info.size[0], info.size[1]), click) and d < best_d:
				best = {"kind": "vehicle", "id": v.id}
				best_d = d
	if not best.is_empty():
		return best
	var found := -1
	var found_depth := -INF
	for b in sim.city.buildings:
		if b.type == "plot":
			continue
		var info: Dictionary = cv.man.buildings.get(b.sprite, {})
		if info.is_empty():
			continue
		var origin := Iso.tile_origin(Vector2i(b.x, b.y))
		var local := click - (origin - Vector2(info.anchor[0], info.anchor[1]))
		if local.x < 0 or local.y < 0 or local.x >= info.size[0] or local.y >= info.size[1]:
			continue
		var t: Texture2D = cv.tex("b_" + b.sprite)
		if not _pick_cache.has(t):
			_pick_cache[t] = t.get_image()
		if _pick_cache[t].get_pixel(int(local.x), int(local.y)).a < 0.2:
			continue
		var depth: float = b.x + b.y + b.w + b.h
		if depth > found_depth:
			found_depth = depth
			found = b.id
	if found >= 0:
		return {"kind": "building", "id": found}
	var t := CityData.to_tile(Iso.to_world(click))
	if sim.city.inside(t):
		var b: int = sim.city.building_at[sim.city.idx(t)]
		if b >= 0:
			return {"kind": "building", "id": b}
	return {}
