extends SceneTree
## Messlauf (kein Pass/Fail): Pflichten der naechsten 30 Tage im Verhaeltnis zum Bargeld im Spielverlauf.
func _initialize() -> void:
	GameCalendar.configure(60.0)
	var spec := {"seed": 21, "map": 128, "steps": 0, "brains": ["wachstum", "kostenoptimierer"], "events": []}
	var s: Simulation = Arena._setup(spec, 0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2100
	for step in 9000:
		if step % Arena.ACT_EVERY == 0:
			for c in s.companies:
				var obs := ObservationBuilder.build(s, c.id, [], 0.0, 10.0)
				for a in RuleBrain.decide(obs, c.personality, rng).actions.slice(0, Arena.DEFAULT_ACTIONS):
					s.executor.execute(c.id, a, "", "fallback")
		if step % 1500 == 0:
			for c in s.companies:
				print("Tag %d %s: Bargeld %.0f, Pflichten30 %.0f, Lohn/h %.1f, Personal %d" % [step / 600, c.personality, c.ledger.cash, s.insolvency.obligations_30d(c), s.personnel.wages_per_hour(c.id), s.personnel.employed(c.id).size()])
		s.step(0.1)
	quit()
