extends SceneTree
## Messung (kein Pass/Fail): Engpaesse der Regel-KI - Buchungen je Kategorie, Fahrzeugzustaende, Tempo in Fahrt,
## Gruende fuer gescheiterte Auftraege, Tankbestand.  Godot_console.exe --headless --path . -s tests/probe_bottlenecks.gd -- --days=40 [--profil=unternehmer]
func _initialize() -> void:
	var days := 40
	var profile := "spedition"
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--days="):
			days = int(str(a).trim_prefix("--days="))
		if str(a).begins_with("--profil="):
			profile = str(a).trim_prefix("--profil=")
	var s := Simulation.new()
	s.start_profile = profile
	var ps: Array = []
	for i in 4:
		ps.append({"player_name": "P%d" % i, "company_name": "F%d" % i, "color": Color.RED, "avatar_style": i,
			"personality": Catalog.PERSONALITIES.keys()[i]})
	s.setup(21, ps)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var mayor_day := -1
	var step := 0
	var busy := {}
	var samples := 0
	var reasons := {}
	var late := [0, 0]
	var states := {}
	var prog := {}      # Fahrzeug -> [Restweg, Zustand]
	var speed := [0.0, 0]   # Felder je Stichprobe (200 Schritte = 20 Sim-s) in Fahrt
	var stuck := 0
	var fail_info: Array = []
	s.logged.connect(func(e):
		var t := str(e.text)
		var i := t.find("gescheitert (")
		if i >= 0:
			var r := t.substr(i + 13, t.find(")", i) - i - 13)
			reasons[r] = int(reasons.get(r, 0)) + 1
			var m := RegEx.create_from_string("Auftrag (A[0-9]+) gescheitert").search(t)
			if m != null and s.contracts.has(m.get_string(1)) and fail_info.size() < 12:
				var k: Contract = s.contracts[m.get_string(1)]
				var fv: FleetVehicle = s.vehicles.get(k.vehicle_id)
				fail_info.append("%s: Frist %d min ab Annahme, Strecke %d, Menge %d/%d abgeholt, %d geliefert, Fz %d (%s, %s), Fremdvergabe %s, Linie %s" % [k.id,
					int(k.deadline - k.accepted_at), k.distance, k.picked, k.qty, k.delivered_qty, k.vehicle_id, fv.state if fv else "-",
					("Fahrer" if fv and s.driver_of(fv) != null else "ohne Fahrer"), str(s.operations.requests.values().any(func(h): return str(h.get("contract", "")) == k.id)), str(s.operations.jobs.has(k.id))]))
	while GameCalendar.day_of(s.game_min) < days:
		if step % 200 == 0:
			for c in s.companies:
				var obs := ObservationBuilder.build(s, c.id, [], 0.0, 10.0)
				for a in RuleBrain.decide(obs, c.personality, rng).actions:
					s.executor.execute(c.id, a, "", "fallback")
			samples += 1
			for v in s.vehicles.values():
				var k := "%d" % v.owner
				var e: Array = busy.get(k, [0, 0])
				e[0] += 1
				if v.state != "idle":
					e[1] += 1
				busy[k] = e
				var why := str(v.state)
				if v.state == "idle":
					why += "/stopps" if not v.stops.is_empty() else "/leer"
					if s.driver_of(v) == null:
						why += "/ohne_fahrer"
				states[why] = int(states.get(why, 0)) + 1
				var rest: int = v.path.size() - v.path_i
				if prog.has(v.id) and prog[v.id][1] == v.state and v.state in ["to_pickup", "to_dropoff", "returning"]:
					var d: int = int(prog[v.id][0]) - rest
					speed[0] += float(d)
					speed[1] += 1
					if d <= 0:
						stuck += 1
				prog[v.id] = [rest, v.state]
		s.step(0.1)
		step += 1
		var day: int = GameCalendar.day_of(s.game_min)
		if day != mayor_day and day % 2 == 0:
			mayor_day = day
			for a in MayorBrain.decide(s.mayor.indicators()).actions:
				s.mayor.execute(a)
	var cats := {}
	for c in s.companies:
		for k in c.ledger.totals:
			cats[k] = true
	var keys: Array = cats.keys()
	keys.sort_custom(func(a, b): return absf(_sum(s, a)) > absf(_sum(s, b)))
	print("== Profil %s: Buchungen nach %d Spieltagen (%d Spielminuten)" % [profile, days, int(s.game_min)])
	print("%-22s %10s %10s %10s %10s" % ["Kategorie", "F0", "F1", "F2", "F3"])
	for k in keys:
		var row := "%-22s" % k
		for c in s.companies:
			row += " %10d" % int(c.ledger.totals.get(k, 0.0))
		print(row)
	print("%-22s" % "GEWINN" + "".join(s.companies.map(func(c): return " %10d" % int(c.ledger.profit()))))
	print("%-22s" % "Bargeld" + "".join(s.companies.map(func(c): return " %10d" % int(c.ledger.cash))))
	for c in s.companies:
		var b: Array = busy.get("%d" % c.id, [1, 0])
		print("  %s %-16s Fz %d  Personal %d  Lohn/h %.0f  erledigt %d  gescheitert %d  Fz-Auslastung %d %%" % [c.company_name, c.personality,
			s.company_vehicles(c.id).size(), s.personnel.employed(c.id).size(), s.personnel.wages_per_hour(c.id), c.stats.completed,
			int(c.stats.get("failed", 0)), int(100.0 * float(b[1]) / maxf(1.0, float(b[0])))])
	print("Fahrzeugzustände (Stichproben): ", states)
	print("Fortschritt in Fahrt: Ø %.1f Felder je 20 Sim-s (%d Messungen, davon %d ohne Fortschritt); Nennwert Van %.1f Felder/s" % [speed[0] / maxf(1.0, float(speed[1])), speed[1], stuck, float(Catalog.VEHICLE_MODELS.van.speed)])
	print("Gründe fürs Scheitern: ", reasons)
	for f in fail_info:
		print("  ", f)
	var fv := {}
	for r in s.operations.requests.values():
		var rk: Contract = s.contracts.get(str(r.contract))
		var key := "%s/%s" % [str(r.status), rk.status if rk else "entfernt"]
		fv[key] = int(fv.get(key, 0)) + 1
	print("Fremdvergaben (Anfrage/Auftrag): ", fv)
	for k in s.contracts.values().filter(func(x): return x.owner >= 0 and x.status == "failed").slice(0, 8):
		print("  gescheitert %s: Frist %d min nach Annahme, Strecke %d, Menge %d, abgeholt %d, geliefert %d, Fz %d, Annahme Tag %d" % [k.id, int(k.deadline - k.accepted_at), k.distance, k.qty, k.picked, k.delivered_qty, k.vehicle_id, GameCalendar.day_of(k.accepted_at)])
	for v in s.vehicles.values().slice(0, 6):
		print("  Fz %d %s %s Warteschlange %s Stopps %d Auftrag %s" % [v.id, v.model, v.state, str(v.queue), v.stops.size(), v.contract_id])
	var done: Array = s.contracts.values().filter(func(k): return k.owner >= 0 and k.status in ["delivered", "failed"])
	var rew := 0.0
	var dist := 0.0
	var slack := 0.0
	for k in done:
		rew += k.reward
		dist += k.distance
		slack += (k.deadline - k.accepted_at)
	var n := maxf(1.0, float(done.size()))
	print("Aufträge abgeschlossen %d: Vergütung Ø %.0f EUR, Strecke Ø %.0f Felder, Frist ab Annahme Ø %.0f Spielminuten" % [done.size(), rew / n, dist / n, slack / n])
	print("Status aller angenommenen Aufträge: ", _count(s.contracts.values().filter(func(k): return k.owner >= 0).map(func(k): return k.status)))
	for c in s.companies:
		print("  %s Tank %d l, Ersatzteile %d" % [c.company_name, int(c.fuel), int(c.parts)])
	quit()


static func _count(a: Array) -> Dictionary:
	var d := {}
	for x in a:
		d[x] = int(d.get(x, 0)) + 1
	return d


static func _sum(s: Simulation, k: String) -> float:
	var t := 0.0
	for c in s.companies:
		t += float(c.ledger.totals.get(k, 0.0))
	return t
