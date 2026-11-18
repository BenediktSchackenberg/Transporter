extends SceneTree
## Messung 18.11.: Polizeiwache-Meldung und Ausbau-Meldung mit dem Spielstand der Partie.
func _init() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	var s := Simulation.from_dict(d.sim if d.has("sim") else d)
	for k in s.towns.count():
		print(s.towns.name_of(k), ": ", str(s.services.build(k, "PO-01", "Test", "probe").msg).left(260))
	print(str(s.water.mayor_expand(2, "hochbehaelter").msg))
	quit()
