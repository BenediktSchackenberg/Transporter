extends SceneTree
## Messlauf (kein Pass/Fail): wie verdienen Regel-KIs, und woraus bestehen Kosten und Erloese?
##   Godot_console.exe --headless --path . -s tests/probe_profit.gd -- --seed=21 --days=20 --brains=wachstum,kostenoptimierer,...
## Gibt je Unternehmen Umsatz, Kosten und alle Buchungskategorien aus (Summe je Kategorie, negativ = Aufwand).


func _initialize() -> void:
	var seed_value := 21
	var days := 20.0
	var brains: Array = Catalog.PERSONALITIES.keys().slice(0, 4)
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("--seed="):
			seed_value = int(s.trim_prefix("--seed="))
		elif s.begins_with("--days="):
			days = float(s.trim_prefix("--days="))
		elif s.begins_with("--brains="):
			brains = s.trim_prefix("--brains=").split(",")
	GameCalendar.configure(60.0)
	var spec := {"seed": seed_value, "map": 128, "steps": int(days * 600.0), "brains": brains, "events": []}
	var s: Simulation = Arena._setup(spec, 0)
	var rngs: Array = []
	for c in s.companies:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value * 100 + c.id
		rngs.append(rng)
	var states := {}      # Fahrzeugzustand -> Stichproben
	var acts := {}        # Aktion -> [ok, fail]
	var fails := {}
	for step in int(spec.steps):
		if step % Arena.ACT_EVERY == 0:
			for c in s.companies:
				var obs := ObservationBuilder.build(s, c.id, [], 0.0, 10.0)
				for a in RuleBrain.decide(obs, c.personality, rngs[c.id]).actions.slice(0, Arena.DEFAULT_ACTIONS):
					var r: Dictionary = s.executor.execute(c.id, a, "", "fallback")
					var n := str(a.get("action", "?"))
					var e: Array = acts.get(n, [0, 0])
					e[0 if r.get("ok", false) else 1] += 1
					acts[n] = e
					if not r.get("ok", false):
						var m := n + ": " + str(r.get("msg", ""))
						fails[m.left(110)] = int(fails.get(m.left(110), 0)) + 1
		if step % 300 == 0:
			for v in s.vehicles.values():
				var k := str(FleetVehicle.STATE_TEXT.get(v.state, v.state))
				states[k] = int(states.get(k, 0)) + 1
		s.step(0.1)
	print("Fahrzeugzustaende (Stichproben): ", states)
	print("Aktionen [ok, fehlgeschlagen]: ", acts)
	var fl: Array = fails.keys()
	fl.sort_custom(func(a, b): return fails[a] > fails[b])
	for m in fl.slice(0, 8):
		print("  Fehler x%d: %s" % [fails[m], m])
	var st := {}
	for k in s.contracts.values():
		var key := "%s%s" % [k.status, "" if k.owner < 0 else "(vergeben)"]
		st[key] = int(st.get(key, 0)) + 1
	print("Auftraege gesamt %d: %s" % [s.contracts.size(), st])
	for c in s.companies:
		var l: Ledger = c.ledger
		print("== %s (%s): Umsatz %.0f, Kosten %.0f, Gewinn %.0f, Bargeld %.0f, Fahrzeuge %d, Personal %d" % [
			c.company_name, c.personality, l.revenue(), l.costs(), l.profit(), l.cash, s.company_vehicles(c.id).size(), s.personnel.workers.values().filter(func(w): return w.employer == c.id).size()])
		var parts: Array = []
		for k in l.totals:
			if absf(float(l.totals[k])) >= 1.0:
				parts.append("%s %.0f" % [k, l.totals[k]])
		print("   ", ", ".join(parts))
		var h: Array = l.history
		if h.size() > 6:
			var q := h.size() / 4
			print("   Gewinnverlauf: ", [snappedf(h[q][1], 1), snappedf(h[2 * q][1], 1), snappedf(h[3 * q][1], 1), snappedf(h[h.size() - 1][1], 1)])
	quit()
