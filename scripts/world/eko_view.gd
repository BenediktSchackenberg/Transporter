class_name EkoView
extends Node2D
## Darstellung des Eko-Modus: Bloecke als Iso-Wuerfel (Farben und Schattierung wie FreeBuildView), je Feld ein Knoten in der
## tiefensortierten Gebaeudeebene; Haeuser der Wesen als Schnitt (ohne Dach, Vorderwaende nur eine Schicht hoch), damit man
## drinnen Einrichtung und Bewohner sieht; Wesen als Pixelfigur (Mensch) oder kleiner Roboter mit Material und Sprechblase.

const BLOCK := 8.0          # Welteinheiten je Block (4 je Feld)
const BLOCK_H := 16.0       # Bildhoehe eines Blocks
const CUT := Color("e2c09a")         # Schnittkante (Mauerkrone) wie beim Fahrzeugwerk
const WINDOW_NIGHT := Color("f5d77a")   # bewohnte Haeuser: Fenster leuchten nachts warm

var sim: Simulation
var cv
var _tiles := {}            # Feld -> TileNode
var _beings := {}           # Name -> BeingNode
var _houses := {}           # Name -> HouseNode
var follow := false         # Kamera folgt dem ersten Wesen (--eko-folgen)


## Wer selbst die Kamera bewegt (Maus ziehen/klicken/scrollen, Minikarte, Pfeiltasten), uebernimmt sie: Folgen aus.
## Taste F: wieder dem zuletzt handelnden Wesen folgen (Benedikt 15.11.: "ich kann mich mit der Maus nicht bewegen").
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F:
			follow = not follow
			sim.log_event("Kamera folgt den Wesen%s." % ("" if follow else " nicht mehr (F: wieder folgen)"), "info")
		elif follow and event.keycode in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_W, KEY_A, KEY_S, KEY_D]:
			_stop_follow()
	elif follow and event is InputEventMouseButton and event.pressed:
		_stop_follow()


func _stop_follow() -> void:
	follow = false
	sim.log_event("Freie Kamera – mit F folgst du wieder den Wesen.", "info")


func setup(simulation: Simulation, city_view) -> void:
	sim = simulation
	cv = city_view
	sim.eko.changed.connect(func(): _dirty = true)   # zusammenfassen: hoechstens alle REFRESH_S neu ordnen (Partie 18.11.: 8 fps)
	_refresh()


const REFRESH_S := 0.2
var _dirty := false
var _since := 0.0
var _house_t := 0.0


func _process(_delta: float) -> void:
	_since += _delta
	if _dirty and _since >= REFRESH_S:
		_dirty = false
		_since = 0.0
		_refresh()
	if follow and not sim.eko.beings.is_empty():   # dem zuletzt handelnden Wesen folgen (nicht einem stillstehenden)
		var tb: Dictionary = sim.eko.beings.get(sim.eko.last_active, sim.eko.beings.values()[0])
		cv.set_camera_world(tb.mover.pos)
	for name in _beings:
		var n: BeingNode = _beings[name]
		var b: Dictionary = sim.eko.beings.get(name, {})
		if not b.is_empty():
			var ground := Iso.to_screen(b.mover.pos) - Vector2(0, sim.eko.height_at(sim.eko.tile_of(b)) * MountainView.STEP)   # am Hang hoeher
			n.place(ground, _cab_of(b), _delta)
			n.queue_redraw()
	_house_t += _delta
	if _house_t >= 0.5:   # Lampe, Ladestation und Baufortschritt: zwei Mal je Sekunde reicht (vorher jedes Bild alle Hausbloecke)
		_house_t = 0.0
		for name in _houses:
			_houses[name].queue_redraw()
	var A: EkoArms = sim.eko.arms
	if not (A.ruins.is_empty() and A.towers.is_empty() and A.blasts.is_empty() and A.zones.is_empty() and A.bombs.is_empty() and sim.eko.estates.estates.is_empty()):
		queue_redraw()


## Fahrersitz im Gelaende-LKW je Bildrichtung (Pixel relativ zum Fahrzeugpunkt; aus tools/vox/offroad.py SEAT berechnet und
## so verschoben, dass der Kopf hinter einer Scheibe sitzt): 0 rechts unten, 1 links unten, 2 links oben, 3 rechts oben.
const DRIVER_SEAT := [Vector2(18, -31), Vector2(-40, -33), Vector2(-56, -56), Vector2(54, -57)]   # 2/3: durch die nahe Seitenscheibe (Rueckfenster verdeckt das Reserverad)
var _ent: EntityView = null


## Fahrerplatz eines Wesens, das gerade im eigenen LKW sitzt: {pos (Bildschirm), dir} – sonst leer.
func _cab_of(b: Dictionary) -> Dictionary:
	if not b.has("im_lkw"):
		return {}
	if _ent == null:
		for c in cv.get_children():
			if c is EntityView:
				_ent = c
	if _ent == null:
		return {}
	var vn: Node2D = _ent.vehicle_nodes.get(int(b.im_lkw))
	if vn == null or int(vn.get_meta("dir", -1)) < 0:
		return {}
	var d := int(vn.get_meta("dir"))
	var seat: Vector2 = DRIVER_SEAT[d] if str(vn.get_meta("model", "")) == "gelaende_lkw" else Vector2(DRIVER_SEAT[d]) * Vector2(1.0, 0.9)
	return {"pos": vn.position + Vector2(vn.get_meta("spring", Vector2.ZERO)) + seat, "dir": d, "door": vn.position + Vector2(vn.get_meta("spring", Vector2.ZERO)) + seat * Vector2(1.0, 0.0) + Vector2(0, -4)}


## Krieg sichtbar: Rauch ueber Ruinen, Wachtuerme, Explosionen (Atompilz), Strahlungszonen, tickende Bomben.
## Dazu die Stammsitze: Grenzlinie in der Farbe des Wesens und ein Schild mit dem Namen.
func _draw() -> void:
	var A: EkoArms = sim.eko.arms
	var ms := Time.get_ticks_msec()
	for name in sim.eko.estates.estates:
		var r: Rect2i = sim.eko.estates.rect_of(name)
		var b: Dictionary = sim.eko.beings.get(name, {})
		var col: Color = Color(b.get("color", Color.WHITE))
		var cid: int = sim.eko.active_firm(b) if not b.is_empty() else -1
		if cid >= 0:
			col = sim.company(cid).color
		var pts := PackedVector2Array()
		for c in [r.position, Vector2i(r.end.x, r.position.y), r.end, Vector2i(r.position.x, r.end.y), r.position]:
			pts.append(Iso.to_screen(Vector2(c) * 32.0))
		draw_polyline(pts, Color(col, 0.85), 3.0)
		var top := Iso.to_screen(Vector2(r.get_center()) * 32.0) + Vector2(0, -60)
		var label := "Stammsitz %s" % name
		var font := ThemeDB.fallback_font
		var wl := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 12.0
		draw_rect(Rect2(top.x - wl * 0.5, top.y - 14, wl, 20), Color(0.08, 0.08, 0.12, 0.8))
		draw_rect(Rect2(top.x - wl * 0.5, top.y - 14, wl, 20), col, false, 2.0)
		draw_string(font, Vector2(top.x - wl * 0.5 + 6, top.y + 1), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
	for z in A.zones:
		var c := Iso.to_screen(sim.city.tile_center(Vector2i(int(z.feld[0]), int(z.feld[1]))))
		draw_circle(c, float(z.radius) * 32.0, Color(0.4, 1.0, 0.2, 0.10 + 0.04 * sin(ms / 400.0)))
	for key in A.ruins:
		var bd: Dictionary = sim.city.building(int(key))
		if bd.is_empty():
			continue
		var c := Iso.to_screen(sim.city.tile_center(Vector2i(int(bd.walk.x), int(bd.walk.y))))
		draw_circle(c, 26.0, Color(0.1, 0.1, 0.1, 0.55))
		for i in 4:   # aufsteigender Rauch
			var ph := fmod(ms / 1800.0 + i * 0.25, 1.0)
			draw_circle(c + Vector2(sin(ph * 6.0 + i) * 6.0, -10.0 - ph * 60.0), 6.0 + ph * 10.0, Color(0.25, 0.25, 0.25, 0.5 * (1.0 - ph)))
	for tw in A.towers:
		var c := Iso.to_screen(sim.city.tile_center(Vector2i(int(tw.feld[0]), int(tw.feld[1]))))
		draw_rect(Rect2(c.x - 5, c.y - 34, 10, 34), Color("#6d5d4b"))
		draw_rect(Rect2(c.x - 8, c.y - 40, 16, 7), Color("#8d7b66"))
		draw_circle(c + Vector2(0, -44), 2.5, Color(1.0, 0.2, 0.2, 0.6 + 0.4 * sin(ms / 250.0)))
	for bm in A.bombs:
		var c := Iso.to_screen(sim.city.tile_center(Vector2i(int(bm.feld[0]), int(bm.feld[1]))))
		draw_circle(c, 5.0, Color("#222"))
		draw_circle(c + Vector2(0, -6), 2.5, Color(1, 0.1, 0.1) if (ms / 300) % 2 == 0 else Color(0.4, 0, 0))
		draw_string(ThemeDB.fallback_font, c + Vector2(-10, -12), "%d s" % int(bm.left), HORIZONTAL_ALIGNMENT_CENTER, 20, 8, Color.RED)
	for bl in A.blasts:
		var t := clampf(float(ms - int(bl.ms)) / 8000.0, 0.0, 1.0)
		var c := Iso.to_screen(sim.city.tile_center(Vector2i(int(bl.feld[0]), int(bl.feld[1]))))
		var rad := float(bl.radius) * 32.0 * (0.3 + 0.7 * t)
		draw_circle(c, rad, Color(1.0, 0.55, 0.1, 0.5 * (1.0 - t)))
		if bool(bl.get("atom", false)):   # Atompilz
			draw_rect(Rect2(c.x - 8, c.y - 120 * t, 16, 120 * t), Color(0.6, 0.5, 0.45, 0.7 * (1.0 - t)))
			draw_circle(c + Vector2(0, -120 * t), 30.0 + 40.0 * t, Color(0.75, 0.6, 0.5, 0.7 * (1.0 - t)))


static func color_of(mat: String) -> Color:
	if FreeBuild.MATERIALS.has(mat):
		return Color(str(FreeBuild.MATERIALS[mat].color))
	return Color(str(EkoWorld.FURNITURE.get(mat, "#ff00ff")))


## Iso-Wuerfel eines Blocks; occ: belegte Nachbarn (verdeckte Flaechen weglassen), origin: Knotenposition.
static func draw_block(n: CanvasItem, p: Vector3i, mat: String, occ: Dictionary, origin: Vector2, cut_top := false, night := false, lift := 0.0) -> void:
	var col := color_of(mat)
	if mat == "glas":
		col = WINDOW_NIGHT if night else col
		col.a = 0.85 if night else 0.6
	var w0 := Vector2(p.x, p.y) * BLOCK
	var up := Vector2(0, -float(p.z) * BLOCK_H - lift)   # lift: Gelaendehoehe am Berg (Pixel)
	var top := up + Vector2(0, -BLOCK_H)
	var p00 := Iso.to_screen(w0) - origin
	var p10 := Iso.to_screen(w0 + Vector2(BLOCK, 0)) - origin
	var p11 := Iso.to_screen(w0 + Vector2(BLOCK, BLOCK)) - origin
	var p01 := Iso.to_screen(w0 + Vector2(0, BLOCK)) - origin
	if not occ.has(p + Vector3i(0, 1, 0)):   # Suedseite
		n.draw_colored_polygon(PackedVector2Array([p01 + up, p11 + up, p11 + top, p01 + top]), col.darkened(0.15))
	if not occ.has(p + Vector3i(1, 0, 0)):   # Ostseite
		n.draw_colored_polygon(PackedVector2Array([p10 + up, p11 + up, p11 + top, p10 + top]), col.darkened(0.32))
	if not occ.has(p + Vector3i(0, 0, 1)):   # Oberseite (an einer Schnittkante als helle Mauerkrone)
		var tc := CUT if cut_top else col.lightened(0.08)
		n.draw_colored_polygon(PackedVector2Array([p00 + top, p10 + top, p11 + top, p01 + top]), tc)
		n.draw_polyline(PackedVector2Array([p00 + top, p10 + top, p11 + top, p01 + top, p00 + top]), tc.darkened(0.25), 0.6)
	if mat in ["lampe", "ladestation"]:   # Leuchten (nachts mit Lichtkegel auf dem Boden)
		var glow := Color(col.r, col.g, col.b, 0.25 + 0.1 * sin(Time.get_ticks_msec() / 300.0))
		n.draw_circle((p00 + p11) * 0.5 + top, 9.0, glow)
		if night and mat == "lampe":
			n.draw_circle((p00 + p11) * 0.5 + up, 26.0, Color(1.0, 0.88, 0.5, 0.16))


static func is_night(sim) -> bool:
	var h := Catalog.hour_of_day(sim.game_min)
	return h < 6.0 or h >= 20.0


## Schnitt fuer Haeuser, die ein Wesen auf seinem Grundstueck selbst baut: je Feld die Grenzen der Bloecke auf dem Grundstueck.
func _cuts() -> Dictionary:
	var out := {}
	for b in sim.eko.beings.values():
		var id := str(b.get("grundstueck", ""))
		if id == "":
			continue
		var r: Rect2i = sim.eko.plot_rect(id)
		var mx := -1
		var my := -1
		var mz := -1
		for p in sim.eko.blocks:
			var t := Vector2i(floori(float(p.x) / EkoWorld.PER_TILE), floori(float(p.y) / EkoWorld.PER_TILE))
			if r.has_point(t):
				mx = maxi(mx, p.x)
				my = maxi(my, p.y)
				mz = maxi(mz, p.z)
		if mz >= 3:   # erst ab einer gewissen Hoehe aufschneiden
			for y in range(r.position.y, r.end.y):
				for x in range(r.position.x, r.end.x):
					out[Vector2i(x, y)] = {"mx": mx, "my": my, "mz": mz}
	return out


func _refresh() -> void:
	var cuts := _cuts()
	var by_tile := {}
	for p in sim.eko.blocks:
		var t := Vector2i(floori(float(p.x) / EkoWorld.PER_TILE), floori(float(p.y) / EkoWorld.PER_TILE))
		if not by_tile.has(t):
			by_tile[t] = []
		by_tile[t].append(p)
	for t in _tiles.keys():
		if not by_tile.has(t):
			_tiles[t].queue_free()
			_tiles.erase(t)
	for t in by_tile:
		var n: TileNode = _tiles.get(t)
		if n == null:
			n = TileNode.new()
			n.sim = sim
			n.position = Iso.to_screen(Vector2(t + Vector2i.ONE) * 32.0)   # Sortierpunkt: vordere Ecke des Feldes
			if sim.eko.height_at(t) > 0.0:
				n.z_index = 1   # am Berg ueber dem Gelaende zeichnen
			cv.buildings_node.add_child(n)
			_tiles[t] = n
		var cells: Array = by_tile[t]
		var cut: Dictionary = cuts.get(t, {})
		var sig := hash(cells)
		if sig != n.sig or cut != n.cut:   # nur geaenderte Felder neu zeichnen
			n.sig = sig
			n.cells = cells
			n.cut = cut
			n.queue_redraw()
	for name in sim.eko.houses:
		if not _houses.has(name):
			var hn := HouseNode.new()
			hn.sim = sim
			hn.owner_name = name
			var h: Dictionary = sim.eko.houses[name]
			hn.position = Iso.to_screen((Vector2(float(h.origin[0]), float(h.origin[1])) + Vector2.ONE * EkoWorld.HOUSE_SIDE) * BLOCK)
			cv.buildings_node.add_child(hn)
			_houses[name] = hn
	for name in sim.eko.beings:
		if not _beings.has(name):
			var bn := BeingNode.new()
			bn.sim = sim
			bn.being = name
			bn.z_index = 3   # ueber Gebaeuden wie die Markierungen der Figuren, sonst verdeckt der Bauhof das Wesen
			bn.scale = Vector2(1.5, 1.5)   # Groesse der Buergerfiguren
			cv.buildings_node.add_child(bn)
			_beings[name] = bn


class TileNode:
	extends Node2D
	var sim: Simulation
	var cells: Array = []
	var cut := {}               # Schnitt eines selbst gebauten Hauses: {mx, my, mz} oder leer
	var sig := 0                # Kennung der Bloecke (nur bei Aenderung neu zeichnen)

	func _draw() -> void:
		var bl: Dictionary = sim.eko.blocks
		var order := cells.duplicate()
		order.sort_custom(func(a, b): return a.x + a.y < b.x + b.y or (a.x + a.y == b.x + b.y and a.z < b.z))
		var occ := bl
		var night := false
		if not cut.is_empty():
			occ = {}
			night = EkoView.is_night(sim)
			order = order.filter(func(p): return bl.has(p) and not (p.z == int(cut.mz) and p.z >= 3) and not ((p.x == int(cut.mx) or p.y == int(cut.my)) and p.z >= 2))
			for p in order:
				occ[p] = true
		for p in order:
			if bl.has(p):
				var up: Vector3i = p + Vector3i(0, 0, 1)
				var t := Vector2i(floori(float(p.x) / EkoWorld.PER_TILE), floori(float(p.y) / EkoWorld.PER_TILE))
				EkoView.draw_block(self, p, str(bl[p]), occ, position, bl.has(up) and not occ.has(up), night, sim.eko.height_at(t) * MountainView.STEP)


## Haus eines Wesens als Schnitt: Dach weg, Vorderwaende (Sueden, Osten) nur bis zur ersten Schicht, damit man hineinsieht.
class HouseNode:
	extends Node2D
	var sim: Simulation
	var owner_name := ""

	func _draw() -> void:
		var h: Dictionary = sim.eko.houses.get(owner_name, {})
		if h.is_empty():
			return
		var o := Vector2i(int(h.origin[0]), int(h.origin[1]))
		var last := EkoWorld.HOUSE_SIDE - 1
		var shown: Array = []
		var occ := {}
		for i in int(h.placed):
			var e: Array = h.blocks[i]
			var p := Vector3i(int(e[0]), int(e[1]), int(e[2]))
			var lx := p.x - o.x
			var ly := p.y - o.y
			if p.z > EkoWorld.HOUSE_WALL:   # Dach im Schnitt weglassen
				continue
			if (lx == last or ly == last) and p.z >= 2:   # Vorderwaende aufgeschnitten
				continue
			shown.append([p, str(e[3])])
			occ[p] = true
		shown.sort_custom(func(a, b): return a[0].x + a[0].y < b[0].x + b[0].y or (a[0].x + a[0].y == b[0].x + b[0].y and a[0].z < b[0].z))
		var night: bool = EkoView.is_night(sim) and h.status == "fertig"
		for s in shown:
			var up: Vector3i = s[0] + Vector3i(0, 0, 1)
			EkoView.draw_block(self, s[0], s[1], occ, position, (s[0].z == 1 and (s[0].x - o.x == last or s[0].y - o.y == last)) or s[0].z == EkoWorld.HOUSE_WALL, night)
		var font := ThemeDB.fallback_font
		var label := "Zuhause von %s" % owner_name if h.status == "fertig" else "%s baut: %d %%" % [h.builder, int(100.0 * float(h.placed) / float(h.blocks.size()))]
		var top := Iso.to_screen(Vector2(o.x + EkoWorld.HOUSE_SIDE / 2, o.y + EkoWorld.HOUSE_SIDE / 2) * EkoView.BLOCK) - position + Vector2(0, -EkoView.BLOCK_H * (EkoWorld.HOUSE_WALL + 2))
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x + 10.0
		draw_rect(Rect2(top.x - w * 0.5, top.y - 12, w, 15), Color(0.1, 0.12, 0.16, 0.8))
		draw_string(font, Vector2(top.x - w * 0.5 + 5, top.y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("#ffe27a") if h.status == "fertig" else Color.WHITE)


class BeingNode:
	extends Node2D
	var sim: Simulation
	var being := ""
	var _last_x := 0.0
	var _facing := 1
	var _cab := {}              # Fahrerplatz (EkoView._cab_of), leer = zu Fuss
	var _trans := 1.0           # 0..1: Ein-/Aussteigen laeuft (0,45 s)
	var _trans_in := false      # true = steigt ein, false = steigt aus
	var _from := Vector2.ZERO
	var _steer := 0.0           # Lenkradausschlag (folgt den Richtungswechseln)
	var _last_dir := -1

	## Position je Bild: zu Fuss am Boden, im LKW auf dem Fahrersitz; beim Wechsel kurzer Uebergang zur bzw. von der Tuer.
	func place(ground: Vector2, cab: Dictionary, dt: float) -> void:
		var was_in := not _cab.is_empty()
		var now_in := not cab.is_empty()
		if was_in != now_in:
			_trans = 0.0
			_trans_in = now_in
			_from = position
		if now_in and _last_dir >= 0 and int(cab.dir) != _last_dir:
			_steer = 1.0 if (int(cab.dir) - _last_dir + 4) % 4 == 1 else -1.0
		_last_dir = int(cab.dir) if now_in else -1
		_steer = move_toward(_steer, 0.0, dt * 1.5)
		_cab = cab
		var target: Vector2 = cab.pos if now_in else ground
		if _trans < 1.0:
			_trans = minf(1.0, _trans + dt / 0.45)
			var e := _trans * _trans * (3.0 - 2.0 * _trans)
			position = _from.lerp(target, e) + Vector2(0, -sin(_trans * PI) * 6.0)   # kleiner Huepfer in die Kabine / heraus
		else:
			position = target

	func driving() -> bool:
		return not _cab.is_empty() and _trans >= 1.0

	## Zustand fuer die Figur: Blickrichtung aus der Bewegung, Taetigkeit aus der letzten Handlung (frisch, ca. 2,5 s).
	func _ctx(b: Dictionary, ms: int) -> Dictionary:
		var m: Mover = b.mover
		var dx := float(m.pos.x) - _last_x
		if absf(dx) > 0.05:
			_facing = 1 if dx > 0.0 else -1
		_last_x = float(m.pos.x)
		var dec: Dictionary = b.get("entscheidung", {})
		var act := str(dec.get("aktion", "")) if ms - int(dec.get("ms", 0)) < 2500 else ""
		var A: EkoArms = sim.eko.arms
		var weapon := ""
		for it in b.get("waffen", []):
			var t := str(A.designs.get(str(it.design), {}).get("typ", ""))
			if t != "ruestung" and t != "":
				weapon = t
				break
		var role := "buergermeister" if int(b.get("amt", -1)) >= 0 else ("unternehmer" if sim.eko.active_firm(b) >= 0 else "frei")
		return {"ms": ms, "walking": not m.arrived(), "facing": _facing, "action": act, "out": float(b.get("out_left", 0.0)) > 0.0,
			"custody": float(b.get("custody_left", 0.0)) > 0.0, "resting": float(b.get("rest_left", 0.0)) > 0.0 and m.arrived(),
			"talking": float(b.get("say_left", 0.0)) > 0.0 and str(b.get("say", "")) != "" and not str(b.get("say", "")).begins_with("Zzz"),
			"armor": A.armor_of(b), "weapon": weapon, "role": role, "carrying": not (b.held as Array).is_empty()}

	func _draw() -> void:
		var b: Dictionary = sim.eko.beings.get(being, {})
		if b.is_empty():
			return
		var col: Color = b.color
		var ms := Time.get_ticks_msec()
		if driving():
			modulate.a = 1.0
			EkoFigure.draw_driver(self, b, int(_cab.dir), ms, _steer, sim.eko.active_firm(b) >= 0)
			_draw_labels(b, -14.0, 0, true)
			return
		if _trans < 1.0:   # Ein-/Aussteigen: Figur wird kleiner bzw. groesser, als ginge sie durch die Tuer
			var k := _trans if _trans_in else 1.0 - _trans
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * lerpf(1.0, 0.55, k))
			modulate.a = lerpf(1.0, 0.35, k)
		else:
			modulate.a = 1.0
		var kalt := float(b.get("kalt", 0.0))
		var nass := float(b.get("nass", 0.0))
		var akku := float(b.get("akku", 100.0))
		draw_circle(Vector2(0, 1), 6.5, Color(0, 0, 0, 0.25))                     # Schatten
		if bool(b.get("faehrt", false)):   # Fahrdienst: kleines gelbes Taxi
			draw_rect(Rect2(-11, -9, 22, 9), Color("#f2c94c"))
			draw_rect(Rect2(-7, -14, 14, 5), Color("#f2c94c").darkened(0.1))
			draw_rect(Rect2(-6, -13, 12, 3), Color("#9ad0f5"))
			draw_rect(Rect2(-3, -16, 6, 2), Color("#222"))
			draw_circle(Vector2(-7, 0), 2.2, Color("#222"))
			draw_circle(Vector2(7, 0), 2.2, Color("#222"))
		if kalt > 50.0:   # Zittern vor Kaelte
			draw_set_transform(Vector2(sin(ms / 35.0) * 0.7, 0))
		var robot := str(b.get("art", "mensch")) == "roboter"
		var head_top := -30.0 if robot else -26.0
		if robot:
			_draw_robot(b)
		else:
			EkoFigure.draw(self, b, _ctx(b, ms))   # animierte Pixelfigur nach Taetigkeit
		draw_set_transform(Vector2.ZERO)
		if nass > 40.0:   # Regentropfen laufen herunter
			for i in 5:
				var ph := fmod(ms / 600.0 + i * 0.37, 1.0)
				var x := -6.0 + 3.0 * i
				draw_line(Vector2(x, head_top + 4 + 22 * ph), Vector2(x, head_top + 6 + 22 * ph), Color(0.55, 0.75, 1.0, 0.9 * (1.0 - ph)), 0.8)
		if robot:   # Akkubalken
			var bar := Rect2(-6, head_top - 4, 12, 2)
			draw_rect(bar, Color(0, 0, 0, 0.55))
			var bc := Color("7dff8a") if akku > 50.0 else (Color("ffd166") if akku > EkoWorld.LOW_AKKU else Color("ff5a5a"))
			draw_rect(Rect2(bar.position, Vector2(12.0 * akku / 100.0, 2)), bc)
			if float(b.get("rest_left", 0.0)) > 0.0 and sim.eko.is_home(b):   # Laden in der Ladestation
				draw_arc(Vector2(0, -14), 11.0 + sin(ms / 200.0), 0.0, TAU, 24, Color(0.36, 0.9, 1.0, 0.6), 1.0)
		var held: Array = b.held
		for i in held.size():   # getragene Bloecke/Kisten ueber dem Kopf gestapelt
			var c := EkoView.color_of(str(held[i]))
			var r := Rect2(-4, head_top - 11 - i * 5, 8, 5)
			draw_rect(r, c)
			draw_rect(r, c.darkened(0.4), false, 0.6)
			if str(held[i]) == "kiste":
				draw_line(r.position + Vector2(0, 2.5), r.position + Vector2(8, 2.5), c.darkened(0.4), 0.5)
		_draw_labels(b, head_top, held.size(), false)

	## Name, Geld, Ziel, letzte Entscheidung, Erkenntnis und Sprechblase (zu Fuss unter der Figur, am Steuer ueber der Kabine).
	func _draw_labels(b: Dictionary, head_top: float, held_n: int, above := false) -> void:
		var col: Color = b.color
		var font := ThemeDB.fallback_font
		var money := float(b.get("geld", 0.0))
		var tag := str(b.name) + ("  %s" % Catalog.money(money) if money > 0.0 else "")
		var tag_y := head_top - 3.0 if above else 12.0   # am Steuer: Schild ueber dem Kopf statt quer ueber der Kabine
		draw_string(font, Vector2(-40, tag_y), tag, HORIZONTAL_ALIGNMENT_CENTER, 80, 7, Color.WHITE)
		# Autonomie sichtbar: Ziel, letzte Entscheidung (warum, Ergebnis), frische Erkenntnis
		var now := Time.get_ticks_msec()
		var info_y := tag_y - 8.0 if above else 19.0
		var info_step := -7.0 if above else 7.0
		var g: Dictionary = b.get("ziel", {})
		if str(g.get("status", "")) == "aktiv":
			draw_string(font, Vector2(-60, info_y), "Ziel: %s (%d %%)" % [str(g.ziel).left(34), int(g.fortschritt)], HORIZONTAL_ALIGNMENT_CENTER, 120, 6, Color("#ffe27a"))
			info_y += info_step
		var dec: Dictionary = b.get("entscheidung", {})
		if not dec.is_empty() and now - int(dec.get("ms", 0)) < 12000:
			var dc: Color = {"gescheitert": Color("#ff8a80"), "laeuft": Color("#9be7ff"), "doppelt": Color("#ffcc80")}.get(str(dec.status), Color("#b9f6ca"))
			var why := str(dec.warum) if str(dec.warum) != "" else str(dec.ergebnis)
			draw_string(font, Vector2(-70, info_y), "%s → %s: %s" % [dec.aktion, dec.status, why.left(40)], HORIZONTAL_ALIGNMENT_CENTER, 140, 6, dc)
			info_y += info_step
		var les: Dictionary = b.get("erkenntnis", {})
		if not les.is_empty() and now - int(les.get("ms", 0)) < 15000:
			draw_string(font, Vector2(-70, info_y), "Gelernt (%s): %s" % [les.art, str(les.text).left(40)], HORIZONTAL_ALIGNMENT_CENTER, 140, 6, Color("#e1bee7"))
		if float(b.say_left) > 0.0 and str(b.say) != "":
			var text := str(b.say)
			var w := minf(160.0, font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x + 10.0)
			var lines := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, w - 8.0, 7)
			var box := Rect2(-w * 0.5, (info_y - 4.0 if above else head_top - 12 - held_n * 5) - lines.y, w, lines.y + 6)
			draw_rect(box, Color(1, 1, 1, 0.92))
			draw_rect(box, col.darkened(0.3), false, 1.0)
			draw_multiline_string(font, box.position + Vector2(4, 9), text, HORIZONTAL_ALIGNMENT_LEFT, w - 8.0, 7, -1, Color("#222"))

	## Lumo (eigener Entwurf): runder Kopf mit Bildschirmgesicht und zwei leuchtenden Augen, die ab und zu blinzeln,
	## Antenne mit pulsierendem Licht, mintgruener Koerper mit Herzschlag-Anzeige, kleine Arme, Kettenfahrwerk.
	func _draw_robot(b: Dictionary) -> void:
		var ms := Time.get_ticks_msec()
		var metal := Color("#a8e6cf")
		var line := Color("#2f5d50")
		var dark := Color("#263238")
		var resting := float(b.get("rest_left", 0.0)) > 0.0
		var bob := 0.0 if resting else sin(ms / 180.0) * 0.4 if not (b.mover as Mover).arrived() else 0.0
		# Kettenfahrwerk
		draw_rect(Rect2(-6, -4, 12, 4), dark)
		for x in [-4.0, 0.0, 4.0]:
			draw_circle(Vector2(x, -2), 1.4, Color("#78909c"))
		# Koerper
		var body := Rect2(-5, -14 + bob, 10, 10)
		draw_rect(body, metal)
		draw_rect(Rect2(body.position.x, body.position.y, 2, body.size.y), metal.lightened(0.25))
		draw_rect(body, line, false, 0.8)
		var scr := Rect2(-3, -12 + bob, 6, 4)
		draw_rect(scr, Color("#10202a"))
		var beat := Color("#7dff8a") if not resting else Color("#ffd166")
		var t := (ms / 120) % 6
		draw_polyline(PackedVector2Array([scr.position + Vector2(0, 2), scr.position + Vector2(2, 2), scr.position + Vector2(3, 0.5 if t < 3 else 3.5),
			scr.position + Vector2(4, 2), scr.position + Vector2(6, 2)]), beat, 0.6)
		# Arme
		draw_line(Vector2(-5, -11 + bob), Vector2(-8, -7 + bob), line, 1.2)
		draw_line(Vector2(5, -11 + bob), Vector2(8, -7 + bob), line, 1.2)
		draw_circle(Vector2(-8, -7 + bob), 1.3, metal.darkened(0.15))
		draw_circle(Vector2(8, -7 + bob), 1.3, metal.darkened(0.15))
		# Kopf
		var head := Rect2(-6, -24 + bob, 12, 9)
		draw_rect(head, metal.lightened(0.1))
		draw_rect(Rect2(head.position.x, head.position.y, head.size.x, 2), metal.lightened(0.35))
		draw_rect(head, line, false, 0.8)
		var face := Rect2(-4.5, -22.5 + bob, 9, 6)
		draw_rect(face, Color("#10202a"))
		var blink := resting or (ms % 3400) < 140
		var eye := Color("6ff3ff").lerp(Color("2a5560"), clampf((EkoWorld.LOW_AKKU - float(b.get("akku", 100.0))) / EkoWorld.LOW_AKKU, 0.0, 0.8))
		for ex in [-2.8, 1.2]:
			if blink:
				draw_line(Vector2(ex, -19.5 + bob), Vector2(ex + 1.8, -19.5 + bob), eye, 0.7)
			else:
				draw_rect(Rect2(ex, -21 + bob, 1.8, 2.6 if float(b.get("akku", 100.0)) > EkoWorld.LOW_AKKU else 1.4), eye)
				draw_rect(Rect2(ex + 0.3, -20.8 + bob, 0.6, 0.6), Color.WHITE)
		draw_rect(Rect2(-5.6, -18.5 + bob, 1.2, 0.8), Color("#ff8fab"))                 # Wangen
		draw_rect(Rect2(4.4, -18.5 + bob, 1.2, 0.8), Color("#ff8fab"))
		# Antenne
		draw_line(Vector2(0, -24 + bob), Vector2(0, -28 + bob), line, 0.8)
		var pulse := 0.5 + 0.5 * sin(ms / 250.0)
		var bulb := Color("#7dff8a").lerp(Color("#d4ffda"), pulse)
		draw_circle(Vector2(0, -29 + bob), 2.6, Color(bulb.r, bulb.g, bulb.b, 0.25))
		draw_circle(Vector2(0, -29 + bob), 1.3, bulb)
