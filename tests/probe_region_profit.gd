extends SceneTree
## Messung (kein Pass/Fail): Gewinn und Kostenarten der Unternehmer in der Region (wie im Spiel: Welt "region", Profil
## "unternehmer"), Regel-KI je Firma alle 200 Schritte, Buergermeister-Regeln alle 2 Tage.
## Godot_console.exe --headless --path . -s tests/probe_region_profit.gd -- --days=60 [--seed=21]
func _initialize() -> void:
	var days := 60
	var seed_v := 21
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--days="):
			days = int(str(a).trim_prefix("--days="))
		if str(a).begins_with("--seed="):
			seed_v = int(str(a).trim_prefix("--seed="))
	var s := Simulation.new()
	s.world_mode = "region"
	s.start_profile = "unternehmer"
	var ps: Array = []
	for i in 4:
		ps.append({"player_name": "P%d" % i, "company_name": "F%d" % i, "color": Color.RED, "avatar_style": i,
			"personality": Catalog.PERSONALITIES.keys()[i]})
	s.setup(seed_v, ps, Catalog.MAP_SIZE, 0.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var step := 0
	var mayor_day := -1
	var t0 := Time.get_ticks_msec()
	var acts := {}
	var snap := {}   # Tag -> [Gewinn je Firma]
	var seen := {}   # Firma -> letzte gelesene Buchungszeit
	var by_note := {}   # "Kategorie: Text" -> Summe (alle Firmen; nur Buchungen ab 50 EUR stehen im Journal)
	while GameCalendar.day_of(s.game_min) < days:
		if step % 50 == 0:
			for c in s.companies:
				var lt := float(seen.get(c.id, -1.0))
				for e in c.ledger.entries:
					if float(e.t) > lt and str(e.cat) in ["supplies", "trade_expense", "property_costs", "penalties"]:
						var key := "%s: %s" % [e.cat, RegEx.create_from_string("[0-9#.,]+").sub(str(e.note), "#", true).left(40)]
						by_note[key] = float(by_note.get(key, 0.0)) + float(e.amount)
				if not c.ledger.entries.is_empty():
					seen[c.id] = float(c.ledger.entries[-1].t)
		if step % 200 == 0:
			for c in s.companies:
				if not c.is_active():
					continue
				var obs := ObservationBuilder.build(s, c.id, [], 0.0, 10.0)
				for a in RuleBrain.decide(obs, c.personality, rng, s.strategy.params_of(c.id)).actions:
					var res: Dictionary = s.executor.execute(c.id, a, "", "fallback")
					if str(a.action) in ["recruit_worker", "assign_staff", "hire_worker"]:
						var rk := "%s %s %s" % [a.action, str(res.get("ok", false)), str(res.get("msg", "")).left(70)]
						acts[rk] = int(acts.get(rk, 0)) + 1
		var day := GameCalendar.day_of(s.game_min)
		if day != mayor_day and day % 2 == 0:
			mayor_day = day
			for M in s.towns.mayors:
				for a in MayorBrain.decide(M.indicators()).actions:
					M.execute(a)
		if day % 15 == 0 and not snap.has(day):
			snap[day] = s.companies.map(func(c): return int(c.ledger.profit()))
		s.step(0.1)
		step += 1
	print("== Region Seed %d: %d Spieltage, %d Firmen, %.0f s Rechenzeit" % [seed_v, days, s.companies.size(), (Time.get_ticks_msec() - t0) / 1000.0])
	var cats := {}
	for c in s.companies:
		for k in c.ledger.totals:
			cats[k] = true
	var head := "%-20s" % "Kategorie"
	for c in s.companies:
		head += " %9s" % ("F%d" % c.id)
	print(head)
	var keys: Array = cats.keys()
	keys.sort()
	for k in keys:
		var row := "%-20s" % k
		for c in s.companies:
			row += " %9d" % int(c.ledger.totals.get(k, 0.0))
		print(row)
	print("%-20s" % "GEWINN" + "".join(s.companies.map(func(c): return " %9d" % int(c.ledger.profit()))))
	print("%-20s" % "Bargeld" + "".join(s.companies.map(func(c): return " %9d" % int(c.ledger.cash))))
	print("%-20s" % "Schulden" + "".join(s.companies.map(func(c): return " %9d" % int(c.ledger.debt))))
	print("Verlauf Gewinn: ", snap)
	var nk: Array = by_note.keys()
	nk.sort_custom(func(a, b): return float(by_note[a]) < float(by_note[b]))
	print("Groesste Posten (Journal, alle Firmen):")
	for k in nk.slice(0, 25):
		print("  %10d  %s" % [int(by_note[k]), k])
	for c in s.companies:
		var vs: Array = s.company_vehicles(c.id)
		var done := 0
		var failed := 0
		for k in s.contracts.values():
			if k.owner == c.id:
				if k.status == "delivered":
					done += 1
				elif k.status == "failed":
					failed += 1
		print("  F%d %-14s %-10s Status %-10s Fz %d  Personal %d  Betriebe %s  erledigt %d gescheitert %d" % [c.id, c.company_name.left(14), c.personality,
			c.status, vs.size(), s.personnel.employed(c.id).size(), str(s.biz.of(c.id).map(func(b): return "%s(%s,%d)" % [b.branch, b.status, int(b.get("result", 0))])).left(160),
			done, failed])
	print("Personalaktionen: ")
	for k in acts:
		print("  %4d  %s" % [int(acts[k]), k])
	print("Laeden/Restaurants: Personal, Theke, Gaeste")
	for b in s.biz.items.values():
		if str(b.branch) in ["restaurant", "baeckerei"]:
			print("  F%d %-10s Personal %d Theke %s Gaeste %.1f" % [int(b.owner), b.branch, s.biz.staff_of(b.id).size(), str(b.get("counter", "-")), float(b.get("guests_avg", 0.0))])
	var cands: Array = []
	for c in s.companies:
		var o := ObservationBuilder.build(s, c.id, [], 0.0, 10.0)
		cands.append(o.get("ressourcen", {}).get("arbeitskraefte", []).size())
	print("Bewerber in der Beobachtung je Firma: ", cands)
	for c in s.companies:
		var o2 := ObservationBuilder.build(s, c.id, [], 0.0, 10.0)
		var d2 := RuleBrain.decide(o2, c.personality, rng, s.strategy.params_of(c.id))
		print("  F%d Entscheidung: %s | %s | pm=%s" % [c.id, str(d2.actions.map(func(a): return a.action)), str(d2.get("summary", "")).left(300), str(o2.has("produktion_markt"))])
		for b in o2.get("betriebe", []):
			print("      %s %s personal %s soll %s min %s" % [b.id, b.branche, str(b.get("personal")), str(b.get("personal_soll", "-")), str(b.get("personal_min", "-"))])
	print("Blockaden:")
	for b in s.biz.items.values():
		if not b.get("blockers", []).is_empty():
			print("  F%d %-12s %s" % [int(b.owner), str(b.branch), str(b.blockers.map(func(x): return "%s: %s" % [x.key, str(x.text).left(90)]))])
	print("Ergebnis je Betrieb (Kostenstelle):")
	for c in s.companies:
		for cc in c.ledger.cc_totals:
			var sum := 0.0
			for k in c.ledger.cc_totals[cc]:
				sum += float(c.ledger.cc_totals[cc][k])
			var b: Dictionary = s.biz.get_b(str(cc))
			print("  F%d %-5s %-12s %9d  %s" % [c.id, str(cc), str(b.get("branch", "allgemein")), int(sum), str(c.ledger.cc_totals[cc]).left(200)])
	quit()
