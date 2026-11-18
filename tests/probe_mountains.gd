extends SceneTree
## Messung 18.11.: Groesse der Berggebiete und aktive Bergwerke.
func _init() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	var s := Simulation.from_dict(d.sim if d.has("sim") else d)
	var sizes: Array = []
	for pid in s.prod.terrain:
		var n: int = (s.prod.terrain[pid].cells as Dictionary).size()
		sizes.append([n, pid, not s.prod.mine_on(pid).is_empty()])
	sizes.sort_custom(func(a, b): return a[0] > b[0])
	print("Berg-Parzellen: ", sizes.size(), " groesste: ", sizes.slice(0, 6), " aktive: ", sizes.filter(func(x): return x[2]))
	quit()
