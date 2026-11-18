extends SceneTree
## Messung 18.11.: bewegen sich die Lkw? Wartezeit, Blockade, Weg.
func _init() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	var s := Simulation.from_dict(d.sim if d.has("sim") else d)
	var p0 := {}
	for v in s.vehicles.values():
		p0[v.id] = v.pos
		print("Lkw %d: %s Feld %s Ziel %s Weg %d/%d wait %.1f wreck %.0f pass %.0f" % [v.id, v.state, v.tile(), v.goal, v.path_i, v.path.size(), v.wait_time, v.wreck_until - s.sim_time, v.pass_until - s.sim_time])
	for i in 300:
		s.step(0.1)
	for v in s.vehicles.values():
		var blk: Variant = s._is_blocked(v)
		print("nach 30 s Lkw %d: %s Feld %s bewegt %.0f px, wait %.1f, blockiert %s" % [v.id, v.state, v.tile(), v.pos.distance_to(p0[v.id]), v.wait_time, str(blk)])
	quit()
