extends SceneTree
## Eisenbahn (Auftrag 22 Phase 6): Bahnhoefe, Strecken, Bahnuebergaenge einer Region ausgeben.
## Aufruf: Godot --headless --path . -s tests/probe_rail.gd [-- --cities=4 --seed=4242 --days=1]

func _init() -> void:
	var cities := 4
	var seed_v := 4242
	var days := 1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cities="):
			cities = int(a.substr(9))
		if a.begins_with("--seed="):
			seed_v = int(a.substr(7))
		if a.begins_with("--days="):
			days = int(a.substr(7))
	GameCalendar.configure(60.0)
	var s := Simulation.new()
	s.world_mode = "region"
	s.start_profile = "unternehmer"
	var pl: Array = []
	for i in cities:
		pl.append({"player_name": "Spieler%d" % i, "company_name": "Firma%d" % i, "color": Catalog.COMPANY_COLORS[i], "avatar_style": i,
			"personality": Catalog.PERSONALITIES.keys()[i]})
	s.setup(seed_v, pl, Catalog.MAP_SIZE, 0.5)
	var t0 := Time.get_ticks_msec()
	var d0 := GameCalendar.day_of(s.game_min)
	var next_print := s.game_min
	while GameCalendar.day_of(s.game_min) < d0 + days:
		s.step(0.1)
		if s.game_min >= next_print and not s.trains.trains.is_empty():
			next_print = s.game_min + 30.0
			print("  %6.0f min  " % s.game_min, " | ".join(s.trains.trains.map(func(t): return "%s %s/%s Halt %d->%d pos %.0f fpos %.0f Versp. %.0f Fg %d %s" % [t.id, t.state, str(t.get("phase", "-")), int(t.stop), int(t.target), float(t.pos), float(t.get("fpos", -1)), float(t.delay), s.trains.passengers(t), str(t.get("grund", ""))])), "  wartend ", range(s.trains.stops.size()).map(func(i): return s.trains.waiting_at(i)))
	var R: RailNet = s.rail
	print("Karte %d Felder, Laufzeit %d ms" % [s.city.size, Time.get_ticks_msec() - t0])
	for key in R.stations:
		var st: Dictionary = R.stations[key]
		var b: Dictionary = s.city.building(int(st.building))
		var ctr: Vector2i = s.towns.get_t(int(key)).center
		print("  %-26s %s  Rechteck %s  Mitte %s  Abstand %d  Bild %s" % [st.name, st.orient, str(st.rect), str(ctr),
			absi(int(st.rect[0]) - ctr.x) + absi(int(st.rect[1]) - ctr.y), str(b.get("sprite", ""))])
	for e in R.edges:
		print("  Strecke %s: %s - %s  %d Felder, %d Bahnübergänge, %d Brückenfelder, %d Tunnelfelder" % [e.id, s.towns.name_of(int(e.a)), s.towns.name_of(int(e.b)), int(e.len),
			e.crossings.size(), int(e.get("bruecke", 0)), int(e.get("tunnel", 0))])
	var sm: Dictionary = s.trains.summary()
	print("  Güterzug: Touren %d, Einfahrten %d, Halte %d" % [int(sm.statistik.get("gueter_touren", 0)), int(sm.statistik.get("gueter_einfahrten", 0)), int(sm.statistik.get("gueter_halte", 0))])
	print("  Regionalbahn: Fahrgäste %d, Schranken %d, Störungen %d (Sperrzeit %d min), auf Straße %d, offen %s" % [int(sm.statistik.fahrgaeste), int(sm.statistik.get("schranken", 0)),
		int(sm.statistik.get("stoerungen", 0)), int(sm.statistik.get("ausfall_min", 0)), int(sm.statistik.get("strasse", 0)), str(sm.stoerungen)])
	if R.has_freight():
		var fb: Dictionary = s.city.building(int(R.freight.building))
		print("  Güterbahnhof %s %s  Anschluss %d Felder an %s, Weiche %s, Großlager-Mitte %s, Bild %s" % [R.freight.orient, str(R.freight.rect), R.freight.branch.size(),
			R.freight.edge, str(R.freight.junction), str(s.city.hub.center), str(fb.get("sprite", ""))])
	for f in R.failed:
		print("  NICHT GEBAUT: ", f)
	quit(0)
