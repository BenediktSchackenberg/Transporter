extends SceneTree
## Diagnose Auftrag 18, Etappe 1: logische Gebaeudebelegung je Seed. Prueft fuer jedes Gebaeude (Rechteck x,y,w,h):
## - Zellen des Rechtecks, die Strasse/Gehweg/Schiene/Wasser sind,
## - Zellen, die in building_at einem anderen Gebaeude gehoeren (Ueberschneidung zweier Baukoerper),
## - building_at-Zellen ausserhalb des eigenen Rechtecks,
## - Strassenzugang (road-Zelle ist Strasse und grenzt an das Rechteck).
## Godot_console.exe --headless --path . -s tests/probe_placement.gd -- [--seeds=21,4242,7] [--days=0]
func _initialize() -> void:
	var seeds := [21, 4242, 7, 99]
	var days := 0
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--seeds="):
			seeds = Array(str(a).trim_prefix("--seeds=").split(",")).map(func(x): return int(x))
		if str(a).begins_with("--days="):
			days = int(str(a).trim_prefix("--days="))
	var t = load("res://tests/run_tests.gd").new()
	for sd in seeds:
		var s := Simulation.new()
		s.world_mode = "region"
		s.start_profile = "unternehmer"
		s.setup(sd, t.players(4))
		if days > 0:
			var rng := RandomNumberGenerator.new()
			rng.seed = 1
			var step := 0
			var mday := -1
			while GameCalendar.day_of(s.game_min) < days:
				if step % 200 == 0:
					for c in s.companies:
						if c.status in ["geschlossen", "verwertung"]:
							continue
						for a in RuleBrain.decide(ObservationBuilder.build(s, c.id, [], 0.0, 10.0), c.personality, rng).actions:
							s.executor.execute(c.id, a, "", "fallback")
				s.step(0.1)
				step += 1
				var d: int = GameCalendar.day_of(s.game_min)
				if d != mday and d % 2 == 0:
					mday = d
					for M in s.towns.mayors:
						for a in MayorBrain.decide(M.indicators()).actions:
							M.execute(a)
		_check(s, sd)
	quit()


func _check(s: Simulation, sd: int) -> void:
	var C := s.city
	var bad_ground := {}   # Typ -> Anzahl Gebaeude
	var examples: Array = []
	var overlap := 0
	var stray := 0
	var no_access := 0
	var types := {}
	for b in C.buildings:
		types[str(b.type)] = int(types.get(str(b.type), 0)) + 1
		var hit := {}
		for y in range(int(b.y), int(b.y) + int(b.h)):
			for x in range(int(b.x), int(b.x) + int(b.w)):
				var c := Vector2i(x, y)
				if not C.inside(c):
					continue
				var g: int = C.g(c)
				if g in [CityData.G.ROAD, CityData.G.SIDEWALK, CityData.G.RAIL, CityData.G.WATER, CityData.G.RUNWAY]:
					hit[CityData.G.keys()[g]] = int(hit.get(CityData.G.keys()[g], 0)) + 1
				var owner: int = C.building_at[C.idx(c)]
				if owner >= 0 and owner != int(b.id):
					overlap += 1
		for k in hit:
			bad_ground[k] = int(bad_ground.get(k, 0)) + 1
		if not hit.is_empty() and examples.size() < 6:
			examples.append("#%d %s (%s) %d,%d %dx%d: %s" % [int(b.id), b.type, str(b.get("sprite", "")), int(b.x), int(b.y), int(b.w), int(b.h), str(hit)])
		var road: Vector2i = b.road
		if not C.is_road(road):
			no_access += 1
	for i in C.building_at.size():
		var id: int = C.building_at[i]
		if id < 0:
			continue
		var b: Dictionary = C.building(id)
		var c := Vector2i(i % C.size, i / C.size)
		if c.x < int(b.x) or c.y < int(b.y) or c.x >= int(b.x) + int(b.w) or c.y >= int(b.y) + int(b.h):
			stray += 1
	print("Seed %d: %d Gebaeude, Rechteck auf Verkehrs-/Wasserflaeche: %s, fremde Belegung im Rechteck: %d Zellen, Belegung ausserhalb des Rechtecks: %d Zellen, ohne Strassenzugang: %d" % [
		sd, C.buildings.size(), str(bad_ground), overlap, stray, no_access])
	for e in examples:
		print("   ", e)
	# Asset-Grundflaeche (Manifest w/h des geladenen Sprites) gegen logische Grundflaeche
	var man: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/iso/manifest.json"))
	var mism := {}
	var keys := {}
	for b in C.buildings:
		var sp := str(b.get("sprite", ""))
		var info: Dictionary = man.buildings.get(sp, {})
		keys[str(b.type)] = keys.get(str(b.type), {})
		keys[str(b.type)][sp] = true
		if info.is_empty():
			if b.type != "plot":
				mism["%s: kein Manifest-Eintrag '%s'" % [b.type, sp]] = int(mism.get("%s: kein Manifest-Eintrag '%s'" % [b.type, sp], 0)) + 1
			continue
		if int(info.w) != int(b.w) or int(info.h) != int(b.h):
			var k := "%s/%s: Bild %dx%d, logisch %dx%d" % [b.type, sp, int(info.w), int(info.h), int(b.w), int(b.h)]
			mism[k] = int(mism.get(k, 0)) + 1
	print("   Bild- vs. logische Grundflaeche abweichend: ", mism)
	print("   geladene Sprites je Typ: ", keys.keys().map(func(k): return "%s:%d" % [k, keys[k].size()]))
	print("   Typen: ", types)
