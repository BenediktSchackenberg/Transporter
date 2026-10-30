extends SceneTree
## Messung (kein Pass/Fail): Stadtkasse P0 ueber 180 Spieltage. 1 Spieltag = 60 Echtzeit-s; hier Sim-Schritte 0.1 s.
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
	for step in 330000:
		if step % 200 == 0:
			for c in s.companies:
				var obs := ObservationBuilder.build(s, c.id, [], 0.0, 10.0)
				for a in RuleBrain.decide(obs, c.personality, rng).actions:
					s.executor.execute(c.id, a, "", "fallback")
		s.step(0.1)
		var day: int = GameCalendar.day_of(s.game_min)
		if day != last_day and day % 15 == 0:
			last_day = day
			if day >= 105 and day % 15 == 0:
				_dump(s)
			print("Tag %d  P0 %d  vat %d" % [day, int(s.economy.accounts.get("P0", 0.0)), int(s.public_sector.vat_total)])
	quit()


func _dump(s: Simulation) -> void:
	var rows: Array = []
	for k in s.economy.flows:
		if k.begins_with("P0>") or k.ends_with(">P0"):
			rows.append([k, s.economy.flows[k]])
	rows.sort_custom(func(a, b): return a[1] > b[1])
	print("FLOWS " + ", ".join(rows.map(func(r): return "%s %d" % [r[0], int(r[1])])))
