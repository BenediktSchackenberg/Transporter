class_name AmbientView
extends Node2D
## Leben auf der Karte (liest nur die Simulation; jede Bewegung haengt an einem echten Zustand):
## 1) Kueste: Badegaeste und Schwimmer (nur bei Waerme, trocken, tagsueber), Brandung, Segelboote, Moewen ueber Hafen und Strand.
## 2) Industrie: Bergwerk (Bagger, pendelnde Muldenkipper, Staub, Halde nach Foerdermenge), Schlote/Hochofenglut/Funken, Traktor
##    auf bewirtschafteten Feldern, Weidetiere, Hafenkran bei angelegtem Schiff - nur solange der Betrieb laeuft.
## 3) Stadtleben: Fussgaenger (Pendelzeiten, bei Regen mit Schirm), Cafe-/Restaurantterrassen, Laternenlicht nachts.
## Jeder Ort ist ein eigener Knoten (Spot) in der y-sortierten Gebaeudeebene; gezeichnet wird nur, was im Bild liegt.

const STEP := 18.0
const SC := 1.8          # Figuren und Fahrzeuge gegenueber Pixelmass (ein Feld ist 64 Bildpunkte breit)
const MAX_BEACH := 140
const MAX_WALK := 180
const MAX_BOATS := 10
const MAX_STEG := 5
const MAX_FIRE := 6
const MAX_HOF := 120
const HOF_RESCAN := 15   # alle 15 Geschaeftsscans (30 s) Innenhoefe neu pruefen (Neubauten)
const RESCAN_S := 2.0
const SKIN := [Color("f1c7a1"), Color("d9a47c"), Color("a8714f"), Color("7a4e33")]
const CLOTH := [Color("e8553d"), Color("3d7cc8"), Color("f2c14e"), Color("4f9a5b"), Color("a05cc0"), Color("f08aa8"), Color("2b2b2b"), Color("eeeeee")]

var sim: Simulation
var cv
var t := 0.0
var beach := 0.0          # 0..1 Strandwetter
var walk := 0.0           # 0..1 Fussgaengeraufkommen
var night := false
var rain := false
var wind := Vector2(1, 0)
var _biz_spots := {}      # Schluessel -> Spot
var _rescan := 0.0
var _spots: Array = []
var ground: GroundOverlay   # Bodenebene unter allen Gebaeuden (Flachwasser, Gaerten): statisch, nur bei neuem Ausschnitt neu gezeichnet
var foam: FoamOverlay       # Schaumkanten am Ufer: bewegt, je Bild, nur ueber die gemerkten Uferzellen
var shore: Array = []       # [Zelle, [Richtungen zur Landseite]] - einmal gesucht, beim Innenhof-Rescan erneuert
var _shore_key := 0
const GROUND_MIN_ZOOM := 0.3   # darunter waeren Schaum, Hecken und Blumen 1-2 Bildpunkte gross (Partie 09.11.: halbe Bildzeit)
var lights: EveningLights  # Lichtebene ueber der Nachtfaerbung (Laternen, Lagerfeuer, Steglaternen)
var hour := 12.0
var temp := 15.0
var _courts := {}          # Zelle -> Spot (Innenhof)
var _court_scans := 0


func setup(simulation: Simulation, city_view) -> void:
	sim = simulation
	cv = city_view
	_build_coast()
	_build_walkers()
	_build_harbors()
	_scan_business()
	ground = GroundOverlay.new()
	ground.view = self
	cv.decor_node.add_child(ground)
	foam = FoamOverlay.new()
	foam.view = self
	cv.decor_node.add_child(foam)
	_scan_shore()
	_build_courts()
	lights = EveningLights.new()
	lights.view = self
	cv.lights_layer.add_child(lights)


func _add(kind: String, cell: Vector2, data: Dictionary, parent: Node = self) -> Spot:
	var s := Spot.new()
	s.view = self
	s.kind = kind
	s.world = cell * 32.0
	s.data = data
	s.position = Iso.to_screen(s.world)
	parent.add_child(s)
	_spots.append(s)
	return s


func _h(a: int, b: int) -> int:
	return absi(hash(Vector2i(a, b)))


# ------------------------------------------------------------------ Kueste
## Badestege an Promenadenstraenden (weit weg vom Hafen, mind. 18 Felder auseinander) und Lagerfeuerplaetze an ruhigen Strandstuecken.
func _build_jetties() -> void:
	var C := sim.city
	var ports: Array = []
	if sim.towns != null:
		for k in sim.towns.count():
			var H: Harbor = sim.towns.harbor(k)
			var b: Dictionary = C.building(H.building)
			if not b.is_empty():
				ports.append(Vector2(float(b.x), float(b.y)))
	var placed: Array = []
	var fires: Array = []
	for sp in _spots.duplicate():
		if sp.kind != "strand":
			continue
		var c := Vector2i(sp.world / 32.0)
		var cf := Vector2(c)
		if ports.any(func(pt): return pt.distance_to(cf) < 14.0):
			continue
		var near_road := false
		for dy in range(-8, 9):
			for dx in range(-8, 9):
				var q0 := c + Vector2i(dx, dy)
				near_road = near_road or (C.inside(q0) and C.is_road(q0))
		if near_road and placed.size() < MAX_STEG and placed.all(func(pt): return pt.distance_to(cf) >= 18.0):
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n := 0
				while n < 5 and C.inside(c + d * (n + 1)) and C.g(c + d * (n + 1)) == CityData.G.WATER:
					n += 1
				if n >= 3 and C.g(c + d) == CityData.G.WATER:
					_add("steg", cf + Vector2(0.5, 0.5), {"dir": Vector2(d), "len": float(n), "seed": int(sp.data.seed)})
					placed.append(cf)
					break
		if placed.has(cf):
			continue
		if not bool(sp.data.promenade) and fires.size() < MAX_FIRE and int(sp.data.seed) % 5 == 0 and fires.all(func(pt): return pt.distance_to(cf) >= 16.0):
			_add("feuer", cf + Vector2(0.5, 0.5), {"seed": int(sp.data.seed), "shore": sp.data.shore})
			fires.append(cf)


## Innenhoefe: freie Rasenfelder, die von drei oder vier Seiten (je bis 3 Felder) bebaut und nicht an der Strasse sind - Waescheleine,
## Spielplatz, Gemuesebeet mit Gartenhaus oder Baum mit Bank. Neubauten verdraengen den Hof, neue Bloecke bekommen einen.
func _build_courts() -> void:
	var C := sim.city
	var seen := {}
	var y := 3
	while y < C.size - 3:
		var x := 3
		while x < C.size - 3:
			var c := Vector2i(x, y)
			if _court_ok(C, c) and (_courts.has(c) or not seen.keys().any(func(o): return absi(o.x - c.x) + absi(o.y - c.y) < 4)):
				seen[c] = true
				if not _courts.has(c) and _courts.size() < MAX_HOF:
					_courts[c] = _add("hof", Vector2(c) + Vector2(0.5, 0.5), {"seed": _h(x * 3, y * 5)})
			x += 2
		y += 2
	for c in _courts.keys():
		if not seen.has(c):
			var sp: Spot = _courts[c]
			_spots.erase(sp)
			sp.queue_free()
			_courts.erase(c)


func _court_ok(C: CityData, c: Vector2i) -> bool:
	if C.g(c) != CityData.G.GRASS or C.building_at[C.idx(c)] != -1:
		return false
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var q := c + Vector2i(dx, dy)
			if not C.inside(q) or C.is_road(q) or C.building_at[C.idx(q)] != -1 or C.g(q) == CityData.G.WATER:
				return false
	var sides := 0
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		for k in range(2, 5):
			var q2: Vector2i = c + d * k
			if C.inside(q2) and C.building_at[C.idx(q2)] >= 0:
				sides += 1
				break
	return sides >= 3


func _build_coast() -> void:
	var C := sim.city
	var n := 0
	var y := 2
	while y < C.size - 2 and n < MAX_BEACH:
		var x := 2
		while x < C.size - 2 and n < MAX_BEACH:
			var c := Vector2i(x, y)
			if C.g(c) == CityData.G.SAND:
				var shore: Array = []
				for dy in range(-3, 4):
					for dx in range(-3, 4):
						var q := c + Vector2i(dx, dy)
						if C.inside(q) and C.g(q) == CityData.G.WATER:
							shore.append(Vector2(dx, dy))
				if not shore.is_empty():
					var prom := false
					for dy2 in range(-3, 4):
						for dx2 in range(-3, 4):
							var q2 := c + Vector2i(dx2, dy2)
							prom = prom or (C.inside(q2) and C.is_road(q2))
					_add("strand", Vector2(c) + Vector2(0.5, 0.5), {"shore": shore.slice(0, 6), "seed": _h(x, y), "promenade": prom})
					n += 1
			x += 4
		y += 4
	# Segelboote: offenes Wasser 5..14 Felder vor der Kueste, Kreisbahn ganz auf Wasser
	var boats := 0
	y = 8
	while y < C.size - 8 and boats < MAX_BOATS:
		var x2 := 8
		while x2 < C.size - 8 and boats < MAX_BOATS:
			var c2 := Vector2i(x2, y)
			if C.g(c2) == CityData.G.WATER and _near_land(c2, 14) and not _near_land(c2, 5):
				var r := 3.0 + float(_h(x2, y) % 3)
				var wet := true
				for i in 8:
					var q2 := c2 + Vector2i((Vector2(r, 0).rotated(TAU * i / 8.0)).round())
					wet = wet and C.inside(q2) and C.g(q2) == CityData.G.WATER
				if wet:
					_add("boot", Vector2(c2) + Vector2(0.5, 0.5), {"r": r, "seed": _h(x2, y), "segel": CLOTH[_h(y, x2) % CLOTH.size()]})
					boats += 1
			x2 += 23
		y += 19
	_build_jetties()
	# Moewen ueber Straenden (Auswahl) - in der Effektebene ueber allem
	var k := 0
	for s in _spots.duplicate():
		if s.kind == "strand" and k % 9 == 0:
			_add("moewen", s.world / 32.0 + Vector2(1.5, -1.0), {"seed": int(s.data.seed)}, cv.fx_node)
		k += 1 if s.kind == "strand" else 0


func _near_land(c: Vector2i, r: int) -> bool:
	for dy in range(-r, r + 1, maxi(1, r / 3)):
		for dx in range(-r, r + 1, maxi(1, r / 3)):
			var q := c + Vector2i(dx, dy)
			if sim.city.inside(q) and sim.city.g(q) not in [CityData.G.WATER]:
				return true
	return false


# ------------------------------------------------------------------ Stadtleben
func _build_walkers() -> void:
	var C := sim.city
	var n := 0
	var y := 3
	while y < C.size - 3 and n < MAX_WALK:
		var x := 3
		while x < C.size - 3 and n < MAX_WALK:
			var c := Vector2i(x, y)
			var walkable := [CityData.G.SIDEWALK, CityData.G.ROAD, CityData.G.PLAZA]
			if C.g(c) in walkable and _near_houses(c):
				var dir := Vector2i(1, 0) if C.inside(c + Vector2i(1, 0)) and C.g(c + Vector2i(1, 0)) == C.g(c) else Vector2i(0, 1)
				var len := 0
				while len < 7 and C.inside(c + dir * (len + 1)) and C.g(c + dir * (len + 1)) == C.g(c):
					len += 1
				if len >= 2:
					var side := Vector2(-dir.y, dir.x) * (0.42 if C.g(c) == CityData.G.ROAD else 0.0)   # auf der Strasse: am Rand (Gehweg der Grafik)
					_add("passanten", Vector2(c) + Vector2(0.5, 0.5) + side, {"dir": Vector2(dir), "len": float(len), "seed": _h(x, y), "laterne": (x + y) % 3 == 0})
					n += 1
			x += 3
		y += 3


## Wohn-/Geschaeftsgebaeude in der Naehe? (Passanten nur in bebauten Vierteln, nicht auf Landstrassen)
func _near_houses(c: Vector2i) -> bool:
	for dy in range(-3, 4, 3):
		for dx in range(-3, 4, 3):
			var q := c + Vector2i(dx, dy)
			if sim.city.inside(q) and sim.city.building_at[sim.city.idx(q)] >= 0:
				return true
	return false


func _build_harbors() -> void:
	if sim.towns == null:
		return
	for k in sim.towns.count():
		var H: Harbor = sim.towns.harbor(k)
		if not H.enabled:
			continue
		var lager: Dictionary = sim.city.building(H.building)
		var port: Dictionary = cv.ship_view._ports.get(k, {})
		if lager.is_empty() or port.is_empty():
			continue
		# Kran auf dem Anleger: Schiff liegt suedlich (berth), abgesetzt wird auf dem Anleger, gelagert am Hafenlager
		var crane := Vector2((float(port.jx0) + float(port.jx1)) * 0.5, float(port.jy) + 0.5)
		var berth: Vector2 = (port.berth as Vector2) / 32.0
		var store := Vector2(float(lager.x) + float(lager.w) * 0.5, float(lager.y) + float(lager.h) + 0.6)
		_add("hafen", crane, {"town": k, "ship": berth - crane, "land": Vector2(0.0, -0.6), "store": store - crane})
		_add("lagerplatz", store, {"town": k})


# ------------------------------------------------------------------ Industrie (Betriebe kommen und gehen)
func _scan_business() -> void:
	var seen := {}
	for b in sim.biz.items.values():
		var kind := ""
		match str(b.branch):
			"bergwerk":
				kind = "bergwerk"
			"stahlwerk", "elektrostahlwerk", "kokerei":
				kind = "huette"
			"muehle", "moebelwerk", "brauerei", "schlachthof":
				kind = "schlot"
			"feld":
				kind = "traktor"
			"tierhaltung":
				kind = "weide"
			"restaurant", "baeckerei":
				kind = "terrasse"
		if kind == "" or b.status == "geschlossen":
			continue
		var bld: Dictionary = sim.city.building(int(b.site))
		if bld.is_empty():
			continue
		var key := "%s:%s" % [kind, b.id]
		seen[key] = true
		if _biz_spots.has(key):
			continue
		var anchor := Vector2(float(bld.x) + float(bld.w) * 0.5, float(bld.y) + float(bld.h) * 0.5)
		var data := {"biz": str(b.id), "w": float(bld.w), "h": float(bld.h), "seed": _h(int(bld.x), int(bld.y))}
		if kind == "traktor" or kind == "weide":
			var p: Dictionary = sim.parcels.parcel(str(b.get("parcel", "")))
			if not p.is_empty() and p.has("rect"):
				data["rect"] = Rect2(float(p.rect[0]), float(p.rect[1]), float(p.rect[2]), float(p.rect[3]))
				anchor = data.rect.position + data.rect.size * 0.5
		if kind == "terrasse":
			anchor = Vector2(float(bld.x) + float(bld.w) + 0.4, float(bld.y) + float(bld.h) - 0.6)
		if kind in ["bergwerk", "huette", "schlot"]:
			# Vorderkante des Gebaeudes: so zeichnet die Tiefensortierung Bagger/Halde davor und Schlote ueber das Dach
			anchor = Vector2(float(bld.x) + float(bld.w) + 0.3, float(bld.y) + float(bld.h) + 0.3)
		_biz_spots[key] = _add(kind, anchor, data)
	for key in _biz_spots.keys():
		if not seen.has(key):
			var s: Spot = _biz_spots[key]
			_spots.erase(s)
			s.queue_free()
			_biz_spots.erase(key)


## Uferzellen (Wasser mit Land daneben, kein Kai) einmal suchen: der Schaum lief vorher je Bild ueber jede Zelle des Ausschnitts.
func _scan_shore() -> void:
	var C: CityData = sim.city
	var key := hash(C.ground)   # nativ und schnell; neu suchen nur, wenn sich Boden/Wasser/Kai geaendert hat
	if key == _shore_key:
		return
	_shore_key = key
	shore = []
	for y in C.size:
		for x in C.size:
			var q := Vector2i(x, y)
			if C.g(q) != CityData.G.WATER:
				continue
			var dirs: Array = []
			var quay := false
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = q + d
				if C.inside(n):
					var g: int = C.g(n)
					if g == CityData.G.QUAY:
						quay = true
					elif g != CityData.G.WATER:
						dirs.append(d)
			if not dirs.is_empty() and not quay:
				shore.append([q, dirs])


# ------------------------------------------------------------------ Takt
func update_view(delta: float) -> void:
	if sim == null:
		return
	t += delta
	_rescan += delta
	if _rescan >= RESCAN_S:
		_rescan = 0.0
		_scan_business()
		_court_scans += 1
		if _court_scans >= HOF_RESCAN:
			_court_scans = 0
			_build_courts()
			_scan_shore()
			ground.drawn = Rect2()   # Neubauten (Gaerten) beim naechsten Bild zeichnen
	hour = Catalog.hour_of_day(sim.game_min)
	night = hour >= 20.5 or hour < 5.5
	var wx: Weather = sim.wx
	rain = wx.is_rain() or wx.is_snow()
	temp = float(wx.cur.get("temp", 15.0))
	beach = 0.0 if rain or night or hour < 9.0 or hour > 19.5 else clampf((temp - 15.0) / 10.0, 0.0, 1.0)
	if beach > 0.0:
		beach = maxf(beach, 0.25)
	walk = 1.0 if (hour >= 7.0 and hour < 9.0) or (hour >= 16.0 and hour < 19.0) else (0.6 if hour >= 9.0 and hour < 16.0 else (0.3 if hour >= 19.0 and hour < 23.0 else 0.05))
	if rain:
		walk *= 0.5
	wind = Vector2(1, -0.3).normalized() * (0.6 + clampf(float(wx.cur.get("wind", 10.0)) / 40.0, 0.0, 1.5))
	# nur Sichtbares zeichnen
	var cam: Camera2D = cv.camera
	var half := get_viewport_rect().size / cam.zoom * 0.5 + Vector2(160, 160)
	var view := Rect2(cam.position - half, half * 2.0)
	var zoom_ok := cam.zoom.x >= GROUND_MIN_ZOOM
	ground.visible = zoom_ok
	foam.visible = zoom_ok
	if zoom_ok:
		# statische Ebene: nur neu zeichnen, wenn der Ausschnitt die gezeichnete Flaeche verlaesst oder der Zoom sich deutlich aendert
		if not ground.drawn.encloses(view) or absf(ground.drawn_zoom - cam.zoom.x) > cam.zoom.x * 0.15:
			ground.view_rect = view.grow(maxf(view.size.x, view.size.y) * 0.25)
			ground.drawn = ground.view_rect
			ground.drawn_zoom = cam.zoom.x
			ground.queue_redraw()
		foam.view_rect = view
		foam.queue_redraw()
	lights.queue_redraw()
	for s in _spots:
		var vis: bool = view.has_point(s.position)
		s.visible = vis
		if vis:
			s.queue_redraw()


func is_active(biz_id: String) -> bool:
	var b: Dictionary = sim.biz.get_b(biz_id)
	return not b.is_empty() and str(b.status) in ["aktiv", "demo"]


## Ein belebter Ort; zeichnet relativ zu seinem Ankerpunkt (lokale Koordinaten in Feldern, z in Hoehenstufen).
class Spot extends Node2D:
	var view: AmbientView
	var kind := ""
	var world := Vector2.ZERO
	var data := {}

	func _p(dx: float, dy: float, z: float = 0.0) -> Vector2:
		return Iso.to_screen(world + Vector2(dx, dy) * 32.0) - Iso.to_screen(world) + Vector2(0, -z * AmbientView.STEP)

	func _draw() -> void:
		match kind:
			"strand":
				_strand()
			"boot":
				_boot()
			"moewen":
				_moewen()
			"passanten":
				_passanten()
			"hafen":
				_hafen()
			"lagerplatz":
				_lagerplatz()
			"bergwerk":
				_bergwerk()
			"huette":
				_huette()
			"schlot":
				_schlot(Vector2(-float(data.w) * 0.5 - 0.3, -float(data.h) * 0.5 - 0.3), 2.8, 4)
			"traktor":
				_traktor()
			"weide":
				_weide()
			"terrasse":
				_terrasse()
			"steg":
				_steg()
			"feuer":
				_feuer()
			"hof":
				_hof()

	## Lichtpunkte fuer die Abendebene: [lokaler Punkt, Radius, Farbe]. Nur was wirklich leuchtet.
	func glows() -> Array:
		match kind:
			"strand":
				if bool(data.get("promenade", false)):
					var lw := _landward()
					return [[_p(lw.x * 1.4, lw.y * 1.4) + Vector2(0, -32), 34.0, Color(1.0, 0.82, 0.5)]]
			"steg":
				var d: Vector2 = data.dir
				var e := d * (float(data.len) + 0.3)
				return [[_p(e.x, e.y, 0.3) + Vector2(0, -26), 30.0, Color(1.0, 0.78, 0.45)]]
			"feuer":
				if _fire_on():
					return [[_p(0, 0) + Vector2(0, -6), 70.0 + 6.0 * sin(view.t * 9.0), Color(1.0, 0.55, 0.2)]]
			"terrasse":
				if view.is_active(str(data.biz)) and view.hour >= 18.0 and view.hour < 23.0 and not view.rain:
					return [[_p(0.5, 0.2) + Vector2(0, -16), 40.0, Color(1.0, 0.75, 0.4)]]
		return []

	func _landward() -> Vector2:
		var lw := Vector2.ZERO
		for w in data.get("shore", []):
			lw -= w
		return lw.normalized() if lw.length() > 0.01 else Vector2(-1, 0)

	func _fire_on() -> bool:
		return not view.rain and view.temp > 6.0 and (view.hour >= 19.5 or view.hour < 0.5)

	func _bench(at: Vector2, facing: Vector2) -> void:
		var bp := _p(at.x, at.y)
		var side := _p(-facing.y * 0.35, facing.x * 0.35) - _p(0, 0)
		draw_line(bp - side, bp + side, Color("6b4f36"), 4.0)                                  # Sitz
		draw_line(bp - side + Vector2(0, -7), bp + side + Vector2(0, -7), Color("7d5c3f"), 3.0)  # Lehne
		draw_line(bp - side, bp - side + Vector2(0, 4), Color("3a3a3a"), 2.0)
		draw_line(bp + side, bp + side + Vector2(0, 4), Color("3a3a3a"), 2.0)

	## Badesteg: Holzplanken auf Pfaehlen ins Wasser; tagsueber ein Angler am Kopf, abends Laterne.
	func _steg() -> void:
		var d: Vector2 = data.dir
		var side := Vector2(-d.y, d.x) * 0.28
		var L := float(data.len) + 0.3
		var z := 0.3
		var a := d * 0.2
		var e := d * L
		var deck := PackedVector2Array([_p((a - side).x, (a - side).y, z), _p((e - side).x, (e - side).y, z), _p((e + side).x, (e + side).y, z), _p((a + side).x, (a + side).y, z)])
		var i := 0.6
		while i < L:   # Pfaehle
			for sg in [-1.0, 1.0]:
				var pp: Vector2 = d * i + side * sg
				draw_line(_p(pp.x, pp.y, 0.0) + Vector2(0, 5), _p(pp.x, pp.y, z), Color("4a3826"), 3.0)
			i += 1.0
		draw_colored_polygon(deck, Color("a07a50"))
		var k := 0.4
		while k < L:   # Plankenfugen
			var q := d * k
			draw_line(_p((q - side).x, (q - side).y, z), _p((q + side).x, (q + side).y, z), Color("7d5c3f"), 1.0)
			k += 0.25
		var lp := _p(e.x, e.y, z) + _p(side.x, side.y) - _p(0, 0)
		draw_line(lp, lp + Vector2(0, -24), Color("2f3a40"), 2.0)
		draw_rect(Rect2(lp + Vector2(-3, -29), Vector2(6, 6)), Color("ffe3a0") if view.night else Color("2f3a40"))
		if not view.night and not view.rain and view.hour >= 6.0:   # Angler mit Rute und wippendem Schwimmer
			var fp := e - side * 0.5 - d * 0.3
			_person(fp, z, int(data.seed) + 11)
			var hand := _p(fp.x, fp.y, z) + Vector2(2, -18)
			var tip := hand + _p(d.x * 1.2, d.y * 1.2) - _p(0, 0) + Vector2(0, -16)
			draw_line(hand, tip, Color("3a2a1a"), 1.5)
			var bob := tip + Vector2(0, 30 + 2.0 * sin(view.t * 2.5))
			draw_line(tip, bob, Color(0.9, 0.9, 0.9, 0.6), 1.0)
			draw_circle(bob, 2.5, Color("e8553d"))

	## Lagerfeuer am ruhigen Strand: Steinring und Holz immer; abends (trocken, nicht kalt) Flammen, Funken und Leute im Kreis.
	func _feuer() -> void:
		var c := _p(0, 0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.6, 1.6))
		for i in 8:
			var ang := TAU * float(i) / 8.0
			draw_circle(c + Vector2(cos(ang) * 11.0, sin(ang) * 5.5), 2.5, Color("8f8a84"))
		draw_line(c + Vector2(-7, 2), c + Vector2(7, -2), Color("5a4030"), 3.0)
		draw_line(c + Vector2(-6, -2), c + Vector2(6, 2), Color("6b4f36"), 3.0)
		if not _fire_on():
			_end()
			return
		for f in 3:
			var fl := 10.0 + 5.0 * sin(view.t * (7.0 + f) + f * 2.0)
			var w := 6.0 - f * 1.5
			var col: Color = [Color("e8553d"), Color("f28b2c"), Color("ffd35a")][f]
			draw_colored_polygon(PackedVector2Array([c + Vector2(-w, 0), c + Vector2(sin(view.t * 5.0 + f) * 2.0, -fl - f * 2.0), c + Vector2(w, 0)]), col)
		for sp in 4:   # Funken steigen auf
			var k := fmod(view.t * 0.7 + sp * 0.27, 1.0)
			draw_circle(c + Vector2(sin(k * 9.0 + sp) * 6.0, -14.0 - k * 40.0), 1.2, Color(1.0, 0.8, 0.3, 1.0 - k))
		_end()
		for g in 4:   # Leute im Kreis
			var ang2 := TAU * (float(g) + 0.5) / 4.0
			_person(Vector2(cos(ang2) * 0.8, sin(ang2) * 0.8), 0.0, int(data.seed) + g * 13)

	## Innenhof (seedstabil eine von vier Nutzungen).
	func _hof() -> void:
		var seed: int = data.seed
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.5, 1.5))
		match seed % 4:
			0:   # Waescheleine, Waesche weht im Wind
				var a := _p(-0.6, -0.2)
				var b := _p(0.6, 0.2)
				draw_line(a, a + Vector2(0, -20), Color("6b6b6b"), 2.0)
				draw_line(b, b + Vector2(0, -20), Color("6b6b6b"), 2.0)
				draw_line(a + Vector2(0, -19), b + Vector2(0, -19), Color("dddddd"), 1.0)
				if not view.rain:
					for i in 4:
						var tp := (a + Vector2(0, -19)).lerp(b + Vector2(0, -19), 0.15 + 0.23 * i)
						var sway := sin(view.t * 2.2 + i) * 2.5 * view.wind.length()
						var col: Color = AmbientView.CLOTH[(seed / 3 + i) % AmbientView.CLOTH.size()]
						draw_colored_polygon(PackedVector2Array([tp + Vector2(-4, 0), tp + Vector2(4, 0), tp + Vector2(4 + sway, 9), tp + Vector2(-4 + sway, 9)]), col)
			1:   # Spielplatz: Sandkasten und Schaukel, tagsueber mit Kind
				var sb := _p(-0.4, 0.3)
				draw_colored_polygon(PackedVector2Array([sb + Vector2(-14, 0), sb + Vector2(0, -7), sb + Vector2(14, 0), sb + Vector2(0, 7)]), Color("e3cf98"))
				draw_polyline(PackedVector2Array([sb + Vector2(-14, 0), sb + Vector2(0, -7), sb + Vector2(14, 0), sb + Vector2(0, 7), sb + Vector2(-14, 0)]), Color("8a6b4a"), 2.0)
				var sw := _p(0.5, -0.3)
				draw_line(sw + Vector2(-10, 0), sw + Vector2(-6, -26), Color("c8553d"), 2.0)
				draw_line(sw + Vector2(10, 0), sw + Vector2(6, -26), Color("c8553d"), 2.0)
				draw_line(sw + Vector2(-6, -26), sw + Vector2(6, -26), Color("c8553d"), 2.0)
				var day := not view.night and not view.rain and view.hour >= 9.0 and view.hour < 19.0
				var ang := sin(view.t * 2.4) * (0.6 if day else 0.05)
				var seat := sw + Vector2(0, -26) + Vector2(sin(ang), cos(ang)) * 18.0
				draw_line(sw + Vector2(0, -26), seat, Color("555555"), 1.0)
				draw_line(seat + Vector2(-3, 0), seat + Vector2(3, 0), Color("6b4f36"), 2.0)
				if day:
					draw_rect(Rect2(seat + Vector2(-2, -6), Vector2(4, 5)), AmbientView.CLOTH[seed % AmbientView.CLOTH.size()])
					draw_circle(seat + Vector2(0, -8), 1.8, AmbientView.SKIN[seed % AmbientView.SKIN.size()])
			2:   # Gemuesebeet und Gartenhaus
				for r in 3:
					for k in 4:
						var bp := _p(-0.7 + k * 0.3, -0.2 + r * 0.3)
						draw_circle(bp, 2.6, Color("4f9a5b") if (r + k) % 2 == 0 else Color("6fb46a"))
				var hs := _p(0.6, 0.4)
				draw_rect(Rect2(hs + Vector2(-8, -12), Vector2(16, 12)), Color("8a6b4a"))
				draw_colored_polygon(PackedVector2Array([hs + Vector2(-10, -12), hs + Vector2(0, -19), hs + Vector2(10, -12)]), Color("a0473a"))
				draw_rect(Rect2(hs + Vector2(-2, -8), Vector2(4, 8)), Color("5a4030"))
			_:   # Baum mit Bank, bei schoenem Wetter sitzt jemand
				var tp2 := _p(0.2, -0.2)
				draw_line(tp2, tp2 + Vector2(0, -14), Color("6b4f36"), 3.0)
				draw_circle(tp2 + Vector2(0, -22), 12.0, Color("3f7a3a"))
				draw_circle(tp2 + Vector2(-4, -26), 7.0, Color("5a9a4a"))
				_bench(Vector2(-0.4, 0.4), Vector2(1, 0))
				if view.walk >= 0.6 and not view.rain:
					_person(Vector2(-0.6, 0.6), 0.0, seed + 5)
		_end()

	## Strandausstattung je Ort (seedstabil): Duenengras zur Landseite, Steine, Treibholz am Wasser, Laterne an der Promenade.
	func _strand_gut() -> void:
		var seed: int = data.seed
		var shore: Array = data.shore
		var landward := Vector2.ZERO
		for w in shore:
			landward -= w
		landward = landward.normalized() if landward.length() > 0.01 else Vector2(-1, 0)
		for i in 3:   # Duenengras: Buesche aus Halmen, wiegen sich im Wind
			var at := landward * (0.9 + 0.35 * float(i)) + Vector2(float((seed >> (i * 4)) % 5) * 0.2 - 0.4, float((seed >> (i * 2)) % 5) * 0.2 - 0.4)
			var gp := _p(at.x, at.y)
			var sway := sin(view.t * 1.6 + float(i + seed % 7)) * 2.0 * view.wind.length()
			for h in 5:
				var dx := float(h - 2) * 2.5
				draw_line(gp + Vector2(dx, 0), gp + Vector2(dx * 1.6 + sway, -10.0 - float(h % 3) * 3.0), Color("8aa35a") if h % 2 == 0 else Color("a8b86a"), 1.5)
		if seed % 3 == 0:   # Steine
			var rp := _p(landward.x * 0.3 + 0.3, landward.y * 0.3 - 0.2)
			draw_colored_polygon(PackedVector2Array([rp + Vector2(-7, 0), rp + Vector2(-3, -5), rp + Vector2(5, -4), rp + Vector2(8, 0), rp + Vector2(2, 3)]), Color("8f8a84"))
			draw_colored_polygon(PackedVector2Array([rp + Vector2(-3, -5), rp + Vector2(5, -4), rp + Vector2(2, -1)]), Color("aaa59e"))
		if seed % 4 == 1 and not shore.is_empty():   # Treibholz an der Wasserlinie
			var w0: Vector2 = shore[0] * 0.45
			draw_line(_p(w0.x - 0.3, w0.y), _p(w0.x + 0.25, w0.y + 0.15), Color("8a6b4a"), 3.0)
			draw_line(_p(w0.x + 0.05, w0.y + 0.05), _p(w0.x + 0.2, w0.y - 0.15), Color("7a5b3a"), 2.0)
		if bool(data.get("promenade", false)):   # Laterne an der Promenade, warmes Licht abends
			var lp := _p(landward.x * 1.4, landward.y * 1.4)
			draw_line(lp, lp + Vector2(0, -30), Color("2f3a40"), 2.0)
			draw_rect(Rect2(lp + Vector2(-3, -35), Vector2(6, 5)), Color("2f3a40"))
			if view.night:
				draw_circle(lp + Vector2(0, -32), 3.0, Color("ffe3a0"))
			var wk := 0.2   # Bohlenweg durch die Duene von der Strasse zum Wasser
			while wk < 1.3:
				var pa := landward * wk
				var sd := Vector2(-landward.y, landward.x) * 0.22
				draw_line(_p((pa - sd).x, (pa - sd).y), _p((pa + sd).x, (pa + sd).y), Color("a07a50"), 3.0)
				wk += 0.16
			if seed % 2 == 0:
				_bench(landward * 1.0 + Vector2(-landward.y, landward.x) * 0.7, -landward)

	# ---- Figuren
	func _at(pt: Vector2) -> void:
		draw_set_transform(pt, 0.0, Vector2(AmbientView.SC, AmbientView.SC))

	func _end() -> void:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	func _person(at: Vector2, z: float, seed: int, phase: float = 0.0, umbrella: bool = false) -> void:
		_at(_p(at.x, at.y, z))
		var base := Vector2.ZERO
		var step := sin(phase) * 1.5
		var cloth: Color = AmbientView.CLOTH[seed % AmbientView.CLOTH.size()]
		draw_line(base + Vector2(-1, 0), base + Vector2(-1 + step, -5), Color("2b2b33"), 1.5)
		draw_line(base + Vector2(1, 0), base + Vector2(1 - step, -5), Color("2b2b33"), 1.5)
		draw_rect(Rect2(base + Vector2(-2.5, -11), Vector2(5, 6)), cloth)
		draw_circle(base + Vector2(0, -13), 2.2, AmbientView.SKIN[(seed / 7) % AmbientView.SKIN.size()])
		if umbrella:
			draw_line(base + Vector2(2, -9), base + Vector2(2, -19), Color("333333"), 1.0)
			draw_colored_polygon(PackedVector2Array([base + Vector2(-5, -18), base + Vector2(2, -23), base + Vector2(9, -18)]), AmbientView.CLOTH[(seed / 3) % AmbientView.CLOTH.size()])
		_end()

	# ---- 1) Kueste
	func _strand() -> void:
		var shore: Array = data.shore
		_strand_gut()
		var tt: float = view.t
		for i in shore.size():   # Brandung: Schaumkronen laufen auf
			var w: Vector2 = shore[i]
			var k := fmod(tt * 0.35 + float(i) * 0.37, 1.0)
			var a := Color(1, 1, 1, 0.55 * (1.0 - k))
			draw_arc(_p(w.x * (1.0 - k * 0.3), w.y * (1.0 - k * 0.3)), 9.0 + k * 6.0, PI * 0.9, PI * 1.9, 8, a, 2.0)
		var people := int(round(float(view.beach) * float(3 + int(data.seed) % 4)))
		if people <= 0:
			return
		var seed: int = data.seed
		for i in people:
			var off := Vector2(float((seed >> (i * 3)) % 7) * 0.22 - 0.7, float((seed >> (i * 5)) % 5) * 0.2 - 0.4)
			var towel: Color = AmbientView.CLOTH[(seed / (i + 3)) % AmbientView.CLOTH.size()]
			if i % 2 == 0:   # Handtuch mit Liegenden, Sonnenschirm
				draw_colored_polygon(PackedVector2Array([_p(off.x - 0.35, off.y - 0.16), _p(off.x + 0.35, off.y - 0.16), _p(off.x + 0.35, off.y + 0.16), _p(off.x - 0.35, off.y + 0.16)]), towel)
				_at(_p(off.x, off.y))
				draw_line(Vector2(-6, -2), Vector2(5, 1), AmbientView.SKIN[(seed + i) % 4], 3.0)
				draw_circle(Vector2(-7, -3), 2.2, AmbientView.SKIN[(seed + i) % 4])
				draw_line(Vector2(9, -4), Vector2(9, -24), Color("dddddd"), 1.0)
				draw_colored_polygon(PackedVector2Array([Vector2(-2, -22), Vector2(9, -28), Vector2(20, -22)]), towel.lightened(0.15))
				draw_colored_polygon(PackedVector2Array([Vector2(-2, -22), Vector2(9, -28), Vector2(9, -22)]), towel.lightened(0.35))
				_end()
			else:   # Schwimmer im Wasser (Kopf wippt) oder Kind mit Ball am Ufer
				if shore.size() > i:
					var w2: Vector2 = shore[i] * 0.8
					var bob := sin(view.t * 2.0 + float(i)) * 1.5
					_at(_p(w2.x, w2.y) + Vector2(0, bob))
					draw_circle(Vector2.ZERO, 2.6, AmbientView.SKIN[(seed + i) % 4])
					draw_arc(Vector2(0, 2), 5.0, 0.0, PI, 8, Color(1, 1, 1, 0.6), 1.2)
					draw_line(Vector2(-6, 1 + sin(view.t * 3.0 + i) * 2.0), Vector2(-3, 0), AmbientView.SKIN[(seed + i) % 4], 1.5)
					_end()
				else:
					_person(off, 0.0, seed + i, view.t * 6.0)
					var ball := _p(off.x + 0.4, off.y) + Vector2(0, -absf(sin(view.t * 3.0)) * 18.0)
					draw_circle(ball, 3.5, Color("f24b3a"))

	func _boot() -> void:
		var tt: float = view.t * 0.08 + float(data.seed % 100) * 0.06
		var r: float = data.r
		var pos := Vector2(cos(tt), sin(tt)) * r
		var head := Vector2(-sin(tt), cos(tt))
		var bob := sin(view.t * 1.7 + float(data.seed % 7)) * 1.2
		_at(_p(pos.x, pos.y) + Vector2(0, bob))
		var c := Vector2.ZERO
		var f := Iso.to_screen(head * 32.0).normalized() * 9.0
		var s := Vector2(-f.y, f.x) * 0.35
		draw_colored_polygon(PackedVector2Array([c + f, c - f + s, c - f - s]), Color("f4efe4"))   # Rumpf
		draw_line(c - f * 0.9, c - f * 2.2, Color(1, 1, 1, 0.45), 2.0)   # Kielwasser
		if view.night:
			draw_circle(c + Vector2(0, -6), 2.0, Color("ffd76a"))
			_end()
			return
		draw_line(c, c + Vector2(0, -22), Color("6b5b48"), 1.5)   # Mast und Segel
		var sail: Color = data.segel
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -21), c + Vector2(0, -3), c + Vector2(10.0 * signf(f.x + 0.01), -4)]), sail)
		_end()

	func _moewen() -> void:
		if view.rain and view.night:
			return
		for i in 3:
			var a := view.t * (0.45 + i * 0.1) + float(i) * 2.1 + float(data.seed % 10)
			var c := Vector2(cos(a) * (40.0 + i * 14.0), sin(a) * (18.0 + i * 6.0) - 70.0 - i * 10.0)
			var flap := sin(view.t * 9.0 + i) * 3.0
			draw_polyline(PackedVector2Array([c + Vector2(-6, flap), c, c + Vector2(6, flap)]), Color("f4f4f4"), 1.6)

	# ---- 3) Stadtleben
	func _passanten() -> void:
		var seed: int = data.seed
		var n := int(round(float(view.walk) * float(1 + seed % 3)))
		var dir: Vector2 = data.dir
		var length: float = data.len
		if bool(data.laterne) and view.night:   # Laternenlicht
			var lp := _p(0.0, 0.0)
			draw_line(lp, lp + Vector2(0, -24), Color("3a3a3a"), 1.5)
			draw_circle(lp + Vector2(0, -25), 9.0, Color(1.0, 0.85, 0.45, 0.25))
			draw_circle(lp + Vector2(0, -25), 2.5, Color("ffe08a"))
		for i in n:
			var speed := 0.12 + float((seed >> i) % 5) * 0.03
			var k := fmod(view.t * speed + float(i) * 0.37 + float(seed % 13) * 0.07, 2.0)
			var u := k if k <= 1.0 else 2.0 - k
			var at := dir * u * length + Vector2(-dir.y, dir.x) * (0.25 * float(i % 2) - 0.1)
			_person(at, 0.0, seed + i * 11, view.t * 8.0 + i, view.rain)

	func _terrasse() -> void:
		var open: bool = view.is_active(str(data.biz)) and not view.night and not view.rain
		for i in 2:
			_at(_p(0.15 + i * 0.7, 0.2))
			var tp := Vector2.ZERO
			draw_line(tp, tp + Vector2(0, -6), Color("6b4f36"), 1.5)
			draw_line(tp + Vector2(-5, -6), tp + Vector2(5, -6), Color("6b4f36"), 2.0)
			if open:
				draw_line(tp, tp + Vector2(0, -20), Color("dddddd"), 1.0)
				draw_colored_polygon(PackedVector2Array([tp + Vector2(-11, -18), tp + Vector2(0, -24), tp + Vector2(11, -18)]), Color("d94f3d") if i == 0 else Color("f2f2f2"))
				for g in 2:
					var sway := sin(view.t * 1.3 + g + i) * 0.6
					var base := Vector2(-9.0 + 18.0 * g, 2.0)
					draw_rect(Rect2(base + Vector2(-2.5, -9 + sway), Vector2(5, 5)), AmbientView.CLOTH[(int(data.seed) + g + i * 3) % AmbientView.CLOTH.size()])
					draw_circle(base + Vector2(0, -11 + sway), 2.0, AmbientView.SKIN[(int(data.seed) + g) % 4])
			_end()

	# ---- 2) Industrie
	func _smoke(from: Vector2, puffs: int, col: Color, size: float) -> void:
		var w: Vector2 = view.wind
		for i in puffs:
			var k := fmod(view.t * 0.25 + float(i) / float(puffs), 1.0)
			var p := from + Vector2(w.x * k * 46.0, -k * 64.0 + w.y * k * 20.0)
			draw_circle(p, size * (0.5 + k * 1.6), Color(col.r, col.g, col.b, 0.55 * (1.0 - k)))

	func _schlot(at: Vector2, z: float, puffs: int) -> void:
		var top := _p(at.x, at.y, z)
		draw_rect(Rect2(top + Vector2(-3, 0), Vector2(6, 14)), Color("7a4a3a"))
		draw_rect(Rect2(top + Vector2(-3.5, -1), Vector2(7, 3)), Color("4a2e25"))
		if view.is_active(str(data.biz)):
			_smoke(top, puffs, Color("bdbdbd") if not view.night else Color("8d8d99"), 4.0)

	func _huette() -> void:
		var active: bool = view.is_active(str(data.biz))
		var cx := -float(data.w) * 0.5 - 0.3
		var cy := -float(data.h) * 0.5 - 0.3
		for sx in [-0.6, 0.4]:
			var top := _p(cx + sx, cy, 3.4)
			draw_rect(Rect2(top + Vector2(-3.5, 0), Vector2(7, 30)), Color("5e5a56"))
			if active:
				_smoke(top, 5, Color("9a9590"), 5.0)
		var front := _p(cx, -0.3, 0.6)
		var glow := 0.55 + 0.45 * sin(view.t * 3.0) if active else 0.0
		draw_rect(Rect2(front + Vector2(-9, -8), Vector2(18, 9)), Color(0.12, 0.1, 0.1))
		if active:
			draw_rect(Rect2(front + Vector2(-8, -7), Vector2(16, 7)), Color(1.0, 0.45 + glow * 0.3, 0.1, 0.85))
			draw_circle(front + Vector2(0, -4), 16.0, Color(1.0, 0.5, 0.1, 0.12 * glow))
			for i in 6:   # Funken beim Abstich
				var k := fmod(view.t * 1.4 + float(i) * 0.17, 1.0)
				var dir := Vector2(cos(float(i) * 1.7), -1.0).normalized()
				draw_circle(front + dir * k * 22.0 + Vector2(0, k * k * 14.0), 1.3, Color(1.0, 0.85, 0.3, 1.0 - k))

	func _bergwerk() -> void:
		var active: bool = view.is_active(str(data.biz))
		var b: Dictionary = view.sim.biz.get_b(str(data.biz))
		var total := float(b.get("total", 0)) if not b.is_empty() else 0.0
		# Halde waechst mit der Foerdermenge
		var heap := clampf(sqrt(total) / 16.0, 0.4, 3.2)
		var hp := _p(0.9, -1.6)   # Halde neben dem Hof
		draw_colored_polygon(PackedVector2Array([hp + Vector2(-26 * heap, 0), hp + Vector2(0, -16 * heap), hp + Vector2(26 * heap, 0)]), Color("6d5d50"))
		draw_colored_polygon(PackedVector2Array([hp + Vector2(-26 * heap, 0), hp + Vector2(0, -16 * heap), hp + Vector2(0, 0)]), Color("85735f"))
		# Muldenkipper pendeln zwischen Abbaufront und Halde (hinten zuerst)
		for i in 2:
			var k := fmod(view.t * 0.12 + float(i) * 0.5, 1.0) if active else float(i) * 0.5
			var u := k * 2.0 if k < 0.5 else 2.0 - k * 2.0
			var at := Vector2(-0.9, -0.3).lerp(Vector2(0.5, -1.3), u)   # Front <-> Halde, am Hofrand
			_at(_p(at.x, at.y))
			draw_rect(Rect2(Vector2(-8, -9), Vector2(16, 7)), Color("e8a33d"))
			draw_rect(Rect2(Vector2(4, -13), Vector2(5, 5)), Color("d9d9d9"))
			if k < 0.5 and active:   # beladen auf dem Weg zur Halde
				draw_rect(Rect2(Vector2(-7, -12), Vector2(10, 3)), Color("6d5d50"))
			draw_circle(Vector2(-5, -1), 2.5, Color("222222"))
			draw_circle(Vector2(5, -1), 2.5, Color("222222"))
			_end()
		# Bagger an der Abbaufront: Arm schwenkt, Staub, nachts Scheinwerfer
		_at(_p(-1.4, -0.5))
		draw_rect(Rect2(Vector2(-9, -7), Vector2(18, 7)), Color("2f2f2f"))
		draw_rect(Rect2(Vector2(-7, -15), Vector2(13, 8)), Color("f2b632"))
		draw_rect(Rect2(Vector2(1, -21), Vector2(5, 6)), Color("9ec6e0"))
		var swing := sin(view.t * 1.1) * 0.7 if active else 0.0
		var arm_end := Vector2(-6, -14) + Vector2(cos(PI + 0.4 + swing), sin(PI + 0.4 + swing) - 0.6) * 24.0
		draw_line(Vector2(-4, -14), arm_end, Color("e0a52a"), 3.0)
		draw_rect(Rect2(arm_end + Vector2(-4, -2), Vector2(8, 6)), Color("5a4a38"))
		if active:
			for i in 4:
				var k2 := fmod(view.t * 0.3 + float(i) * 0.25, 1.0)
				draw_circle(arm_end + Vector2(k2 * 14.0, -k2 * 18.0), 4.0 + k2 * 8.0, Color(0.75, 0.7, 0.62, 0.35 * (1.0 - k2)))
			if view.night:
				draw_circle(Vector2(0, -22), 24.0, Color(1.0, 0.95, 0.75, 0.14))
				draw_circle(Vector2(0, -22), 2.5, Color("fff3c4"))
		_end()

	func _traktor() -> void:
		if not data.has("rect") or not view.is_active(str(data.biz)) or view.night:
			return
		var r: Rect2 = data.rect
		var lanes := maxi(2, int(r.size.y))
		var k := fmod(view.t * 0.03 + float(int(data.seed) % 10) * 0.1, 1.0) * float(lanes)
		var lane := int(k)
		var u := k - float(lane)
		if lane % 2 == 1:
			u = 1.0 - u
		var at := Vector2(r.position.x + 0.5 + u * (r.size.x - 1.0), r.position.y + 0.5 + float(lane)) - world / 32.0
		_at(_p(at.x, at.y))
		var tp := Vector2.ZERO
		draw_rect(Rect2(tp + Vector2(-7, -9), Vector2(11, 7)), Color("3f8f3a"))
		draw_rect(Rect2(tp + Vector2(-1, -15), Vector2(6, 6)), Color("2f6e2b"))
		draw_circle(tp + Vector2(-5, -1), 3.5, Color("222222"))
		draw_circle(tp + Vector2(4, -2), 2.5, Color("222222"))
		for i in 3:   # Staub hinter dem Traktor
			var d := float(i + 1) * 6.0
			draw_circle(tp + Vector2((-d if lane % 2 == 0 else d), -2), 2.0 + i, Color(0.7, 0.6, 0.45, 0.3 - i * 0.08))
		_end()

	func _weide() -> void:
		if not data.has("rect"):
			return
		var r: Rect2 = data.rect
		for i in 5:
			var s := (int(data.seed) >> i) % 97
			var base := Vector2(r.position.x + 0.5 + float(s % 9) / 9.0 * (r.size.x - 1.0), r.position.y + 0.5 + float(s % 7) / 7.0 * (r.size.y - 1.0))
			var drift := Vector2(sin(view.t * 0.05 + i), cos(view.t * 0.04 + i * 2.0)) * 0.4
			var at := base + drift - world / 32.0
			_at(_p(at.x, at.y))
			var cp := Vector2.ZERO
			var body := Color("f2f2ee") if i % 2 == 0 else Color("6b4a32")
			draw_rect(Rect2(cp + Vector2(-5, -7), Vector2(10, 5)), body)
			draw_rect(Rect2(cp + Vector2(4, -9), Vector2(4, 4)), body.darkened(0.2))
			draw_line(cp + Vector2(-3, -2), cp + Vector2(-3, 0), Color("333333"), 1.0)
			draw_line(cp + Vector2(3, -2), cp + Vector2(3, 0), Color("333333"), 1.0)
			_end()

	const GROUP_COL := {"baustoffe": Color("9a8f80"), "lebensmittel": Color("d9a441"), "getraenke": Color("4f8fd1"), "kuehlware": Color("e8f0f6"), "moebel": Color("a0673a"), "pakete": Color("c8553d"), "elektronik": Color("6a6f78")}

	func _cargo_col(item: String) -> Color:
		var a: Dictionary = Production.art(item)
		return GROUP_COL.get(str(a.get("ladung", "pakete")), Color("c8553d"))

	## Kran und Hafenarbeiter am realen Posten (Harbor.queue[0]): Anschlagen, Heben, Schwenken, Absetzen, leer zurueck; Einfuhr vom Schiff
	## an Land, Ausfuhr umgekehrt. Ohne Posten ruht der Kran mit dem ehrlichen Grund (naechstes Schiff, kein Personal).
	func _hafen() -> void:
		var H: Harbor = view.sim.towns.harbor(int(data.town))
		var ship_pt: Vector2 = data.ship
		var land_pt: Vector2 = data.land
		var store_pt: Vector2 = data.store
		var working: bool = not H.queue.is_empty() and H.rate_per_min() > 0.0
		var pg := H.current_progress()
		var head: Dictionary = H.queue[0] if not H.queue.is_empty() else {}
		var inbound: bool = head.get("dir", "ein") == "ein"
		var src := ship_pt if inbound else land_pt
		var dst := land_pt if inbound else ship_pt
		var swing := 1.0   # 0 = ueber der Quelle, 1 = ueber dem Ziel
		var rope := 18.0
		var loaded := false
		if not H.queue.is_empty():
			if pg < 0.2:
				swing = 0.0; rope = 18.0 + pg / 0.2 * 30.0; loaded = pg > 0.15              # Anschlagen
			elif pg < 0.35:
				swing = 0.0; rope = 48.0 - (pg - 0.2) / 0.15 * 32.0; loaded = true           # Heben
			elif pg < 0.65:
				swing = (pg - 0.35) / 0.3; rope = 16.0; loaded = true                         # Schwenken
			elif pg < 0.8:
				swing = 1.0; rope = 16.0 + (pg - 0.65) / 0.15 * 30.0; loaded = pg < 0.78      # Absetzen
			else:
				swing = 1.0 - (pg - 0.8) / 0.2; rope = 18.0                                   # leer zurueck
		# Kran: Portal auf dem Anleger, Ausleger zeigt zum Haken
		var base := _p(0.0, 0.0)
		var top := base + Vector2(0, -78)
		draw_rect(Rect2(base + Vector2(-10, -6), Vector2(20, 6)), Color("4a4a4a"))
		draw_line(base + Vector2(-8, -6), top, Color("d9a32c"), 3.0)
		draw_line(base + Vector2(8, -6), top, Color("d9a32c"), 3.0)
		draw_line(base + Vector2(-5, -30), base + Vector2(5, -50), Color("b8861f"), 1.5)
		draw_rect(Rect2(top + Vector2(-6, -8), Vector2(12, 8)), Color("e0b23a"))
		var tip_at := src.lerp(dst, clampf(swing, 0.0, 1.0))
		var tip := _p(tip_at.x, tip_at.y) + Vector2(0, -74)
		draw_line(top + Vector2(0, -4), tip, Color("e0b23a"), 3.0)
		draw_line(top + Vector2(0, -4), top - (tip - top) * 0.25, Color("e0b23a"), 3.0)   # Gegengewicht
		draw_rect(Rect2(top - (tip - top) * 0.25 + Vector2(-5, -6), Vector2(10, 8)), Color("555555"))
		draw_line(tip, tip + Vector2(0, rope), Color("333333"), 1.0)
		if loaded and not head.is_empty():
			var col := _cargo_col(str(head.item))
			draw_rect(Rect2(tip + Vector2(-9, rope), Vector2(18, 10)), col)
			draw_rect(Rect2(tip + Vector2(-9, rope), Vector2(18, 3)), col.lightened(0.25))
		else:
			draw_line(tip + Vector2(-3, rope), tip + Vector2(3, rope), Color("333333"), 2.0)
		# Hafenarbeiter: so viele wie angestellt; bei Arbeit pendeln sie zwischen Kran und Lager (mit Kiste), sonst stehen sie am Lager
		var n := mini(H.workers().size(), 6)
		for w in n:
			if working:
				var k := fmod(view.t * 0.18 + float(w) * 0.29, 1.0)
				var u := k * 2.0 if k < 0.5 else 2.0 - k * 2.0
				var at := (land_pt + Vector2(0.3 * w - 0.6, 0.0)).lerp(store_pt + Vector2(0.4 * w - 0.8, 0.0), u)
				_person(at, 0.0, 3000 + w * 17, view.t * 7.0 + w)
				var carry := (k < 0.5) == inbound
				if carry:
					var cp := _p(at.x, at.y) + Vector2(-4, -24)
					draw_rect(Rect2(cp, Vector2(8, 6)), _cargo_col(str(head.get("item", ""))))
			else:
				_person(store_pt + Vector2(0.45 * w - 1.0, 0.5), 0.0, 3000 + w * 17)
		# Leerlaufgrund ueber dem Kran
		var why := H.idle_reason()
		if why != "" and not view.night:
			draw_string(ThemeDB.fallback_font, top + Vector2(-60, -20), why, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.85))

	## Lagerplatz am Hafenlager: Kistenstapel nach Bestand (je Stapel 25 Ladeeinheiten, hoechstens 12); leer = nur Paletten.
	func _lagerplatz() -> void:
		var H: Harbor = view.sim.towns.harbor(int(data.town))
		if Engine.get_process_frames() % 60 == 0 or not data.has("units"):
			var units := 0
			for l in view.sim.stock.lots.values():
				if int(l.loc) == H.building:
					units += H.units_of(str(l.item), int(l.qty))
			data["units"] = units
		var stacks := clampi(int(data.units) / 25, 0, 12)
		for i in 6:   # Palettenreihe (immer da)
			var pp := _p(-1.2 + float(i % 3) * 0.8, float(i / 3) * 0.7)
			draw_colored_polygon(PackedVector2Array([pp + Vector2(-10, 0), pp + Vector2(0, -5), pp + Vector2(10, 0), pp + Vector2(0, 5)]), Color("9a7b52"))
		for i in stacks:
			var sp := _p(-1.2 + float(i % 3) * 0.8, float((i / 3) % 2) * 0.7)
			var h := 1 + i / 6
			for lvl in h:
				var cp := sp + Vector2(0, -8 - lvl * 9)
				var col := Color("c8553d") if (i + lvl) % 3 == 0 else (Color("3d7cc8") if (i + lvl) % 3 == 1 else Color("b08a5a"))
				draw_rect(Rect2(cp + Vector2(-9, 0), Vector2(18, 9)), col)
				draw_rect(Rect2(cp + Vector2(-9, 0), Vector2(18, 2)), col.lightened(0.3))


## Bodenebene (in der Deko-Ebene, also unter allen Gebaeuden und Fahrzeugen): Flachwasser und Schaumkanten an Naturufern
## (Kaikante bleibt gerade, ohne Schaum), Hecken mit Gartentor und Blumen um Wohnhaeuser. Nur der sichtbare Ausschnitt; seedstabil.
class GroundOverlay extends Node2D:
	var view: AmbientView
	var view_rect := Rect2()
	var drawn := Rect2()       # zuletzt gezeichnete Flaeche (Bildschirmkoordinaten)
	var drawn_zoom := 0.0
	const SHALLOW := Color(0.55, 0.85, 0.85, 0.32)
	const HOUSES := ["house", "semi", "villa"]

	func _cell(q: Vector2, inset: float = 0.0) -> PackedVector2Array:
		var a := q + Vector2(inset, inset)
		var b := q + Vector2(1.0 - inset, 1.0 - inset)
		return PackedVector2Array([Iso.to_screen(a * 32.0), Iso.to_screen(Vector2(b.x, a.y) * 32.0), Iso.to_screen(b * 32.0), Iso.to_screen(Vector2(a.x, b.y) * 32.0)])

	func _draw() -> void:
		if view == null or view.sim == null or view_rect.size.x <= 0.0:
			return
		var C: CityData = view.sim.city
		for e in view.shore:   # Flachwasser an der Uferkante
			var q: Vector2i = e[0]
			if view_rect.has_point(Iso.to_screen((Vector2(q) + Vector2(0.5, 0.5)) * 32.0)):
				draw_colored_polygon(_cell(Vector2(q), 0.0), SHALLOW)
		# Gaerten: Hecke um das Baufeld (bzw. 1 Feld um das Haus), Luecke zur Strasse = Gartentor; Blumen im Vorgarten
		for b in C.buildings:
			if str(b.type) not in HOUSES:
				continue
			var anchor := Iso.to_screen(Vector2(float(b.x) + 1.0, float(b.y) + 1.0) * 32.0)
			if not view_rect.has_point(anchor):
				continue
			var lot := Rect2(float(b.x) - 1.0, float(b.y) - 1.0, float(b.w) + 2.0, float(b.h) + 2.0)
			if b.has("lot"):
				lot = Rect2(float(b.lot[0]), float(b.lot[1]), float(b.lot[2]), float(b.lot[3]))
			var road: Vector2i = b.get("road", Vector2i(-1, -1))
			var fence: bool = absi(hash(Vector2i(int(b.x), int(b.y)))) % 3 == 0
			var corners := [lot.position, Vector2(lot.end.x, lot.position.y), lot.end, Vector2(lot.position.x, lot.end.y)]
			for i in 4:
				var a: Vector2 = corners[i]
				var e: Vector2 = corners[(i + 1) % 4]
				var steps := int(a.distance_to(e) / 0.5)
				for k2 in steps:
					var pa := a.lerp(e, float(k2) / float(steps))
					var pb := a.lerp(e, float(k2 + 1) / float(steps))
					var mid2 := (pa + pb) * 0.5
					var cell := Vector2i(floori(mid2.x), floori(mid2.y))
					if C.inside(cell) and (C.is_road(cell) or C.g(cell) == CityData.G.WATER):
						continue
					if road.x >= 0 and (mid2 - (Vector2(road) + Vector2(0.5, 0.5))).length() < 1.6:
						continue   # Gartentor zur Strasse
					var sa := Iso.to_screen(pa * 32.0)
					var sb := Iso.to_screen(pb * 32.0)
					if fence:   # weisser Lattenzaun
						draw_line(sa + Vector2(0, -6), sb + Vector2(0, -6), Color("f2efe6"), 1.5)
						draw_line(sa + Vector2(0, -3), sb + Vector2(0, -3), Color("f2efe6"), 1.5)
						draw_line(sa, sa + Vector2(0, -9), Color("ffffff"), 2.0)
					else:       # Hecke mit Hoehe: dunkler Fuss, Flaeche, helle Oberkante
						draw_colored_polygon(PackedVector2Array([sa, sb, sb + Vector2(0, -8), sa + Vector2(0, -8)]), Color("3d6b2c"))
						draw_line(sa + Vector2(0, -8), sb + Vector2(0, -8), Color("7fb557"), 3.0)
			var sd := absi(hash(Vector2i(int(b.x), int(b.y))))
			for f in 3:   # Blumen im Vorgarten (zur Strasse hin)
				var fp := Vector2(float(b.x) + float(b.w) * 0.5, float(b.y) + float(b.h) * 0.5)
				if road.x >= 0:
					fp = fp.lerp(Vector2(road) + Vector2(0.5, 0.5), 0.55)
				fp += Vector2(float((sd >> (f * 3)) % 5) * 0.15 - 0.3, float((sd >> (f * 5)) % 5) * 0.15 - 0.3)
				var fs := Iso.to_screen(fp * 32.0)
				draw_circle(fs, 2.5, [Color("e8553d"), Color("f2c14e"), Color("d47ad1"), Color("f4f4f4")][(sd + f) % 4])


## Schaumkanten am Ufer (bewegt): je Bild, aber nur die gemerkten Uferzellen im Ausschnitt.
class FoamOverlay extends Node2D:
	var view: AmbientView
	var view_rect := Rect2()

	func _draw() -> void:
		if view == null or view.sim == null or view_rect.size.x <= 0.0:
			return
		var t: float = view.t
		var foam := 0.45 + 0.35 * clampf(view.wind.length() - 0.6, 0.0, 1.0)
		for e in view.shore:
			var q: Vector2i = e[0]
			var x := q.x
			var y := q.y
			if not view_rect.has_point(Iso.to_screen((Vector2(q) + Vector2(0.5, 0.5)) * 32.0)):
				continue
			for d in e[1]:   # Schaumkante zur Landseite, laeuft leicht auf
				var k := 0.5 + 0.5 * sin(t * 1.3 + float(x * 7 + y * 13) * 0.3)
				var off: Vector2 = Vector2(d) * (0.38 + 0.08 * k)
				var mid := Vector2(q) + Vector2(0.5, 0.5) + off
				var side: Vector2 = Vector2(-d.y, d.x) * 0.5
				var jit := float((x * 31 + y * 17) % 5) * 0.03
				draw_line(Iso.to_screen((mid - side * (0.9 - jit)) * 32.0), Iso.to_screen((mid + side * (0.85 + jit)) * 32.0), Color(1, 1, 1, foam * (0.6 + 0.4 * k)), 2.0)


## Abendstimmung: weiches warmes Licht ueber der Nachtfaerbung (Laternen, Steglaternen, Lagerfeuer, Terrassen am Abend).
## Staerke folgt CityView.night_factor (Daemmerung blendet ein); nur sichtbare Orte.
class EveningLights extends Node2D:
	var view: AmbientView

	func _draw() -> void:
		if view == null or view.cv == null:
			return
		var nf: float = view.cv.night_factor
		if nf < 0.05:
			return
		for s in view._spots:
			if not s.visible:
				continue
			for g in s.glows():
				var at: Vector2 = s.position + g[0]
				var r: float = g[1]
				var col: Color = g[2]
				for ring in 4:
					var f := 1.0 - float(ring) / 4.0
					draw_circle(at, r * f, Color(col.r, col.g, col.b, 0.07 * nf))
				draw_circle(at, 3.0, Color(col.r, col.g, col.b, 0.9 * nf))
