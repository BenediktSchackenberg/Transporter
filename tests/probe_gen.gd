extends SceneTree
func _init() -> void:
	for seed in [99293, 21, 1675]:
		var g := CornerRegionGenerator.new(4)
		var t := Time.get_ticks_msec()
		var cd := g.generate(seed, Catalog.MAP_SIZE, 0.5)
		print("Seed %d: Versuch %s, %d ms, Fehler je Versuch %s" % [seed, str(cd.gen_params.get("versuch")), Time.get_ticks_msec() - t, str(g.failures)])
	quit()
