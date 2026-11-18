extends SceneTree
## Messung 18.11.: kommt Viktors kaputter Lkw jetzt in die Werkstatt, steigt er aus?
func _init() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	var s := Simulation.from_dict(d.sim if d.has("sim") else d)
	var v: FleetVehicle = s.vehicles[2]
	var b: Dictionary = s.eko.beings.get("Viktor", {})
	print("vorher: ", v.state, " Zustand ", v.condition, " Feld ", v.tile(), " im_lkw ", b.has("im_lkw"))
	var seen := {}
	for i in 6000:
		s.step(0.1)
		seen[v.state] = true
		if v.state == "idle" and v.condition > 50.0:
			break
	print("nachher: ", v.state, " Zustand ", v.condition, " Feld ", v.tile(), " Zustände ", seen.keys(), " im_lkw ", b.has("im_lkw"), " Unfaelle ", s.collisions.stats)
	quit()
