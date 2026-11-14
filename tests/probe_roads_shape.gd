extends SceneTree
## Treppenstufen der Land- und Zubringerstrassen zaehlen (Zickzack in der Schraegansicht): Anteil der Strassenfelder ausserhalb der
## Orte, die genau zwei Nachbarn ueber Eck haben (Kurve). Aufruf: Godot --headless --path . -s tests/probe_roads_shape.gd [-- --seed=4242]

func _init() -> void:
	var seed_v := 4242
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			seed_v = int(a.substr(7))
	var s := Simulation.new()
	s.world_mode = "region"
	s.start_profile = "unternehmer"
	var pl: Array = []
	for i in 4:
		pl.append({"player_name": "Spieler%d" % i, "company_name": "Firma%d" % i, "color": Catalog.COMPANY_COLORS[i], "avatar_style": i,
			"personality": Catalog.PERSONALITIES.keys()[i]})
	s.setup(seed_v, pl, Catalog.MAP_SIZE, 0.5)
	var cd: CityData = s.city
	var roads := 0
	var bends := 0
	for y in range(1, cd.size - 1):
		for x in range(1, cd.size - 1):
			var i := cd.idx(Vector2i(x, y))
			if cd.ground[i] != CityData.G.ROAD or cd.district[i] != 4:
				continue
			roads += 1
			var h := int(cd.is_road(Vector2i(x - 1, y))) + int(cd.is_road(Vector2i(x + 1, y)))
			var v := int(cd.is_road(Vector2i(x, y - 1))) + int(cd.is_road(Vector2i(x, y + 1)))
			if h == 1 and v == 1:
				bends += 1
	var hp: Dictionary = s.regional.plan_highway()
	print("Landstrassen: %d Felder, %d Kurvenfelder (%.1f %%), Autobahn ok=%s Felder %d" % [roads, bends, 100.0 * bends / maxf(1.0, roads), str(hp.get("ok")), hp.get("cells", []).size()])
	quit()
