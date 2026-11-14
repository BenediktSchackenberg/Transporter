extends SceneTree
## Auftrag 24: Langlauf Werkstaetten und Fahrzeugwerk (Regel-Buergermeister wie im Spiel ohne Modell).
##   Godot_console.exe --headless --path . -s tests/probe_vehicle_works.gd -- --days=10


func _initialize() -> void:
	var days := 10
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--days="):
			days = int(str(a).trim_prefix("--days="))
	var s := Simulation.new()
	s.world_mode = "region"
	s.start_profile = "unternehmer"
	var ps: Array = []
	for i in 4:
		ps.append({"player_name": "P%d" % i, "company_name": "F%d" % i, "color": Catalog.COMPANY_COLORS[i], "avatar_style": i,
			"personality": Catalog.PERSONALITIES.keys()[i]})
	s.setup(4242, ps, Catalog.MAP_SIZE, 0.5)
	var mayor_day := -1
	var W: VehicleWorks = s.vworks
	while GameCalendar.day_of(s.game_min) < days:
		var day := GameCalendar.day_of(s.game_min)
		if day != mayor_day:
			mayor_day = day
			for M in s.towns.mayors:
				for a in MayorBrain.decide(M.indicators()).actions:
					var r: Dictionary = M.execute(a)
					if str(a.action) == "fahrzeug_entwerfen":
						print("Tag %d %s: %s -> %s" % [day, M.name, str(a.name), r.msg])
			var f := W.plant()
			print("Tag %d: Werk %s, Band %d, Hof %d, gebaut %d, verkauft F%d/B%d, Personal %s" % [day, f.get("name", "-"), W.line.size(), W.hof.size(),
				int(W.stats.gebaut), int(W.stats.verkauft_firmen), int(W.stats.verkauft_buerger),
				"-" if f.is_empty() else "%d/%d/%d" % [s.municipal.staff_count(f.id, "monteur"), s.municipal.staff_count(f.id, "ingenieur"), s.municipal.staff_count(f.id, "autohaendler")]])
		s.step(0.1)
	for code in ["KW-01", "KW-02", "FZ-01"]:
		var fs: Array = s.municipal.facilities.values().filter(func(x): return str(x.code) == code)
		print("%s: %s" % [code, ", ".join(fs.map(func(x): return "%s (%s, Personal %d)" % [x.name, s.towns.name_of(int(x.town)), s.municipal.staff_count(x.id)]))])
	for d in W.designs.values():
		print("Modell %s %s %s: Nutzlast %d, Tempo %.2f, Preis %s, Status %s, gebaut %d, verkauft %d" % [d.id, d.name, d.klasse, int(d.capacity), float(d.speed), Catalog.money(float(d.price)), d.status, int(d.gebaut), int(d.verkauft)])
	print("Angebote Werk: %d" % s.resources.available_offers().filter(func(o): return o.has("werk")).size())
	var rich := s.citizens.people.filter(func(p): return float(p.balance) >= 15000.0).size()
	print("Buerger mit >= 15 000 EUR: %d von %d, Pkw-Kredite %d" % [rich, s.citizens.people.size(), W.loans.size()])
	print("Statistik: %s" % str(W.stats))
	print("Hinweis: %s, Haushalt verfuegbar %s, Kasse %s" % [str(W.plant().get("hinweis", "")), Catalog.money(s.towns.mayor(W.plant_town()).available_budget()), Catalog.money(s.towns.mayor(W.plant_town()).cash())])
	var bals: Array = s.citizens.people.map(func(p): return float(p.balance))
	bals.sort()
	print("Guthaben Median %.0f, 90%% %.0f, max %.0f; kaufkraeftig %d" % [bals[bals.size() / 2], bals[int(bals.size() * 0.9)], bals[-1], s.citizens.people.filter(func(p): return W._can_buy(p, 6000.0)).size()])
	print("Geld erhalten: %.4f / %.4f" % [s.economy.conservation_error(), s.population.account_error()])
	quit(0)
