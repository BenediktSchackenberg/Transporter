extends SceneTree
## Auftrag 8: Standortwahl am Spielstand (Abfallhof, Polizeiwache, Wohnhaus, Laden) je Stadt.
func _init() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	var s := Simulation.from_dict(d.sim if d.has("sim") else d)
	for k in s.towns.count():
		if not s.town_plan.has(k):
			continue
		print("== %s (%s)" % [s.towns.name_of(k), s.town_plan.of(k).label])
		for req in [{"w": 4, "h": 3, "art": "laerm", "label": "Betriebshof Abfallwirtschaft"}, {"w": 3, "h": 2, "art": "oeffentlich", "label": "Polizeiwache"},
				{"w": 5, "h": 4, "art": "wohnen", "label": "Einfamilienhaus"}, {"w": 4, "h": 3, "art": "versorgung", "label": "Bäckerei"}]:
			var t0 := Time.get_ticks_usec()
			var ch: Dictionary = s.sites.choose(k, req)
			print("  %s (%d ms): %s" % [req.label, (Time.get_ticks_usec() - t0) / 1000, str(ch.get("begruendung", ch.get("msg", ""))).left(330)])
	quit()
