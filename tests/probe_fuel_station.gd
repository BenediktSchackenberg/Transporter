extends SceneTree
## Tankstellenbestand ueber einige Spieltage aus einem Spielstand (Haushaltsabsatz vs. Tankwagen).
##   godot --headless --path . -s tests/probe_fuel_station.gd -- <spielstand.json> [tage]
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var d = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var s := Simulation.from_dict(d.sim if d.has("sim") else d)
	var days := int(args[1]) if args.size() > 1 else 3
	print("Einwohner %d, Tag = %d Spielmin" % [s.citizens.population(), int(GameCalendar.day_game_min)])
	for day in days + 1:
		var line := "Tag +%d:" % day
		for st in s.resources.supplies.values():
			if st.kind == "fuel":
				line += " %s Bestand %d l, Lieferungen %d, trocken %d Tage;" % [st.id, int(st.stock), int(st.deliveries), int(st.dry_days)]
		print(line)
		if day < days:
			var end := s.game_min + GameCalendar.day_game_min
			while s.game_min < end:
				s.step(1.0)
	quit()
