extends SceneTree
## Messung 18.11.: Strassenweg Grosslager -> Stadtlager je Stadt.
func _init() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	var s := Simulation.from_dict(d.sim if d.has("sim") else d)
	var hub: Dictionary = s.city.building(int(s.hub.loc))
	for k in s.towns.count():
		var D: CityDepot = s.towns.depot(k)
		var dst: Dictionary = s.city.building(D.building)
		var m := Mover.new()
		m.pos = s.city.tile_center(hub.road)
		var ok: bool = s.route(m, s.fleet._free_neighbor(dst.road))
		print("Stadt %d: Grosslager %d road %s -> Lager %d (%s) road %s is_road %s: Weg %s (%d Punkte)" % [k, s.hub.loc, hub.road, D.building, dst.get("name", ""), dst.road, s.city.is_road(dst.road), ok, m.path.size() if "path" in m else -1])
	# Breitensuche ueber Strassenfelder ab dem Grosslager
	var seen := {hub.road: true}
	var todo: Array[Vector2i] = [hub.road]
	var i := 0
	while i < todo.size():
		var c: Vector2i = todo[i]
		i += 1
		for dd in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = c + dd
			if not seen.has(q) and s.city.inside(q) and s.city.is_road(q):
				seen[q] = true
				todo.append(q)
	print("vom Grosslager erreichbare Strassenfelder: ", seen.size())
	var q0 := Vector2i(194, 192)
	var in_st := false
	for key in s.settlements:
		for a in s.settlements[key].get("roads", []):
			if Vector2i(int(a[0]), int(a[1])) == q0:
				in_st = true
	print("194,192 in Siedlungsstrassen: ", in_st, " ground ", s.city.g(q0), " roadworks ", s.nav.roadworks.has(q0), " barrier ", s.nav.barriers.has(q0), " solid ", s.nav.road.is_point_solid(q0), " region ", s.nav.road.region)
	s.access.reapply([[194, 192]])
	print("nach reapply solid ", s.nav.road.is_point_solid(q0))
	var bad := 0
	var allr := 0
	for x in s.city.size:
		for y in s.city.size:
			var q := Vector2i(x, y)
			if s.city.is_road(q):
				allr += 1
				if s.nav.road.is_point_solid(q):
					bad += 1
	var sr := 0
	var sbad := 0
	for key in s.settlements:
		for a in s.settlements[key].get("roads", []):
			sr += 1
			if s.nav.road.is_point_solid(Vector2i(int(a[0]), int(a[1]))):
				sbad += 1
	print("Strassenfelder gesamt %d, davon im Navigationsgitter gesperrt %d; Siedlungsstrassen %d, gesperrt %d; Baustellen %d Sperren %d" % [allr, bad, sr, sbad, s.nav.roadworks.size(), s.nav.barriers.size()])
	for k in s.towns.count():
		var dst: Dictionary = s.city.building(s.towns.depot(k).building)
		var best := 9999
		for q in seen:
			best = mini(best, absi(q.x - dst.road.x) + absi(q.y - dst.road.y))
		print("Stadt %d: Lager-Strasse erreichbar %s, naechstes erreichbares Feld %d entfernt, solid im road-Gitter %s" % [k, seen.has(dst.road), best, s.nav.road.is_point_solid(dst.road)])
	quit()
