extends SceneTree
## Auftrag 8: naechster Abschnitt des Stadtplans und Entscheidung des Regel-Buergermeisters (am Spielstand).
func _init() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	var s := Simulation.from_dict(d.sim if d.has("sim") else d)
	for k in s.towns.count():
		if not s.town_plan.has(k):
			continue
		var M: Mayor = s.towns.mayor(k)
		var ind := M.indicators()
		print("%s: %s" % [s.towns.name_of(k), ind.get("stadtplan_naechster_abschnitt", {})])
		var dec: Dictionary = MayorBrain.new().decide(ind) if MayorBrain.new().has_method("decide") else {}
		print("   Regel-Bürgermeister: ", (dec.get("actions", []) as Array).map(func(a): return a.action))
	quit()
