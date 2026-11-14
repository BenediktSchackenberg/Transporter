class_name PortraitArt
extends Control
## Animiertes Pixel-Portraet einer KI-Figur (Auftrag 23): Aussehen aus dem Namen (Hautton, Frisur, Haarfarbe, Bart, Kopfbedeckung,
## Brille, Ohrring, Sommersprossen, Kragen, Krawatte/Schal, Jacke in Firmenfarbe, Hintergrund), damit jede Figur unverwechselbar ist.
## Die Animation zeigt, woran die Figur gerade arbeitet (activity) und ihre Stimmung (mood -1..1); eine vom Sprachmodell gewaehlte
## Geste (gesture) hat Vorrang. Raster 32 x 32 Bildpunkte, gezeichnet mit scharfen Kanten in der Groesse des Steuerelements.
##
## activity: denkt | telefoniert | unterschreibt | rechnet | plant | liest | geht | spricht | wartet
## gesture:  jubeln | fluchen | grübeln | telefonieren | zuversichtlich | nervös | winken | schulterzucken | daumen_hoch | kaffee

const GESTURES := ["jubeln", "fluchen", "grübeln", "telefonieren", "zuversichtlich", "nervös", "winken", "schulterzucken", "daumen_hoch", "kaffee"]
const SKINS := [Color("f3d2b5"), Color("e8b98f"), Color("d29a6a"), Color("b07a4f"), Color("8a5a36"), Color("5e3b22")]
const HAIRS := [Color("2a1c14"), Color("4a2e1c"), Color("7a4a26"), Color("b07a3a"), Color("d8b25a"), Color("c0502a"), Color("8a8a8a"), Color("e8e4dc"), Color("3a2a5a"), Color("1e3a5a")]
const EYES := [Color("3a2a1c"), Color("2a4a7a"), Color("2a6a3a"), Color("5a5a5a")]
const BGS := [Color("1d2440"), Color("23324a"), Color("2a2238"), Color("1f3a3a"), Color("3a2a22")]

var seed_name := ""
var color := Color("e07a2a")
var activity := "wartet"
var gesture := ""
var mood := 0.0
var _f := {}            # Merkmale
var _base: ImageTexture
var _t := 0.0


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER   # quadratisch bleiben, auch in hohen Karten


func setup(name_key: String, firm_color: Color) -> void:
	seed_name = name_key
	color = firm_color
	var h := absi(hash(name_key))
	var r := func(k: int, n: int) -> int: return absi(hash([h, k])) % n
	_f = {"skin": SKINS[r.call(1, SKINS.size())], "hair": HAIRS[r.call(2, HAIRS.size())], "style": r.call(3, 8), "beard": r.call(4, 6),
		"hat": r.call(5, 7), "glasses": r.call(6, 6), "earring": r.call(7, 5) == 0, "freckles": r.call(8, 5) == 0, "eye": EYES[r.call(9, EYES.size())],
		"collar": r.call(10, 3), "tie": r.call(11, 4), "bg": BGS[r.call(12, BGS.size())], "brow": r.call(13, 3), "head_w": 10 + r.call(14, 3),
		"phase": float(r.call(15, 100)) / 10.0}
	_base = ImageTexture.create_from_image(_paint_base())
	queue_redraw()


func _process(delta: float) -> void:
	if not is_visible_in_tree() or _base == null:
		return
	_t += delta
	queue_redraw()


# ------------------------------------------------------------------ feste Teile (einmal je Figur)
func _paint_base() -> Image:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var bg: Color = _f.bg
	for y in 32:
		for x in 32:
			img.set_pixel(x, y, bg.lerp(color.darkened(0.55), float(y) / 40.0))
	var sky := absi(hash(seed_name + "sky"))
	var x0 := 0
	while x0 < 32:   # Skyline mit Fenstern
		var w := 3 + (sky >> (x0 % 16)) % 4
		var hh := 6 + (sky >> ((x0 + 3) % 20)) % 9
		for y in range(32 - hh, 32):
			for x in range(x0, mini(32, x0 + w)):
				var lit := (x + y * 3 + sky) % 7 == 0 and y < 30
				img.set_pixel(x, y, Color("f2c14e").darkened(0.2) if lit else bg.darkened(0.35))
		x0 += w + 1
	return img


# ------------------------------------------------------------------ Zeichnen
func _px(x: float, y: float, w: float, h: float, c: Color) -> void:
	var side := minf(size.x, size.y)
	var s := side / 32.0
	draw_rect(Rect2((size - Vector2(side, side)) * 0.5 + Vector2(x, y) * s, Vector2(w, h) * s), c)


func _draw() -> void:
	if _base == null:
		return
	var side := minf(size.x, size.y)
	draw_texture_rect(_base, Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side)), false)
	var g := gesture if gesture != "" else _gesture_from_activity()
	var t := _t + float(_f.phase)
	var bob := 0.0
	if activity == "geht":
		bob = 1.0 if int(t * 4.0) % 2 == 0 else 0.0
	elif g == "jubeln":
		bob = -1.0 if int(t * 5.0) % 2 == 0 else 0.0
	var breathe := 1.0 if fmod(t, 3.2) < 1.6 else 0.0
	var shrug := 2.0 if g == "schulterzucken" and fmod(t, 1.6) < 0.9 else 0.0
	_body(bob + breathe * 0.5 - shrug * 0.5, shrug)
	_head(bob, g, t)
	_hands_and_props(bob, g, t)
	_effects(g, t)


func _gesture_from_activity() -> String:
	match activity:
		"denkt":
			return "grübeln"
		"telefoniert":
			return "telefonieren"
	if mood <= -0.6:
		return "nervös"
	return ""


func _body(dy: float, shrug: float) -> void:
	var jacket := color.darkened(0.15)
	var hw: int = _f.head_w
	var cx := 16.0 - float(hw) / 2.0
	_px(cx + 2, 22 + dy, hw - 4, 3, Color(_f.skin).darkened(0.1))   # Hals
	_px(5, 25 + dy - shrug, 22, 8, jacket)                            # Schultern
	_px(4, 27 + dy - shrug, 24, 6, jacket)
	_px(15, 25 + dy, 2, 7, jacket.darkened(0.25))                     # Knopfleiste
	match int(_f.collar):
		0:
			_px(12, 24 + dy, 8, 2, Color("f0ece4"))   # Hemdkragen
		1:
			_px(11, 24 + dy, 10, 2, color.lightened(0.3))   # Rollkragen
		_:
			_px(12, 24 + dy, 3, 3, Color("f0ece4"))
			_px(17, 24 + dy, 3, 3, Color("f0ece4"))
	match int(_f.tie):
		1:
			_px(15, 25 + dy, 2, 5, Color("b8402f"))   # Krawatte
		2:
			_px(11, 25 + dy, 10, 2, Color("3e7cb1"))  # Schal
		3:
			_px(15, 25 + dy, 2, 2, Color("2a2a2a"))   # Fliege
			_px(14, 25 + dy, 4, 1, Color("2a2a2a"))


func _head(dy: float, g: String, t: float) -> void:
	var skin: Color = _f.skin
	if g == "fluchen":
		skin = skin.lerp(Color("d0482f"), 0.3 + 0.1 * sin(t * 8.0))
	var hw: int = _f.head_w
	var x0 := 16.0 - float(hw) / 2.0
	var y0 := 8.0 + dy
	_px(x0, y0 + 1, hw, 13, skin)          # Gesicht
	_px(x0 + 1, y0, hw - 2, 15, skin)
	_px(x0 - 1, y0 + 6, 1, 3, skin.darkened(0.08))   # Ohren
	_px(x0 + hw, y0 + 6, 1, 3, skin.darkened(0.08))
	if _f.earring:
		_px(x0 + hw, y0 + 9, 1, 1, Color("f2c14e"))
	_hair(x0, y0, hw)
	# Augen (blinzeln alle ~4 s), Blickrichtung nach Taetigkeit
	var blink := fmod(t, 4.1) < 0.14
	var look := Vector2.ZERO
	match activity:
		"unterschreibt", "rechnet", "plant":
			look = Vector2(0, 1)
		"denkt":
			look = Vector2(1, -1)
		"liest":
			look = Vector2(-1 if fmod(t, 1.4) < 0.7 else 1, 1)
	if g == "nervös":
		look = Vector2(-1 if fmod(t * 3.0, 2.0) < 1.0 else 1, 0)
	var ey := y0 + 6
	for ex: float in [x0 + 2.0, x0 + float(hw) - 4.0]:
		if blink:
			_px(ex, ey + 1, 2, 1, skin.darkened(0.45))
		else:
			_px(ex, ey, 2, 2, Color("f8f6f0"))
			_px(ex + (1.0 if look.x > 0 else 0.0), ey + (1.0 if look.y > 0 else 0.0) - (0.0 if look.y >= 0 else 0.0), 1, 1, _f.eye)
	# Augenbrauen: wuetend schraeg, besorgt hochgezogen
	var bc: Color = Color(_f.hair).darkened(0.2)
	for side: int in [0, 1]:
		var bx := x0 + 2.0 if side == 0 else x0 + float(hw) - 4.0
		var tilt := 0.0
		if g == "fluchen" or mood < -0.3:
			tilt = 1.0 if side == 0 else -1.0
		if g in ["nervös", "schulterzucken"]:
			tilt = -1.0 if side == 0 else 1.0
		_px(bx, ey - 2 + maxf(0.0, tilt), 1, 1, bc)
		_px(bx + 1, ey - 2 + maxf(0.0, -tilt), 1, 1, bc)
	if int(_f.glasses) == 1:
		_frame(x0 + 1.5, ey - 1, Color("2a2a2a"))
		_frame(x0 + float(hw) - 4.5, ey - 1, Color("2a2a2a"))
		_px(x0 + 4.5, ey, float(hw) - 9.0, 1, Color("2a2a2a"))
	elif int(_f.glasses) == 2:   # Sonnenbrille
		_px(x0 + 1, ey - 0.5, float(hw) - 2.0, 2.5, Color("1a1a22"))
	if _f.freckles:
		_px(x0 + 2, ey + 3, 1, 1, skin.darkened(0.25))
		_px(x0 + float(hw) - 3, ey + 3, 1, 1, skin.darkened(0.25))
	_px(16 - 0.5, ey + 2, 1, 2, skin.darkened(0.18))   # Nase
	_beard(x0, y0, hw)
	_mouth(y0, g, t)
	_hat(x0, y0, hw)


func _frame(x: float, y: float, c: Color) -> void:
	_px(x, y, 3, 1, c)
	_px(x, y + 3, 3, 1, c)
	_px(x, y, 1, 4, c)
	_px(x + 3, y, 1, 4, c)


func _hair(x0: float, y0: float, hw: int) -> void:
	var c: Color = _f.hair
	match int(_f.style):
		0:   # kurz
			_px(x0, y0 - 1, hw, 3, c)
		1:   # lang
			_px(x0 - 1, y0 - 1, hw + 2, 3, c)
			_px(x0 - 1, y0 + 2, 2, 12, c)
			_px(x0 + float(hw) - 1, y0 + 2, 2, 12, c)
		2:   # Dutt
			_px(x0, y0 - 1, hw, 3, c)
			_px(14, y0 - 4, 4, 3, c)
		3:   # Locken
			for k in int(hw / 2) + 1:
				_px(x0 - 1 + float(k) * 2.0, y0 - 2 + float(k % 2), 2, 3, c)
			_px(x0 - 1, y0 + 1, 2, 5, c)
			_px(x0 + float(hw) - 1, y0 + 1, 2, 5, c)
		4:   # Glatze mit Kranz
			_px(x0 - 1, y0 + 4, 2, 4, c)
			_px(x0 + float(hw) - 1, y0 + 4, 2, 4, c)
		5:   # Pferdeschwanz
			_px(x0, y0 - 1, hw, 3, c)
			_px(x0 + float(hw), y0 + 2, 2, 7, c)
		6:   # Irokese
			_px(14, y0 - 4, 4, 5, c)
		_:   # Seitenscheitel
			_px(x0, y0 - 1, hw, 2, c)
			_px(x0, y0 + 1, 4, 2, c)


func _beard(x0: float, y0: float, hw: int) -> void:
	var c: Color = Color(_f.hair).darkened(0.1)
	match int(_f.beard):
		1:   # Vollbart
			_px(x0, y0 + 10, hw, 4, c)
			_px(x0 + 2, y0 + 14, hw - 4, 1, c)
		2:   # Schnurrbart
			_px(13, y0 + 10, 6, 1, c)
		3:   # Dreitagebart
			for k in hw:
				if k % 2 == 0:
					_px(x0 + float(k), y0 + 12, 1, 1, c.lerp(Color(_f.skin), 0.5))


func _mouth(y0: float, g: String, t: float) -> void:
	var my := y0 + 11
	var talking := activity in ["telefoniert", "spricht"] or g in ["telefonieren", "fluchen", "winken"]
	if g == "jubeln":
		_px(14, my - 1, 4, 3, Color("5a1e1e"))
		return
	if talking and int(t * 6.0) % 2 == 0:
		_px(14.5, my - 0.5, 3, 2, Color("5a1e1e"))
		return
	if g == "kaffee" and fmod(t, 2.4) < 1.0:
		return   # Tasse vor dem Mund
	var happy := mood > 0.25 or g in ["zuversichtlich", "daumen_hoch", "winken"]
	var sad := mood < -0.25 or g in ["nervös", "fluchen"]
	var lip := Color("8a3a32")
	_px(14, my, 4, 1, lip)
	if happy:
		_px(13, my - 1, 1, 1, lip)
		_px(18, my - 1, 1, 1, lip)
	elif sad:
		_px(13, my + 1, 1, 1, lip)
		_px(18, my + 1, 1, 1, lip)


func _hat(x0: float, y0: float, hw: int) -> void:
	match int(_f.hat):
		1:   # Kappe in Firmenfarbe
			_px(x0 - 1, y0 - 2, hw + 2, 3, color)
			_px(x0 + float(hw) - 2, y0 + 1, 4, 1, color.darkened(0.3))
		2:   # Bauhelm
			_px(x0 - 1, y0 - 3, hw + 2, 4, Color("f2c14e"))
			_px(x0 - 2, y0 + 1, hw + 4, 1, Color("c8961f"))
		3:   # Muetze
			_px(x0 - 1, y0 - 3, hw + 2, 4, color.lightened(0.2))
			_px(15, y0 - 5, 2, 2, Color("f0ece4"))
		4:   # Hut
			_px(x0 - 3, y0, hw + 6, 1, Color("2a2a2a"))
			_px(x0, y0 - 4, hw, 4, Color("3a3a3a"))
			_px(x0, y0 - 1, hw, 1, color)


func _hands_and_props(dy: float, g: String, t: float) -> void:
	var skin: Color = _f.skin
	match g:
		"grübeln":   # Hand am Kinn
			_px(18, 20 + dy, 3, 3, skin)
			_px(19, 23 + dy, 2, 4, color.darkened(0.15))
			return
		"telefonieren":   # Hoerer am Ohr
			_px(22, 13 + dy, 2, 6, Color("2a2a2a"))
			_px(22, 18 + dy, 3, 3, skin)
			_px(23, 21 + dy, 2, 5, color.darkened(0.15))
			return
		"jubeln":
			for side: float in [-1.0, 1.0]:
				var x := 16.0 + side * 10.0
				_px(x, 8 + dy - (1.0 if int(t * 5.0) % 2 == 0 else 0.0), 2, 14, color.darkened(0.15))
				_px(x - 0.5, 5 + dy - (1.0 if int(t * 5.0) % 2 == 0 else 0.0), 3, 3, skin)
			return
		"winken":
			var a := 1.0 if int(t * 4.0) % 2 == 0 else -1.0
			_px(24 + a, 12 + dy, 3, 3, skin)
			_px(24, 15 + dy, 2, 11, color.darkened(0.15))
			return
		"daumen_hoch", "zuversichtlich":
			_px(22, 17 + dy, 3, 3, skin)
			_px(23, 15 + dy, 1, 2, skin)
			_px(22, 20 + dy, 2, 6, color.darkened(0.15))
			return
		"schulterzucken":
			for side: float in [-1.0, 1.0]:
				_px(16.0 + side * 9.0 - 1.0, 21 + dy, 3, 2, skin)
			return
		"kaffee":
			var up := fmod(t, 2.4) < 1.0
			var cy := 18.0 if up else 24.0
			_px(14, cy + dy, 4, 4, Color("f0ece4"))
			_px(18, cy + 1 + dy, 1, 2, Color("f0ece4"))
			_px(14.5, cy + dy, 3, 1, Color("6b3e1e"))
			return
	match activity:
		"unterschreibt":   # Blatt und Stift, der Stift wandert
			_px(9, 27, 14, 5, Color("f0ece4"))
			for k in 3:
				_px(11, 28 + k, 8, 0.5, Color("9a9a9a"))
			var px := 11.0 + fmod(t * 6.0, 9.0)
			_px(px, 26, 1, 3, Color("2a2a2a"))
			_px(px - 0.5, 28, 3, 2, skin)
		"rechnet":   # Taschenrechner, Tasten leuchten
			_px(11, 26, 10, 6, Color("4a4f58"))
			_px(12, 26.5, 8, 1.5, Color("9cc3a0"))
			for k in 6:
				var lit := int(t * 5.0) % 6 == k
				_px(12 + float(k % 3) * 3.0, 28.5 + float(k / 3) * 1.5, 2, 1, Color("f2c14e") if lit else Color("8a8f98"))
		"plant":   # Bauplan
			_px(8, 25, 16, 7, Color("2f5d8a"))
			_px(10, 27, 8, 0.5, Color("e8f0ff"))
			_px(10, 27, 0.5, 4, Color("e8f0ff"))
			_px(17.5, 27, 0.5, 4, Color("e8f0ff"))
			_px(10, 30.5, 8, 0.5, Color("e8f0ff"))
		"liest":   # Klemmbrett mit Auftragsliste
			_px(10, 25, 12, 7, Color("a0784e"))
			_px(11, 26, 10, 6, Color("f0ece4"))
			for k in 3:
				_px(12, 27 + float(k) * 1.5, 7, 0.5, Color("6b6b6b"))
		"spricht":
			var a2 := 1.0 if int(t * 3.0) % 2 == 0 else 0.0
			_px(21, 20 - a2 + dy, 3, 3, skin)
		"wartet":
			var tap := int(t * 2.0) % 2
			_px(12 + float(tap), 26, 3, 2, skin)


func _effects(g: String, t: float) -> void:
	match g:
		"grübeln":   # Gedankenblase mit wandernden Punkten
			_px(24, 9, 1, 1, Color(1, 1, 1, 0.8))
			_px(25, 6, 2, 2, Color(1, 1, 1, 0.85))
			_px(24, 0, 8, 5, Color(1, 1, 1, 0.92))
			for k in 3:
				if int(t * 3.0) % 4 > k:
					_px(25 + float(k) * 2.0, 2, 1, 1, Color("2a2a2a"))
		"telefonieren":   # Schallwellen
			var a := fmod(t * 2.0, 1.0)
			_px(26 + a * 3.0, 12, 1, 4, Color(1, 1, 1, 0.7 * (1.0 - a)))
		"jubeln":   # Konfetti
			for k in 8:
				var x := fmod(float(k) * 4.3 + t * 3.0 * (1.0 + float(k % 3)), 32.0)
				var y := fmod(float(k) * 7.1 + t * 9.0, 24.0)
				_px(x, y, 1, 1, [Color("f2c14e"), Color("e07a5f"), Color("6fcf97"), Color("56ccf2")][k % 4])
		"fluchen":   # Dampf ueber dem Kopf
			for k in 2:
				var a2 := fmod(t * 1.5 + float(k) * 0.5, 1.0)
				_px(10 + float(k) * 10.0, 5 - a2 * 5.0, 2, 2, Color(1, 1, 1, 0.6 * (1.0 - a2)))
		"nervös":   # Schweisstropfen
			var a3 := fmod(t * 0.8, 1.0)
			_px(22, 9 + a3 * 6.0, 1, 2, Color("8fd3ff"))
		"daumen_hoch", "zuversichtlich":
			if fmod(t, 1.5) < 0.4:
				_px(26, 5, 1, 3, Color("f2f2a0"))
				_px(25, 6, 3, 1, Color("f2f2a0"))
	if activity == "geht":   # Bewegungsstreifen
		for k in 3:
			var x2 := fmod(-t * 20.0 + float(k) * 11.0, 32.0)
			_px(x2 if x2 >= 0.0 else x2 + 32.0, 29 + float(k % 2), 4, 0.5, Color(1, 1, 1, 0.25))
	if activity == "wartet" and gesture == "" and fmod(t, 9.0) > 7.5:   # kurzes Gaehnen/Zz
		_px(24, 4, 2, 1, Color(1, 1, 1, 0.7))
		_px(25, 5, 1, 1, Color(1, 1, 1, 0.7))
		_px(24, 6, 2, 1, Color(1, 1, 1, 0.7))
