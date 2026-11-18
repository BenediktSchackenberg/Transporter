extends SceneTree
## Messung 18.11.: warum kommen die Buergermeister-Projekte nicht voran (Material, Bautrupp)?
func _init() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	var s := Simulation.from_dict(d.sim if d.has("sim") else d)
	for e in s.construction.public.values():
		var town := Towns.town_of_id(str(e.project))
		var D: CityDepot = s.towns.depot(town)
		var missing := {}
		var res: Dictionary = D.project_reserved(str(e.project)) if D.has_method("project_reserved") else {}
		print("%s Stadt %d Baufirma %s Status %s Rest %d Tage, wartet: %s | Material vollst. %s" % [e.project, town, e.builder, e.status, int(e.days_left), str(e.get("waiting", "")), D.project_complete(str(e.project))])
	print("Stadtlager-Bestellungen Ort 0: ", s.towns.depot(0).orders.values().map(func(o): return "%s %s %s" % [o.item, o.qty, o.status + " | " + str(o.get("decision", "")).left(60) + " | " + str(o.get("supplier", "")) + " loc " + str(o.get("loc", ""))]).slice(0, 40))
	print("Bautrupps: ", s.crews.crews.values().map(func(c): return "%s %s" % [c.get("id", ""), c.get("state", "")]) if "crews" in s.crews else "?")
	quit()
