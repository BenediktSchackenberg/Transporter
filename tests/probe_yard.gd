extends SceneTree
## Messung (kein Pass/Fail): Hof-Imperium (Auftrag 11) im Regelspiel. Vier Regel-KI-Firmen, Regel-Buergermeister alle 2 Spieltage.
## Je 15 Tage: Gebaeude je Firma, Spezialisierungen, Bauantraege, Gebote, Investitionsakten, Restposten-Verkaeufe.
##   Godot_console.exe --headless --path . -s tests/probe_yard.gd -- --days=60
func _initialize() -> void:
	var days := 60
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--days="):
			days = int(str(a).trim_prefix("--days="))
	var s := Simulation.new()
	var ps: Array = []
	for i in 4:
		ps.append({"player_name": "P%d" % i, "company_name": "F%d" % i, "color": Color.RED, "avatar_style": i,
			"personality": Catalog.PERSONALITIES.keys()[i]})
	s.setup(21, ps)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var last_day := -1
	var mayor_day := -1
	var step := 0
	while GameCalendar.day_of(s.game_min) < days:
		if step % 200 == 0:
			for c in s.companies:
				var obs := ObservationBuilder.build(s, c.id, [], 0.0, 10.0)
				for a in RuleBrain.decide(obs, c.personality, rng).actions:
					s.executor.execute(c.id, a, "", "fallback")
		s.step(0.1)
		step += 1
		var day: int = GameCalendar.day_of(s.game_min)
		if day != mayor_day and day % 2 == 0:
			mayor_day = day
			for a in MayorBrain.decide(s.mayor.indicators()).actions:
				s.mayor.execute(a)
		if day != last_day and day % 15 == 0:
			last_day = day
			print("== Tag %d  Gebote offen %d  Anträge %s  Restposten verkauft %d EUR  Akten %d (gemessen %d)" % [day, s.estate.auctions.size(),
				str(s.estate.permits.values().map(func(p): return "%s:%s" % [p.typ, p.status])), int(s.city_depot.stats.get("material_sales", 0.0)),
				s.yard.records.size(), s.yard.records.filter(func(r): return r.status == "gemessen").size()])
			for c in s.companies:
				var fac: Array = s.estate.facilities.values().filter(func(f): return f.owner == c.id).map(func(f): return "%s(%s)" % [f.typ, f.status.left(4)])
				print("  %s %-16s Fz %d  Kasse %7d  Gebäude %s  Spez %s  Grund %d" % [c.company_name, c.personality, s.company_vehicles(c.id).size(), int(c.ledger.cash),
					str(fac), str(s.estate.specializations(c.id)), s.estate.plot_of(c.id).size()])
	for r in s.yard.records:
		if r.status == "gemessen":
			print("  Akte %s %s: erwartet %s, gemessen %s" % [r.fid, r.typ, str(r.erwartung), str(r.gemessen)])
	print("Faktoren ", s.yard.factors)
	quit()
