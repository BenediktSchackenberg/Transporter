extends SceneTree
## Messung 18.11.: warum findet der Buergermeister nach der Erschliessung kein Grundstueck fuer den Abfallhof (4x?)?
func _init() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	var s := Simulation.from_dict(d.sim if d.has("sim") else d)
	var k := 0
	var info: Array = CityGenerator.TYPES[Municipal.TYPES["AW-01"].building]
	print("AW-01 braucht ", info[1], "x", info[2])
	var th: Dictionary = s.city.building(int(s.towns.get_t(k).get("town_hall", -1)))
	var M: Mayor = s.towns.mayor(k)
	for pid in ["G1968", "G1600", "G1601", "G2160"]:
		var p: Dictionary = s.parcels.parcel(pid)
		var pr := Rect2i(int(p.rect[0]), int(p.rect[1]), int(p.rect[2]), int(p.rect[3]))
		var free_any := false
		var road_any := false
		for y in range(pr.position.y, pr.end.y - int(info[2]) + 1):
			for x in range(pr.position.x, pr.end.x - int(info[1]) + 1):
				var r := Rect2i(x, y, int(info[1]), int(info[2]))
				if s.civic._cells_free(r):
					free_any = true
					if s.civic._touches_road(r):
						road_any = true
		var roads := 0
		for y in range(pr.position.y - 1, pr.end.y + 1):
			for x in range(pr.position.x - 1, pr.end.x + 1):
				if s.city.is_road(Vector2i(x, y)): roads += 1
		print(pid, " ", p.state, " Groesse ", pr.size, " Erschl ", p.get("erschliessung", {}), " frei-Platz ", free_any, " mit Strasse ", road_any, " Strassenfelder am/im Grundstueck ", roads)
	if true:
		quit()
		return
	for prj in M.projects.values():
		print("Projekt ", prj.id, " ", prj.kind, " ", prj.status, " Grundstuecke ", prj.parcels)
		for pid in prj.parcels:
			var p: Dictionary = s.parcels.parcel(str(pid))
			if p.is_empty(): continue
			var pr := Rect2i(int(p.rect[0]), int(p.rect[1]), int(p.rect[2]), int(p.rect[3]))
			print("   ", pid, " Zustand ", p.state, " Zone ", p.zone, " Groesse ", pr.size, " Eigner ", p.owner, " Erschl ", p.get("erschliessung", {}), " Abstand ", absi(pr.position.x - int(th.x)) + absi(pr.position.y - int(th.y)), " passt ", s.civic._fit(pr, int(info[1]), int(info[2])).size.x > 0)
	quit()
