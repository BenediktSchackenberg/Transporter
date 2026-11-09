extends SceneTree
## Wie teuer wird die Disposition (Hofrunde) im Verlauf einer Partie? 4 Firmen, Regel-KI als Modell-Ersatz, Hofrunde alle 60 Spielminuten.
## Aufruf: --headless --path . -s tests/probe_dispatch_growth.gd -- --days=50
func _init() -> void:
	var days := 50
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--days="):
			days = int(a.split("=")[1])
	var ps: Array = []
	for i in 4:
		ps.append({"player_name": "S%d" % i, "company_name": "F%d" % i, "color": Catalog.COMPANY_COLORS[i], "avatar_style": i, "personality": Catalog.PERSONALITIES.keys()[i]})
	var s := Simulation.new()
	s.world_mode = "region"
	s.start_profile = "unternehmer"
	s.setup(29912, ps, Catalog.MAP_SIZE, 0.5)
	var ctls: Array = []
	for cid in 4:
		var c := AgentController.new()
		c.setup_for_test(s, cid)
		c.config["provider"] = "ollama"
		ctls.append(c)
	var acc := {"obs": 0.0, "chances": 0.0, "decide": 0.0, "help": 0.0, "n": 0, "rule": 0.0}
	for d in days:
		for h in 2:   # 2 x 60 Spielminuten je Tag
			for i in 60:
				s.step(0.5)
			for c in ctls:
				var t := Time.get_ticks_usec()
				var obs := ObservationBuilder.build(s, c.cid, [], 0.0, 10.0, "", "")
				var t1 := Time.get_ticks_usec()
				ObservationBuilder._chances(s)
				var t2 := Time.get_ticks_usec()
				RuleBrain.decide(obs, s.company(c.cid).personality, RandomNumberGenerator.new(), s.strategy.params_of(c.cid))
				var t3 := Time.get_ticks_usec()
				c._run_dispatch_help()
				var t4 := Time.get_ticks_usec()
				acc.obs += (t1 - t) / 1000.0
				acc.chances += (t2 - t1) / 1000.0
				acc.decide += (t3 - t2) / 1000.0
				acc.help += (t4 - t3) / 1000.0
				acc.n += 1
				if h == 0 and d % 2 == 0:   # Modellrunde ersetzen: volle Regel-KI alle 2 Tage
					var tr := Time.get_ticks_usec()
					c._run_fallback()
					acc.rule += (Time.get_ticks_usec() - tr) / 1000.0
		if d % 5 == 4:
			var n := float(acc.n)
			print("Tag %2d: je Hofrunde Beobachtung %.1f ms (davon _chances ~%.1f), Regel-KI %.1f ms, ganze Hofrunde %.1f ms | Fahrzeuge %d, Vertraege %d, Gebaeude %d" % [d + 1, acc.obs / n, acc.chances / n, acc.decide / n, acc.help / n, s.vehicles.size(), s.contracts.size(), s.city.buildings.size()])
			acc = {"obs": 0.0, "chances": 0.0, "decide": 0.0, "help": 0.0, "n": 0, "rule": 0.0}
	quit()
