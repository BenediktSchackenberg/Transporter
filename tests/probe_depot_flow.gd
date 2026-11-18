extends SceneTree
## Messung 18.11.: wo haengen die Stadtlager-Bestellungen (Status, Auftrag, Alter)?
func _init() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	var s := Simulation.from_dict(d.sim if d.has("sim") else d)
	var today := GameCalendar.day_of(s.game_min)
	for k in s.towns.count():
		var D: CityDepot = s.towns.depot(k)
		var st := {}
		for o in D.orders.values():
			var c: Contract = s.contracts.get(str(o.get("contract", "")))
			var key := "%s/%s/reissued %d" % [o.status, c.status if c != null else "-", int(o.get("reissued", 0))]
			if str(o.status) in ["transport", "unterwegs", "bestellt", "stadt_lkw", "wartet_strasse"]:
				st[key] = int(st.get(key, 0)) + 1
		print("Stadt %d Tag %d: %s" % [k, today, st])
		var ex: Array = D.orders.values().filter(func(o): return str(o.status) in ["transport", "bestellt"])
		for o in ex.slice(0, 4):
			print("   ", o.id, " ", o.status, " ", o.item, " x", o.qty, " loc ", o.get("loc"), " bestellt Tag ", o.get("ordered"), " supplier ", o.get("supplier"), " hist ", (o.get("history", []) as Array).slice(0, 4))
	var D1: CityDepot = s.towns.depot(1)
	print("Stadt 1 Lager-Gebaeude ", D1.building, " town_ready ", s.town_ready(1), " loc64 ", s.city.building(64).get("name", "?"))
	D1.on_day(today + 1)
	var st2 := {}
	for o in D1.orders.values():
		st2[str(o.status)] = int(st2.get(str(o.status), 0)) + 1
	var locs := {}
	for o in D1.orders.values():
		if str(o.status) == "stadt_lkw":
			locs[int(o.loc)] = int(locs.get(int(o.loc), 0)) + 1
	print("Stadt-Lkw ab Gebaeude: ", locs, " Lkw: ", s.fleet.vehicles.filter(func(v): return v.kind == "stadtlkw").map(func(v): return (v.orders as Array).size()))
	print("nach Tageswechsel: ", st2, " Beispiel-Log ", (D1.orders.get("T1B17", {}).get("log", []) as Array).slice(-3))
	quit()
