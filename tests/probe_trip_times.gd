extends SceneTree
## Fahrtmessung (kein Pass/Fail): Region mit Regel-KI, danach je abgeschlossenem Auftrag geschaetzte gegen gebrauchte Zeit und
## Spielminuten je Fahrzeugzustand (Sim.trip_log). Godot_console.exe --headless --path . -s tests/probe_trip_times.gd -- --days=20 [--seed=21]
func _initialize() -> void:
	var days := 20
	var seed_v := 21
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--days="):
			days = int(str(a).trim_prefix("--days="))
		if str(a).begins_with("--seed="):
			seed_v = int(str(a).trim_prefix("--seed="))
	var s := Simulation.new()
	s.world_mode = "region"
	if OS.get_cmdline_user_args().has("--unternehmer"):
		s.start_profile = "unternehmer"
	var ps: Array = []
	for i in 4:
		ps.append({"player_name": "P%d" % i, "company_name": "F%d" % i, "color": Color.RED, "avatar_style": i,
			"personality": Catalog.PERSONALITIES.keys()[i]})
	s.setup(seed_v, ps, Catalog.MAP_SIZE, 0.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var step := 0
	var log: Array = []
	var t0 := Time.get_ticks_msec()
	while GameCalendar.day_of(s.game_min) < days:
		if step % 200 == 0:
			for c in s.companies:
				if not c.is_active():
					continue
				var obs := ObservationBuilder.build(s, c.id, [], 0.0, 10.0)
				for a in RuleBrain.decide(obs, c.personality, rng, s.strategy.params_of(c.id)).actions:
					s.executor.execute(c.id, a, "", "fallback")
		s.step(0.1)
		step += 1
		if s.trip_log.size() > 0:
			log.append_array(s.trip_log)
			s.trip_log.clear()
	print("== Fahrten Seed %d, %d Tage, %.0f s: %d abgeschlossen" % [seed_v, days, (Time.get_ticks_msec() - t0) / 1000.0, log.size()])
	var ratios: Array = []
	var states := {}
	var fails := 0
	var tempo := 0.0
	for tr in log:
		if tr.status == "failed":
			fails += 1
		if int(tr.geschaetzt) > 0:
			ratios.append(float(tr.gebraucht) / float(tr.geschaetzt))
		tempo += float(tr.tempo_mittel)
		for k in tr.zustaende:
			states[k] = float(states.get(k, 0.0)) + float(tr.zustaende[k])
	ratios.sort()
	if not ratios.is_empty():
		print("gebraucht/geschaetzt: Median %.2f, 75 %% %.2f, 90 %% %.2f; gescheitert %d; Tempo im Mittel %.2f" % [ratios[ratios.size() / 2], ratios[ratios.size() * 3 / 4], ratios[ratios.size() * 9 / 10], fails, tempo / maxf(1.0, log.size())])
	var keys := states.keys()
	keys.sort_custom(func(a, b): return states[a] > states[b])
	for k in keys:
		print("  %-14s %7.0f min  (%.0f je Auftrag)" % [k, states[k], states[k] / maxf(1.0, log.size())])
	for tr in log.slice(0, 12):
		print("  ", tr.id, " ", tr.status, " geschaetzt ", tr.geschaetzt, " gebraucht ", tr.gebraucht, " Frist ", tr.frist_ab_zuteilung, " Felder ", tr.felder_luftlinie, " Tempo ", tr.tempo_mittel, " ", tr.zustaende)
	quit()
