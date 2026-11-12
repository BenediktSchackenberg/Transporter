extends SceneTree
## Strombilanz je Stadt (Auftrag 22 Phase 3): Grundlast, Betriebe, Bezug bei der Kraftwerksgesellschaft E0, Tarife der Betriebe,
## Monatsausgleich nach festen Anteilen. Aufruf: Godot --headless --path . -s tests/probe_power.gd [-- --days=35 --cities=4]

func _init() -> void:
	var days := 35
	var cities := 4
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--days="):
			days = int(a.substr(7))
		if a.begins_with("--cities="):
			cities = int(a.substr(9))
	GameCalendar.configure(60.0)
	var s := Simulation.new()
	s.world_mode = "region"
	s.start_profile = "unternehmer"
	var pl: Array = []
	for i in cities:
		pl.append({"player_name": "Spieler%d" % i, "company_name": "Firma%d" % i, "color": Catalog.COMPANY_COLORS[i], "avatar_style": i,
			"personality": Catalog.PERSONALITIES.keys()[i]})
	s.setup(4242, pl, Catalog.MAP_SIZE, 0.5)
	var G: PowerGrid = s.grid
	var d0 := GameCalendar.day_of(s.game_min)
	var settled := 0
	while GameCalendar.day_of(s.game_min) < d0 + days:
		var day := GameCalendar.day_of(s.game_min)
		while GameCalendar.day_of(s.game_min) == day:
			s.step(0.1)
		if day % 7 == 0 or not G.last_settle.is_empty() and int(G.last_settle.get("tag", -1)) != settled:
			print("Tag %3d  Leistung %d kW  Bedarf %d kW  Kraftwerk %d kW  Notstrom %d kW  Gesellschaft E0 %s" % [day, int(G.capacity), int(G.last.bedarf),
				int(G.last.get("kraftwerk_kw", 0)), int(G.last.get("notstrom_kw", 0)), Catalog.money(float(s.economy.accounts.get("E0", 0.0)))])
			var st: Dictionary = G.last.get("staedte", {})
			for key in st:
				var a: Dictionary = G.by_town.get(key, {})
				print("         %-14s Grundlast %5.0f kW  Betriebe %5.0f/%5.0f kW  aus %d  | Bezug %10s  Tarife %10s  Ausgleich %10s" % [s.towns.name_of(int(key)),
					float(st[key].grundlast), float(st[key].versorgt), float(st[key].betriebe), int(st[key].abgeschaltet),
					Catalog.money(float(a.get("bezug", 0.0))), Catalog.money(float(a.get("tarif", 0.0))), Catalog.money(float(a.get("ausschuettung", 0.0)))])
		if not G.last_settle.is_empty() and int(G.last_settle.get("tag", -1)) != settled:
			settled = int(G.last_settle.tag)
			print("         Monatsausgleich Tag %d: Ergebnis %s  Anteile %s" % [settled, Catalog.money(float(G.last_settle.ergebnis)), str(G.last_settle.anteile)])
	var ns: Dictionary = G.net.summary()
	print("Netz: %d Trassen, %d Felder; Schaeden %d, repariert %d (%s), Ausfall %.1f Spieltage, offen %s" % [int(ns.trassen), int(ns.laenge_felder),
		int(ns.statistik.schaeden), int(ns.statistik.reparaturen), Catalog.money(float(ns.statistik.kosten)), float(ns.statistik.ausfall_min) / GameCalendar.days_to_min(1.0), str(ns.defekt)])
	var K: PowerPlant = s.plant
	print("Kraftwerk: %.0f MWh, Brennstoff %s, Personal %s, Wartung %s, Notstrom %s, Entsorgung %s; Geldfehler %.2f" % [float(K.stats.mwh),
		Catalog.money(float(K.stats.fuel_cost)), Catalog.money(float(K.stats.crew)), Catalog.money(float(K.stats.maintenance)),
		Catalog.money(float(K.stats.emergency_cost)), Catalog.money(float(K.stats.disposal)), s.economy.conservation_error()])
	quit()
