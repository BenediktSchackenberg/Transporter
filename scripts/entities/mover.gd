class_name Mover
extends RefCounted
## Gemeinsame Pfadverfolgung fuer Fahrzeuge (mit Rechtsverkehr-Spurversatz) und Figuren.

var pos := Vector2.ZERO
var path: Array[Vector2i] = []
var path_i := 0
var heading := Vector2.RIGHT
var speed := 2.5            # Tiles pro Sim-Sekunde
var lane := 7.0             # Spurversatz in Pixel (0 fuer Fussgaenger)
var goal := Vector2i(-1, -1)
var wait_time := 0.0        # wie lange schon blockiert
var distance_moved := 0.0   # tatsaechliche Pixelstrecke des letzten advance-Aufrufs
var tiles_moved := 0        # Zaehler fuer Treibstoff/Verschleiss (vom Besitzer abgeholt)


func set_path(p: Array[Vector2i]) -> void:
	path = p
	path_i = 1 if p.size() > 1 else 0
	goal = p[-1] if not p.is_empty() else Vector2i(-1, -1)
	if p.size() == 1:
		path_i = 1


func arrived() -> bool:
	return path_i >= path.size()


func tile() -> Vector2i:
	return CityData.to_tile(pos)


func next_tile() -> Vector2i:
	return path[path_i] if path_i < path.size() else tile()


func point_for(i: int) -> Vector2:
	var cell := path[i]
	var center := Vector2(cell.x * 32 + 16, cell.y * 32 + 16)
	if lane == 0.0 or i == 0:
		return center
	var d := Vector2(path[i] - path[i - 1])
	return center + Vector2(-d.y, d.x) * lane


## Bewegt um dt Sim-Sekunden. factor skaliert die Geschwindigkeit (Wetter, Stau, Stoerung).
func advance(dt: float, factor: float) -> void:
	distance_moved = 0.0
	var budget := speed * 32.0 * dt * factor
	while budget > 0.0 and path_i < path.size():
		var tgt := point_for(path_i)
		var to := tgt - pos
		var dist := to.length()
		if dist > 0.01:
			heading = to / dist
		distance_moved += minf(budget, dist)
		if budget >= dist:
			pos = tgt
			budget -= dist
			path_i += 1
			tiles_moved += 1
		else:
			pos += heading * budget
			budget = 0.0
