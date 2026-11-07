extends SceneTree
## Messung (kein Pass/Fail): Wachstum des Kuestenorts mit Regel-KI (Unternehmer alle 200 Schritte, Buergermeister alle 2 Tage).
## Je 10 Tage: Gebaeude, Wohnhaeuser, Einwohner, Stadtkasse, Bauantraege, Bauvorhaben, Stadtprojekte, Betriebe und Stufen, Hafen.
## Godot_console.exe --headless --path . -s tests/probe_growth.gd -- --days=90 [--seed=4242]
func _initialize() -> void:
	var days := 90
	var seed_v := 4242
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--days="):
			days = int(str(a).trim_prefix("--days="))
		if str(a).begins_with("--seed="):
			seed_v = int(str(a).trim_prefix("--seed="))
	var s := Simulation.new()
	s.world_mode = "kueste"
	s.start_profile = "unternehmer"
	var ps: Array = []
	for i in 4:
		ps.append({"player_name": "P%d" % i, "company_name": "F%d" % i, "color": Color.RED, "avatar_style": i,
			"personality": Catalog.PERSONALITIES.keys()[i]})
	s.setup(seed_v, ps)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var mayor_day := -1
	var report_day := -1
	var step := 0
	var mayor_actions := {}
	var mayor_fail := {}
	var b0: int = s.city.buildings.size()
	print("Start: %s, %d Gebäude, %d Einwohner, Kasse %d" % [s.city.town_name, b0, s.citizens.population(), int(s.economy.accounts.P0)])
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
				var r: Dictionary = s.mayor.execute(a)
				mayor_actions[a.action] = int(mayor_actions.get(a.action, 0)) + 1
				if not r.get("ok", false):
					var k := "%s: %s" % [a.action, str(r.get("msg", "")).left(70)]
					mayor_fail[k] = int(mayor_fail.get(k, 0)) + 1
		if day != report_day and day % 10 == 0:
			report_day = day
			var M: Mayor = s.mayor
			var g: Dictionary = M.goals()
			var prj := {}
			for p in M.projects.values():
				var k2 := "%s/%s" % [p.kind if p.has("kind") else "plan", p.status]
				prj[k2] = int(prj.get(k2, 0)) + 1
			var bp := {}
			for p in s.construction.projects.values():
				bp[p.status] = int(bp.get(p.status, 0)) + 1
			var biz := []
			for b in s.biz.items.values():
				if BusinessStages.has_stages(str(b.branch)):
					biz.append("%s:%s S%d N%.2f" % [b.id, b.branch, BusinessStages.stage_of(b), float(b.get("demand_avg", 0.0))])
			print("Tag %d: Gebäude %d (+%d), Wohnhäuser %d, Geschäfte %d, Einwohner %d, Kasse %d, verfügbar %d, reserviert %d" % [day, s.city.buildings.size(), s.city.buildings.size() - b0,
				int(g.get("wohnhaeuser", -1)), int(g.get("geschaefte", -1)), s.citizens.population(), int(s.economy.accounts.P0), int(M.available_budget()), int(M.commitments)])
			print("   Anträge %d, Bauvorhaben %s, Stadtprojekte %s, Hafen S%d Rückstau %.1f, Ausbauten %d" % [s.permits.apps.size(), str(bp), str(prj), s.harbor.stage, s.harbor.backlog_ships(), int(s.stages.stats.ausbauten)])
			print("   Betriebe: %s" % ", ".join(biz))
	var man := {}
	for m in s.harbor.manifest:
		var k3 := "%s/%s" % [m.kind, m.item]
		man[k3] = int(man.get(k3, 0)) + int(m.qty)
	print("Manifest: ", man, " Einträge ", s.harbor.manifest.size())
	var M2: Mayor = s.mayor
	var zones := {}
	for p in s.parcels.search({"limit": 5000}):
		var k4 := "%s/%s/%s" % [p.zone, p.state, s.parcels.utility_level(p)]
		zones[k4] = int(zones.get(k4, 0)) + 1
	print("Wohnungssuchende %d, Leerstand %.3f, Bauträger-Mittel %d, Haushalte %d" % [M2.waiting, M2.vacancy(), int(s.construction.available_funds(Construction.DEVELOPER)), s.households.homes.size()])
	print("Grundstücke zone/zustand/erschliessung: ", zones)
	var probe := {"def": "doppelhaus", "floors": 1, "parking": int(Planning.DEFS.doppelhaus.parking), "financing": {"eigenmittel": 1.0e9}}
	for p in s.parcels.search({"zone": "wohnen", "limit": 5000}).filter(func(p): return s.parcels.utility_level(p) == "voll" and p.state == "frei"):
		var chk := Planning.assess(p, probe)
		print("  %s Fläche %d Eigentümer %s ok %s Fragen %s Kosten %d Mängel %s" % [p.id, int(p.area), p.owner, str(chk.ok), str(chk.questions).left(80), int(chk.costs.get("gesamt", -1)) if chk.has("costs") else -1, str(chk.blocking).left(200)])
	var fl: Array = []
	for k5 in s.economy.flows:
		if "P0" in str(k5):
			fl.append([k5, int(s.economy.flows[k5])])
	fl.sort_custom(func(a, b): return a[1] > b[1])
	print("Geldflüsse P0: ", fl.slice(0, 16))
	print("Bürgermeister-Aktionen: ", mayor_actions)
	print("gescheitert: ", mayor_fail)
	quit()
