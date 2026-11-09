extends SceneTree
## Sucht Ruckler: misst jeden Simulationsschritt auf der Regionskarte (4 Spieler) ueber mehrere Spieltage und listet die teuersten.
## Aufruf: --headless --path . -s tests/probe_step_spikes.gd -- --days=6


func _init() -> void:
	var days := 6
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--days="):
			days = int(a.split("=")[1])
	var ps: Array = []
	for i in 4:
		ps.append({"player_name": "S%d" % i, "company_name": "F%d" % i, "color": Catalog.COMPANY_COLORS[i], "avatar_style": i, "personality": Catalog.PERSONALITIES.keys()[i]})
	var s := Simulation.new()
	s.world_mode = "region"
	s.start_profile = "unternehmer"
	s.setup(76512, ps, Catalog.MAP_SIZE, 0.5)
	var steps := int(GameCalendar.days_to_min(days) / Catalog.GAME_MIN_PER_SIM_SEC / 0.05)
	var times: Array = []
	var total := 0.0
	for i in steps:
		var gm := s.game_min
		var t := Time.get_ticks_usec()
		s.step(0.05)
		var ms := (Time.get_ticks_usec() - t) / 1000.0
		total += ms
		times.append([ms, gm])
	times.sort_custom(func(a, b): return a[0] > b[0])
	print("%d Schritte, Mittel %.2f ms, ueber 50 ms: %d, ueber 200 ms: %d" % [steps, total / steps, times.filter(func(x): return x[0] > 50.0).size(), times.filter(func(x): return x[0] > 200.0).size()])
	for x in times.slice(0, 15):
		print("  %8.1f ms  bei Spielminute %.1f (Tag %.2f, Minute im Tag %.0f)" % [x[0], x[1], x[1] / 120.0, fmod(x[1], 120.0)])
	quit()
