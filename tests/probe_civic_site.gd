extends SceneTree
## Messung 18.11.: warum findet kommunal_bauen in den Wildnis-Staedten kein Grundstueck (Polizeiwache 3x2)?
func _init() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	var s := Simulation.from_dict(d.sim if d.has("sim") else d)
	for k in s.towns.count():
		var th: Dictionary = s.city.building(int(s.towns.get_t(k).get("town_hall", -1)))
		var n := {"alle": 0, "frei": 0, "oeffentlich": 0, "eigene_stadt": 0, "bebaubar": 0, "zone_ok": 0, "nah": 0, "passt": 0}
		var states := {}
		for p in s.parcels.items.values():
			n.alle += 1
			states[str(p.state)] = int(states.get(str(p.state), 0)) + 1
			if p.state != "frei": continue
			n.frei += 1
			if not Towns.is_public(str(p.owner)): continue
			n.oeffentlich += 1
			if Towns.town_of_owner(str(p.owner)) != k: continue
			n.eigene_stadt += 1
			if not s.parcels.is_buildable(p): continue
			n.bebaubar += 1
			if str(p.zone) in ["korridor", "industrie"]: continue
			n.zone_ok += 1
			var pr := Rect2i(int(p.rect[0]), int(p.rect[1]), int(p.rect[2]), int(p.rect[3]))
			if th.is_empty() or absi(pr.position.x - int(th.x)) + absi(pr.position.y - int(th.y)) > 70: continue
			n.nah += 1
			if s.civic._fit(pr, 3, 2).size.x > 0:
				n.passt += 1
		print("%s: %s  Rathaus %s" % [s.towns.name_of(k), str(n), str([th.get("x"), th.get("y")]) if not th.is_empty() else "-"])
	quit()
