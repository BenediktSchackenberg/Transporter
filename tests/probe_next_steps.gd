extends SceneTree
## Messung 18.11.: welche naechsten Schritte sehen die Wesen im Spielstand?
func _init() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	var s := Simulation.from_dict(d.sim if d.has("sim") else d)
	for name in s.eko.beings:
		var B: Dictionary = s.eko.beings[name]
		print("== %s (Akku %d, baut %s, im LKW %s)" % [name, int(B.get("akku", 0)), str(B.get("baut", "-")), B.has("im_lkw")])
		for st in s.eko.next_steps(B):
			print("   - ", str(st).left(230))
	quit()
