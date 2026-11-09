extends SceneTree
## Entwickeln sich die Staedte unterschiedlich? Je Stadt alle 10 Tage: Einwohner, Beschaeftigung, Zustimmung, Wohnungen, Wartende, Betriebe.
## Aufruf: --headless --path . -s tests/probe_towns.gd -- --days=60 --seed=99293
func _init() -> void:
	var days := 60
	var seed := 99293
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--days="):
			days = int(a.split("=")[1])
		if a.begins_with("--seed="):
			seed = int(a.split("=")[1])
	var ps: Array = []
	for i in 4:
		ps.append({"player_name": "S%d" % i, "company_name": "F%d" % i, "color": Catalog.COMPANY_COLORS[i], "avatar_style": i, "personality": "wachstum"})
	var s := Simulation.new()
	s.world_mode = "region"
	s.start_profile = "unternehmer"
	s.setup(seed, ps, Catalog.MAP_SIZE, 0.5)
	for d in range(0, days + 1, 10):
		while s.game_min < d * 120.0:
			s.step(0.5)
		var rows: Array = []
		for k in s.towns.count():
			var M: Mayor = s.towns.mayor(k)
			var biz := s.biz.items.values().filter(func(b): return s.towns.of_building(int(b.site)) == k).size()
			var houses := s.city.buildings.filter(func(b): return str(b.type) in ["house", "semi", "villa", "apartment", "rowhouse"] and s.towns.of_building(int(b.id)) == k).size()
			rows.append("%s: Einw %d, besch %.0f%%, Zust %.0f, Whg %d/%d, wart %d, Haeuser %d, Betr %d" % [s.towns.name_of(k).left(10), s.citizens.population_of(k),
				s.citizens.employment_rate_of(k) * 100.0, M.approval, M.occupied_units(), M.stock_units, M.waiting, houses, biz])
		print("Tag %d | %s" % [d, " | ".join(rows)])
	quit()
