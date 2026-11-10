extends SceneTree
## Analyse eines Spielstands (user://saves/quicksave.json oder --file=): Wohnungsbau und Insolvenzen.
## Aufruf: Godot --headless --path . -s tests/probe_save_analysis.gd [-- --file=user://saves/x.json]

func _init() -> void:
	var path := "user://saves/quicksave.json"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--file="):
			path = a.substr(7)
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	var s := Simulation.from_dict(d.sim)
	print("Spielzeit: %s (Tag %d)" % [Catalog.game_minutes_to_text(s.game_min), GameCalendar.day_of(s.game_min)])
	print("\n== Staedte und Wohnen")
	for t in s.towns.list:
		var k := int(t.id)
		var houses := s.city.buildings.filter(func(b): return s.towns.of_building(int(b.id)) == k and str(b.type) in ["house", "semi", "villa", "apartment", "highrise"]).size()
		var units: Array = s.housing.units.values().filter(func(u): return s.towns.of_building(int(u.building)) == k)
		var vacant := units.filter(func(u): return u.tenant == "").size()
		var M = s.towns.mayor(k)
		print("%s: %d Einwohner, %d Wohnhaeuser, %d Wohneinheiten (%d frei), Kasse %.0f, Zustimmung %s" % [t.name, s.citizens.population_of(k), houses, units.size(), vacant,
			float(s.economy.accounts[Towns.account_of(k)]), str(snappedf(float(M.approval), 0.1)) if "approval" in M else "-"])
	print("Wohnen gesamt: ", s.housing.summary())
	print("\n== Bauvorhaben (Construction.projects) nach Art und Status")
	var by := {}
	for p in s.construction.projects.values():
		var key := "%s/%s" % [str(p.get("kind", p.get("def", "?"))), str(p.get("status", "?"))]
		by[key] = int(by.get(key, 0)) + 1
	print(by)
	var stuck: Array = s.construction.projects.values().filter(func(p): return str(p.get("status", "")) not in ["fertig", "abgeschlossen", "abgebrochen", "uebergeben"])
	for p in stuck.slice(0, 15):
		print("  offen: %s %s %s seit Tag %s, Bauherr %s, Firma %s, Grund %s" % [p.get("id"), p.get("def", p.get("kind", "")), p.get("status"),
			str(p.get("day", p.get("start_day", "?"))), str(p.get("owner", p.get("payer", ""))), str(p.get("builder", "")), str(p.get("reason", p.get("note", "")))])
	print("Bauantraege: ", s.permits.summary())
	print("Bauunternehmen: ", s.construction.builders.values().map(func(b): return "%s %s Kap %s" % [b.name, b.get("status", ""), str(b.get("capacity", ""))]))
	print("\n== Unternehmen")
	for c in s.companies:
		var tot: Dictionary = c.ledger.totals
		var keys: Array = tot.keys()
		keys.sort_custom(func(a, b): return absf(float(tot[a])) > absf(float(tot[b])))
		print("%d %s (%s): Status %s seit Tag %d – %s | Bargeld %.0f, Gewinn %.0f, Schulden %.0f" % [c.id, c.company_name, c.player_name, c.status,
			GameCalendar.day_of(float(c.status_since)), str(c.status_reason).left(110), c.ledger.cash, c.ledger.profit(), c.ledger.debt])
		print("    groesste Posten: ", ", ".join(keys.slice(0, 8).map(func(k): return "%s %.0f" % [k, float(tot[k])])))
	print("\n== Geschlossene Firmen (Archiv)")
	for a in s.insolvency.archive:
		print("  ", JSON.stringify(a).left(300))
	print("\n== Bauland und Bautraeger")
	print("Bautraeger D0: Kasse %.0f, verfuegbar %.0f" % [float(s.economy.accounts["D0"]), s.construction.available_funds("D0")])
	for t in s.towns.list:
		var k := int(t.id)
		var M = s.towns.mayor(k)
		var cnt := {}
		for z in ["wohnen", "mischgebiet"]:
			for u in ["voll", "teilweise"]:
				cnt["%s/%s" % [z, u]] = s.parcels.search({"zone": z, "min_area": 12, "utilities": u, "limit": 999, "town": k}).size()
		print("%s: Wohnungssuchende %d, Leerstand %.3f, freie Grundstuecke %s, Zustimmung %s, verfuegbar %.0f" % [t.name, int(M.waiting), M.vacancy(), str(cnt),
			str(M.get("approval")) if "approval" in M else "-", M.available_budget()])
	print("\n== Warum baut der Bautraeger nicht? (erste Grundstuecke je Stadt)")
	for t in s.towns.list:
		var k := int(t.id)
		var free: Array = s.parcels.search({"zone": "wohnen", "min_area": 12, "utilities": "teilweise", "limit": 160, "town": k}) + s.parcels.search({"zone": "wohnen", "min_area": 12, "utilities": "voll", "limit": 160, "town": k})
		for p in free.slice(0, 4):
			for def_id in ["einfamilienhaus", "doppelhaus"]:
				var probe := {"def": def_id, "floors": int(Planning.DEFS[def_id].floors[0]), "parking": int(Planning.DEFS[def_id].parking), "financing": {"eigenmittel": 1.0e9}}
				var chk := Planning.assess(p, probe)
				print("  %s %s %s: ok=%s Fragen=%s Gruende=%s Kosten=%s" % [t.name, p.id, def_id, str(chk.ok), str(chk.get("questions", [])).left(160), str(chk.get("blocking", [])).left(220), str(chk.get("costs", {}).get("gesamt", "-"))])
	print("\n== Bebaubare Wohngrundstuecke je Stadt (Einfamilien-/Doppelhaus passt)")
	for t in s.towns.list:
		var k := int(t.id)
		var shapes := {}
		var good := 0
		var all := 0
		for z in ["wohnen", "mischgebiet"]:
			for u in ["voll", "teilweise", "keine"]:
				for p in s.parcels.search({"zone": z, "min_area": 1, "utilities": u, "limit": 9999, "town": k}):
					all += 1
					var sh := "%dx%d" % [int(p.rect[2]), int(p.rect[3])]
					shapes[sh] = int(shapes.get(sh, 0)) + 1
					for def_id in ["doppelhaus", "einfamilienhaus"]:
						var probe := {"def": def_id, "floors": int(Planning.DEFS[def_id].floors[0]), "parking": int(Planning.DEFS[def_id].parking), "financing": {"eigenmittel": 1.0e9}}
						if Planning.assess(p, probe).ok:
							good += 1
							shapes["bebaubar_" + u] = int(shapes.get("bebaubar_" + u, 0)) + 1
							break
		var keys := shapes.keys()
		keys.sort_custom(func(a, b): return int(shapes[a]) > int(shapes[b]))
		print("%s: %d freie Wohn-/Mischgrundstuecke, davon bebaubar %d (erschlossen voll %d, teilweise %d, unerschlossen %d); Formen %s" % [t.name, all, good,
			int(shapes.get("bebaubar_voll", 0)), int(shapes.get("bebaubar_teilweise", 0)), int(shapes.get("bebaubar_keine", 0)),
			", ".join(keys.filter(func(x): return not str(x).begins_with("bebaubar")).slice(0, 6).map(func(x): return "%s:%d" % [x, shapes[x]]))])
	var allp := {}
	for p in s.parcels.items.values():
		var key := "%s/%s" % [str(p.get("zone", "?")), str(p.get("state", "?"))]
		allp[key] = int(allp.get(key, 0)) + 1
	print("Alle Grundstuecke nach Zone/Zustand: ", allp)
	if OS.get_cmdline_user_args().has("--flows"):   # 30 Tage weiter: Geldfluesse der Stadtkassen nach Gegenkonto
		s.economy.flows.clear()
		var dep0: Dictionary = s.public_sector.departments.duplicate()
		for i in 30 * 600:
			s.step(0.1)
		print("\n== Geldfluesse der Stadtkassen in 30 Tagen (Gegenkonto: Betrag)")
		for t in s.towns.list:
			var acc := Towns.account_of(int(t.id))
			var rows: Array = []
			for fk in s.economy.flows:
				var parts: PackedStringArray = str(fk).split(">")
				if parts.size() == 2 and (parts[0] == acc or parts[1] == acc):
					rows.append([("+" if parts[1] == acc else "-") + (parts[0] if parts[1] == acc else parts[1]), float(s.economy.flows[fk])])
			rows.sort_custom(func(a, b): return float(a[1]) > float(b[1]))
			print("%s (%s): Kasse %.0f | %s" % [t.name, acc, float(s.economy.accounts[acc]), ", ".join(rows.slice(0, 14).map(func(r): return "%s %.0f" % [r[0], r[1]]))])
		var dep := {}
		for k in s.public_sector.departments:
			dep[k] = snappedf(float(s.public_sector.departments[k]) - float(dep0.get(k, 0.0)), 1.0)
		print("Ressorts (30 Tage, alle Staedte): ", dep)
		print("Kommunale Dienste: Tageskosten je Stadt ", s.towns.list.map(func(t): return "%s %.0f" % [t.name, s.municipal.daily_cost(int(t.id))]))
		print("Kommunal Beschaeftigte: %d" % s.citizens.employed_count(Municipal.EMPLOYER))
	print("\nInvarianten: Geld %.4f" % s.economy.conservation_error())
	quit()
