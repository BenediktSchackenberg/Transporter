extends SceneTree
## Etappe 13: Lage der Feuerwachen (Personal im Dienst, Ehrenamtliche, Fahrzeuge, Funktionen) nach einigen Spielstunden.
## Aufruf: Godot --headless --path . -s tests/probe_fire13.gd -- [--hours=2] [--days=0]

func _init() -> void:
	var hours := 2.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hours="):
			hours = float(a.substr(8))
		if a.begins_with("--days="):
			hours += 24.0 * float(a.substr(7))
	var s := Simulation.new()
	s.world_mode = "region"
	s.start_profile = "unternehmer"
	var pl: Array = []
	for i in 4:
		pl.append({"player_name": "S%d" % i, "company_name": "F%d" % i, "color": Catalog.COMPANY_COLORS[i], "avatar_style": i,
			"personality": Catalog.PERSONALITIES.keys()[i]})
	s.setup(4242, pl, Catalog.MAP_SIZE, 0.5)
	var steps := int(hours * 60.0 / Catalog.GAME_MIN_PER_SIM_SEC / 0.1)
	for i in steps:
		s.step(0.1)
	var M: Municipal = s.municipal
	var F: FireService = s.fire
	print("Zeit: Tag %d %.1f Uhr" % [GameCalendar.day_of(s.game_min), GameCalendar.hour_of(s.game_min)])
	for st in M.facilities.values():
		if not str(st.code).begins_with("FW-"):
			continue
		var staff: Array = M.staff_of(st.id)
		print("%s %s (%s): Personal %d, im Dienst %d, Ehrenamt %d, frei einsatzbereit %d, Fahrzeuge %s, Funktionen %s" % [st.code, st.name,
			s.towns.name_of(int(st.town)), staff.size(), F._pros_on_duty(st), M.volunteers_of(st.id).size(), F._crew_free(st),
			st.vehicles.map(func(v): return "%s:%s" % [M.vehicles[v].type, M.vehicles[v].status]),
			staff.map(func(p): return str(p.get("funktion", "-")))])
	print("Einsaetze: ", F.fires.values().map(func(f): return "%s %s %s %s" % [f.id, f.kind, f.status, f.phase]))
	print("Statistik: ", F.stats)
	quit()
