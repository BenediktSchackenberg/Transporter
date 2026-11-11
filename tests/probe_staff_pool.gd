extends SceneTree
## Arbeitsmarkt fuer kommunale Dienste je Stadt: Einwohner, Arbeitslose, Bildung 0, kommunal Beschaeftigte je Einrichtung.
## Aufruf: Godot --headless --path . -s tests/probe_staff_pool.gd [-- --days=2]
func _init() -> void:
	var days := 2
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--days="):
			days = int(a.substr(7))
	var s := Simulation.new()
	s.world_mode = "region"
	s.start_profile = "unternehmer"
	var pl: Array = []
	for i in 4:
		pl.append({"player_name": "Spieler%d" % i, "company_name": "Firma%d" % i, "color": Catalog.COMPANY_COLORS[i], "avatar_style": i, "personality": Catalog.PERSONALITIES.keys()[i]})
	s.setup(4242, pl, Catalog.MAP_SIZE, 0.5)
	var t := 0.0
	while t < 60.0 * days:
		s.step(0.1)
		t += 0.1
	for k in s.towns.count():
		var ppl: Array = s.citizens.people.filter(func(p): return s.citizens.home_town(p) == k)
		var by_emp := {}
		for p in ppl:
			by_emp[str(p.employer)] = int(by_emp.get(str(p.employer), 0)) + 1
		print("%s: Einwohner %d, Buerger %d, arbeitslos %d, Arbeitgeber %s" % [s.towns.name_of(k), s.citizens.population_of(k), ppl.size(), s.citizens.unemployed_of(k), str(by_emp)])
		for f in s.municipal.of_town(k):
			print("    %s %s: Personal %d / Bedarf %s" % [f.code, f.name, s.municipal.staff_of(f.id).size(), str(f.get("staff_need", {}))])
	quit()
