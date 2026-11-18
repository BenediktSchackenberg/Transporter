class_name EkoFigure
extends RefCounted
## Pixelfigur eines Wesens (Benedikt 15.11.2026: "die KI-Spieler sehen lieblos aus, je Spielfigur eine gute animierte Pixelfigur,
## die je nach dem, was sie macht, interagiert"). Aussehen fest aus dem Namen (Haut, Frisur, Haarfarbe, Hose, Gesicht), Kleidung in
## der Spielerfarbe, Rolle sichtbar (Buergermeister: Zylinder und Amtskette; Unternehmer: Krawatte, Aktentasche; Ruestung: Helm und
## Brustpanzer; Waffe in der Hand). Animation nach Zustand: gehen, stehen (atmen, blinzeln), tragen, bauen, reden, untersuchen,
## angreifen, ausruhen, ausser Gefecht, Gewahrsam. Zeichnung in ganzen Pixeln (draw_rect), Ursprung an den Fuessen.

const SKIN := ["#ffdbac", "#f1c9a5", "#e0ac69", "#c68642", "#8d5524"]
const HAIR := ["#2d1b0f", "#5a3825", "#a0522d", "#d4a017", "#1c1c1c", "#b5b5b5", "#e25822", "#6b3fa0"]
const PANTS := ["#2d2a32", "#3b4a6b", "#4e3b2a", "#2f4f3a", "#555555"]
const OUTLINE := Color("#1b1b24")


static func look(name: String) -> Dictionary:
	var h := absi(hash(name))
	return {"skin": Color(SKIN[h % SKIN.size()]), "hair": Color(HAIR[(h / 7) % HAIR.size()]), "style": (h / 61) % 5,
		"pants": Color(PANTS[(h / 13) % PANTS.size()]), "beard": (h / 101) % 4 == 0, "glasses": (h / 211) % 5 == 0}


## ctx: {ms, walking, facing (1/-1), action (letzte Handlung, frisch), out, custody, resting, talking, armor, weapon (Typ oder ""),
##       role ("buergermeister"|"unternehmer"|"frei"), carrying}
static func draw(n: CanvasItem, b: Dictionary, ctx: Dictionary) -> void:
	var L := look(str(b.name))
	var ms: int = ctx.ms
	var col: Color = b.color
	if bool(ctx.out):
		_lying(n, L, col, ms)
		return
	var f: int = ctx.facing
	var walking: bool = ctx.walking
	var resting: bool = ctx.resting
	var act: String = ctx.action
	var step := sin(ms / 110.0) if walking else 0.0
	var bob := (absf(step) * -1.0) if walking else (-1.0 if (ms / 900) % 2 == 0 else 0.0)   # Gehen: Wippen, Stehen: Atmen
	var sit := 4.0 if resting else 0.0
	var y0 := bob + sit
	# Beine
	if resting:
		_px(n, -4, -4, 3, 2, L.pants)
		_px(n, 1, -4, 3, 2, L.pants)
		_px(n, -5, -3, 2, 2, Color("#222"))
		_px(n, 3, -3, 2, 2, Color("#222"))
	else:
		var a := int(round(step * 2.0))   # Schrittweite: Beine schwingen gegeneinander
		_px(n, -3 + a, -7 + y0, 3, 6, L.pants)
		_px(n, 0 - a, -7 + y0, 3, 6, L.pants)
		_px(n, -3 + a + (1 if f > 0 else -1), -1 + y0, 3, 1, Color("#222"))   # Schuhe
		_px(n, 0 - a + (1 if f > 0 else -1), -1 + y0, 3, 1, Color("#222"))
	# Koerper
	var armor: float = ctx.armor
	_px(n, -4, -16 + y0, 8, 9, col)
	_px(n, -4, -16 + y0, 8, 1, col.lightened(0.2))
	_px(n, 3 if f > 0 else -4, -16 + y0, 1, 9, col.darkened(0.25))
	if armor > 0.0:   # Brustpanzer
		_px(n, -3, -15 + y0, 6, 6, Color("#9aa3ad"))
		_px(n, -3, -15 + y0, 6, 1, Color("#cfd6dd"))
	match str(ctx.role):
		"unternehmer":
			_px(n, -1, -15 + y0, 2, 1, Color.WHITE)
			_px(n, 0 if f > 0 else -1, -14 + y0, 1, 4, Color("#a31d1d"))   # Krawatte
		"buergermeister":   # Amtskette (V-Form mit Anhaenger)
			for p in [Vector2i(-3, 0), Vector2i(-2, 1), Vector2i(-1, 2), Vector2i(0, 2), Vector2i(1, 1), Vector2i(2, 0)]:
				_px(n, p.x, -15 + y0 + p.y, 1, 1, Color("#f2c94c"))
			_px(n, -1, -12 + y0, 2, 2, Color("#f2c94c"))
	# Arme (je nach Taetigkeit)
	var arm_col := col.darkened(0.1)
	var hand: Color = L.skin
	var phase := ms / 120.0
	var front_x := 4 if f > 0 else -6
	var back_x := -6 if f > 0 else 4
	if bool(ctx.custody):   # Handschellen vor dem Bauch
		_px(n, -3, -11 + y0, 6, 2, arm_col)
		_px(n, -1, -10 + y0, 2, 1, Color("#cccccc"))
	elif bool(ctx.carrying):   # Arme hoch, Last ueber dem Kopf
		_px(n, -6, -22 + y0, 2, 7, arm_col)
		_px(n, 4, -22 + y0, 2, 7, arm_col)
	elif act == "Place" or act == "Bauwerk":   # Hammer schwingen
		var up := sin(ms / 70.0) > 0.0
		_px(n, back_x, -15 + y0, 2, 6, arm_col)
		_px(n, front_x, (-19 if up else -14) + y0, 2, 6, arm_col)
		_px(n, front_x + (2 if f > 0 else -3), (-21 if up else -12) + y0, 3, 2, Color("#6b6b6b"))
		_px(n, front_x + (1 if f > 0 else 0), (-20 if up else -13) + y0, 1, 4, Color("#8b5a2b"))
	elif act == "Attack":   # Schlag mit Blitz
		var hit := (ms / 90) % 3
		_px(n, back_x, -15 + y0, 2, 6, arm_col)
		_px(n, front_x + hit * f, -16 + y0, 4, 2, arm_col)
		n.draw_circle(Vector2(front_x + (7 + hit) * f, -15 + y0), 2.0 + hit, Color(1.0, 0.9, 0.3, 0.8))
	elif act == "Inspect":   # Lupe vor dem Auge
		_px(n, back_x, -15 + y0, 2, 6, arm_col)
		_px(n, front_x, -20 + y0, 2, 5, arm_col)
		n.draw_arc(Vector2(front_x + 3 * f, -22 + y0), 2.5, 0.0, TAU, 10, Color("#8a6d3b"), 1.0)
		n.draw_circle(Vector2(front_x + 3 * f, -22 + y0), 1.8, Color(0.7, 0.9, 1.0, 0.6))
	elif bool(ctx.talking):   # Geste beim Reden
		_px(n, back_x, -15 + y0, 2, 6, arm_col)
		var g := int(round(sin(ms / 160.0) * 2.0))
		_px(n, front_x, -17 + y0 - g, 2, 6, arm_col)
		_px(n, front_x, -18 + y0 - g, 2, 2, hand)
	elif walking:
		var s := int(round(sin(phase) * 2.0))
		_px(n, -6, -15 + y0 + s, 2, 6, arm_col)
		_px(n, 4, -15 + y0 - s, 2, 6, arm_col)
		_px(n, -6, -10 + y0 + s, 2, 2, hand)
		_px(n, 4, -10 + y0 - s, 2, 2, hand)
		if str(ctx.role) == "unternehmer":   # Aktentasche
			_px(n, front_x - (1 if f < 0 else 0), -9 + y0 - s, 3, 3, Color("#4a2f1a"))
	else:
		_px(n, -6, -15 + y0, 2, 7, arm_col)
		_px(n, 4, -15 + y0, 2, 7, arm_col)
		_px(n, -6, -9 + y0, 2, 2, hand)
		_px(n, 4, -9 + y0, 2, 2, hand)
	# Waffe in der Hand
	var wt: String = ctx.weapon
	if wt != "" and act != "Attack" and not bool(ctx.carrying):
		var wx := 5 if f > 0 else -7
		match wt:
			"nahkampf":
				_px(n, wx, -16 + y0, 1, 7, Color("#c0c6cc"))
				_px(n, wx - 1, -10 + y0, 3, 1, Color("#8b5a2b"))
			"fernkampf":
				_px(n, wx - (2 if f < 0 else 0), -11 + y0, 4, 2, Color("#333"))
			"sprengsatz":
				n.draw_circle(Vector2(wx + 1, -9 + y0), 2.0, Color("#222"))
				_px(n, wx + 1, -12 + y0, 1, 2, Color("#e6a23c"))
			"atom":
				_px(n, wx - 1, -12 + y0, 4, 4, Color("#4b5320"))
				_px(n, wx, -11 + y0, 2, 2, Color("#f2e600"))
	# Kopf
	_px(n, -4, -24 + y0, 8, 8, L.skin)
	_px(n, (3 if f > 0 else -4), -24 + y0, 1, 8, L.skin.darkened(0.15))
	var blink := (ms / 120) % 28 == 0
	var ex := 1 if f > 0 else -2
	if resting or blink:
		_px(n, ex - 1, -20 + y0, 2, 1, OUTLINE)
		_px(n, ex + 2, -20 + y0, 1, 1, OUTLINE)
	else:
		_px(n, ex - 1, -21 + y0, 1, 2, OUTLINE)
		_px(n, ex + 2, -21 + y0, 1, 2, OUTLINE)
	if bool(L.glasses):
		_px(n, ex - 2, -21 + y0, 6, 1, Color(0.2, 0.2, 0.25, 0.8))
	var mouth_open := bool(ctx.talking) and (ms / 140) % 2 == 0
	_px(n, ex, -18 + y0, 2, 2 if mouth_open else 1, Color("#7a2e2e"))
	if bool(L.beard):
		_px(n, -3, -18 + y0, 6, 2, L.hair)
	# Haare / Kopfbedeckung
	if armor > 0.0:
		_px(n, -5, -26 + y0, 10, 3, Color("#8a939c"))
		_px(n, -5, -26 + y0, 10, 1, Color("#cfd6dd"))
	elif str(ctx.role) == "buergermeister":
		_px(n, -4, -25 + y0, 8, 1, Color("#111"))
		_px(n, -3, -31 + y0, 6, 6, Color("#111"))
		_px(n, -3, -27 + y0, 6, 1, Color("#7a1f1f"))
	else:
		match int(L.style):
			0:   # kurz
				_px(n, -4, -25 + y0, 8, 2, L.hair)
			1:   # lang
				_px(n, -4, -25 + y0, 8, 2, L.hair)
				_px(n, -5, -24 + y0, 2, 7, L.hair)
				_px(n, 3, -24 + y0, 2, 7, L.hair)
			2:   # Glatze mit Kranz
				_px(n, -4, -22 + y0, 1, 3, L.hair)
				_px(n, 3, -22 + y0, 1, 3, L.hair)
			3:   # Pferdeschwanz, schwingt beim Gehen
				_px(n, -4, -25 + y0, 8, 2, L.hair)
				var sw := int(round(step * 2.0))
				_px(n, (-6 if f > 0 else 4) + sw, -23 + y0, 2, 5, L.hair)
			4:   # Locken
				for i in 5:
					_px(n, -5 + i * 2, -26 + y0 + (i % 2), 2, 2, L.hair)
	if resting:   # Zzz
		var zp := fmod(ms / 1200.0, 1.0)
		n.draw_string(ThemeDB.fallback_font, Vector2(4 + zp * 6, -26 - zp * 10), "z", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(1, 1, 1, 1.0 - zp))
	if bool(ctx.custody):
		n.draw_string(ThemeDB.fallback_font, Vector2(-3, -34), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("#4aa3ff"))


## Fahrer hinter der Scheibe (Benedikt 18.11.2026: "wie sie mit dem Fahrzeug faehrt ... muss wesentlich besser und detaillierter
## werden"). Ursprung = Kopfmitte auf dem Fahrersitz (EkoView.DRIVER_SEAT). dir wie die Fahrzeugbilder: 0 rechts unten, 1 links unten
## (Gesicht sichtbar), 2 links oben, 3 rechts oben (Hinterkopf durch die Rueckscheibe). Lenkrad mit beiden Haenden, lenkt bei
## Richtungswechseln (steer -1..1) sichtbar ein, der Kopf wippt mit der Federung, schaut ab und zu zur Seite, blinzelt, spricht.
static func draw_driver(n: CanvasItem, b: Dictionary, dir: int, ms: int, steer: float, boss: bool) -> void:
	var L := look(str(b.name))
	var col: Color = b.color
	var front := dir <= 1
	var f := 1 if dir == 0 or dir == 3 else -1
	var bob := roundf(sin(ms / 95.0 + absi(hash(str(b.name))) % 7) * 0.6)
	var talking := float(b.get("say_left", 0.0)) > 0.0 and str(b.get("say", "")) != ""
	var look_t := (ms / 100) % 60
	var glance := 0 if look_t < 46 else (f * -1 if look_t < 53 else f)   # schaut kurz in den Spiegel und zur Seite
	var robot := str(b.get("art", "mensch")) == "roboter"
	# Oberkoerper und Schultern (Sitzlehne dahinter)
	_px(n, -6, 2 + bob, 12, 6, Color("#2b2d33"))
	_px(n, -5, 3 + bob, 10, 5, col)
	_px(n, -5, 3 + bob, 10, 1, col.lightened(0.2))
	if boss and front:   # Hemdkragen und Krawatte
		_px(n, -1, 3 + bob, 2, 1, Color.WHITE)
		_px(n, (0 if f > 0 else -1), 4 + bob, 1, 3, Color("#a31d1d"))
	if int(b.get("amt", -1)) >= 0 and front:
		_px(n, -2, 4 + bob, 4, 1, Color("#f2c94c"))
	# Kopf
	if robot:
		_px(n, -5, -5 + bob, 10, 8, Color("#a8e6cf"))
		_px(n, -4, -4 + bob, 8, 5, Color("#10202a") if front else Color("#7fb8a4"))
		if front:
			_px(n, -3 + glance, -3 + bob, 2, 2, Color("#6ff3ff"))
			_px(n, 1 + glance, -3 + bob, 2, 2, Color("#6ff3ff"))
		var pulse := 0.5 + 0.5 * sin(ms / 250.0)
		_px(n, 0, -8 + bob, 1, 3, Color("#2f5d50"))
		n.draw_circle(Vector2(0.5, -8.5 + bob), 1.3, Color("#7dff8a").lerp(Color("#d4ffda"), pulse))
	else:
		_px(n, -4, -5 + bob, 8, 8, L.skin)
		if front:
			_px(n, (3 if f > 0 else -4), -5 + bob, 1, 8, (L.skin as Color).darkened(0.15))
			var ex := (1 if f > 0 else -2) + glance
			if (ms / 120) % 31 == 0:
				_px(n, ex - 1, -1 + bob, 4, 1, OUTLINE)
			else:
				_px(n, ex - 1, -2 + bob, 1, 2, OUTLINE)
				_px(n, ex + 2, -2 + bob, 1, 2, OUTLINE)
			if bool(L.glasses):
				_px(n, ex - 2, -2 + bob, 6, 1, Color(0.2, 0.2, 0.25, 0.8))
			_px(n, ex, 1 + bob, 2, 2 if talking and (ms / 140) % 2 == 0 else 1, Color("#7a2e2e"))
			if bool(L.beard):
				_px(n, -3, 1 + bob, 6, 2, L.hair)
		# Haare: von vorn nur oben, von hinten der ganze Hinterkopf
		if int(b.get("amt", -1)) >= 0:
			_px(n, -4, -6 + bob, 8, 1, Color("#111"))
			_px(n, -3, -10 + bob, 6, 4, Color("#111"))
		elif front:
			match int(L.style):
				2:
					_px(n, -4, -3 + bob, 1, 3, L.hair)
					_px(n, 3, -3 + bob, 1, 3, L.hair)
				4:
					for i in 5:
						_px(n, -5 + i * 2, -7 + bob + (i % 2), 2, 2, L.hair)
				_:
					_px(n, -4, -6 + bob, 8, 2, L.hair)
		else:
			_px(n, -4, -6 + bob, 8, 7 if int(L.style) != 2 else 3, L.hair)
			if int(L.style) == 3:
				_px(n, -1, 1 + bob, 2, 3, L.hair)
	# Lenkrad und Haende (von vorn sichtbar; lenkt bei Richtungswechseln ein, kleine Korrekturen im Gelaende)
	var turn := steer + sin(ms / 260.0) * 0.15
	if front:
		var wc := Vector2(f * 2.0, 7.0 + bob)
		n.draw_arc(wc, 4.5, PI + 0.3, TAU - 0.3, 10, Color("#1b1b1f"), 1.6)
		var hl := wc + Vector2(-4, -1).rotated(turn * 0.6)
		var hr := wc + Vector2(4, -1).rotated(turn * 0.6)
		_px(n, hl.x - 1, hl.y - 1, 2, 2, L.skin)
		_px(n, hr.x - 1, hr.y - 1, 2, 2, L.skin)
		_px(n, -6, 4 + bob, 2, 3, col.darkened(0.1))
		_px(n, 4, 4 + bob, 2, 3, col.darkened(0.1))
	else:   # von hinten: Ellbogen wandern mit dem Lenken
		var el := int(round(turn * 2.0))
		_px(n, -7, 4 + bob - el, 2, 3, col.darkened(0.15))
		_px(n, 5, 4 + bob + el, 2, 3, col.darkened(0.15))
	# Scheibe davor: leichte Toenung und ein wandernder Lichtreflex
	n.draw_rect(Rect2(-7, -9, 14, 18), Color(0.55, 0.75, 0.95, 0.12))
	var gl := fmod(ms / 2600.0, 1.0) * 22.0 - 11.0
	n.draw_line(Vector2(gl - 3, 8), Vector2(gl + 3, -8), Color(1, 1, 1, 0.18), 1.5)


## Ausser Gefecht: liegend, blass, Sterne kreisen.
static func _lying(n: CanvasItem, L: Dictionary, col: Color, ms: int) -> void:
	var grey := col.lerp(Color("#777777"), 0.5)
	_px(n, -10, -4, 7, 3, L.pants)
	_px(n, -3, -5, 9, 4, grey)
	_px(n, 6, -6, 6, 5, (L.skin as Color).lerp(Color("#bbbbbb"), 0.4))
	_px(n, 8, -5, 1, 1, OUTLINE)
	for i in 3:
		var a := ms / 300.0 + i * TAU / 3.0
		n.draw_string(ThemeDB.fallback_font, Vector2(9 + cos(a) * 6, -9 + sin(a) * 2), "*", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color("#ffe27a"))


static func _px(n: CanvasItem, x: float, y: float, w: float, h: float, c: Color) -> void:
	n.draw_rect(Rect2(round(x), round(y), w, h), c)
