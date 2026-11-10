extends SceneTree
## Auftrag 20 Etappe 4: Entfernungen und Fahrzeiten zwischen den Feuerwachen der Region (Nachbarschaftshilfe) und Brandstatistik.
## Aufruf: Godot --headless --path . -s tests/probe_fire.gd -- --days=20

func _init() -> void:
	var days := 3
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--days="):
			days = int(a.substr(7))
	var s := Simulation.new()
	s.world_mode = "region"
	s.start_profile = "unternehmer"
	var pl: Array = []
	for i in 4:
		pl.append({"player_name": "Spieler%d" % i, "company_name": "Firma%d" % i, "color": Catalog.COMPANY_COLORS[i],
			"avatar_style": i, "personality": Catalog.PERSONALITIES.keys()[i]})
	s.setup(4242, pl, Catalog.MAP_SIZE, 0.5)
	for i in int(days * 600):
		s.step(0.1)
	var fw: Array = s.municipal.facilities.values().filter(func(f): return f.code == "FW-01")
	for a in fw:
		var row := []
		for b in fw:
			var ra: Vector2i = s.city.building(int(a.building)).road
			var rb: Vector2i = s.city.building(int(b.building)).road
			var p: Array = s.nav.road_path(ra, rb)
			row.append("%s:%d/%d" % [s.towns.name_of(int(b.town)), (rb - ra).length(), p.size()])
		print(s.towns.name_of(int(a.town)), " -> ", row)
	print("Braende: ", s.fire.stats, " aktiv: ", s.fire.summary().brennt)
	quit()
