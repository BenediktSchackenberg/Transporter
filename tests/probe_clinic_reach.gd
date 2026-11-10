extends SceneTree
## Etappe 14: Erreichbarkeit der Kliniken je Stadt (Strassenweg vom Rathaus) und Verbleib der Notfaelle nach einigen Tagen.
## Aufruf: Godot --headless --path . -s tests/probe_clinic_reach.gd -- [--days=10] [--seed=4242]

func _init() -> void:
	var days := 10
	var seed_v := 4242
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--days="):
			days = int(a.substr(7))
		if a.begins_with("--seed="):
			seed_v = int(a.substr(7))
	var s := Simulation.new()
	s.world_mode = "region"
	s.start_profile = "unternehmer"
	var pl: Array = []
	for i in 4:
		pl.append({"player_name": "S%d" % i, "company_name": "F%d" % i, "color": Catalog.COMPANY_COLORS[i], "avatar_style": i,
			"personality": Catalog.PERSONALITIES.keys()[i]})
	s.setup(seed_v, pl, Catalog.MAP_SIZE, 0.5)
	for i in days * 600:
		s.step(0.1)
	for h in s.rescue.hospitals():
		var hr: Vector2i = s.city.building(int(h.building)).road
		for t in s.towns.list:
			var th: Vector2i = s.city.building(int(t.town_hall)).road
			print("%s -> %s: Weg %d Felder" % [t.name, h.name, s.nav.path_length(th, hr)])
	print("Rettung: ", s.rescue.stats)
	for h in s.rescue.hospitals():
		print("Betten %s: %d, belegt %d, Ankunft %d, Material %s, Aerzte %d, Pflege %d" % [h.name, s.rescue.beds(h), s.rescue.occupied(h), s.rescue._incoming(h.id),
			str(h.get("material_ok", "-")), s.municipal.staff_count(h.id, "arzt"), s.municipal.staff_count(h.id, "pflege")])
	for m in s.rescue.missions.values():
		var c := Vector2i(int(m.cell[0]), int(m.cell[1]))
		print("Einsatz %s %s Zelle %s: free_bed=%s" % [m.id, s.towns.name_of(int(m.town)), c, s.rescue.free_bed(c, false).get("name", "-")])
	print("Notversorgt: ", s.rescue.missions.values().filter(func(m): return bool(m.get("notversorgt", false))).map(func(m): return "%s %s" % [s.towns.name_of(int(m.town)), m.get("critical")]))
	quit()
