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
	for k in s.towns.count():
		var growth: Dictionary = s.eko.city_growth_status(k)
		var depot: CityDepot = s.towns.depot(k)
		print("STADT %s: %s Wohnungen %d/%d, fehlend %s" % [s.towns.name_of(k), growth.stufe,
			int(growth.bewohnbar), int(growth.wohnungen), str(growth.fehlende_anschluesse)])
		print("  Stadtlager: %d Mitarbeiter, %d Einheiten am Wareneingang, %d Bestellungen" % [depot.roster().size(),
			depot.backlog_units(), depot.open_orders().size()])
		print("  Amtslage Lager: %s" % str(s.towns.mayor(k).stadtlager_indicators()).left(450))
		if args.has("--resolve") and depot.backlog_units() > 0 and depot.roster().is_empty():
			var hire: Dictionary = s.towns.mayor(k).execute({"action": "expand_depot", "kind": "staff", "reason": "Projektmaterial einlagern"})
			print("  Probelauf Personaleinstellung: %s" % str(hire))
			depot.on_day(GameCalendar.day_of(s.game_min) + 1)
			print("  Probelauf naechster Tag: Personal %d, Wareneingang %d" % [depot.roster().size(), depot.backlog_units()])
		for art in ["wasser", "abwasser"]:
			for option in s.water.main_brief(k):
				if str(option.art) == art:
					print("  %s: %s Felder %d, Ziel %s, Gebaeudepunkte %d" % [art, option.id,
						int(option.felder), str(option.get("ziel", [])), int(option.gebaeude_nahe)])
	quit()
