class_name OffroadFx
extends Node2D
## Fahrgefuehl des Gelaende-LKW (Benedikt 18.11.2026: "die Animation ... wie sie mit dem Fahrzeug faehrt ist sehr schlecht,
## das muss wesentlich besser und detaillierter werden"). Diese Ebene liegt flach auf dem Boden (Reifenspuren, verblassen
## langsam); die Kind-Ebene `dust` liegt ueber den Objekten (Staub, Schlamm, Schnee, Auspuffwoelkchen).
## Gefuettert von EntityView je Bild: feed(id, pos, heading, moving, offroad, dt). Alles in Weltkoordinaten, gezeichnet ueber Iso.

const TRACK_LIFE := 120.0      # Sekunden, bis eine Spur verblasst ist
const TRACK_MAX := 2400
const PUFF_MAX := 260
const REAR := -24.0            # Hinterachse relativ zur Fahrzeugmitte entlang der Fahrtrichtung (offroad.py: Achsen x0+14/x0+56, Mitte 45)
const FRONT := 18.0            # Vorderachse
const TRACK_W := 9.5           # halbe Spurweite

var sim: Simulation
var tracks: Array = []         # [a: Vector2, b: Vector2, t: float, wet: bool]
var puffs: Array = []          # {p: Vector2 (Welt), h: float (Hoehe px), v: Vector2, vh: float, t: float, life: float, r: float, c: Color, kind}
var dust := DustLayer.new()
var exh := DustLayer.new()     # Auspuffwoelkchen ueber dem Fahrzeug
var _last := {}                # Fahrzeug-ID -> {pos, acc, puff, exh, moving_t}
var _time := 0.0


func _ready() -> void:
	z_index = -9               # flach ueber den Bodenkacheln (-10), unter allen Objekten
	dust.fx = self
	dust.z_as_relative = false
	dust.z_index = -1          # unter den Fahrzeugen: Wolken hinter dem Wagen verdeckt der Wagen (Auspuff liegt hoeher, siehe ExhLayer)
	exh.fx = self
	exh.z_as_relative = false
	exh.z_index = 20
	add_child(exh)
	add_child(dust)


## pos/heading in Weltkoordinaten; soil: Untergrund ("gras", "sand", "acker", "kies"; "" = befestigt: keine Spuren, kein Staub);
## Rueckgabe: Federweg in Pixeln fuer das Fahrzeugbild.
func feed(id: int, pos: Vector2, heading: Vector2, soil: String, dt: float) -> Vector2:
	var offroad := soil != ""
	var st: Dictionary = _last.get(id, {})
	if st.is_empty():
		st = {"pos": pos, "acc": 0.0, "puff": 0.0, "exh": 0.0, "moving_t": 0.0, "bump": 0.0, "bump_v": 0.0, "moved_at": -9.0, "speed": 0.0}
		_last[id] = st
	var step: float = (pos - st.pos).length()
	# Die Position springt nur im Simulationstakt (nicht jedes Bild): Bewegung und Tempo ueber die Zeit seit dem letzten Sprung
	if step > 0.01:
		var gap := maxf(_time - float(st.moved_at), dt)
		st.speed = lerpf(float(st.speed), step / minf(gap, 0.5), 0.3)
		st.moved_at = _time
	var moving := _time - float(st.moved_at) < 0.4
	var speed: float = float(st.speed) if moving else 0.0
	st.pos = pos
	var h := heading.normalized() if heading.length() > 0.01 else Vector2.RIGHT
	var side := Vector2(-h.y, h.x)
	var weather := _ground()
	st.moving_t = (float(st.moving_t) + dt) if moving else 0.0
	# Federung: im Gelaende Unebenheiten (zufaellige Stoesse, gedaempft), auf der Strasse nur leichtes Schwingen
	if moving and offroad and randf() < dt * minf(speed / 12.0, 6.0):
		st.bump_v = float(st.bump_v) - randf_range(1.2, 3.0)
	st.bump_v = float(st.bump_v) - float(st.bump) * 60.0 * dt   # Feder
	st.bump_v = float(st.bump_v) * (1.0 - minf(1.0, 7.0 * dt))  # Daempfer
	st.bump = clampf(float(st.bump) + float(st.bump_v) * dt * 10.0, -3.0, 2.0)
	var sway := sin(_time * 9.0 + id) * (0.6 if moving and offroad else 0.0)
	if not moving:
		return Vector2(0, round(float(st.bump)))
	# Reifenspuren je ~5 Weltpixel (nur im Gelaende; nasser Boden: tiefer und dunkler)
	if offroad:
		st.acc = float(st.acc) + step
		if float(st.acc) >= 5.0:
			st.acc = 0.0
			var rear := pos + h * REAR
			for s in [-1.0, 1.0]:
				var a: Vector2 = rear + side * TRACK_W * s
				var key := "%d%s" % [id, "L" if s < 0 else "R"]
				var prev: Vector2 = st.get(key, a)
				if prev.distance_to(a) < 20.0:
					tracks.append([prev, a, _time, weather == "nass" or soil == "acker"])
				st[key] = a
			if tracks.size() > TRACK_MAX:
				tracks = tracks.slice(tracks.size() - TRACK_MAX)
		# Staub / Schlamm / Schnee hinter den Raedern
		st.puff = float(st.puff) + dt * clampf(speed / 6.0, 2.0, 18.0)
		while float(st.puff) >= 1.0:
			st.puff = float(st.puff) - 1.0
			for axle in [REAR, FRONT]:
				var s := 1.0 if randf() < 0.5 else -1.0
				var at: Vector2 = pos + h * (float(axle) - 9.0) + side * TRACK_W * 1.3 * s   # hinter dem Rad aufgewirbelt
				_puff(at, weather if weather != "trocken" else soil, h)
	# Auspuff: beim Anfahren eine dunkle Wolke, sonst ab und zu ein graues Woelkchen
	st.exh = float(st.exh) - dt
	var starting := float(st.moving_t) < 0.6
	if float(st.exh) <= 0.0:
		st.exh = randf_range(0.12, 0.2) if starting else randf_range(0.45, 0.9)   # beim Anfahren kraeftiger
		var ex: Vector2 = pos + h * 6.0 + side * 10.0   # Auspuff links hinter der Kabine, Oeffnung auf z = 37
		puffs.append({"p": ex, "h": 74.0, "v": -h * 6.0, "vh": 22.0, "t": 0.0, "life": 1.6, "r": 2.5,
			"c": Color(0.25, 0.25, 0.27, 0.5) if starting else Color(0.62, 0.63, 0.66, 0.3), "kind": "exh"})
	if puffs.size() > PUFF_MAX:
		puffs = puffs.slice(puffs.size() - PUFF_MAX)
	return Vector2(round(sway * 0.5), round(float(st.bump)))


func _ground() -> String:
	if sim != null and sim.wx != null:
		if sim.wx.is_snow():
			return "schnee"
		if sim.wx.is_rain():
			return "nass"
	return "trocken"


func _puff(at: Vector2, weather: String, h: Vector2) -> void:
	var back := -h * randf_range(6.0, 16.0) + Vector2(randf_range(-5, 5), randf_range(-5, 5))
	match weather:
		"nass":   # Schlammspritzer fliegen im Bogen und fallen
			puffs.append({"p": at, "h": 2.0, "v": back * 2.0, "vh": randf_range(25.0, 45.0), "t": 0.0, "life": 0.7,
				"r": randf_range(1.0, 1.8), "c": Color(0.33, 0.24, 0.15, 0.95), "kind": "mud"})
		"schnee":
			puffs.append({"p": at, "h": 2.0, "v": back, "vh": randf_range(8.0, 16.0), "t": 0.0, "life": 1.3,
				"r": randf_range(2.5, 4.0), "c": Color(0.96, 0.97, 1.0, 0.75), "kind": "dust"})
		"gras":   # Gras: wenig Staub, dafuer fliegen Halme und Erdkruemel
			if randf() < 0.5:
				puffs.append({"p": at, "h": 2.0, "v": back * 1.5, "vh": randf_range(14.0, 26.0), "t": 0.0, "life": 0.6,
					"r": 1.0, "c": Color(0.36, 0.55, 0.22, 0.95) if randf() < 0.6 else Color(0.42, 0.3, 0.18, 0.95), "kind": "mud"})
			else:
				puffs.append({"p": at, "h": 1.0, "v": back, "vh": randf_range(3.0, 7.0), "t": 0.0, "life": 1.2,
					"r": randf_range(2.0, 3.0), "c": Color(0.7, 0.63, 0.48, 0.32), "kind": "dust"})
		_:   # Sand, Acker, Kies: Staubfahne
			var dc := Color(0.86, 0.78, 0.58, 0.55) if soil_color_sand(weather) else Color(0.74, 0.64, 0.47, 0.5)
			puffs.append({"p": at, "h": 1.0, "v": back, "vh": randf_range(4.0, 10.0), "t": 0.0, "life": randf_range(1.6, 2.6),
				"r": randf_range(3.0, 5.0), "c": dc, "kind": "dust"})


static func soil_color_sand(kind: String) -> bool:
	return kind == "sand"


func forget(id: int) -> void:
	_last.erase(id)


func step(dt: float) -> void:
	_time += dt
	for p in puffs:
		p.t += dt
		p.p += p.v * dt
		p.v *= 1.0 - minf(1.0, 1.8 * dt)
		if p.kind == "mud":
			p.vh -= 120.0 * dt
			p.h = maxf(0.0, p.h + p.vh * dt)
		else:
			p.h += p.vh * dt
			p.vh *= 1.0 - minf(1.0, 1.2 * dt)
	puffs = puffs.filter(func(p): return p.t < p.life and not (p.kind == "mud" and p.h <= 0.0 and p.t > 0.1))
	if not tracks.is_empty() and _time - float(tracks[0][2]) > TRACK_LIFE:
		tracks = tracks.filter(func(tr): return _time - float(tr[2]) <= TRACK_LIFE)
	queue_redraw()
	dust.queue_redraw()
	exh.queue_redraw()


func _draw() -> void:
	for tr in tracks:
		var age := (_time - float(tr[2])) / TRACK_LIFE
		var wet: bool = tr[3]
		var a := (0.5 if wet else 0.36) * (1.0 - age)
		if a <= 0.01:
			continue
		var c := Color(0.24, 0.17, 0.09, a) if wet else Color(0.25, 0.22, 0.12, a)
		var p0: Vector2 = Iso.to_screen(tr[0])
		var p1: Vector2 = Iso.to_screen(tr[1])
		draw_line(p0, p1, c, 4.0 if wet else 3.2)                    # Reifenbreite
		draw_line(p0, p1, Color(c.r, c.g, c.b, a * 0.8), 1.2)         # Profilrille dunkler in der Mitte


class DustLayer:
	extends Node2D
	var fx: OffroadFx

	func _draw() -> void:
		var want_exh := self == fx.exh
		for p in fx.puffs:
			if (p.kind == "exh") != want_exh:
				continue
			var k: float = p.t / p.life
			var c: Color = p.c
			var s: Vector2 = Iso.to_screen(p.p) - Vector2(0, p.h)
			if p.kind == "mud":
				draw_rect(Rect2(s.round(), Vector2(p.r, p.r)), c)
				continue
			var r: float = p.r * (1.0 + 2.2 * k)
			c.a *= (1.0 - k) * (1.0 - k)
			draw_circle(s, r, c)
			draw_circle(s + Vector2(-r * 0.3, -r * 0.3), r * 0.55, Color(1, 1, 1, c.a * 0.25))   # helle Kuppe
