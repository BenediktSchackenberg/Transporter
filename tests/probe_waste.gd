extends SceneTree
## Muellbilanz (Auftrag 22 Phase 1): erzeugter Abfall je Tag, Inhalt der Tonnen, gewogen an der Deponie, ueberquellende Tonnen,
## Muellwagen je Stadt. Aufruf: Godot --headless --path . -s tests/probe_waste.gd [-- --days=31 --region]

func _init() -> void:
	var days := 31
	var region := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--days="):
			days = int(a.substr(7))
		if a == "--region":
			region = true
	GameCalendar.configure(60.0)
	var s := Simulation.new()
	if region:
		s.world_mode = "region"
		s.start_profile = "unternehmer"
	var pl: Array = []
	for i in 2:
		pl.append({"player_name": "Spieler%d" % i, "company_name": "Firma%d" % i, "color": Catalog.COMPANY_COLORS[i], "avatar_style": i,
			"personality": Catalog.PERSONALITIES.keys()[i]})
	s.setup(4242, pl, Catalog.MAP_SIZE if region else 256, 0.5)
	var W: Waste = s.waste
	var made := 0.0
	var seen := {}
	var d0 := GameCalendar.day_of(s.game_min)
	while GameCalendar.day_of(s.game_min) < d0 + days:
		var day := GameCalendar.day_of(s.game_min)
		var before := _in_bins(W)
		var t0 := float(W.total.tons)
		while GameCalendar.day_of(s.game_min) == day:
			s.step(0.1)
			for v in s.fleet.vehicles:
				if v.kind == "muell":
					if not seen.has(v.id):
						seen[v.id] = {"start": s.game_min, "stops": v.stops.size(), "dist": s.city.tile_of(v.mover.pos).distance_to(Vector2(W.landfill_road)) if s.city.has_method("tile_of") else 0.0}
					seen[v.id]["end"] = s.game_min
					seen[v.id]["load"] = maxf(float(seen[v.id].get("load", 0.0)), float(v.load))
		made += _in_bins(W) - before + (float(W.total.tons) - t0) * 1000.0
		var trucks := {}
		for v in s.fleet.vehicles:
			if v.kind == "muell":
				trucks[int(v.town)] = int(trucks.get(int(v.town), 0)) + 1
		print("Tag %3d  in Tonnen %7.0f kg  gewogen %6.2f t  erzeugt %6.2f t  ueberquellend %3d/%d  Wagen %s  Deponie %.0f/%.0f t" % [day,
			_in_bins(W), float(W.total.tons), made / 1000.0, W.overflowing().size(), W.bins.size(), str(trucks), W.deposited, W.capacity])
	var durs: Array = []
	for id in seen:
		durs.append("%.2fd/%dH/%.2ft" % [(float(seen[id].end) - float(seen[id].start)) / GameCalendar.day_game_min, int(seen[id].stops), float(seen[id].load)])
	print("Touren (Dauer Tage / Halte / max. Ladung): ", ", ".join(durs.slice(0, 30)))
	quit()


func _in_bins(W: Waste) -> float:
	var kg := 0.0
	for b in W.bins:
		kg += float(W.bins[b])
	return kg
