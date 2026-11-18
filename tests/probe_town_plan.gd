extends SceneTree
## Auftrag 8: Stadtprofile eines Spielstands (beim Laden aus dem Bestand abgeleitet) und Bauland je Viertel.
func _init() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	var s := Simulation.from_dict(d.sim if d.has("sim") else d)
	for key in s.town_plan.towns:
		var p: Dictionary = s.town_plan.towns[key]
		print("Stadt %s: %s – %s | Kern %s, Wasser %s, Achse %s | %s" % [s.towns.name_of(int(key)), p.label, TownPlan.FORMS[p.form].text, p.kern, p.wasser_richtung, p.achse, p.landschaft])
		for v in p.viertel:
			print("   %s %s (%s) bei %s r%d, max %d Geschosse – %s" % [v.id, v.rolle, v.zone, v.mitte, int(v.radius), int(v.geschosse), v.text])
	quit()
