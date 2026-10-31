extends SceneTree
## Messung (kein Pass/Fail): Sektorkonten, Mieten, Raeumungen und Wohnungslose ueber 120 Spieltage (1 Spieltag = 60 Sim-s).
func _initialize() -> void:
	var s := Simulation.new()
	var ps: Array = []
	for i in 4:
		ps.append({"player_name": "P%d" % i, "company_name": "F%d" % i, "color": Color.RED, "avatar_style": i,
			"personality": Catalog.PERSONALITIES.keys()[i]})
	s.setup(21, ps)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var last_day := -1
	for step in 72000:
		if step % 200 == 0:
			for c in s.companies:
				var obs := ObservationBuilder.build(s, c.id, [], 0.0, 10.0)
				for a in RuleBrain.decide(obs, c.personality, rng).actions:
					s.executor.execute(c.id, a, "", "fallback")
		s.step(0.1)
		var day: int = GameCalendar.day_of(s.game_min)
		if day != last_day and day % 15 == 0:
			last_day = day
			var a: Dictionary = s.economy.accounts
			var h: Dictionary = s.housing.summary()
			print("Tag %d  H0 %d  X0 %d  S0 %d  P0 %d  V0 %d | Einheiten %d Leerstand %.1f %% Miete %d Raeumungen %d wohnungslos %d | Erhaltung %.2f" % [day,
				int(a.H0), int(a.X0), int(a.S0), int(a.P0), int(a.V0), int(h.einheiten), float(h.leerstand) * 100.0, int(h.mieteinnahmen),
				int(h.raeumungen), int(h.wohnungslos), s.economy.conservation_error()])
	quit()
