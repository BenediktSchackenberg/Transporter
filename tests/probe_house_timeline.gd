extends SceneTree
## Diagnose: Verlauf der ersten fertigen Bautraeger-Haeuser (Region, Regel-KI) - wo gehen die Tage hin?
## Godot_console.exe --headless --path . -s tests/probe_house_timeline.gd -- --days=30
func _initialize() -> void:
	var days := 30
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--days="):
			days = int(str(a).trim_prefix("--days="))
	var t = load("res://tests/run_tests.gd").new()
	var s := Simulation.new()
	s.world_mode = "region"
	s.start_profile = "unternehmer"
	s.setup(21, t.players(4))
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var step := 0
	var mayor_day := -1
	while GameCalendar.day_of(s.game_min) < days:
		if step % 200 == 0:
			for c in s.companies:
				if c.status in ["geschlossen", "verwertung"]:
					continue
				var obs := ObservationBuilder.build(s, c.id, [], 0.0, 10.0)
				for a in RuleBrain.decide(obs, c.personality, rng).actions:
					s.executor.execute(c.id, a, "", "fallback")
		var day := GameCalendar.day_of(s.game_min)
		if day != mayor_day and day % 2 == 0:
			mayor_day = day
			for M in s.towns.mayors:
				for a in MayorBrain.decide(M.indicators()).actions:
					M.execute(a)
		s.step(0.1)
		step += 1
	var shown := 0
	for p in s.construction.projects.values():
		if p.client != Construction.DEVELOPER or shown >= 3:
			continue
		if p.status not in ["uebergeben", "pruefung"]:
			continue
		shown += 1
		print("== %s %s Status %s plan %s lost %s" % [p.id, p.def, p.status, str(p.get("plan_days")), str(p.lost_days)])
		for h in p.history:
			print("   Tag %d: %s" % [int(h.day), str(h.text).left(140)])
	quit()
