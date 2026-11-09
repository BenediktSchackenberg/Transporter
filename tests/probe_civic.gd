extends SceneTree
## Auftrag 19 Abnahmeprobe: vier Buergermeister, Besuche im Grosslager, Projekte, Bau, Eroeffnung (Regel-Planer, ohne LLM).
## Aufruf: --headless --path . -s tests/probe_civic.gd -- --days=45 --seed=21
func _init() -> void:
	var days := 45
	var seed := 21
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
	var C: CivicWorks = s.civic
	for k in C.profiles:
		print("Stadt %d %s: %s, Vision: %s, Besuch ab Tag %d um %d Uhr" % [k, s.towns.name_of(k), C.profiles[k].persona, C.profiles[k].vision, C.profiles[k].next_visit, int(C.profiles[k].visit_hour)])
	var seen := 0
	var t0 := Time.get_ticks_msec()
	var max_tick := 0
	while s.game_min < days * 120.0:
		var t := Time.get_ticks_usec()
		s.step(0.5)
		max_tick = maxi(max_tick, Time.get_ticks_usec() - t)
		while seen < C.log.size():
			var e: Dictionary = C.log[seen]
			print("  Tag %d %s: %s" % [int(e.day), s.towns.name_of(int(e.town)), str(e.text).left(170)])
			seen += 1
	print("--- nach %d Tagen (%d ms, laengster Schritt %.0f ms)" % [days, Time.get_ticks_msec() - t0, max_tick / 1000.0])
	for a in C.anlagen.values():
		var e: Dictionary = s.construction.public.get(a.project, {})
		print("  %s %s: %s [%s] %s, Bau %s" % [a.id, s.towns.name_of(int(a.town)), a.title, a.template, a.status, ("%d/%d Tage, %s" % [int(e.days_left), int(e.days), e.get("waiting", "")]) if not e.is_empty() else "-"])
	for a in C.anlagen.values():
		var e2: Dictionary = s.construction.public.get(a.project, {})
		if not e2.is_empty() and str(e2.get("waiting", "")).contains("Material"):
			var D: CityDepot = s.towns.depot(int(a.town))
			var res: Dictionary = D.project_res.get(a.project, {})
			var miss := {}
			for it in res.get("items", {}):
				if int(res.reserved.get(it, 0)) < int(res.items[it]):
					miss[it] = "%d/%d (Lager %d)" % [int(res.reserved.get(it, 0)), int(res.items[it]), D.stock_of(it)]
			var ords: Array = D.orders.values().filter(func(o): return miss.has(o.item) and o.status not in ["bezahlt", "abgelehnt"]).map(func(o): return "%s %s %d %s %s" % [o.id, o.item, int(o.qty), o.status, o.get("decision", "")])
			print("  FEHLT %s: %s | Bestellungen: %s" % [a.title, miss, ords])
			for o in D.orders.values():
				if miss.has(o.item) and o.status not in ["bezahlt", "abgelehnt"]:
					var kk: Contract = s.contracts.get(str(o.contract))
					print("     %s Verlauf: %s | Vertrag %s %s Inhaber %s exkl %s bis %.0f jetzt %.0f" % [o.id, o.history.map(func(h): return "T%d %s" % [int(h.day), str(h.text).left(60)]), o.contract, kk.status if kk else "-", kk.owner if kk else "-", kk.exclusive_for if kk else "-", kk.offer_until if kk else 0.0, s.game_min])
	for k in C.profiles:
		var tt := Time.get_ticks_usec()
		var ana := C.analyze(k)
		var t1 := Time.get_ticks_usec()
		var ids := C.ideas(k, ana)
		var t2 := Time.get_ticks_usec()
		var v := C.validate(k, str(ids[0].template), "")
		var t3 := Time.get_ticks_usec()
		print("Zeit Stadt %d: Analyse %.1f ms, Ideen %.1f ms, Validierung %.1f ms" % [k, (t1 - tt) / 1000.0, (t2 - t1) / 1000.0, (t3 - t2) / 1000.0])
	print("Kommentare: ", C.comments.map(func(c): return c.text.left(80)))
	print("Statistik: ", C.stats, " Grosslager: ", s.hub.stats)
	quit()
