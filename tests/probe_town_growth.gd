extends SceneTree
## Diagnose (kein Pass/Fail): warum waechst eine Stadt der Region nicht? Je Stadt alle 20 Tage: Wohngrundstuecke (frei/erschlossen),
## Bautraeger-Antraege und -Vorhaben, Buergermeister-Projekte mit Status, Wartende, Kasse. Regel-KI wie probe_region.
## Godot_console.exe --headless --path . -s tests/probe_town_growth.gd -- --days=60 [--seed=21]
func _initialize() -> void:
	var days := 60
	var seed_v := 21
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--days="):
			days = int(str(a).trim_prefix("--days="))
		if str(a).begins_with("--seed="):
			seed_v = int(str(a).trim_prefix("--seed="))
	var t = load("res://tests/run_tests.gd").new()
	var s := Simulation.new()
	s.world_mode = "region"
	s.start_profile = "unternehmer"
	s.setup(seed_v, t.players(4))
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var mayor_day := -1
	var report_day := -1
	var step := 0
	while GameCalendar.day_of(s.game_min) < days:
		if step % 200 == 0:
			for c in s.companies:
				if c.status in ["geschlossen", "verwertung"]:
					continue
				var obs := ObservationBuilder.build(s, c.id, [], 0.0, 10.0)
				for a in RuleBrain.decide(obs, c.personality, rng).actions:
					s.executor.execute(c.id, a, "", "fallback")
		s.step(0.1)
		step += 1
		var day: int = GameCalendar.day_of(s.game_min)
		if day != mayor_day and day % 2 == 0:
			mayor_day = day
			for M in s.towns.mayors:
				for a in MayorBrain.decide(M.indicators()).actions:
					M.execute(a)
		if day != report_day and day % 20 == 0:
			report_day = day
			_report(s, day)
	quit()


func _report(s: Simulation, day: int) -> void:
	print("=== Tag %d · Bautraeger-Mittel %d" % [day, int(s.construction.available_funds(Construction.DEVELOPER))])
	for k in s.towns.count():
		var M: Mayor = s.towns.mayor(k)
		var wohnen: Array = s.parcels.items.values().filter(func(p): return p.zone == "wohnen" and s.towns.of_parcel(str(p.id)) == k)
		var frei: Array = wohnen.filter(func(p): return p.state == "frei")
		var voll: Array = s.parcels.search({"zone": "wohnen", "min_area": 12, "utilities": "voll", "limit": 400, "town": k})
		var apps: Array = s.permits.apps.values().filter(func(a): return a.applicant == Construction.DEVELOPER and s.towns.of_parcel(str(a.parcel)) == k)
		var projs: Array = s.construction.projects.values().filter(func(p): return s.towns.of_parcel(str(p.parcel)) == k)
		print("%s: Wartende %d, Leerstand %.2f, Kasse %d/verfuegbar %d" % [s.towns.name_of(k), M.waiting, M.vacancy(), int(M.cash()), int(M.available_budget())])
		print("  Wohngrundstuecke %d, frei %d, voll erschlossen+frei(Suche) %d, Flaechen frei: %s" % [wohnen.size(), frei.size(), voll.size(),
			str(frei.slice(0, 8).map(func(p): return int(p.area)))])
		print("  Bautraeger-Antraege: %s" % str(apps.map(func(a): return "%s %s %s" % [a.parcel, a.status, str(a.get("result", "")).left(60)])))
		print("  Bauvorhaben: %s" % str(projs.map(func(p): return "%s %s %s" % [p.client, p.status, str(p.get("def", ""))])))
		var ind: Dictionary = M.indicators()
		print("  Partei %s, Plaene: %s" % [M.party, str(ind.plaene.map(func(pl): return "%s %s %s offen %d" % [pl.name, pl.status, str(pl.get("zone", "")), pl.ids_zur_entwicklung.size()]))])
		print("  Vorschlaege: %s" % str(ind.entwicklungsvorschlaege.map(func(c): return "%s %d Grundst. voll %d" % [c.zone, c.grundstuecke.size(), int(c.davon_voll_erschlossen)])))
		for prj in M.projects.values():
			var e: Dictionary = s.construction.public.get(prj.id, {})
			var zones := {}
			for pid in prj.get("parcels", []):
				var pp: Dictionary = s.parcels.parcel(str(pid))
				zones[str(pp.get("zone", "?")) + "/" + s.parcels.utility_level(pp)] = int(zones.get(str(pp.get("zone", "?")) + "/" + s.parcels.utility_level(pp), 0)) + 1
			var D: CityDepot = s.towns.depot(k)
			var res: Dictionary = D.project_res.get(prj.id, {})
			if not res.is_empty() and not D.project_complete(prj.id):
				var miss := {}
				for it in res.items:
					if int(res.reserved.get(it, 0)) < int(res.items[it]):
						miss[it] = "%d/%d Lager %d" % [int(res.reserved.get(it, 0)), int(res.items[it]), D.stock_of(it)]
				print("    fehlt %s; Bestellungen: %s" % [str(miss), str(D.orders.values().filter(func(o): return miss.has(o.item) and o.status not in ["eingelagert", "bezahlt"]).map(func(o): return "%s %s %d %s seit %d %s" % [o.id, o.item, int(o.qty), o.status, int(o.day), str(o.get("supplier", ""))]))])
			print("  Projekt %s %s %s Teile %s Grundstuecke %s | Bau: start %s rest %s/%s warten '%s' Firma %s" % [prj.id, prj.kind, prj.status, str(prj.get("parts", [])), str(zones),
				str(e.get("start", "-")), str(e.get("days_left", "-")), str(e.get("days", "-")), str(e.get("waiting", "")), str(e.get("builder", "-"))])
