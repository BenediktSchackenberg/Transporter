extends SceneTree
## Messung (kein Pass/Fail) fuer Auftrag 17: Region mit n Staedten, Regel-KI fuer alle Unternehmen (auch spaetere Gruender) alle
## 200 Schritte, Regel-Buergermeister je Stadt alle 2 Tage. Je 15 Tage: Staedte (Einwohner, Kasse, Betriebe, Unternehmen), Gruender,
## Fluege, Pendler, Binnenhandel, Identitaet. Godot_console.exe --headless --path . -s tests/probe_region.gd -- --days=60 [--towns=4] [--seed=21]
func _initialize() -> void:
	var days := 60
	var n := 4
	var seed_v := 21
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--days="):
			days = int(str(a).trim_prefix("--days="))
		if str(a).begins_with("--towns="):
			n = int(str(a).trim_prefix("--towns="))
		if str(a).begins_with("--seed="):
			seed_v = int(str(a).trim_prefix("--seed="))
	var t = load("res://tests/run_tests.gd").new()
	var s := Simulation.new()
	s.world_mode = "region"
	s.start_profile = "unternehmer"
	var t0 := Time.get_ticks_msec()
	s.setup(seed_v, t.players(n))
	print("Setup %d ms; Städte %s" % [Time.get_ticks_msec() - t0, str(s.towns.list.map(func(x): return x.name))])
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var mayor_day := -1
	var report_day := -1
	var step := 0
	var tick_ms := 0
	while GameCalendar.day_of(s.game_min) < days:
		if step % 200 == 0:
			for c in s.companies:
				if c.status in ["geschlossen", "verwertung"]:
					continue
				var obs := ObservationBuilder.build(s, c.id, [], 0.0, 10.0)
				for a in RuleBrain.decide(obs, c.personality, rng).actions:
					s.executor.execute(c.id, a, "", "fallback")
		var st := Time.get_ticks_usec()
		s.step(0.1)
		tick_ms += Time.get_ticks_usec() - st
		step += 1
		var day: int = GameCalendar.day_of(s.game_min)
		if day != mayor_day and day % 2 == 0:
			mayor_day = day
			for M in s.towns.mayors:
				for a in MayorBrain.decide(M.indicators()).actions:
					M.execute(a)
		if day != report_day and day % 15 == 0:
			report_day = day
			print("Tag %d (Schritt Ø %.2f ms):" % [day, float(tick_ms) / 1000.0 / maxf(1.0, float(step))])
			for k in s.towns.count():
				var M: Mayor = s.towns.mayor(k)
				var biz: int = s.biz.items.values().filter(func(b): return b.status != "geschlossen" and s.towns.of_building(int(b.site)) == k).size()
				print("  %s: Einwohner %d, Kasse %d (verfügbar %d), Betriebe %d, Unternehmen mit Heimat %d, Projekte %d, Zustimmung %d" % [s.towns.name_of(k),
					s.citizens.population_of(k), int(M.cash()), int(M.available_budget()), biz, s.founders.active_home(k), M.projects.values().filter(func(p): return p.status != "fertig").size(), int(M.approval)])
			var a: Dictionary = s.air.summary()
			print("  Unternehmen %d · Gründungen %d · abgelehnt %d · Flüge %d · Passagiere %d · Fracht %d LE · Flugkasse %d · Pendler %d · Umzüge %d · Identität %s" % [s.companies.size(),
				s.founders.history.size(), s.founders.refusals.size(), int(a.statistik.fluege), int(a.statistik.passagiere), int(a.statistik.fracht_einheiten), int(a.kasse),
				int(s.commute.stats.pendler), int(s.commute.stats.umzuege), str(t.identity_ok(s))])
	for h in s.founders.history:
		print("Gründung Tag %d in %s: Firma %d %s – %s" % [int(h.tag), s.towns.name_of(int(h.stadt)), int(h.firma), h.branche, h.anlass])
	for r in s.founders.refusals.slice(-5):
		print("Abgelehnt Tag %d %s %s: %s" % [int(r.tag), s.towns.name_of(int(r.stadt)), r.branche, r.grund])
	var inner := 0
	for d in s.prod.deals.values():
		if d.seller != Production.IMPORT and d.buyer != Production.IMPORT and s.towns.of_building(int(d.seller_loc)) != s.towns.of_building(int(d.buyer_loc)):
			inner += 1
	print("Binnenhandel zwischen Städten: %d Geschäfte" % inner)
	quit()
