class_name EkoView
extends Node2D
## Darstellung des Eko-Modus: Bloecke als Iso-Wuerfel (Farben und Schattierung wie FreeBuildView), je Feld ein Knoten in der
## tiefensortierten Gebaeudeebene; Haeuser der Wesen als Schnitt (ohne Dach, Vorderwaende nur eine Schicht hoch), damit man
## drinnen Einrichtung und Bewohner sieht; Wesen als Pixelfigur (Mensch) oder kleiner Roboter mit Material und Sprechblase.

const BLOCK := 8.0          # Welteinheiten je Block (4 je Feld)
const BLOCK_H := 16.0       # Bildhoehe eines Blocks

var sim: Simulation
var cv
var _tiles := {}            # Feld -> TileNode
var _beings := {}           # Name -> BeingNode
var _houses := {}           # Name -> HouseNode
var follow := false         # Kamera folgt dem ersten Wesen (--eko-folgen)


func setup(simulation: Simulation, city_view) -> void:
	sim = simulation
	cv = city_view
	sim.eko.changed.connect(_refresh)
	_refresh()


func _process(_delta: float) -> void:
	if follow and not sim.eko.beings.is_empty():
		cv.set_camera_world(sim.eko.beings.values()[0].mover.pos)
	for name in _beings:
		var n: BeingNode = _beings[name]
		var b: Dictionary = sim.eko.beings.get(name, {})
		if not b.is_empty():
			n.position = Iso.to_screen(b.mover.pos)
			n.queue_redraw()
	for name in _houses:
		_houses[name].queue_redraw()   # Lampe und Ladestation leuchten, Baufortschritt


static func color_of(mat: String) -> Color:
	if FreeBuild.MATERIALS.has(mat):
		return Color(str(FreeBuild.MATERIALS[mat].color))
	return Color(str(EkoWorld.FURNITURE.get(mat, "#ff00ff")))


## Iso-Wuerfel eines Blocks; occ: belegte Nachbarn (verdeckte Flaechen weglassen), origin: Knotenposition.
static func draw_block(n: CanvasItem, p: Vector3i, mat: String, occ: Dictionary, origin: Vector2) -> void:
	var col := color_of(mat)
	if mat == "glas":
		col.a = 0.6
	var w0 := Vector2(p.x, p.y) * BLOCK
	var up := Vector2(0, -float(p.z) * BLOCK_H)
	var top := up + Vector2(0, -BLOCK_H)
	var p00 := Iso.to_screen(w0) - origin
	var p10 := Iso.to_screen(w0 + Vector2(BLOCK, 0)) - origin
	var p11 := Iso.to_screen(w0 + Vector2(BLOCK, BLOCK)) - origin
	var p01 := Iso.to_screen(w0 + Vector2(0, BLOCK)) - origin
	if not occ.has(p + Vector3i(0, 1, 0)):   # Suedseite
		n.draw_colored_polygon(PackedVector2Array([p01 + up, p11 + up, p11 + top, p01 + top]), col.darkened(0.15))
	if not occ.has(p + Vector3i(1, 0, 0)):   # Ostseite
		n.draw_colored_polygon(PackedVector2Array([p10 + up, p11 + up, p11 + top, p10 + top]), col.darkened(0.32))
	if not occ.has(p + Vector3i(0, 0, 1)):   # Oberseite
		n.draw_colored_polygon(PackedVector2Array([p00 + top, p10 + top, p11 + top, p01 + top]), col.lightened(0.08))
		n.draw_polyline(PackedVector2Array([p00 + top, p10 + top, p11 + top, p01 + top, p00 + top]), col.darkened(0.25), 0.6)
	if mat in ["lampe", "ladestation"]:   # Leuchten
		var glow := Color(col.r, col.g, col.b, 0.25 + 0.1 * sin(Time.get_ticks_msec() / 300.0))
		n.draw_circle((p00 + p11) * 0.5 + top, 9.0, glow)


func _refresh() -> void:
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
			cv.buildings_node.add_child(n)
			_tiles[t] = n
		n.cells = by_tile[t]
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

	func _draw() -> void:
		var bl: Dictionary = sim.eko.blocks
		var order := cells.duplicate()
		order.sort_custom(func(a, b): return a.x + a.y < b.x + b.y or (a.x + a.y == b.x + b.y and a.z < b.z))
		for p in order:
			if bl.has(p):
				EkoView.draw_block(self, p, str(bl[p]), bl, position)


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
		for s in shown:
			EkoView.draw_block(self, s[0], s[1], occ, position)
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

	func _draw() -> void:
		var b: Dictionary = sim.eko.beings.get(being, {})
		if b.is_empty():
			return
		var col: Color = b.color
		draw_circle(Vector2(0, 1), 6.5, Color(0, 0, 0, 0.25))                     # Schatten
		var robot := str(b.get("art", "mensch")) == "roboter"
		var head_top := -30.0 if robot else -24.0
		if robot:
			_draw_robot(b)
		else:
			draw_rect(Rect2(-3, -6, 2, 6), Color("#2d2a32"))                        # Beine
			draw_rect(Rect2(1, -6, 2, 6), Color("#2d2a32"))
			draw_rect(Rect2(-4, -16, 8, 10), col)                                   # Koerper
			draw_rect(Rect2(-3, -23, 6, 7), Color("#f1c9a5"))                       # Kopf
			draw_rect(Rect2(-3, -24, 6, 2), col.darkened(0.4))                      # Haare
		var held: Array = b.held
		for i in held.size():   # getragene Bloecke/Kisten ueber dem Kopf gestapelt
			var c := EkoView.color_of(str(held[i]))
			var r := Rect2(-4, head_top - 7 - i * 5, 8, 5)
			draw_rect(r, c)
			draw_rect(r, c.darkened(0.4), false, 0.6)
			if str(held[i]) == "kiste":
				draw_line(r.position + Vector2(0, 2.5), r.position + Vector2(8, 2.5), c.darkened(0.4), 0.5)
		var font := ThemeDB.fallback_font
		var money := float(b.get("geld", 0.0))
		var tag := str(b.name) + ("  %s" % Catalog.money(money) if money > 0.0 else "")
		draw_string(font, Vector2(-40, 12), tag, HORIZONTAL_ALIGNMENT_CENTER, 80, 7, Color.WHITE)
		if float(b.say_left) > 0.0 and str(b.say) != "":
			var text := str(b.say)
			var w := minf(160.0, font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x + 10.0)
			var lines := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, w - 8.0, 7)
			var box := Rect2(-w * 0.5, head_top - 12 - held.size() * 5 - lines.y, w, lines.y + 6)
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
		for ex in [-2.8, 1.2]:
			if blink:
				draw_line(Vector2(ex, -19.5 + bob), Vector2(ex + 1.8, -19.5 + bob), Color("#6ff3ff"), 0.7)
			else:
				draw_rect(Rect2(ex, -21 + bob, 1.8, 2.6), Color("#6ff3ff"))
				draw_rect(Rect2(ex + 0.3, -20.8 + bob, 0.6, 0.6), Color.WHITE)
		draw_rect(Rect2(-5.6, -18.5 + bob, 1.2, 0.8), Color("#ff8fab"))                 # Wangen
		draw_rect(Rect2(4.4, -18.5 + bob, 1.2, 0.8), Color("#ff8fab"))
		# Antenne
		draw_line(Vector2(0, -24 + bob), Vector2(0, -28 + bob), line, 0.8)
		var pulse := 0.5 + 0.5 * sin(ms / 250.0)
		var bulb := Color("#7dff8a").lerp(Color("#d4ffda"), pulse)
		draw_circle(Vector2(0, -29 + bob), 2.6, Color(bulb.r, bulb.g, bulb.b, 0.25))
		draw_circle(Vector2(0, -29 + bob), 1.3, bulb)
