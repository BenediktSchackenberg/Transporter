extends SceneTree
## Sonde (kein Pass/Fail): Wo bricht die Kette "KI -> Antrag/Beschluss -> Projekt -> Bau" im Kuestenort ab?
## 90 Tage, alle Entscheidungen der Regel-KI und des Buergermeisters samt Ergebnis, plus Pläne/Anträge/Zähler.
func _initialize() -> void:
	var ps: Array = []
	for i in 4:
		ps.append({"player_name": "P%d" % i, "company_name": "F%d" % i, "color": Color.RED, "avatar_style": i,
			"personality": Catalog.PERSONALITIES.keys()[i]})
	var s := Simulation.new()
	s.world_mode = "kueste"
	s.start_profile = "unternehmer"
	s.setup(4242, ps, Catalog.MAP_SIZE, 0.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var last_day := -1
	var mayor_due := 0.0
	for step in 216000:
		if step % 200 == 0:
			for c in s.companies:
				var obs := ObservationBuilder.build(s, c.id, [], 0.0, 10.0)
				for a in RuleBrain.decide(obs, c.personality, rng).actions:
					var r: Dictionary = s.executor.execute(c.id, a, "", "fallback")
					print("  [KI %s] %s -> %s : %s" % [c.company_name, str(a.get("action", a)), str(r.get("ok", r)), str(r.get("msg", "")).left(110)])
		s.step(0.1)
		# Buergermeister (Regelbasiert wie MayorAgent bei provider "demo"): alle ~2 Tage eine Entscheidungsrunde
		if s.game_min >= mayor_due:
			mayor_due = s.game_min + GameCalendar.days_to_min(2.0)
			var d := MayorBrain.decide(s.mayor.indicators())
			var parsed: Dictionary = AgentController.parse_response(JSON.stringify(d))
			print("  [BM %s]" % str(parsed.get("summary", "")).left(140))
			for a in parsed.actions.slice(0, 4):
				var res: Dictionary = s.mayor.execute(a)
				print("    BM %s -> %s : %s" % [str(a.get("action", a)), str(res.get("ok", res)), str(res.get("msg", "")).left(110)])
		var day: int = GameCalendar.day_of(s.game_min)
		if day != last_day and (day % 30 == 0 or day <= 2):
			last_day = day
			_dump(s, day)
	quit()


func _dump(s: Simulation, day: int) -> void:
	var prj_states := {}
	for pr in s.construction.projects.values():
		prj_states[pr.status] = int(prj_states.get(pr.status, 0)) + 1
	var pub_states := {}
	for pid in s.construction.public:
		pub_states[s.construction.public[pid].status] = int(pub_states.get(s.construction.public[pid].status, 0)) + 1
	var plan_states := {}
	for pl in s.mayor.plans.values():
		plan_states[pl.status] = int(plan_states.get(pl.status, 0)) + 1
	var app_states := {}
	for ap in s.permits.apps.values():
		app_states[ap.status] = int(app_states.get(ap.status, 0)) + 1
	print("== Tag %d | Projekte %s | Stadtprojekte %s | Pläne %s | Bauanträge %s | Gebäude %d | P0 %d" % [
		day, str(prj_states) if not prj_states.is_empty() else "leer", str(pub_states) if not pub_states.is_empty() else "leer",
		str(plan_states) if not plan_states.is_empty() else "leer", str(app_states) if not app_states.is_empty() else "leer",
		s.city.buildings.size(), int(s.economy.accounts.get("P0", 0.0))])
	var shown := 0
	for e in s.log_entries:
		if shown >= 6:
			break
		if int(e.get("day", 0)) >= day - 5:
			print("   LOG Tag %d: %s" % [int(e.day), str(e.text).left(110)])
			shown += 1
