extends SceneTree
## Auftrag 20 Etappe 12 (Abnahme J): Langlauf der Region mit allen kommunalen Diensten im Regelbetrieb.
## Misst Zeit je Spieltag, Kosten der Dienst-Updates je Simulationsschritt und prueft am Ende die Invarianten
## (Geldkonservierung, Buergerkonten, Warenbilanz). Gibt die Kennzahlen aller Dienste aus.
## Aufruf: Godot --headless --path . -s tests/probe_services.gd -- --days=30 [--seed=4242]

func _init() -> void:
	var days := 30
	var seed_v := 4242
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--days="):
			days = int(a.substr(7))
		if a.begins_with("--seed="):
			seed_v = int(a.substr(7))
	var s := Simulation.new()
	s.world_mode = "region"
	s.start_profile = "unternehmer"
	var pl: Array = []
	for i in 4:
		pl.append({"player_name": "Spieler%d" % i, "company_name": "Firma%d" % i, "color": Catalog.COMPANY_COLORS[i],
			"avatar_style": i, "personality": Catalog.PERSONALITIES.keys()[i]})
	s.setup(seed_v, pl, Catalog.MAP_SIZE, 0.5)
	var day_ms: Array = []
	var worst := 0.0
	for d in days:
		var t0 := Time.get_ticks_usec()
		for i in 600:
			var ts := Time.get_ticks_usec()
			s.step(0.1)
			worst = maxf(worst, float(Time.get_ticks_usec() - ts) / 1000.0)
		day_ms.append(float(Time.get_ticks_usec() - t0) / 1000.0)
	var mean := 0.0
	for x in day_ms:
		mean += float(x)
	mean /= maxf(1.0, float(day_ms.size()))
	print("Laufzeit: %d Tage, Mittel %.0f ms je Spieltag (600 Schritte), langsamster Schritt %.1f ms" % [days, mean, worst])
	# Kosten der Dienst-Updates je Schritt (ohne Rest der Simulation)
	var parts := {"Feuerwehr": s.fire, "Rettung": s.rescue, "Winterdienst": s.winter, "Bus": s.transit, "Recycling": s.recycling, "Regionalrat": s.council}
	var line := []
	for name in parts:
		var t1 := Time.get_ticks_usec()
		for i in 600:
			parts[name].update(0.0)
		line.append("%s %.3f ms" % [name, float(Time.get_ticks_usec() - t1) / 1000.0 / 600.0])
	print("Dienst-Updates je Schritt: ", ", ".join(line))
	var t2 := Time.get_ticks_usec()
	for t in s.towns.list:
		s.services.needs(int(t.id))
		s.education.summary(int(t.id))
	print("Bedarfsanalyse aller Staedte: %.1f ms" % (float(Time.get_ticks_usec() - t2) / 1000.0))
	print("Einrichtungen: ", s.municipal.facilities.size(), " Fahrzeuge: ", s.municipal.vehicles.size(), " Personal: ", s.citizens.employed_count(Municipal.EMPLOYER))
	print("Feuerwehr: ", s.fire.stats)
	print("Rettung: ", s.rescue.summary())
	print("Winterdienst: ", s.winter.stats)
	print("Bus: ", s.transit.summary())
	print("Bildung: ", s.towns.list.map(func(t): return s.education.summary(int(t.id))))
	print("Recycling: ", s.recycling.summary())
	print("Rat: ", s.council.history.map(func(h): return h.antraege.map(func(a): return "%s %s" % [a.kind, a.result])))
	print("Entscheidungen: ", s.services.log.map(func(e): return "T%d %s: %s" % [int(e.day), s.towns.name_of(int(e.town)), e.text]))
	print("Kassen: ", s.towns.list.map(func(t): return "%s %.0f" % [t.name, float(s.economy.accounts[Towns.account_of(int(t.id))])]))
	print("Invarianten: Geld %.4f, Buergerkonten %.4f, Warenbilanz %d" % [s.economy.conservation_error(), s.population.account_error(), s.stock.balance_error()])
	quit()
