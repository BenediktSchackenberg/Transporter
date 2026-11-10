extends SceneTree
## Strassenbau in einem Spielstand: Projekte der Buergermeister nach Art und Status, Regionalprojekte, Strassenfelder, abgelehnte
## Erschliessungen (Protokoll). Aufruf: Godot --headless --path . -s tests/probe_roads.gd [-- --file=user://saves/quicksave.json]

func _init() -> void:
	var path := "user://saves/quicksave.json"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--file="):
			path = a.substr(7)
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	var s := Simulation.from_dict(d.sim)
	print("Spielzeit Tag %d" % GameCalendar.day_of(s.game_min))
	var roads := 0
	for y in s.city.size:
		for x in s.city.size:
			if s.city.is_road(Vector2i(x, y)):
				roads += 1
	print("Strassenfelder gesamt: %d" % roads)
	for t in s.towns.list:
		var M: Mayor = s.towns.mayor(int(t.id))
		var by := {}
		var spent := {}
		for p in M.projects.values() if M.projects is Dictionary else M.projects:
			var key := "%s/%s" % [str(p.get("kind", "?")), str(p.get("status", "?"))]
			by[key] = int(by.get(key, 0)) + 1
			spent[str(p.get("kind", "?"))] = float(spent.get(str(p.get("kind", "?")), 0.0)) + float(p.get("cost", 0.0))
		print("%s: Projekte %s" % [t.name, str(by)])
		print("    Ausgaben je Art: %s" % str(spent))
	print("Regionalprojekte: ", s.regional.projects.values().map(func(p): return "%s %s %s" % [p.get("kind", ""), p.get("status", ""), str(p.get("towns", p.get("shares", "")))]) if "projects" in s.regional else "-")
	var refused := {}
	for e in s.log_entries:
		var tx := str(e.get("text", e.get("msg", "")))
		if tx.contains("Erschließung") or tx.contains("plan_infrastructure") or tx.contains("Straße"):
			var key := tx.left(70)
			refused[key] = int(refused.get(key, 0)) + 1
	print("Protokoll (letzte Eintraege zu Strassen/Erschliessung): ", refused)
	quit()
