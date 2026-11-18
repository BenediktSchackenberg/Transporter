extends SceneTree
## Messung 18.11.: Grundstuecke rund um Liorufers Kern – Eigentum, Zustand.
func _init() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	var s := Simulation.from_dict(d.sim if d.has("sim") else d)
	var kern: Array = s.town_plan.of(1).kern
	var c0 := Vector2(int(kern[0]), int(kern[1]))
	var stat := {}
	for p in s.parcels.items.values():
		var c := Vector2(int(p.rect[0]) + int(p.rect[2]) / 2.0, int(p.rect[1]) + int(p.rect[3]) / 2.0)
		if c.distance_to(c0) <= 12.0:
			var t := "%s/%s/%s/bebaubar %s" % [p.owner, p.state, p.zone, s.parcels.is_buildable(p)]
			stat[t] = int(stat.get(t, 0)) + 1
	print("um Liorufer-Kern ", kern, ": ", stat, " land-flag ", s.town_plan.of(1).get("land"), " kern0 ", s.town_plan.of(0).kern)
	quit()
