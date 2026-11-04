extends SceneTree
## Messung (kein Pass/Fail): Bevoelkerung ueber viele Spieltage (Auftrag 10, Etappe 2). Je 30 Tage: Einwohner, Beschaeftigung,
## Glueck, Bildung, Weiterbildung, Verhalten des letzten Monats, Wohnungslose, Stadtkasse.
##   Godot_console.exe --headless --path . -s tests/probe_residents.gd -- --days=360
func _initialize() -> void:
	var days := 360
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--days="):
			days = int(str(a).trim_prefix("--days="))
	var s := Simulation.new()
	var ps: Array = []
	for i in 4:
		ps.append({"player_name": "P%d" % i, "company_name": "F%d" % i, "color": Color.RED, "avatar_style": i,
			"personality": Catalog.PERSONALITIES.keys()[i]})
	s.setup(21, ps)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var last_day := -1
	var step := 0
	while GameCalendar.day_of(s.game_min) < days:
		if step % 200 == 0:
			for c in s.companies:
				var obs := ObservationBuilder.build(s, c.id, [], 0.0, 10.0)
				for a in RuleBrain.decide(obs, c.personality, rng).actions:
					s.executor.execute(c.id, a, "", "fallback")
		s.step(0.1)
		step += 1
		var day: int = GameCalendar.day_of(s.game_min)
		if day != last_day and day % 30 == 0:
			last_day = day
			var P: Population = s.population
			var edu := 0.0
			for p in s.citizens.people:
				edu += float(p.education)
			print("Tag %d  Einw %d  Besch %.3f  Glueck %.1f  Bildung %.2f  Kurs %d  Verhalten %s  ohneWhg %d  P0 %d  Warteliste %d" % [day, s.citizens.population(),
				s.citizens.employment_rate(), P.mean_need("glueck"), edu / maxf(1.0, s.citizens.people.size()), P.in_course_count(), str(P.behavior),
				s.housing.homeless_count(), int(s.economy.accounts.get("P0", 0.0)), int(s.mayor.waiting)])
	quit()
