class_name NavGrid
extends RefCounted
## Wegfindung: Strassennetz fuer Fahrzeuge, Fusswege fuer Figuren.
## Baustellen sperren Strassenzellen (Fahrzeuge planen um), Staus erhoehen die Kosten.

var city: CityData
var road := AStarGrid2D.new()
var walk := AStarGrid2D.new()
var roadworks := {}   # Vector2i -> bis Spielminute
var jams := {}        # Vector2i -> bis Spielminute


func build(c: CityData) -> void:
	city = c
	for grid in [road, walk]:
		grid.region = Rect2i(0, 0, c.size, c.size)
		grid.cell_size = Vector2(1, 1)
		grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
		grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	road.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	walk.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	walk.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	walk.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	road.update()
	walk.update()
	for y in c.size:
		for x in c.size:
			var p := Vector2i(x, y)
			road.set_point_solid(p, not c.is_road(p))
			walk.set_point_solid(p, not c.walkable(p))
			if c.is_road(p):
				walk.set_point_weight_scale(p, 4.0)   # Strasse nur zum Ueberqueren


func road_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	if from == to:
		return [from]
	return road.get_id_path(from, to)


func walk_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	if from == to:
		return [from]
	return walk.get_id_path(from, to, true)


func path_length(from: Vector2i, to: Vector2i) -> int:
	return maxi(1, road_path(from, to).size() - 1)


func is_blocked_road(p: Vector2i) -> bool:
	return roadworks.has(p)


func add_roadwork(p: Vector2i, until: float) -> void:
	roadworks[p] = until
	road.set_point_solid(p, true)


func add_jam(p: Vector2i, until: float) -> void:
	jams[p] = until
	road.set_point_weight_scale(p, 6.0)


## Abgelaufene Baustellen/Staus entfernen. Gibt true zurueck, wenn sich etwas geaendert hat.
func expire(now: float) -> bool:
	var changed := false
	for p in roadworks.keys():
		if roadworks[p] <= now:
			roadworks.erase(p)
			road.set_point_solid(p, false)
			changed = true
	for p in jams.keys():
		if jams[p] <= now:
			jams.erase(p)
			road.set_point_weight_scale(p, 1.0)
			changed = true
	return changed
