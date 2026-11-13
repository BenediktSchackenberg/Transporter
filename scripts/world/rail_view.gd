class_name RailView
extends Node2D
## Eisenbahn auf der Karte (Auftrag 22 Phase 6 Schritt 1): Holzschwellen und zwei Stahlschienen je Gleisfeld (gerade Stuecke und
## Bogen aus den Nachbarfeldern, Schotter liefert die Bodenkachel), erhoehte Bahnsteige mit weisser Sicherheitslinie, Prellboecke an
## stumpfen Gleisenden, Bahnuebergaenge mit Schienen ueber der Fahrbahn und Andreaskreuzen, Ausfahrsignale an den Bahnhofsenden.
## Bruecken: Stahlbetontrog auf Pfeilern ueber dem Wasser; Tunnel: Gleis verschwindet im Berg, Portal an Ein- und Ausfahrt.
## Zeichnet nur den sichtbaren Ausschnitt, neu nur bei Aenderung (Pruefung alle 0,5 s).

const SLEEPER := Color(0.36, 0.26, 0.18, 0.95)
const STEEL := Color(0.72, 0.74, 0.78)
const STEEL_DARK := Color(0.35, 0.36, 0.4)
const PLATFORM := Color(0.74, 0.72, 0.68)
const PLATFORM_SIDE := Color(0.52, 0.5, 0.47)
const SAFETY := Color(0.96, 0.96, 0.92)
const GAUGE := 4.5            # halbe Spurweite (Weltmass, Feld = 32)
const SLEEPER_HALF := 7.5
const SLEEPER_STEP := 5.3
const PLATFORM_H := 4.0       # Bahnsteighoehe in Pixeln
const MAX_FIGURES := 14       # wartende Fahrgaeste je Bahnsteig (Darstellung)
const COATS := [Color(0.75, 0.25, 0.22), Color(0.22, 0.42, 0.72), Color(0.3, 0.55, 0.32), Color(0.85, 0.7, 0.25), Color(0.45, 0.32, 0.55), Color(0.35, 0.35, 0.38)]

var sim: Simulation
var _poll := 0.0
var _key := ""


func setup(simulation: Simulation) -> void:
	sim = simulation


func _net() -> RailNet:
	return sim.rail if sim != null else null


func _process(delta: float) -> void:
	_poll -= delta
	if _poll > 0.0 or _net() == null or not _net().is_built():
		return
	_poll = 0.5
	var waits := ""
	if sim.trains != null and not sim.trains.stops.is_empty():
		for i in sim.trains.stops.size():
			waits += "%d," % mini(sim.trains.waiting_at(i), MAX_FIGURES)
	var extra := ""
	if sim.trains != null:   # Schranken (blinken, solange zu) und Stoerungen
		extra = "%s|%s|%d|%s|%s" % [str(sim.trains.closed.keys()), str(sim.trains.disruptions.keys()), (int(Time.get_ticks_msec() / 500) % 2) if not sim.trains.closed.is_empty() else 0,
			str(sim.trains.double_blocks.keys()), str(sim.trains.planned_tracks.keys()) + str(sim.trains.branch_clear())]
	var key := "%s|%d|%s|%s|%s" % [str(_view_cells()), _net().cells.size(), str(sim.trains.blocks.keys()) if sim.trains != null else "", waits, extra]
	if key != _key:
		_key = key
		queue_redraw()


func _view_cells() -> Rect2i:
	var inv := get_canvas_transform().affine_inverse()
	var vs := get_viewport_rect().size
	var lo := Vector2i(999999, 999999)
	var hi := Vector2i(-999999, -999999)
	for c in [Vector2.ZERO, Vector2(vs.x, 0), vs, Vector2(0, vs.y)]:
		var w := Iso.to_world(inv * c) / 32.0
		lo = Vector2i(mini(lo.x, int(w.x)), mini(lo.y, int(w.y)))
		hi = Vector2i(maxi(hi.x, int(w.x)), maxi(hi.y, int(w.y)))
	return Rect2i(lo - Vector2i(2, 2), hi - lo + Vector2i(4, 4))


static func _s(w: Vector2) -> Vector2:
	return Iso.to_screen(w)


func _draw() -> void:
	var N := _net()
	if N == null or not N.is_built():
		return
	var view := _view_cells()
	if view.size.x * view.size.y > 160000:
		return
	# erst Bahnsteige (Boden), dann Gleise, dann Signale/Kreuze (stehen auf)
	for q in N.cells:
		if N.cells[q] in ["bahnsteig", "rampe"] and view.has_point(q):
			_draw_platform(q)
	if sim.trains != null and not sim.trains.stops.is_empty():
		for i in sim.trains.stops.size():
			var stn: Dictionary = N.station_of(int(sim.trains.stops[i].town))
			if not stn.is_empty():
				_draw_waiting(stn, mini(sim.trains.waiting_at(i), MAX_FIGURES), view)
	for q in N.cells:
		if N.cells[q] == "bruecke" and view.has_point(q):
			_draw_bridge(q, N.links(q))
	for q in N.cells:
		var kind: String = N.cells[q]
		if kind == "tunnel":
			if view.has_point(q):
				for d in N.links(q):
					if N.cells.get(q + d, "") != "tunnel":
						_draw_portal(q, d)
			continue
		if kind not in ["bahnsteig", "rampe"] and view.has_point(q):
			_draw_track(q, N.links(q), kind == "uebergang")
	if sim.trains != null:
		for pid in sim.trains.planned_tracks:   # zweites Gleis im Bau: abgesteckt
			var pc: Array = sim.trains.planned_cells(str(pid))
			for i in range(0, pc.size(), 2):
				if view.has_point(pc[i]):
					var f := _s((Vector2(pc[i]) + Vector2(0.5, 0.5)) * 32.0 + Vector2(6, 6))
					draw_line(f, f + Vector2(0, -8), Color(0.95, 0.55, 0.12), 1.5)
		for dz in sim.trains.disruptions.values():
			if view.has_point(Vector2i(int(dz.cell[0]), int(dz.cell[1]))):
				_draw_disruption(dz)
	var all_st: Array = N.stations.values()
	if N.has_freight():
		all_st = all_st + [N.freight]
	for st in all_st:
		var loop: Array = st.get("loop", [])
		if loop.size() >= 2:   # Weichen: Ausweichgleis schraeg an das Hauptgleis
			var ld := Vector2i(int(st.loop_dir[0]), int(st.loop_dir[1]))
			var l0 := Vector2i(int(loop[0][0]), int(loop[0][1]))
			var l1 := Vector2i(int(loop[-1][0]), int(loop[-1][1]))
			var along := Vector2i(int(loop[1][0]), int(loop[1][1])) - l0
			for pr in [[l0, l0 - ld - along], [l1, l1 - ld + along]]:
				if view.has_point(pr[0]):
					_draw_seg(_mid(pr[0]), _mid(pr[1]), true)
		for e in st.ends:
			var q := Vector2i(int(e[0]), int(e[1]))
			var tq := _track_next_to(q, st)
			if not view.has_point(q):
				continue
			if st.has("branch"):   # Gueterbahnhof: Signal am Anschluss-Ende, Prellbock am anderen
				if int(st.end[0]) == q.x and int(st.end[1]) == q.y:
					_draw_signal(q, tq, sim.trains == null or sim.trains.branch_clear())
				else:
					_draw_buffer(tq, q - tq)
			elif N.cells.has(q):
				_draw_signal(q, tq, _clear(int(st.town), tq))
			else:
				_draw_buffer(tq, q - tq)


static func _mid(q: Vector2i) -> Vector2:
	return (Vector2(q) + Vector2(0.5, 0.5)) * 32.0


## Ausfahrsignal am Gleisende neben dem Bahnhofsgleis tq: Fahrt, wenn der Block in dieser Richtung frei ist (RailTraffic).
func _clear(town: int, tq: Vector2i) -> bool:
	var T: RailTraffic = sim.trains
	if T == null or T.stops.is_empty():
		return true
	var s := T.stop_of_town(town)
	if s < 0:
		return true
	var st: Dictionary = T.stops[s]
	var idx := -1
	for i in range(int(st.from), int(st.to) + 1):
		if T.path[i] == tq:
			idx = i
			break
	if idx < 0:
		return true
	var d := 1 if absi(idx - int(st.to)) <= absi(idx - int(st.from)) else -1
	return T.signal_clear(s, d)


func _track_next_to(q: Vector2i, st: Dictionary) -> Vector2i:
	for a in st.track:
		var t := Vector2i(int(a[0]), int(a[1]))
		if absi(t.x - q.x) + absi(t.y - q.y) == 1:
			return t
	return q


## Gleisfeld: je Nachbarrichtung ein halbes Gleis von der Mitte zum Rand; zwei gegenueberliegende Richtungen = gerades Stueck,
## zwei rechtwinklige = Bogen (Viertelkreis um die Feldecke).
func _draw_track(q: Vector2i, dirs: Array, crossing: bool) -> void:
	var c := (Vector2(q) + Vector2(0.5, 0.5)) * 32.0
	if sim.trains != null and sim.trains.is_double_cell(q) and dirs.size() >= 1:   # zweigleisig: zwei Gleise nebeneinander
		var off := RailTraffic.DOUBLE_OFFSET
		for side: float in [-1.0, 1.0]:
			var mids: Array = []
			for d in dirs:
				var dv := Vector2(d)
				var nv := Vector2(-dv.y, dv.x)
				var m0: Vector2 = c + nv * side * off
				_draw_seg(m0, m0 + dv * 16.0, not crossing)
				mids.append(m0)
			if mids.size() == 2 and mids[0] != mids[1]:
				_draw_seg(mids[0], mids[1], false)
		if crossing:
			_draw_andreas(q, dirs)
			_draw_barrier(q, dirs, sim.trains.closed.has(q))
		return
	if dirs.size() == 2 and dirs[0] + dirs[1] != Vector2i.ZERO:
		_draw_curve(c, Vector2(dirs[0]), Vector2(dirs[1]), crossing)
		return
	if dirs.is_empty():
		dirs = [Vector2i(1, 0), Vector2i(-1, 0)]
	for d in dirs:
		_draw_half(c, Vector2(d), crossing)
	if crossing:
		_draw_andreas(q, dirs)
		_draw_barrier(q, dirs, sim.trains != null and sim.trains.closed.has(q))


func _draw_half(c: Vector2, d: Vector2, crossing: bool) -> void:
	_draw_seg(c, c + d * 16.0, not crossing)


## Gerades Gleisstueck von a nach b (Weltmass): Schwellen (ausser auf der Fahrbahn) und zwei Schienen mit Schattenkante.
func _draw_seg(a: Vector2, b: Vector2, sleepers: bool) -> void:
	var len := a.distance_to(b)
	if len <= 0.01:
		return
	var d := (b - a) / len
	var n := Vector2(-d.y, d.x)
	if sleepers:
		var t := SLEEPER_STEP * 0.5
		while t < len:
			var m := a + d * t
			draw_line(_s(m - n * SLEEPER_HALF), _s(m + n * SLEEPER_HALF), SLEEPER, 2.0)
			t += SLEEPER_STEP
	for side in [-1.0, 1.0]:
		draw_line(_s(a + n * GAUGE * side) + Vector2(0, 0.6), _s(b + n * GAUGE * side) + Vector2(0, 0.6), STEEL_DARK, 1.4)
		draw_line(_s(a + n * GAUGE * side), _s(b + n * GAUGE * side), STEEL, 1.0)


## Bogen zwischen den Randmitten in Richtung d1 und d2: Viertelkreis um die gemeinsame Feldecke (Radius 16).
func _draw_curve(c: Vector2, d1: Vector2, d2: Vector2, crossing: bool) -> void:
	var corner := c + (d1 + d2) * 16.0
	var a1 := (c + d1 * 16.0 - corner).angle()
	var a2 := (c + d2 * 16.0 - corner).angle()
	if absf(wrapf(a2 - a1, -PI, PI)) > PI * 0.5 + 0.01:
		a2 = a1 - PI * 0.5 if wrapf(a2 - a1, -PI, PI) > 0 else a1 + PI * 0.5
	var steps := 8
	if not crossing:
		for i in steps:
			var ang := lerp_angle(a1, a2, (float(i) + 0.5) / float(steps))
			var u := Vector2.from_angle(ang)
			draw_line(_s(corner + u * (16.0 - SLEEPER_HALF)), _s(corner + u * (16.0 + SLEEPER_HALF)), SLEEPER, 2.0)
	for r in [16.0 - GAUGE, 16.0 + GAUGE]:
		var pts := PackedVector2Array()
		for i in steps + 1:
			pts.append(_s(corner + Vector2.from_angle(lerp_angle(a1, a2, float(i) / float(steps))) * r))
		draw_polyline(pts, STEEL, 1.0)


## Brueckenfeld: Trog (Betongrau) entlang des Gleises, Pfeiler jedes dritte Feld bis zur Wasserlinie.
func _draw_bridge(q: Vector2i, dirs: Array) -> void:
	var c := (Vector2(q) + Vector2(0.5, 0.5)) * 32.0
	var d := Vector2(dirs[0]) if not dirs.is_empty() else Vector2(1, 0)
	var n := Vector2(-d.y, d.x)
	var a := c - d * 16.0
	var b := c + d * 16.0
	var w := 11.0
	var top := PackedVector2Array([_s(a - n * w), _s(b - n * w), _s(b + n * w), _s(a + n * w)])
	var side := PackedVector2Array([_s(a + n * w), _s(b + n * w), _s(b + n * w) + Vector2(0, 5), _s(a + n * w) + Vector2(0, 5)])
	draw_colored_polygon(side, Color(0.5, 0.5, 0.52))
	draw_colored_polygon(top, Color(0.62, 0.6, 0.56))
	draw_line(_s(a + n * w), _s(b + n * w), Color(0.4, 0.42, 0.46), 1.0)
	draw_line(_s(a - n * w), _s(b - n * w), Color(0.4, 0.42, 0.46), 1.0)
	if (q.x + q.y) % 3 == 0:
		var f := _s(c)
		draw_rect(Rect2(f + Vector2(-3, 4), Vector2(6, 12)), Color(0.55, 0.55, 0.57))


## Tunnelportal: dunkle Oeffnung mit Steinrahmen, wo das Gleis in den Berg faehrt (Feld q liegt im Tunnel, d zeigt nach draussen).
func _draw_portal(q: Vector2i, d: Vector2i) -> void:
	var c := (Vector2(q) + Vector2(0.5, 0.5)) * 32.0 + Vector2(d) * 14.0
	var n := Vector2(-d.y, d.x)
	var a := _s(c - n * 12.0)
	var b := _s(c + n * 12.0)
	var h := Vector2(0, -18)
	draw_colored_polygon(PackedVector2Array([a, b, b + h, a + h]), Color(0.55, 0.52, 0.47))
	var a2 := _s(c - n * 8.0)
	var b2 := _s(c + n * 8.0)
	draw_colored_polygon(PackedVector2Array([a2, b2, b2 + h * 0.7, (a2 + b2) * 0.5 + h * 0.85, a2 + h * 0.7]), Color(0.08, 0.08, 0.1))


## Wartende Fahrgaeste: kleine Figuren (Mantel in wechselnden Farben, Kopf) verteilt auf dem Bahnsteig.
func _draw_waiting(stn: Dictionary, n: int, view: Rect2i) -> void:
	var plat: Array = stn.platform
	for i in n:
		var a: Array = plat[(i * 7 + 2) % plat.size()]
		var q := Vector2i(int(a[0]), int(a[1]))
		if not view.has_point(q):
			continue
		var off := Vector2(float((i * 13) % 20) + 6.0, float((i * 7) % 18) + 7.0)
		var f := _s(Vector2(q) * 32.0 + off) + Vector2(0, -PLATFORM_H)
		var coat: Color = COATS[i % COATS.size()]
		draw_rect(Rect2(f + Vector2(-3, -14), Vector2(6, 11)), coat)
		draw_rect(Rect2(f + Vector2(-3, -3), Vector2(2.4, 3.5)), Color(0.15, 0.15, 0.18))
		draw_rect(Rect2(f + Vector2(0.6, -3), Vector2(2.4, 3.5)), Color(0.15, 0.15, 0.18))
		draw_circle(f + Vector2(0, -17), 3.0, Color(0.93, 0.78, 0.64))


## Schranke am Bahnuebergang: je Strassenseite ein Baum quer ueber die Fahrbahn (zu: rot-weiss, rote Lampe blinkt) bzw. hochgeklappt.
func _draw_barrier(q: Vector2i, dirs: Array, shut: bool) -> void:
	var d := Vector2(dirs[0])
	var n := Vector2(-d.y, d.x)
	var c := (Vector2(q) + Vector2(0.5, 0.5)) * 32.0
	var blink := int(Time.get_ticks_msec() / 500) % 2 == 0
	for side in [-1.0, 1.0]:
		var post: Vector2 = c + n * side * 13.0 + d * side * 14.0
		var pf := _s(post)
		draw_rect(Rect2(pf + Vector2(-1.5, -9), Vector2(3, 9)), Color(0.25, 0.25, 0.28))
		if shut:
			var tip: Vector2 = _s(post - d * side * 26.0) + Vector2(0, -7)
			var root := pf + Vector2(0, -7)
			for k in 4:
				var a := root.lerp(tip, float(k) / 4.0)
				var b := root.lerp(tip, float(k + 1) / 4.0)
				draw_line(a, b, Color(0.9, 0.12, 0.1) if k % 2 == 0 else Color(0.97, 0.97, 0.95), 2.2)
			draw_circle(pf + Vector2(0, -11), 2.2, Color(1.0, 0.15, 0.1) if blink else Color(0.35, 0.08, 0.06))
		else:
			draw_line(pf + Vector2(0, -7), pf + Vector2(0, -26), Color(0.9, 0.12, 0.1), 2.2)


## Stoerungsstelle: Warndreieck; bei "Baum auf dem Gleis" liegt ein Baum quer ueber dem Gleis.
func _draw_disruption(dz: Dictionary) -> void:
	var q := Vector2i(int(dz.cell[0]), int(dz.cell[1]))
	var c := (Vector2(q) + Vector2(0.5, 0.5)) * 32.0
	if str(dz.art) == "Baum auf dem Gleis":
		var a := _s(c + Vector2(-14, 10))
		var b := _s(c + Vector2(12, -10))
		draw_line(a, b, Color(0.42, 0.28, 0.16), 4.0)
		for k in 5:
			draw_circle(b.lerp(a, 0.15 * float(k)) + Vector2(float(k % 2) * 3.0 - 1.5, -2.0), 5.0 - float(k) * 0.5, Color(0.22, 0.45, 0.2))
	var w := _s(c) + Vector2(0, -26)
	draw_colored_polygon(PackedVector2Array([w + Vector2(0, -10), w + Vector2(9, 6), w + Vector2(-9, 6)]), Color(1.0, 0.82, 0.1))
	draw_line(w + Vector2(0, -5), w + Vector2(0, 1), Color.BLACK, 1.6)
	draw_circle(w + Vector2(0, 3.5), 1.0, Color.BLACK)


## Erhoehter Bahnsteig: Oberseite hell, sichtbare Kanten (Sued/Ost) dunkler, weisse Linie an der Gleiskante.
func _draw_platform(q: Vector2i) -> void:
	var a := Vector2(q) * 32.0
	var up := Vector2(0, -PLATFORM_H)
	var p0 := _s(a)
	var p1 := _s(a + Vector2(32, 0))
	var p2 := _s(a + Vector2(32, 32))
	var p3 := _s(a + Vector2(0, 32))
	draw_colored_polygon(PackedVector2Array([p1, p2, p2 + up, p1 + up]), PLATFORM_SIDE)
	draw_colored_polygon(PackedVector2Array([p2, p3, p3 + up, p2 + up]), PLATFORM_SIDE.darkened(0.1))
	draw_colored_polygon(PackedVector2Array([p0 + up, p1 + up, p2 + up, p3 + up]), PLATFORM)
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if _net().cells.get(q + d, "") == "gleis":
			var c := a + Vector2(16, 16) + Vector2(d) * 13.0
			var n := Vector2(-d.y, d.x) * 16.0
			draw_line(_s(c - n) + up, _s(c + n) + up, SAFETY, 1.0)


## Bahnuebergang: Andreaskreuz (weiss-rot) an zwei Ecken neben dem Gleis.
func _draw_andreas(q: Vector2i, dirs: Array) -> void:
	var d := Vector2(dirs[0])
	var n := Vector2(-d.y, d.x)
	var c := (Vector2(q) + Vector2(0.5, 0.5)) * 32.0
	for side in [-1.0, 1.0]:
		var f := _s(c + d * side * 18.0 + n * side * 14.0)
		draw_line(f, f + Vector2(0, -14), STEEL_DARK, 1.2)
		var m := f + Vector2(0, -14)
		draw_line(m + Vector2(-4, -3), m + Vector2(4, 3), Color(0.85, 0.15, 0.12), 2.0)
		draw_line(m + Vector2(-4, 3), m + Vector2(4, -3), Color(0.95, 0.95, 0.95), 2.0)


## Ausfahrsignal am Bahnhofsende: Mast mit Schirm, gruen = Block frei, rot = Block belegt.
func _draw_signal(q: Vector2i, t: Vector2i, clear := true) -> void:
	var d := Vector2(q - t)
	var n := Vector2(-d.y, d.x)
	var f := _s((Vector2(t) + Vector2(0.5, 0.5)) * 32.0 + d * 14.0 + n * 12.0)
	draw_line(f, f + Vector2(0, -18), STEEL_DARK, 1.5)
	draw_rect(Rect2(f + Vector2(-3, -26), Vector2(6, 9)), Color(0.1, 0.1, 0.12))
	draw_circle(f + Vector2(0, -21.5), 1.8, Color(0.3, 0.95, 0.4) if clear else Color(1.0, 0.2, 0.15))


## Prellbock am stumpfen Gleisende.
func _draw_buffer(t: Vector2i, d: Vector2i) -> void:
	var c := (Vector2(t) + Vector2(0.5, 0.5)) * 32.0 + Vector2(d) * 13.0
	var n := Vector2(-d.y, d.x)
	var a := _s(c - n * 7.0)
	var b := _s(c + n * 7.0)
	draw_colored_polygon(PackedVector2Array([a, b, b + Vector2(0, -6), a + Vector2(0, -6)]), Color(0.75, 0.2, 0.15))
	draw_line(a + Vector2(0, -6), b + Vector2(0, -6), Color(0.95, 0.95, 0.9), 1.5)
