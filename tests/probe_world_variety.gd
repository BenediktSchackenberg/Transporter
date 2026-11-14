extends SceneTree
## Kartenvielfalt (Auftrag 23, Phase 2): erzeugt die Region (Generator 4) fuer mehrere Seeds, meldet Gueltigkeit, Versuche und
## Ortscharaktere und speichert je Seed ein Kartenbild (Strassen grau, Gebaeude dunkel, Wasser blau, Berge braun).
## Aufruf: Godot --headless --path . -s tests/probe_world_variety.gd [-- --seeds=1,2,3 --out=user://welt --version=4]

func _init() -> void:
	var seeds := [11, 4242, 97089, 123456]
	var out := "user://welt"
	var ver := 4
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seeds="):
			seeds = Array(a.substr(8).split(",")).map(func(x): return int(x))
		if a.begins_with("--out="):
			out = a.substr(6)
		if a.begins_with("--version="):
			ver = int(a.substr(10))
	for sd in seeds:
		var g := CornerRegionGenerator.new(4, ver)
		var t0 := Time.get_ticks_msec()
		var cd: CityData = g.generate(sd, Catalog.MAP_SIZE, 0.5)
		var img := Image.create(cd.size, cd.size, false, Image.FORMAT_RGB8)
		for y in cd.size:
			for x in cd.size:
				var i := cd.idx(Vector2i(x, y))
				var col := Color(0.35, 0.55, 0.3)
				if cd.ground[i] == CityData.G.WATER:
					col = Color(0.2, 0.4, 0.8)
				elif cd.height.size() > 0 and cd.height[i] > 0:
					col = Color(0.5, 0.4, 0.3)
				elif cd.building_at[i] >= 0:
					col = Color(0.12, 0.12, 0.12)
				elif cd.ground[i] == CityData.G.ROAD:
					col = Color(0.75, 0.75, 0.75)
				img.set_pixel(x, y, col)
		var path := "%s_%d.png" % [out, sd]
		img.save_png(path)
		print("Seed %d: ok=%s Versuch %s, %d ms, Orte %s, Fehler %s -> %s" % [sd, str(g.report.get("ok")), str(cd.gen_params.get("versuch")),
			Time.get_ticks_msec() - t0, str(cd.towns.map(func(t): return "%s(%s,%s)" % [t.name, t.get("charakter", "?"), t.get("ecke", "")])),
			str(g.failures.filter(func(f): return not f.is_empty())), ProjectSettings.globalize_path(path)])
	quit()
