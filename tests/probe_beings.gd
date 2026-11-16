extends SceneTree
## Zustand der freien Wesen aus einem Spielstand: Privatgeld, Firmenkasse, Ziel, Stammsitz-Bauten, letzte Ereignisse.
## Aufruf: Godot --headless --path . -s tests/probe_beings.gd [-- --file=user://saves/x.json]

func _init() -> void:
	var path := "user://saves/quicksave.json"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--file="):
			path = a.substr(7)
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	var s := Simulation.from_dict(d.sim)
	print("Spielzeit: %s" % Catalog.game_minutes_to_text(s.game_min))
	for b in s.eko.beings.values():
		var cid: int = s.eko.active_firm(b)
		var c = s.company(cid) if cid >= 0 else null
		var e: Dictionary = s.eko.estates.estates.get(b.name, {})
		print("\n== %s: privat %s, Firma %s (%s, %d Fahrzeuge), Amt %d" % [b.name, Catalog.money(float(b.get("geld", 0.0))),
			c.company_name if c else "-", Catalog.money(c.ledger.cash) if c else "-", c.vehicle_ids.size() if c else 0, int(b.get("amt", -1))])
		print("   Ziel: %s" % JSON.stringify(b.get("ziel", {})).left(200))
		print("   Stammsitz-Bauten: %s" % ", ".join((e.get("bauten", []) as Array).map(func(x): return "%s(%s)" % [x.art, x.status])))
		for ev in (b.events as Array).slice(-4):
			print("   · %s" % str(ev).left(160))
	quit()
