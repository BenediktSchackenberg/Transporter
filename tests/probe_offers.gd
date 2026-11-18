extends SceneTree
## Auftrag 8: Standortangebote fuer die Unternehmer (am Spielstand).
func _init() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	var s := Simulation.from_dict(d.sim if d.has("sim") else d)
	for c in s.companies:
		var t0 := Time.get_ticks_usec()
		var o: Array = s.sites.offers(c.home_town, "einfamilienhaus")
		print("%s (Stadt %d, %d ms): %s" % [c.company_name, c.home_town, (Time.get_ticks_usec() - t0) / 1000, JSON.stringify(o).left(600)])
	quit()
