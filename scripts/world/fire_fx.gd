class_name FireFx
extends Node2D
## Brand auf der Karte (Auftrag 20, Etappe 4): flackernde Flammenzungen und aufsteigender Rauch ueber dem Gebaeude, Groesse nach
## Brandstaerke; waehrend des Loeschangriffs ein Wasserstrahl-Bogen vom Fahrzeug zum Brandherd. Nach dem Loeschen nur noch Restrauch.
## Reine Anzeige; gezeichnet (keine Texturen), damit der Effekt bei jeder Zoomstufe und bei Tag deutlich sichtbar ist.

var intensity := 0.0          # 0..1
var burning := true
var spray_from := Vector2.ZERO   # lokale Koordinaten; Vector2.ZERO = kein Strahl
var spraying := false
var width := 40.0             # halbe Breite des Brandherds in Pixel
var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var k := clampf(intensity, 0.15, 1.0) if burning else 0.0
	# Rauch: Wolken steigen zyklisch auf, wachsen und verblassen; dunkel bei Brand, hell als Restrauch
	var puffs := 6 + int(10.0 * k)
	for i in puffs:
		var phase := fmod(_t * 0.35 + float(i) / float(puffs), 1.0)
		var x := sin(float(i) * 2.3) * width * 0.6 + phase * 40.0
		var y := -10.0 - phase * (90.0 + 120.0 * k)
		var r := 6.0 + phase * (16.0 + 22.0 * k)
		var a := (1.0 - phase) * (0.75 if burning else 0.35)
		var c := Color(0.16, 0.15, 0.15, a) if burning else Color(0.7, 0.7, 0.72, a)
		draw_circle(Vector2(x, y), r, c)
	if not burning:
		return
	# Flammen: Zungen mit flackernder Hoehe, aussen orange-rot, innen gelb
	var tongues := 3 + int(5.0 * k)
	for i in tongues:
		var u := (float(i) + 0.5) / float(tongues) * 2.0 - 1.0
		var x := u * width
		var h := (14.0 + 34.0 * k) * (0.7 + 0.3 * sin(_t * 9.0 + float(i) * 1.7)) * (1.0 - absf(u) * 0.35)
		var w := 6.0 + 6.0 * k
		draw_colored_polygon(PackedVector2Array([Vector2(x - w, 0), Vector2(x + w, 0), Vector2(x + sin(_t * 6.0 + float(i)) * 3.0, -h)]),
			Color(0.95, 0.32, 0.08, 0.95))
		draw_colored_polygon(PackedVector2Array([Vector2(x - w * 0.5, 0), Vector2(x + w * 0.5, 0), Vector2(x, -h * 0.6)]),
			Color(1.0, 0.85, 0.3, 0.95))
	# Glut am Fuss
	draw_rect(Rect2(-width, -2.0, width * 2.0, 4.0), Color(1.0, 0.55, 0.15, 0.8))
	# Wasserstrahl: Bogen aus Tropfen vom Fahrzeug zum Brandherd
	if spraying:
		var to := Vector2(0, -10)
		for i in 18:
			var s := fmod(float(i) / 18.0 + _t * 1.6, 1.0)
			var p := spray_from.lerp(to, s) + Vector2(0, -sin(s * PI) * 40.0)
			draw_circle(p, 2.5, Color(0.8, 0.92, 1.0, 0.9))
