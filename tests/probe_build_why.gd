extends SceneTree
## Warum bauen die Unternehmer nichts (Steinwerke, freies Bauen)? Region mit Regel-KI; je Entscheidung: Machbarkeit laut Beobachtung,
## Bargeld, Zahl der Aktionen, ob Bauaktionen dabei waren. Godot_console.exe --headless --path . -s tests/probe_build_why.gd -- --days=15
func _initialize() -> void:
	var days := 15
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--days="):
			days = int(str(a).trim_prefix("--days="))
	var s := Simulation.new()
	s.world_mode = "region"
	s.start_profile = "unternehmer"
	var ps: Array = []
	for i in 4:
		ps.append({"player_name": "P%d" % i, "company_name": "F%d" % i, "color": Color.RED, "avatar_style": i, "personality": Catalog.PERSONALITIES.keys()[i]})
	s.setup(21, ps, Catalog.MAP_SIZE, 0.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var step := 0
	var why := {}
	var acts := {}
	while GameCalendar.day_of(s.game_min) < days:
		if step % 200 == 0:
			for c in s.companies:
				if not c.is_active():
					continue
				var obs := ObservationBuilder.build(s, c.id, [], 0.0, 10.0)
				var sw: Dictionary = obs.get("steinbauten", {})
				var k := "%s stein=%s grund=%s cash>%dk" % [c.personality, str(sw.get("jetzt_moeglich")), str(sw.get("grund", "")), int(c.ledger.cash / 25000.0) * 25]
				why[k] = int(why.get(k, 0)) + 1
				var dec: Dictionary = RuleBrain.decide(obs, c.personality, rng, s.strategy.params_of(c.id))
				var n: int = dec.actions.size()
				acts["Aktionen=%d" % n] = int(acts.get("Aktionen=%d" % n, 0)) + 1
				for a in dec.actions:
					if str(a.action) in ["create_stone_work", "free_build", "hub_buy"]:
						var r: Dictionary = s.executor.execute(c.id, a, "", "fallback")
						var key := "%s %s %s" % [a.action, str(r.ok), str(r.msg).left(90)]
						acts[key] = int(acts.get(key, 0)) + 1
					else:
						s.executor.execute(c.id, a, "", "fallback")
		s.step(0.1)
		step += 1
	for k in why:
		print(why[k], "  ", k)
	for k in acts:
		print(acts[k], "  ", k)
	print("Steinwerke: %d, Freibauten: %d" % [s.stone.works.size(), s.freebuild.builds.size()])
	quit()
