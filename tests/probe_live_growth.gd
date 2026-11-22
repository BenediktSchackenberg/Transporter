extends SceneTree
## Diagnose eines bestehenden Spielstands ohne ihn zu verändern.
## Godot --headless --path . -s res://tests/probe_live_growth.gd -- <quicksave.json>

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("Spielstandpfad fehlt")
		quit(1)
		return
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var s := Simulation.from_dict(data.sim if data.has("sim") else data)
	var days := 0
	for arg in args:
		if str(arg).begins_with("--days="):
			days = int(str(arg).trim_prefix("--days="))
	var target_day := GameCalendar.day_of(s.game_min) + days
	while GameCalendar.day_of(s.game_min) < target_day:
		s.step(0.5)
	if days > 0:
		print("PROBELAUF: %d Spieltage vorwaerts, Spielstand nicht geschrieben" % days)
	for k in s.towns.count():
		var growth: Dictionary = s.eko.city_growth_status(k)
		var depot: CityDepot = s.towns.depot(k)
		print("STADT %s: %s Wohnungen %d/%d, fehlend %s" % [s.towns.name_of(k), growth.stufe,
			int(growth.bewohnbar), int(growth.wohnungen), str(growth.fehlende_anschluesse)])
		if args.has("--details"):
			print("  Haeuser ohne Anschluss: %s" % str(growth.get("betroffene_haeuser", [])))
			print("  Wasserquellen: %s; Wasserstandorte: %s" % [str(s.water.sources_of(k)), str(s.towns.mayor(k).indicators().get("versorgungsanlagen_standorte", [])).left(900)])
			print("  Ausbaupruefung: %s" % str([s.water.expansion_need(k, "wasserwerk"), s.water.expansion_need(k, "hochbehaelter"), s.water.expansion_need(k, "klaeranlage")]).left(650))
			print("  Verkehrsstandorte: %s" % str(s.towns.mayor(k).transport_indicators()).left(850))
		print("  Stadtlager: %d Mitarbeiter, %d Einheiten am Wareneingang, %d Bestellungen" % [depot.roster().size(),
			depot.backlog_units(), depot.open_orders().size()])
		print("  Stahl: Bestand %d, Projektreserven %s" % [depot.stock_of("stahl"), str(depot.project_res.keys().slice(-4))])
		var connector_status: Array = []
		for project_id in (["P9", "P12"] if k == 0 else ["T1P7", "T1P11"]):
			var work: Dictionary = s.construction.public.get(project_id, {})
			connector_status.append([project_id, work.get("status", ""), work.get("waiting", ""), work.get("days_left", 0)])
		print("  Anschluesse: %s" % str(connector_status))
		print("  Amtslage Lager: %s" % str(s.towns.mayor(k).stadtlager_indicators()).left(450))
		if args.has("--resolve") and depot.backlog_units() > 0 and depot.roster().is_empty():
			var hire: Dictionary = s.towns.mayor(k).execute({"action": "expand_depot", "kind": "staff", "reason": "Projektmaterial einlagern"})
			print("  Probelauf Personaleinstellung: %s" % str(hire))
			depot.on_day(GameCalendar.day_of(s.game_min) + 1)
			print("  Probelauf naechster Tag: Personal %d, Wareneingang %d" % [depot.roster().size(), depot.backlog_units()])
		for art in ["wasser", "abwasser"]:
			for option in s.water.main_options(k, art):
				if str(option.art) == art:
					print("  %s: %s Felder %d, Ziel %s, Gebaeudepunkte %d, Wohnungen +%d, Betriebe +%d" % [art, option.id,
						int(option.felder), str(option.get("ziel", [])), int(option.gebaeude_nahe),
						int(option.get("wohnungen_neu_am_netz", 0)), int(option.get("betriebe_neu_am_netz", 0))])
					if args.has("--details") and art == "wasser":
						var before: Dictionary = s.water.compute_net(k)
						var built: Dictionary = s.water.main_cells(k, art)
						for xy in option.cells:
							built["%d:%d" % [int(xy[0]), int(xy[1])]] = true
						var after: Dictionary = s.water.compute_net(k)
						for xy in option.cells:
							built.erase("%d:%d" % [int(xy[0]), int(xy[1])])
						var newly_connected := 0
						for unit in s.housing.units.values():
							if s.towns.of_building(int(unit.building)) == k:
								var road: Vector2i = s.city.building(int(unit.building)).road
								if after.has(road) and not before.has(road):
									newly_connected += 1
						print("    Vorschau: Drucknetz +%d Felder, %d Wohneinheiten neu angeschlossen" % [after.size() - before.size(), newly_connected])
	if args.has("--details"):
		for name in s.eko.beings:
			var being: Dictionary = s.eko.beings[name]
			if int(being.get("firma", -1)) >= 0:
				var firm: Dictionary = s.eko.firm_obs(being)
				print("FIRMA %s: %d EUR, %d Lieferungen, %d LKW; Wirtschaftsoptionen %s; Fahrzeuge %s" % [
					name, int(firm.get("bargeld", 0)), int(firm.get("lieferungen", 0)), (firm.get("fahrzeuge", []) as Array).size(),
					str(firm.get("wirtschaftsoptionen", [])).left(500), str(firm.get("fahrzeugangebote", [])).left(850)])
	quit()
