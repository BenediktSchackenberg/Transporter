extends SceneTree
## Autobahn (Auftrag 21): Verkehrszaehlung ueber N Tage, geplante Trasse (Felder, Anschlussstellen, Kreuzungen, Kosten, Bund/Staedte),
## Rechenzeit der Planung. Optional --build: Autobahn sofort beschliessen und fertigstellen (Sichtpruefung, Fahrzeiten).
## Aufruf: Godot --headless --path . -s tests/probe_highway.gd -- [--days=30] [--seed=4242] [--file=user://saves/x.json]

func _init() -> void:
	var days := 30
	var seed_v := 4242
	var path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--days="):
			days = int(a.substr(7))
		if a.begins_with("--seed="):
			seed_v = int(a.substr(7))
		if a.begins_with("--file="):
			path = a.substr(7)
	var s: Simulation
	if path != "":
		s = Simulation.from_dict(JSON.parse_string(FileAccess.get_file_as_string(path)).sim)
	else:
		s = Simulation.new()
		s.world_mode = "region"
		s.start_profile = "unternehmer"
		var pl: Array = []
		for i in 4:
			pl.append({"player_name": "S%d" % i, "company_name": "F%d" % i, "color": Catalog.COMPANY_COLORS[i], "avatar_style": i,
				"personality": Catalog.PERSONALITIES.keys()[i]})
		s.setup(seed_v, pl, Catalog.MAP_SIZE, 0.5)
	for i in days * 600:
		s.step(0.1)
	var R: RegionalProjects = s.regional
	print("Verkehrszaehlung (Fahrzeugsekunden Ueberland je Tag): ", R.traffic.map(func(e): return int(e.total)))
	print("Mittel 14 Tage %.0f, Anteile %s" % [R.traffic_mean(14), str(R.traffic_shares())])
	var t0 := Time.get_ticks_msec()
	var hp: Dictionary = R.plan_highway()
	print("Planung %d ms: ok=%s Felder %d, Anschlussstellen %d, Kreuzungen %d, Kosten %.0f, Tage %d, Abschnitte %s" % [Time.get_ticks_msec() - t0, str(hp.ok),
		hp.get("cells", []).size(), hp.get("junctions", []).size(), hp.get("crossings", []).size(), float(hp.get("kosten", 0.0)), int(hp.get("tage", 0)), str(hp.get("legs", []))])
	quit()
