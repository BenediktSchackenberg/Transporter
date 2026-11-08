extends SceneTree
## Diagnose (kein Pass/Fail): warum schliessen Firmen in der Region? Regel-KI wie probe_region. Protokolliert Statuswechsel je Firma
## und zeigt am Ende Kasse, Schulden, Betriebe und die groessten Erfolgsposten; dazu Stadtkassen-Verlauf mit Einnahmen/Ausgaben.
## Godot_console.exe --headless --path . -s tests/probe_closures.gd -- --days=120 [--seed=21]
func _initialize() -> void:
	var days := 120
	var seed_v := 21
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--days="):
			days = int(str(a).trim_prefix("--days="))
		if str(a).begins_with("--seed="):
			seed_v = int(str(a).trim_prefix("--seed="))
	var t = load("res://tests/run_tests.gd").new()
	var s := Simulation.new()
	s.world_mode = "region"
	s.start_profile = "unternehmer"
	s.setup(seed_v, t.players(4))
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var mayor_day := -1
	var check_day := -1
	var step := 0
	var last_status := {}
	var town_cash := {}
	while GameCalendar.day_of(s.game_min) < days:
		if step % 200 == 0:
			for c in s.companies:
				if c.status in ["geschlossen", "verwertung"]:
					continue
				var obs := ObservationBuilder.build(s, c.id, [], 0.0, 10.0)
				for a in RuleBrain.decide(obs, c.personality, rng).actions:
					s.executor.execute(c.id, a, "", "fallback")
		s.step(0.1)
		step += 1
		var day: int = GameCalendar.day_of(s.game_min)
		if day != mayor_day and day % 2 == 0:
			mayor_day = day
			for M in s.towns.mayors:
				for a in MayorBrain.decide(M.indicators()).actions:
					M.execute(a)
		if day != check_day:
			check_day = day
			for c in s.companies:
				if str(last_status.get(c.id, "")) != c.status:
					print("Tag %3d Firma %d (%s, %s, Heimat %s): %s -> %s | %s | Kasse %d Schulden %d" % [day, c.id, c.company_name, c.personality,
						s.towns.name_of(int(c.home_town)), str(last_status.get(c.id, "-")), c.status, str(c.status_reason).left(110), int(c.ledger.cash), int(c.ledger.debt)])
					last_status[c.id] = c.status
			if day % 20 == 0:
				var row := []
				for k in s.towns.count():
					row.append("%s %d" % [s.towns.name_of(k), int(s.towns.mayor(k).cash())])
				town_cash[day] = row
	print("\n--- Firmen am Ende ---")
	for c in s.companies:
		var tot: Array = c.ledger.totals.keys().map(func(k): return [k, float(c.ledger.totals[k])])
		tot.sort_custom(func(a, b): return absf(a[1]) > absf(b[1]))
		var biz: Array = s.biz.items.values().filter(func(b): return int(b.owner) == c.id).map(func(b): return "%s/%s" % [b.branch, b.status])
		print("Firma %d %s [%s] Kasse %d Schulden %d Betriebe %s" % [c.id, c.company_name, c.status, int(c.ledger.cash), int(c.ledger.debt), str(biz)])
		print("   Posten: %s" % str(tot.slice(0, 9).map(func(x): return "%s %d" % [x[0], int(x[1])])))
		var rep: Array = c.ledger.entries.filter(func(e): return e.cat == "repairs")
		if not rep.is_empty():
			print("   Reparaturen (letzte %d): %s" % [rep.size(), str(rep.slice(-8).map(func(e): return "T%d %s %d" % [GameCalendar.day_of(float(e.t)), str(e.note).left(40), int(e.amount)]))])
		var vs: Array = s.vehicles.values().filter(func(v): return v.owner == c.id)
		print("   Fahrzeuge: %s" % str(vs.map(func(v): return "#%d %s Preis %d Zustand %d km %d %s" % [v.id, v.model, int(v.purchase_price), int(v.condition), int(v.odometer), v.state])))
	for c in s.companies.filter(func(c): return c.focus != ""):
		print("Fokus %s Firma %d: Schritte %s" % [c.focus, c.id, str(["eisenerz", "kohle", "kalkstein", "rohmaterial"].map(func(art): return "%s=%s" % [art, str(s.mining.next_step(c.id, art).get("schritt", "-"))]))])
		print("   letzte Ergebnisse: %s" % str(s.action_results.get(c.id, []).slice(-10).map(func(r): return str(r.text).left(140))))
		var obs := ObservationBuilder.build(s, c.id, [], 0.0, 10.0)
		print("   Regel-KI jetzt: %s" % str(RuleBrain.decide(obs, c.personality, rng).actions.map(func(x): return str(x).left(120))))
	print("\n--- Geldfluesse der Stadtkassen (seit Beginn) ---")
	for k in s.towns.count():
		var acct: String = s.towns.mayor(k).acct()
		var ins: Array = []
		var outs: Array = []
		for fk in s.economy.flows:
			var parts: PackedStringArray = str(fk).split(">")
			var amt := float(s.economy.flows[fk])
			if parts.size() == 2 and parts[1] == acct:
				ins.append([parts[0], amt])
			elif parts.size() == 2 and parts[0] == acct:
				outs.append([parts[1], amt])
		ins.sort_custom(func(a, b): return a[1] > b[1])
		outs.sort_custom(func(a, b): return a[1] > b[1])
		print("%s (%s): ein %d %s" % [s.towns.name_of(k), acct, int(ins.reduce(func(t, x): return t + x[1], 0.0)), str(ins.slice(0, 7).map(func(x): return "%s %d" % [x[0], int(x[1])]))])
		print("   aus %d %s" % [int(outs.reduce(func(t, x): return t + x[1], 0.0)), str(outs.slice(0, 8).map(func(x): return "%s %d" % [x[0], int(x[1])]))])
		var M: Mayor = s.towns.mayor(k)
		print("   Projekte: %s" % str(M.projects.values().map(func(p): return "%s %s %d" % [p.kind, p.status, int(p.cost)])))
	print("\n--- Stadtkassen ---")
	for d in town_cash:
		print("Tag %d: %s" % [d, ", ".join(town_cash[d])])
	quit()
