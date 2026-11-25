extends SceneTree
## Offene Eko-Baustellen je Firma aus einem Spielstand: Status, Fortschritt, was fehlt, naechster Schritt, Fahrzeuge.
##   godot --headless --path . -s tests/probe_eko_sites.gd -- <spielstand.json>
func _init() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	var s := Simulation.from_dict(d.sim if d.has("sim") else d)
	print("Spielminute %d" % int(s.game_min))
	for c in s.companies:
		print("== %s (cid %d)" % [c.company_name, c.id])
		var homes = s.eko.homes if s.eko != null and "homes" in s.eko else null
		if homes != null:
			for st in homes.open_sites(c.id):
				print("  Baustelle %s: %s" % [st.get("id", "?"), JSON.stringify(st).left(700)])
			print("  naechster Schritt: %s" % homes.next_step(c.id))
		for v in s.vehicles.values():
			if v.owner == c.id:
				print("  Fahrzeug #%d %s state=%s no_fuel=%s cond=%d stops=%d contract=%s" % [v.id, v.model, v.state, v.no_fuel, int(v.condition), v.stops.size(), v.contract_id])
	quit()
