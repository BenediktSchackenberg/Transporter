class_name CrewArt
extends RefCounted
## Bauleute und Baumaschinen fuer Erschliessungsbaustellen (Auftrag 15, Etappe D), prozedural in derselben 2:1-Projektion wie
## Gelaende und Gebaeude. Alle Funktionen zeichnen auf ein CanvasItem; `s` bildet (Feldkoordinate, Hoehe) auf Bildschirmpunkte ab:
## s.call(Vector2 feld, float z) -> Vector2. Eine Hoehenstufe z = 1 entspricht STEP Bildpunkten (wie ShipView).

const SKIN := Color("e0b48a")
const PANTS := Color("3a3f4a")
const YELLOW := Color("e8b024")
const YELLOW_D := Color("b8860f")
const STEEL := Color("5b6068")
const TYRE := Color("26282c")


## Quader (x0..x1, y0..y1 in Feldern, Hoehe z0..z1); sichtbar sind Oberseite, Suedseite (y1) und Ostseite (x1).
static func box(ci: CanvasItem, s: Callable, x0: float, y0: float, x1: float, y1: float, z0: float, z1: float, col: Color) -> void:
	ci.draw_colored_polygon(PackedVector2Array([s.call(Vector2(x0, y1), z0), s.call(Vector2(x1, y1), z0), s.call(Vector2(x1, y1), z1), s.call(Vector2(x0, y1), z1)]), col.darkened(0.15))
	ci.draw_colored_polygon(PackedVector2Array([s.call(Vector2(x1, y0), z0), s.call(Vector2(x1, y1), z0), s.call(Vector2(x1, y1), z1), s.call(Vector2(x1, y0), z1)]), col.darkened(0.3))
	ci.draw_colored_polygon(PackedVector2Array([s.call(Vector2(x0, y0), z1), s.call(Vector2(x1, y0), z1), s.call(Vector2(x1, y1), z1), s.call(Vector2(x0, y1), z1)]), col.lightened(0.08))


## Quader um einen Mittelpunkt, ausgerichtet nach Richtung d (Einheitsvektor in Feldern): Laenge l entlang d, Breite w quer.
static func obox(ci: CanvasItem, s: Callable, c: Vector2, d: Vector2, l: float, w: float, z0: float, z1: float, col: Color) -> void:
	var n := Vector2(-d.y, d.x)
	var p := [c - d * l * 0.5 - n * w * 0.5, c + d * l * 0.5 - n * w * 0.5, c + d * l * 0.5 + n * w * 0.5, c - d * l * 0.5 + n * w * 0.5]
	var top := PackedVector2Array()
	for q in p:
		top.append(s.call(q, z1))
	for k in 4:   # Seitenflaechen (hintere werden von der Oberseite ueberdeckt)
		var a: Vector2 = p[k]
		var b: Vector2 = p[(k + 1) % 4]
		var side := PackedVector2Array([s.call(a, z0), s.call(b, z0), s.call(b, z1), s.call(a, z1)])
		ci.draw_colored_polygon(side, col.darkened(0.12 + 0.08 * k))
	ci.draw_colored_polygon(top, col.lightened(0.08))


## Bauarbeiter: Helm, Warnweste (Firmenfarbe als Streifen), Arme mit Werkzeug. action: gehen | schaufeln | haemmern | tragen | winken | messen
static func worker(ci: CanvasItem, s: Callable, at: Vector2, t: float, action: String, vest: Color, firm: Color, seed_v: int) -> void:
	var p: Vector2 = s.call(at, 0.0)
	var ph := t * 6.0 + float(seed_v % 17)
	var step := sin(ph) if action == "gehen" or action == "tragen" else 0.0
	var sc := 1.6
	# Schatten
	ci.draw_circle(p + Vector2(0, 1), 5.0 * sc * 0.6, Color(0, 0, 0, 0.25))
	# Beine
	ci.draw_line(p + Vector2(-2, 0) * sc, p + Vector2(-2 + step * 2.0, -7) * sc, PANTS, 2.5 * sc)
	ci.draw_line(p + Vector2(2, 0) * sc, p + Vector2(2 - step * 2.0, -7) * sc, PANTS, 2.5 * sc)
	# Rumpf mit Weste und Reflexstreifen
	var bend := 2.0 * maxf(0.0, sin(ph * 0.5)) if action == "schaufeln" else 0.0
	ci.draw_rect(Rect2(p + Vector2(-3.5 + bend * 0.5, -15) * sc, Vector2(7, 8) * sc), vest)
	ci.draw_rect(Rect2(p + Vector2(-3.5 + bend * 0.5, -12) * sc, Vector2(7, 1.2) * sc), Color("e8e8e8"))
	ci.draw_rect(Rect2(p + Vector2(-3.5 + bend * 0.5, -9.5) * sc, Vector2(7, 1.0) * sc), firm)
	# Kopf mit Helm
	var head := p + Vector2(bend, -18) * sc
	ci.draw_circle(head, 2.6 * sc, SKIN)
	ci.draw_rect(Rect2(head + Vector2(-3.2, -3.4) * sc, Vector2(6.4, 2.2) * sc), YELLOW if vest != Color("ffffff") else Color("ffffff"))
	ci.draw_rect(Rect2(head + Vector2(-3.8, -1.6) * sc, Vector2(7.6, 0.8) * sc), YELLOW_D)
	# Arme und Werkzeug
	var sh := p + Vector2(bend * 0.6, -14) * sc
	match action:
		"schaufeln":
			var k := sin(ph * 0.5)
			var hand := sh + Vector2(5 + 3.0 * k, 3 + 2.0 * k) * sc
			ci.draw_line(sh, hand, SKIN, 2.0 * sc)
			ci.draw_line(hand + Vector2(-4, -4) * sc, hand + Vector2(4, 6) * sc, Color("8a6a45"), 1.5 * sc)
			ci.draw_rect(Rect2(hand + Vector2(3, 5) * sc, Vector2(3, 3) * sc), STEEL)
			if k > 0.6:
				ci.draw_circle(hand + Vector2(6, 2 - 4.0 * (k - 0.6)) * sc, 1.2 * sc, Color("7a5a3a"))
		"haemmern":
			var up := absf(sin(ph * 1.5))
			var hand2 := sh + Vector2(5, -2 - 4.0 * up) * sc
			ci.draw_line(sh, hand2, SKIN, 2.0 * sc)
			ci.draw_line(hand2, hand2 + Vector2(1, -5) * sc, Color("8a6a45"), 1.5 * sc)
			ci.draw_rect(Rect2(hand2 + Vector2(-1, -7) * sc, Vector2(4, 2) * sc), STEEL)
		"tragen":
			ci.draw_line(sh, sh + Vector2(3, -3) * sc, SKIN, 2.0 * sc)
			ci.draw_line(sh + Vector2(-8, -4) * sc, sh + Vector2(10, -6) * sc, Color("a0784e"), 2.5 * sc)   # Brett/Bohle auf der Schulter
		"winken":
			var w := sin(ph * 0.8)
			ci.draw_line(sh, sh + Vector2(4 + 2.0 * w, -6) * sc, SKIN, 2.0 * sc)
			ci.draw_line(sh, sh + Vector2(-4, 4) * sc, SKIN, 2.0 * sc)
		"messen":
			ci.draw_line(sh, sh + Vector2(4, 1) * sc, SKIN, 2.0 * sc)
			ci.draw_line(p + Vector2(7, 0) * sc, p + Vector2(7, -16) * sc, Color("d23b2f"), 1.5 * sc)   # Messlatte rot-weiss
			ci.draw_line(p + Vector2(7, -8) * sc, p + Vector2(7, -12) * sc, Color("f0ece4"), 1.5 * sc)
		_:
			ci.draw_line(sh, sh + Vector2(2 - step * 2.0, 7) * sc, SKIN, 2.0 * sc)
			ci.draw_line(sh + Vector2(-1, 0), sh + Vector2(-2 + step * 2.0, 7) * sc, SKIN, 2.0 * sc)


## Kettenbagger an c, Blick in Richtung d; Arm schwenkt und graebt (dig 0..1).
static func excavator(ci: CanvasItem, s: Callable, c: Vector2, d: Vector2, t: float, working: bool) -> void:
	var n := Vector2(-d.y, d.x)
	obox(ci, s, c - n * 0.18, d, 0.9, 0.16, 0.0, 0.22, TYRE)   # Ketten
	obox(ci, s, c + n * 0.18, d, 0.9, 0.16, 0.0, 0.22, TYRE)
	var swing := sin(t * 0.9) * 0.6 if working else 0.0
	var dd := d.rotated(swing)
	obox(ci, s, c - dd * 0.08, dd, 0.62, 0.48, 0.22, 0.75, YELLOW)        # Oberwagen
	obox(ci, s, c - dd * 0.05 + Vector2(-dd.y, dd.x) * 0.12, dd, 0.26, 0.22, 0.75, 1.25, YELLOW_D)   # Fahrerhaus
	var dig := 0.5 + 0.5 * sin(t * 1.8) if working else 0.3
	var boom0: Vector2 = s.call(c + dd * 0.25, 0.8)
	var boom1: Vector2 = s.call(c + dd * 0.85, 1.9 - 0.6 * dig)
	var stick: Vector2 = s.call(c + dd * 1.25, 0.6 - 0.5 * dig)
	ci.draw_line(boom0, boom1, YELLOW, 7.0)
	ci.draw_line(boom1, stick, YELLOW_D, 5.0)
	ci.draw_colored_polygon(PackedVector2Array([stick + Vector2(-6, -2), stick + Vector2(7, -2), stick + Vector2(4, 8), stick + Vector2(-5, 6)]), STEEL)
	if working and dig > 0.8:
		ci.draw_circle(stick + Vector2(0, 2), 4.0, Color("7a5a3a"))


## Kipplaster (dump=0..1 hebt die Mulde); load: Ladung sichtbar.
static func dump_truck(ci: CanvasItem, s: Callable, c: Vector2, d: Vector2, firm: Color, load: bool, dump: float = 0.0) -> void:
	var n := Vector2(-d.y, d.x)
	for k in [-0.3, 0.3]:
		for side in [-1.0, 1.0]:
			var w: Vector2 = s.call(c + d * k + n * side * 0.24, 0.12)
			ci.draw_circle(w, 5.0, TYRE)
	obox(ci, s, c, d, 1.0, 0.44, 0.12, 0.28, STEEL)                       # Rahmen
	obox(ci, s, c + d * 0.36, d, 0.3, 0.46, 0.28, 0.9, firm)               # Fahrerhaus in Firmenfarbe
	obox(ci, s, c + d * 0.37 + Vector2(0, 0), d, 0.22, 0.4, 0.62, 0.82, Color("9cc3d8"))   # Fenster
	var lift := 0.5 * dump
	obox(ci, s, c - d * 0.16, d, 0.62, 0.48, 0.3 + lift * 0.2, 0.68 + lift, Color("c8553d"))   # Mulde
	if load:
		obox(ci, s, c - d * 0.16, d, 0.5, 0.38, 0.68 + lift, 0.8 + lift, Color("8d8a82"))   # Schotter


## Walzenzug: Walze vorn, rollt hin und her.
static func roller(ci: CanvasItem, s: Callable, c: Vector2, d: Vector2) -> void:
	obox(ci, s, c + d * 0.3, d, 0.28, 0.6, 0.0, 0.34, STEEL)       # Walze
	obox(ci, s, c - d * 0.12, d, 0.5, 0.44, 0.1, 0.5, YELLOW)
	obox(ci, s, c - d * 0.2, d, 0.24, 0.3, 0.5, 1.0, YELLOW_D)     # Fahrerstand
	ci.draw_line(s.call(c - d * 0.2, 1.0), s.call(c - d * 0.2, 1.25), Color("d6802a"), 3.0)   # Rundumleuchte


## Fahrmischer mit drehender Trommel.
static func mixer(ci: CanvasItem, s: Callable, c: Vector2, d: Vector2, t: float, firm: Color) -> void:
	obox(ci, s, c, d, 1.0, 0.42, 0.1, 0.28, STEEL)
	obox(ci, s, c + d * 0.36, d, 0.28, 0.44, 0.28, 0.9, firm)
	var a: Vector2 = s.call(c - d * 0.42, 0.45)
	var b: Vector2 = s.call(c + d * 0.15, 1.1)
	ci.draw_line(a, b, Color("d46a2a"), 16.0)
	for k in 3:   # Spiralstreifen laufen mit der Drehung
		var f := fmod(t * 0.8 + float(k) / 3.0, 1.0)
		ci.draw_line(a.lerp(b, f) + Vector2(-3, -6), a.lerp(b, f) + Vector2(3, 6), Color("f2c14e"), 2.0)


## Ramme: Mast mit fallendem Baer ueber dem Pfahl (hit 0..1 = Schlag).
static func pile_driver(ci: CanvasItem, s: Callable, c: Vector2, d: Vector2, t: float, working: bool) -> void:
	obox(ci, s, c, d, 0.8, 0.5, 0.0, 0.3, TYRE)
	obox(ci, s, c, d, 0.6, 0.45, 0.3, 0.75, Color("d0482f"))
	var top: Vector2 = s.call(c + d * 0.42, 4.2)
	var foot: Vector2 = s.call(c + d * 0.42, 0.0)
	ci.draw_line(foot, top, Color("d0482f"), 4.0)
	ci.draw_line(s.call(c, 0.75), top, STEEL, 2.0)   # Abspannung
	var k := fmod(t * 0.9, 1.0) if working else 0.0
	var ram := foot.lerp(top, 0.35 + 0.55 * (1.0 - k * k))
	ci.draw_rect(Rect2(ram + Vector2(-5, -9), Vector2(10, 9)), STEEL)
	if working and k > 0.9:
		ci.draw_line(foot + Vector2(-10, -4), foot + Vector2(-16, -10), Color(1, 1, 1, 0.6), 2.0)
		ci.draw_line(foot + Vector2(10, -4), foot + Vector2(16, -10), Color(1, 1, 1, 0.6), 2.0)


## Mobilkran: Ausleger ueber die Baustelle, Haken mit Last (hook = Weltpunkt der Last, lift 0..1).
static func crane(ci: CanvasItem, s: Callable, c: Vector2, hook: Vector2, lift: float, load_col: Color) -> void:
	var d := (hook - c).normalized() if hook != c else Vector2(1, 0)
	obox(ci, s, c, d, 1.2, 0.6, 0.0, 0.35, STEEL)
	obox(ci, s, c - d * 0.1, d, 0.6, 0.5, 0.35, 0.9, YELLOW)
	var pivot: Vector2 = s.call(c, 0.9)
	var tip: Vector2 = s.call(hook, 5.0)
	ci.draw_line(pivot, tip, YELLOW, 5.0)
	ci.draw_line(pivot + Vector2(0, -4), tip + Vector2(0, -4), YELLOW_D, 2.0)
	var z := 1.2 + 2.6 * lift
	var load_at: Vector2 = s.call(hook, z)
	ci.draw_line(tip, load_at, Color("222222"), 1.5)
	ci.draw_rect(Rect2(load_at + Vector2(-14, 0), Vector2(28, 6)), load_col)


## Baucontainer (Bauleitung) mit Firmenschild.
static func site_office(ci: CanvasItem, s: Callable, c: Vector2, firm: Color, label: String) -> void:
	box(ci, s, c.x - 0.5, c.y - 0.25, c.x + 0.5, c.y + 0.25, 0.0, 0.95, Color("dcdcd2"))
	box(ci, s, c.x - 0.5, c.y - 0.25, c.x + 0.5, c.y + 0.25, 0.95, 1.05, firm)
	var w0: Vector2 = s.call(Vector2(c.x - 0.3, c.y + 0.25), 0.4)
	ci.draw_rect(Rect2(w0 + Vector2(0, -10), Vector2(16, 9)), Color("9cc3d8"))
	ci.draw_string(ThemeDB.fallback_font, s.call(Vector2(c.x - 0.5, c.y), 1.9), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.95))


## Materialstapel: Bohlen, Steine oder Fertigteile.
static func stack(ci: CanvasItem, s: Callable, c: Vector2, kind: String, amount: float) -> void:
	var col: Color = {"holz": Color("a0784e"), "stein": Color("a39b8b"), "stahlbeton": Color("b8bcbf"), "schotter": Color("8d8a82")}.get(kind, Color("a39b8b"))
	if kind == "schotter":
		var top: Vector2 = s.call(c, 0.25 + 0.35 * amount)
		var l: Vector2 = s.call(c + Vector2(-0.4, 0.2), 0.0)
		var r: Vector2 = s.call(c + Vector2(0.4, -0.2), 0.0)
		var f: Vector2 = s.call(c + Vector2(0.2, 0.4), 0.0)
		ci.draw_colored_polygon(PackedVector2Array([l, top, r, f]), col)
		return
	var layers := maxi(1, int(round(4.0 * amount)))
	for k in layers:
		box(ci, s, c.x - 0.35, c.y - 0.18, c.x + 0.35, c.y + 0.18, 0.18 * k, 0.18 * k + 0.15, col)


## Absperrbake (rot-weiss) an p.
static func barrier(ci: CanvasItem, s: Callable, p: Vector2) -> void:
	var a: Vector2 = s.call(p, 0.0)
	ci.draw_line(a, a + Vector2(0, -14), Color("2a2a2a"), 2.0)
	for k in 3:
		ci.draw_rect(Rect2(a + Vector2(-5, -14 + 4 * k), Vector2(10, 4)), Color("d23b2f") if k % 2 == 0 else Color("f0ece4"))
