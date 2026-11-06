class_name AirView
extends Node2D
## Die Fluganimation (Auftrag 16, Etappe E2): zeichnet die Flugzeuge des Flughafens als leichtgewichtiges Overlay
## ueber der Karte – das gebackene Flugzeug-Sprite mit Hoehe (Höhenoffset in der 2:1-Projektion) plus einem weichen
## Bodenschatten, der unten auf dem Boden bleibt, waehrend das Flugzeug ueber der Landschaft fliegt. Liest nur aus
## Simulation/Airport; die Flugbewegung ist eine deterministische Funktion der Spieluhr (ShipView-Muster), daher
## bleibt der Flug bei Speichern/Laden nahtlos fortlaufend.

const STEP := 32.0            # 1 Hoehe-Feld = 32 Bildschirm-Pixel (2*STEP*0.5 = 64, die y-Komponente von Iso)
var sim: Simulation
var man: Dictionary
var air_node := Node2D.new()
var _plane: Node2D
var _tex := {}
var _piv := {}
var _night := 0.0


func setup(simulation: Simulation, city_view: CityView) -> void:
	sim = simulation
	man = city_view.man
	air_node.y_sort_enabled = false
	air_node.z_index = 15
	add_child(air_node)
	_plane = _make_plane()


func tex(n: String) -> Texture2D:
	if not _tex.has(n):
		_tex[n] = load("res://assets/iso/%s.png" % n) if ResourceLoader.exists("res://assets/iso/%s.png" % n) else null
	return _tex.get(n)


## Fusspunkt des Flugzeugmodells (z=0, Mitte) in Bildkoordinaten – liegt auf der Textur (negativ x = nach links).
func pivot(dir: int) -> Vector2:
	var key := "air_%d" % dir
	if not _piv.has(key):
		var e: Dictionary = man.aircraft.get(key, {})
		_piv[key] = Vector2(e.pivot[0], e.pivot[1]) if e.has("pivot") else Vector2.ZERO
	return _piv.get(key)


func _make_plane() -> Node2D:
	var n := Node2D.new()
	n.name = "plane"
	n.visible = false
	var shadow := Sprite2D.new()
	shadow.name = "shadow"
	shadow.texture = tex("air_shadow")
	shadow.centered = false
	n.add_child(shadow)
	var body := Sprite2D.new()
	body.name = "body"
	body.texture = tex("air_0")
	body.centered = false
	n.add_child(body)
	var lit := Sprite2D.new()
	lit.name = "lit"
	lit.texture = tex("air_0_lit")
	lit.centered = false
	lit.modulate.a = 0.0
	n.add_child(lit)
	air_node.add_child(n)
	return n


## Fahrtrichtung aus dem Flugfortschritt: Vorwärtsdifferenz der Positionskurve (stabil, ruckelfrei).
static func _dir_of(a: Vector2, b: Vector2) -> int:
	var d := b - a
	if d.length() < 0.001:
		return 0
	if absf(d.x) >= absf(d.y):
		return 0 if d.x >= 0.0 else 2
	return 1 if d.y >= 0.0 else 3


func update_view(_delta: float) -> void:
	if sim == null or not sim.airport.enabled or _plane == null:
		if _plane != null:
			_plane.visible = false
		return
	var st := sim.airport.state(sim.game_min)
	if st.is_empty():
		_plane.visible = false
		return
	var dir := _dir_of(sim.airport.state(sim.game_min - 0.5).pos, sim.airport.state(sim.game_min + 0.5).pos)
	var ground := Iso.to_screen(st.pos)
	var lift := -2.0 * float(st.h) * STEP * 0.5
	_plane.position = ground
	var body: Sprite2D = _plane.get_node("body")
	var key := "air_%d" % dir
	body.texture = tex(key)
	body.offset = -pivot(dir) + Vector2(0, lift)
	var lit: Sprite2D = _plane.get_node("lit")
	lit.texture = tex(key + "_lit")
	lit.offset = body.offset
	lit.modulate.a = _night
	var shadow: Sprite2D = _plane.get_node("shadow")
	shadow.offset = -pivot(dir)
	# Der Bodenschatten bleibt unten auf dem Boden; je hoeher der Flug, desto groesser und weicher (Tiefenillusion).
	shadow.scale = Vector2(1.0, 1.0).lerp(Vector2(1.6, 1.35), clampf(float(st.h) / 12.0, 0.0, 1.0))
	shadow.modulate.a = 0.42 * (1.0 - clampf(float(st.h) / 20.0, 0.0, 0.55))
	_plane.visible = true


## Naechtlichter (Positions-/Blinklichter) folgen der Naechte der Stadt.
func set_night(f: float) -> void:
	_night = f
