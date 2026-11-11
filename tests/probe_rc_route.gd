extends SceneTree
## Diagnose: wo stehen die Recyclinghoeffe der Startausstattung, wie lang ist der Wertstoffwagen-Wege (Hof -> Grosslager und zurueck)?

func _init() -> void:
	GameCalendar.configure(60.0)
	var s := Simulation.new()
	s.world_mode = "region"
	s.start_profile = "unternehmer"
	var pl: Array = []
	for i in 4:
		pl.append({"player_name": "Spieler%d" % i, "company_name": "Firma%d" % i, "color": Catalog.COMPANY_COLORS[i], "avatar_style": i,
			"personality": Catalog.PERSONALITIES.keys()[i]})
	s.setup(4242, pl, Catalog.MAP_SIZE, 0.5)
	run(s, 60.0)   # wie im Test: ein Tag laufen lassen
	var M: Municipal = s.municipal
	print("Grosslager: enabled=%s loc=%d" % [s.hub.enabled, int(s.hub.loc)])
	var hub_road: Vector2i = s.city.building(int(s.hub.loc)).road if s.hub.enabled else Vector2i(-1, -1)
	var order: Array = range(s.towns.count())
	order.sort_custom(func(a, b): return s.citizens.unemployed_of(a) > s.citizens.unemployed_of(b))
	print("Hof-Suche-Reihenfolge (meiste Arbeitslose zuerst): %s" % str(order))
	var k_first: int = int(order[0])
	for k in order:
		for f in M.of_town(k, "recycling"):
			if str(f.code) != "RC-01":
				continue
			var yroad: Vector2i = s.city.building(int(f.building)).road
			var mark := " <-- waehlt der Test" if k == k_first else ""
			print("%s (Stadt %d, %s): Hof-Strasse %s, Luftlinie %d Felder%s" % [f.name, k, M.TYPES["RC-01"].label, str(yroad), yroad.distance_to(hub_road), mark])
			var mv := Mover.new()
			mv.pos = s.city.tile_center(yroad)
			var ok := s.route(mv, hub_road)
			var path_len := mv.path.size() if ok else -1
			print("    Route Hof->Grosslager: ok=%s Wegpunkte=%d -> Hin ~%.0f Sim-S, Hin+Rueck ~%.0f Sim-S (SPEED 3)" % [ok, path_len, path_len / 3.0, 2.0 * path_len / 3.0])
			break
	quit()


func run(s: Simulation, sim_seconds: float) -> void:
	var t := 0.0
	while t < sim_seconds:
		s.step(0.1)
		t += 0.1
