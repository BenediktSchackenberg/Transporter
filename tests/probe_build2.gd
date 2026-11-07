extends SceneTree
## Sonde 2 (kein Pass/Fail): Die 4 "laufenden" Stadtprojekte stecken fest. Warum?
## Protokoll: Stadtkasse/Reserven, offene Beschaffungsvorschlaege mit Kassenlage, Projektmangel, Trupps.
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
	var mayor_due := 0.0
	var last_dump := -1
	for step in 120000:   # 60 Tage
		if step % 200 == 0:
			for c in s.companies:
				var obs := ObservationBuilder.build(s, c.id, [], 0.0, 10.0)
				for a in RuleBrain.decide(obs, c.personality, rng).actions:
					s.executor.execute(c.id, a, "", "fallback")
		s.step(0.1)
		if s.game_min >= mayor_due:
			mayor_due = s.game_min + GameCalendar.days_to_min(2.0)
			var d := MayorBrain.decide(s.mayor.indicators())
			var parsed: Dictionary = AgentController.parse_response(JSON.stringify(d))
			for a in parsed.actions.slice(0, 4):
				s.mayor.execute(a)
		var day: int = GameCalendar.day_of(s.game_min)
		if day == 40 or day == 60:
			last_dump = day
			_dump(s, day)
	quit()


func _dump(s: Simulation, day: int) -> void:
	print("== Tag %d ==============" % day)
	var h: Dictionary = s.mayor.indicators().haushalt
	print("Kasse: kasse=%s reserviert=%s verfuegbar=%s" % [str(h.kasse), str(h.reserviert), str(h.verfuegbar)])
	print("--- Stadtprojekte ---")
	for pid in s.construction.public:
		var e: Dictionary = s.construction.public[pid]
		var prj: Dictionary = s.mayor.projects.get(pid, {})
		print("  %s [%s] status=%s start=Tag %s days_left=%s builder=%s waiting=%s | complete=%s" % [
			pid, str(prj.get("kind", "")), e.status, str(e.start), str(e.days_left), e.builder,
			str(e.get("waiting", "")), str(s.city_depot.project_complete(str(pid)))])
		var res: Dictionary = s.city_depot.project_res.get(pid, {})
		print("    Material: brauchen=%s reserviert=%s" % [str(res.get("items", {})), str(res.get("reserved", {}))])
	print("--- Offene Beschaffungsvorschlaege (Status vorschlag) ---")
	for o in s.city_depot.orders.values():
		if o.status == "vorschlag":
			print("    %s: %d x %s | %s | Schätzung %s | krit=%s | Tag %s" % [
				o.id, int(o.qty), o.item, str(o.reason).left(60), str(o.get("estimate", "")), str(o.crit), str(o.day)])
	print("--- Projektbestellungen (alle Status != bezahlt) ---")
	for o in s.city_depot.orders.values():
		if str(o.get("project", "")) != "" and o.status not in ["bezahlt", "abgelehnt"]:
			print("    %s: %d x %s status=%s | lief.=%s bestellt=Tag %s | an=Tag %s" % [
				o.id, int(o.qty), o.item, str(o.status), str(o.supplier), str(o.get("ordered", o.day)), str(o.get("arrived", "-"))])
	if s.harbor.enabled:
		print("    Hafen: naechstes Schiff in %s Tagen, Manifest: %s" % [str(s.harbor.state().get("naechstes_in_tagen", "-")), str(s.harbor.state().get("manifest", ""))])
	print("--- Trupps ---")
	for t in s.crews.crews.values():
		print("    %s (%s): %s job=%s" % [t.id, t.builder, t.state, str(t.job)])
