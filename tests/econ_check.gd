extends SceneTree
## Wirtschaftscheck (kein Pass/Fail): 4 Demo-Firmen ueber 3 Spieltage, Entscheidungen alle 20 Sim-Sekunden.
##   Godot_console.exe --headless --path . -s res://tests/econ_check.gd
func _initialize() -> void:
	var s := Simulation.new()
	var ps: Array = []
	for i in 4:
		ps.append({"player_name": "P%d" % i, "company_name": "F%d" % i, "color": Color.RED, "avatar_style": i,
			"personality": Catalog.PERSONALITIES.keys()[i]})
	s.setup(4711, ps)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var t0 := Time.get_ticks_msec()
	for step in 21600:
		if step % 200 == 0:
			for c in s.companies:
				var obs := ObservationBuilder.build(s, c.id, [], 0.0, 10.0)
				for a in RuleBrain.decide(obs, c.personality, rng).actions:
					s.executor.execute(c.id, a, "", "fallback")
		s.step(0.1)
	for c in s.companies:
		var top: Array = c.ledger.totals.keys()
		top.sort_custom(func(a, b): return absf(c.ledger.totals[a]) > absf(c.ledger.totals[b]))
		print("%s %-16s Gewinn %7d  geliefert %2d  Fzg %d  Personal %d  %s" % [c.company_name, c.personality, int(c.ledger.profit()),
			c.stats.completed, c.vehicle_ids.size(), s.personnel.employed(c.id).size(),
			", ".join(top.slice(0, 6).map(func(k): return "%s %d" % [k, int(c.ledger.totals[k])]))])
	for c in s.companies:
		print("  %s Hof: %s" % [c.company_name, ", ".join(s.estate.facilities.values().filter(func(f): return f.owner == c.id).map(func(f): return "%s(%s,St%d)" % [f.typ, f.status, f.level]))])
	print("Laufzeit %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit()
