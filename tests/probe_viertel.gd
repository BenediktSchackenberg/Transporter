extends SceneTree
## Auftrag 8: Viertel des Stadtplans erschliessen (am Spielstand) – Projekt, Kosten, Umwidmung.
func _init() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	var s := Simulation.from_dict(d.sim if d.has("sim") else d)
	for k in s.towns.count():
		if not s.town_plan.has(k):
			continue
		var M: Mayor = s.towns.mayor(k)
		for v in s.town_plan.of(k).viertel:
			if str(v.zone) == "gruen":
				continue
			var r: Dictionary = M.execute({"action": "viertel_erschliessen", "viertel": v.id, "reason": "Probe"})
			print("%s %s %s: %s" % [s.towns.name_of(k), v.id, v.rolle, str(r.msg).left(230)])
			pass
	quit()
