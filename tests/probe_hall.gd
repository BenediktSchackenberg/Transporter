extends SceneTree
## Messung 18.11.: findet Viktor jetzt einen Platz fuer das Buergeramt beim eigenen Betriebshof?
func _init() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	var s := Simulation.from_dict(d.sim if d.has("sim") else d)
	for c in s.companies:
		var st: Dictionary = s.settlements.get(str(c.home_town), {})
		if not st.has("center"):
			print(c.player_name, ": noch kein Betriebshof")
			continue
		for id in s.eko.homes.sites.keys().filter(func(x): return int(s.eko.homes.sites[x].cid) == c.id).slice(1):
			s.eko.homes.sites.erase(id)   # nur Probe: Baustellenlimit freimachen
		var r: Dictionary = s.eko.homes.plan(c.id, {"action": "buergeramt_bauen", "typ": "buergeramt"}) if false else s.eko.input(s.eko.firm_being(c.id), "Firma", {"aktion": {"action": "buergeramt_bauen"}})
		print(c.player_name, " Hof ", st.center, ": ", str(r.get("msg", "")).left(220))
		for sid in s.eko.homes.sites:
			var si: Dictionary = s.eko.homes.sites[sid]
			if str(si.typ) == "buergeramt":
				var p: Dictionary = s.parcels.parcel(str(si.parcel))
				print("   Bürgeramt auf ", si.parcel, " ", p.rect, " Abstand zum Hof ", absi(int(p.rect[0]) - int(st.center[0])) + absi(int(p.rect[1]) - int(st.center[1])))
	quit()
